"""Shared, dependency-free app assembly and validation for installs and releases."""
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess

BUNDLE_ID = "com.jayden.applectl"


def project_version(project):
    version = (project / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("VERSION must contain a stable major.minor.patch version")
    swift = project / "Sources/AppleCore/ToolVersion.swift"
    if swift.exists():
        match = re.search(r'let current = "([^"]+)"', swift.read_text())
        if not match or match.group(1) != version:
            raise ValueError("Swift tool version does not match VERSION")
    return version


def build_bundle(project, app, scratch):
    version = project_version(project)
    arguments = ["swift", "build", "-c", "release", "--scratch-path", str(scratch)]
    subprocess.run(arguments, cwd=project, check=True)
    binary_dir = Path(subprocess.check_output([*arguments, "--show-bin-path"], cwd=project, text=True).strip())
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    info = plistlib.loads((project / "Support/Info.plist").read_bytes())
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = version
    info["CFBundleIconFile"] = "AppIcon.icns"
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
    shutil.copy2(binary_dir / "applectl-native", app / "Contents/MacOS/applectl-native")
    shutil.copy2(project / "assets/AppIcon.icns", app / "Contents/Resources/AppIcon.icns")
    sign_bundle(app)
    verify_bundle(app, version)


def sign_bundle(app):
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", BUNDLE_ID, str(app)], check=True)


def verify_bundle(app, version, architecture=None):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "applectl-native":
        raise ValueError("Unexpected application identity")
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
        raise ValueError("Application metadata version mismatch")
    binary = app / "Contents/MacOS/applectl-native"
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()
    architecture = architecture or platform.machine()
    if architecture not in architectures:
        raise ValueError(f"This package does not support {architecture}; download the matching architecture")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)
    actual = subprocess.check_output([str(binary), "--version"], text=True).strip()
    if actual != version:
        raise ValueError("Compiled command version mismatch")
    if not (app / "Contents/Resources/AppIcon.icns").is_file():
        raise ValueError("Application icon is missing")
