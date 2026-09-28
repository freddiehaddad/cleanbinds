from contextlib import chdir, redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".github" / "scripts" / "validate-release.py"
SPEC = importlib.util.spec_from_file_location("validate_release", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class MetadataTests(unittest.TestCase):
    def test_duplicate_metadata_is_rejected(self):
        for key in ("X-Curse-Project-ID", "Interface"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "Duplicate TOC"):
                release.metadata(f"## {key}: 1\n## {key}: 2\n")

    def test_forever_version_uses_the_interface(self):
        for interface, version in (("16001", "1.60.1"), ("16002", "1.60.2"), ("16100", "1.61.0")):
            with self.subTest(interface=interface):
                self.assertEqual(release.forever_version(interface), version)

    def test_other_flavors_and_ambiguous_interfaces_are_rejected(self):
        for interface in ("", "160101", "120100", "11509", "16001,16002", "16001\n"):
            with self.subTest(interface=interface), self.assertRaisesRegex(ValueError, "WoW Forever"):
                release.forever_version(interface)


class CurseForgeTests(unittest.TestCase):
    def setUp(self):
        # patch.dict(os.environ) can drop native empty variables on Windows.
        self.environment = patch.object(release.os, "environ", {"CF_API_TOKEN": "test-upload-token"})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.request = patch.object(release.subprocess, "run")
        self.curl = self.request.start()
        self.addCleanup(self.request.stop)
        self.curl.return_value = subprocess.CompletedProcess([], 0, "[]", "")
        self.output = io.StringIO()
        self.capture = redirect_stdout(self.output)
        self.capture.__enter__()
        self.addCleanup(self.capture.__exit__, None, None, None)
        self.version = {"id": 123, "gameVersionTypeID": 88568, "name": "1.60.1"}

    def response(self, versions):
        self.curl.return_value.stdout = json.dumps(versions)

    def test_exact_flavor_and_patch_are_required(self):
        self.response([
            {**self.version, "id": 124, "gameVersionTypeID": 517},
            {**self.version, "id": 125, "name": "1.60.2"},
            self.version,
        ])
        self.assertEqual(release.check_curseforge("1.60.1"), 123)
        command = self.curl.call_args.args[0]
        self.assertEqual(command[-1], "https://wow.curseforge.com/api/game/wow/versions")
        self.assertEqual(command[command.index("--connect-timeout") + 1], "10")
        self.assertEqual(command[command.index("--max-time") + 1], "30")
        self.assertEqual(self.curl.call_args.kwargs["timeout"], 35)
        self.assertNotIn("--location", command)
        self.assertIn("X-Api-Token: test-upload-token", command)
        self.assertNotIn("test-upload-token", self.output.getvalue())

    def test_missing_token_does_not_make_a_request(self):
        with patch.dict(os.environ, {"CF_API_TOKEN": ""}):
            with self.assertRaisesRegex(ValueError, "CF_API_TOKEN"):
                release.check_curseforge("1.60.1")
        self.curl.assert_not_called()

    def test_no_version_fallback(self):
        for versions in (
            [],
            [{**self.version, "name": "1.60.0"}],
            [{**self.version, "gameVersionTypeID": 517}],
            [self.version, self.version],
        ):
            with self.subTest(versions=versions), self.assertRaisesRegex(ValueError, "refusing to fall back"):
                self.response(versions)
                release.check_curseforge("1.60.1")

    def test_invalid_version_records_are_rejected(self):
        for versions in (None, {}, {"errorMessage": "Unauthorized"}, ["1.60.1"]):
            with self.subTest(versions=versions), self.assertRaisesRegex(ValueError, "list of version records"):
                self.response(versions)
                release.check_curseforge("1.60.1")

    def test_invalid_ids_are_rejected(self):
        for version_id in (None, 0, -1, True, "123", 123.0):
            with self.subTest(version_id=version_id), self.assertRaisesRegex(ValueError, "invalid version ID"):
                self.response([{**self.version, "id": version_id}])
                release.check_curseforge("1.60.1")

    def test_invalid_json_is_not_echoed(self):
        self.curl.return_value.stdout = "<html>test-upload-token</html>"
        with self.assertRaisesRegex(ValueError, "invalid version JSON") as error:
            release.check_curseforge("1.60.1")
        self.assertNotIn("test-upload-token", str(error.exception))

    def test_http_and_network_failures_are_reported(self):
        for code, message in ((22, "HTTP 401"), (28, "Operation timed out"), (6, "Could not resolve host")):
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, message):
                self.curl.return_value = subprocess.CompletedProcess([], code, "", message)
                release.check_curseforge("1.60.1")

    def test_process_timeout_does_not_expose_the_token(self):
        self.curl.side_effect = subprocess.TimeoutExpired(["curl", "test-upload-token"], 35)
        with self.assertRaisesRegex(ValueError, "lookup timed out") as error:
            release.check_curseforge("1.60.1")
        self.assertNotIn("test-upload-token", str(error.exception))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cleanbinds-release-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.source_toc = (ROOT / "CleanBinds.toc").read_text(encoding="utf-8")
        runtime = [
            line.strip() for line in self.source_toc.splitlines()
            if line.strip() and not line.startswith("#")
        ]
        self.files = {
            name: (ROOT / name).read_bytes()
            for name in ["CleanBinds.toc", "LICENSE", "Media/Icon.tga", *runtime]
        }
        for name, content in self.files.items():
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        self.git("init", "--quiet", "--template=")
        self.git("add", "--force", ".")
        self.git("commit", "--quiet", "-m", "Release fixture")
        for tag in ("v9.8.7", "v9.8.7-alpha.1", "v9.8.7-beta.1"):
            self.git("tag", "-a", tag, "-m", tag)

    def git(self, *args):
        result = subprocess.run(
            [
                "git", "-c", "user.name=Release tests",
                "-c", "user.email=release-tests@example.invalid",
                "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false",
                "-c", "core.autocrlf=false",
                "-c", f"core.hooksPath={self.repo / '.git' / 'hooks'}", *args,
            ],
            cwd=self.repo, capture_output=True, text=True, check=False, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def archive(self, tag="v9.8.7", changes=None):
        files = {"CleanBinds/" + name: content for name, content in self.files.items()}
        files["CleanBinds/CleanBinds.toc"] = self.source_toc.replace(
            "@project-version@", tag
        ).encode("utf-8")
        files["CleanBinds/CHANGELOG.md"] = b"Release fixture\n"
        for name, content in (changes or {}).items():
            if content is None:
                del files[name]
            else:
                files[name] = content
        archive = self.root / "release.zip"
        with ZipFile(archive, "w") as package:
            for name, content in files.items():
                package.writestr(name, content)
        return archive

    def validate(self, tag="v9.8.7", archive=None):
        command = [sys.executable, str(SCRIPT), tag]
        if archive is not None:
            command.append(str(archive))
        return subprocess.run(
            command, cwd=self.repo, capture_output=True, text=True, timeout=15, check=False,
        )

    def test_stable_alpha_and_beta_packages(self):
        for tag in ("v9.8.7", "v9.8.7-alpha.1", "v9.8.7-beta.1"):
            with self.subTest(tag=tag):
                result = self.validate(tag, self.archive(tag))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("(11 files)", result.stdout)

    def test_recovery_metadata_uses_the_verified_archive_and_live_id(self):
        for tag, channel in (
            ("v9.8.7", "release"), ("v9.8.7-alpha.1", "alpha"), ("v9.8.7-beta.1", "beta"),
        ):
            with self.subTest(tag=tag):
                archive = self.archive(tag)
                before = archive.read_bytes()
                metadata = self.root / "curseforge.json"
                with chdir(self.repo), redirect_stdout(io.StringIO()):
                    with patch.object(release, "check_curseforge", return_value=123) as lookup:
                        release.main([tag, str(archive), "--curseforge-metadata", str(metadata)])
                lookup.assert_called_once_with("1.60.1")
                self.assertEqual(json.loads(metadata.read_text(encoding="utf-8")), {
                    "displayName": f"{tag}-forever",
                    "gameVersions": [123],
                    "releaseType": channel,
                    "changelog": "Release fixture\n",
                    "changelogType": "markdown",
                })
                self.assertEqual(archive.read_bytes(), before)

    def test_invalid_archive_cannot_produce_recovery_metadata(self):
        archive = self.archive(changes={"CleanBinds/Core.lua": b"changed"})
        metadata = self.root / "curseforge.json"
        with chdir(self.repo), redirect_stderr(io.StringIO()):
            with patch.object(release, "check_curseforge", return_value=123):
                with self.assertRaises(SystemExit) as error:
                    release.main(["v9.8.7", str(archive), "--curseforge-metadata", str(metadata)])
        self.assertEqual(error.exception.code, 2)
        self.assertFalse(metadata.exists())

    def test_malformed_or_lightweight_tags_are_rejected(self):
        self.git("tag", "v1.2.3")
        for tag, message in (
            ("v01.2.3", "Use vMAJOR.MINOR.PATCH"),
            ("v1.2", "Use vMAJOR.MINOR.PATCH"),
            ("v1.2.3", "annotated Git tag"),
            ("v1.2.4", "annotated Git tag"),
        ):
            with self.subTest(tag=tag):
                result = self.validate(tag)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_tag_must_match_head(self):
        self.git("commit", "--quiet", "--allow-empty", "-m", "Different commit")
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checked-out commit", result.stderr)

    def test_source_project_id_is_checked_without_an_archive(self):
        for replacement in ("", "## X-Curse-Project-ID: 0\n", "## X-Curse-Project-ID: 1234\n"):
            with self.subTest(replacement=replacement):
                (self.repo / "CleanBinds.toc").write_text(
                    self.source_toc.replace("## X-Curse-Project-ID: 1715823\n", replacement),
                    encoding="utf-8",
                )
                result = self.validate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Source X-Curse-Project-ID", result.stderr)

    def test_packaged_project_ids_and_version_are_checked(self):
        for field, value in (
            ("X-Curse-Project-ID", "1715823"), ("X-Wago-ID", "vNAWeoKo"),
            ("Version", "@project-version@"), ("Interface", "16001"),
        ):
            with self.subTest(field=field):
                toc = self.source_toc.replace(f"## {field}: {value}", f"## {field}: wrong")
                toc = toc.replace("@project-version@", "v9.8.7").encode("utf-8")
                result = self.validate(archive=self.archive(changes={"CleanBinds/CleanBinds.toc": toc}))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Packaged {field}", result.stderr)

    def test_package_contents_are_checked(self):
        for changes, message in (
            ({"CleanBinds/README.md": b"unexpected"}, "Unexpected package contents"),
            ({"CleanBinds/Core.lua": None}, "Unexpected package contents"),
            ({"CleanBinds/Core.lua": b""}, "empty file"),
            ({"CleanBinds/Core.lua": b"changed"}, "differs from its source"),
        ):
            with self.subTest(message=message):
                result = self.validate(archive=self.archive(changes=changes))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
