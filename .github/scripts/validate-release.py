import argparse
from pathlib import Path
import re
import subprocess
from zipfile import BadZipFile, ZipFile


parser = argparse.ArgumentParser(description="Validate a release tag and its installable addon ZIP.")
parser.add_argument("tag")
parser.add_argument("archive", nargs="?")
args = parser.parse_args()

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

if args.archive is None:
    print(f"Release tag verified: {args.tag}")
    raise SystemExit(0)


def metadata(text):
    return dict(re.findall(r"^## ([^:\r\n]+):[ \t]*(.*)$", text, re.MULTILINE))


source_toc = Path("CleanBinds.toc").read_text(encoding="utf-8")
source_metadata = metadata(source_toc)
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
icon = source_metadata["IconTexture"]
if not icon.startswith(icon_prefix):
    parser.error("The icon must be included inside the CleanBinds addon directory.")
expected.add("CleanBinds/" + icon.removeprefix(icon_prefix).replace("\\", "/"))

try:
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
            "Interface": source_metadata["Interface"],
            "Version": args.tag,
            "X-Wago-ID": "vNAWeoKo",
            "SavedVariables": "CleanBindsDB",
            "SavedVariablesPerCharacter": "CleanBindsCharacterDB",
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
except (BadZipFile, FileNotFoundError) as error:
    parser.error(str(error))

print(f"Installable package verified: {args.archive} ({len(expected)} files)")
