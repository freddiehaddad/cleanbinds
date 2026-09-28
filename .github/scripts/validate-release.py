import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from zipfile import BadZipFile, ZipFile


def metadata(text):
    result = {}
    for key, value in re.findall(r"^## ([^:\r\n]+):[ \t]*(.*)$", text, re.MULTILINE):
        if key in result:
            raise ValueError(f"Duplicate TOC metadata: {key}.")
        result[key] = value.strip()
    return result


def forever_version(interface):
    if not re.fullmatch(r"16[0-9]{3}", interface):
        raise ValueError("Interface must specify one WoW Forever version (16xxx).")
    number = int(interface)
    return f"{number // 10000}.{number // 100 % 100}.{number % 100}"


def check_curseforge(game_version):
    token = os.environ.get("CF_API_TOKEN")
    if not token:
        raise ValueError("CF_API_TOKEN must be configured before publishing.")
    try:
        response = subprocess.run(
            [
                "curl", "--fail", "--silent", "--show-error",
                "--connect-timeout", "10", "--max-time", "30",
                "--header", f"X-Api-Token: {token}",
                "https://wow.curseforge.com/api/game/wow/versions",
            ],
            capture_output=True,
            encoding="utf-8",
            timeout=35,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise ValueError("CurseForge version lookup timed out.") from None
    if response.returncode != 0:
        raise ValueError(
            f"CurseForge version lookup failed (curl {response.returncode}): "
            f"{response.stderr.strip()}"
        )
    try:
        versions = json.loads(response.stdout)
    except json.JSONDecodeError:
        raise ValueError("CurseForge returned invalid version JSON.") from None
    if not isinstance(versions, list) or any(not isinstance(v, dict) for v in versions):
        raise ValueError("CurseForge must return a list of version records.")
    matches = [
        version for version in versions
        if version.get("gameVersionTypeID") == 88568 and version.get("name") == game_version
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one CurseForge Forever {game_version} version; "
            "refusing to fall back to another patch or flavor."
        )
    version_id = matches[0].get("id")
    if type(version_id) is not int or version_id <= 0:
        raise ValueError("CurseForge returned an invalid version ID.")
    print(f"CurseForge version verified: Forever {game_version} (ID {version_id}).")
    return version_id


def main(argv=None):
    parser = argparse.ArgumentParser(description="Validate a release tag and its installable addon ZIP.")
    parser.add_argument("tag")
    parser.add_argument("archive", nargs="?")
    parser.add_argument("--curseforge", action="store_true", help="Check live CurseForge compatibility.")
    parser.add_argument(
        "--curseforge-metadata", type=Path,
        help="Write CurseForge upload metadata for the verified archive using live version IDs.",
    )
    args = parser.parse_args(argv)
    if args.curseforge_metadata and args.archive is None:
        parser.error("--curseforge-metadata requires an archive.")

    number = r"(?:0|[1-9][0-9]*)"
    if not re.fullmatch(rf"v{number}\.{number}\.{number}(?:-(?:alpha|beta)\.{number})?", args.tag):
        parser.error("Use vMAJOR.MINOR.PATCH, optionally followed by -alpha.N or -beta.N.")

    tag_type = subprocess.run(
        ["git", "cat-file", "-t", f"refs/tags/{args.tag}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if tag_type.returncode != 0 or tag_type.stdout.strip() != "tag":
        parser.error("The release must use an annotated Git tag.")

    tag_commit = subprocess.check_output(
        ["git", "rev-parse", f"refs/tags/{args.tag}^{{commit}}"], text=True
    ).strip()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if tag_commit != head:
        parser.error("The release tag must point to the checked-out commit.")

    try:
        source_toc = Path("CleanBinds.toc").read_text(encoding="utf-8-sig")
        source_metadata = metadata(source_toc)
        project_metadata = {
            "X-Curse-Project-ID": "1715823",
            "X-Wago-ID": "vNAWeoKo",
            "SavedVariables": "CleanBindsDB",
            "SavedVariablesPerCharacter": "CleanBindsCharacterDB",
        }
        for key, value in project_metadata.items():
            if source_metadata.get(key) != value:
                parser.error(f"Source {key} must be {value!r}; use a tag with publishing configured.")
        game_version = forever_version(source_metadata.get("Interface", ""))
        if args.curseforge or args.curseforge_metadata:
            version_id = check_curseforge(game_version)
        if args.archive is None:
            print(f"Release tag and metadata verified: {args.tag}")
            return

        expected = {
            "CleanBinds/CleanBinds.toc",
            "CleanBinds/LICENSE",
            "CleanBinds/CHANGELOG.md",
        }
        for line in source_toc.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                expected.add("CleanBinds/" + line.replace("\\", "/"))
        icon_prefix = "Interface\\AddOns\\CleanBinds\\"
        icon = source_metadata.get("IconTexture", "")
        if not icon.startswith(icon_prefix):
            parser.error("The icon must be included inside the CleanBinds addon directory.")
        expected.add("CleanBinds/" + icon.removeprefix(icon_prefix).replace("\\", "/"))

        with ZipFile(args.archive) as archive:
            files = [entry.filename for entry in archive.infolist() if not entry.is_dir()]
            if len(files) != len(set(files)) or set(files) != expected:
                parser.error(
                    f"Unexpected package contents; missing={sorted(expected - set(files))}, "
                    f"extra={sorted(set(files) - expected)}."
                )
            if archive.testzip() is not None:
                parser.error("The release ZIP failed its CRC check.")
            packaged_toc = archive.read("CleanBinds/CleanBinds.toc").decode("utf-8-sig")
            packaged_metadata = metadata(packaged_toc.replace("\r\n", "\n"))
            required_metadata = {
                **project_metadata,
                "Interface": source_metadata["Interface"],
                "Version": args.tag,
            }
            for key, value in required_metadata.items():
                if packaged_metadata.get(key) != value:
                    parser.error(f"Packaged {key} must be {value!r}.")
            for entry in files:
                content = archive.read(entry)
                if not content:
                    parser.error(f"The package contains an empty file: {entry}")
                if entry in {"CleanBinds/CleanBinds.toc", "CleanBinds/CHANGELOG.md"}:
                    continue
                source = Path(entry.removeprefix("CleanBinds/")).read_bytes()
                if entry.endswith((".lua", ".xml")) or entry == "CleanBinds/LICENSE":
                    content = content.replace(b"\r\n", b"\n")
                    source = source.replace(b"\r\n", b"\n")
                if content != source:
                    parser.error(f"The packaged file differs from its source: {entry}")
            if args.curseforge_metadata:
                release_type = "release"
                if "-alpha." in args.tag:
                    release_type = "alpha"
                elif "-beta." in args.tag:
                    release_type = "beta"
                payload = {
                    "displayName": f"{args.tag}-forever",
                    "gameVersions": [version_id],
                    "releaseType": release_type,
                    "changelog": archive.read("CleanBinds/CHANGELOG.md").decode("utf-8-sig"),
                    "changelogType": "markdown",
                }
                args.curseforge_metadata.write_text(json.dumps(payload), encoding="utf-8")
    except (BadZipFile, FileNotFoundError, ValueError) as error:
        parser.error(str(error))

    print(f"Installable package verified: {args.archive} ({len(expected)} files)")


if __name__ == "__main__":
    main()
