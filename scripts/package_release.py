#!/usr/bin/env python3
"""Build one native macOS release archive, without requesting personal-data permissions."""
import argparse
import hashlib
from pathlib import Path
import platform
import shutil
import tarfile
import tempfile

from bundle import build_bundle, project_version

RELEASE_FILES = ["VERSION", "README.md", "README.zh-CN.md", "AUDIT.md", "THIRD_PARTY.md", "LICENSE"]
RELEASE_SCRIPTS = ["applectl.py", "install.py", "bundle.py", "live_verify.py"]


def validate_tag(project, tag):
    version = project_version(project)
    if tag != "v" + version:
        raise ValueError("Release tag must match VERSION and the compiled Swift tool version")
    return version


def copy_release_contents(project, destination):
    for name in RELEASE_FILES:
        shutil.copy2(project / name, destination / name)
    for directory in ("licenses", "skills", "assets"):
        shutil.copytree(project / directory, destination / directory, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
    scripts = destination / "scripts"
    scripts.mkdir()
    for name in RELEASE_SCRIPTS:
        shutil.copy2(project / "scripts" / name, scripts / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    parser.add_argument("--check-version", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    version = project_version(project) if args.check_version else validate_tag(project, args.tag)
    if args.check_version:
        print("Version verified: " + version)
        return
    if args.arch != platform.machine():
        raise ValueError("Build releases on the matching native runner architecture")
    name = f"applectl-{version}-macos-{args.arch}"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    archive = args.output_dir / (name + ".tar.gz")
    if archive.exists():
        raise ValueError("Release archive already exists; preserved it")
    with tempfile.TemporaryDirectory(prefix="applectl-release-") as working:
        package = Path(working) / name
        package.mkdir()
        copy_release_contents(project, package)
        build_bundle(project, package / "AppleCtl.app", Path(working) / "build")
        with tarfile.open(archive, "w:gz") as output:
            output.add(package, arcname=name)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(f"Created {archive.name} ({args.arch}, SHA256 {digest})")


if __name__ == "__main__":
    main()
