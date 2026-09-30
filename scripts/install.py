#!/usr/bin/env python3
"""Build and install this project without replacing unrelated commands or apps."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
destination = Path.home() / "Library/Application Support/AppleCtl"
app = destination / "AppleCtl.app"
launcher = Path.home() / ".local/bin/applectl"
marker = destination / ".managed-by-applectl"
if destination.exists() and not marker.is_file():
    raise SystemExit("An unmanaged AppleCtl installation exists; inspect it before replacing it.")
if launcher.exists() and "Launch the signed local app" not in launcher.read_text(errors="replace"):
    raise SystemExit("An unrelated applectl command exists; it was preserved.")
build = Path(tempfile.gettempdir()) / "applectl-release-build"
subprocess.run(["swift", "build", "-c", "release", "--scratch-path", str(build)], cwd=project, check=True)
binary_dir = subprocess.check_output(["swift", "build", "-c", "release", "--scratch-path", str(build), "--show-bin-path"], cwd=project, text=True).strip()
destination.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="applectl-install-", dir=destination) as staging:
    candidate = Path(staging) / "AppleCtl.app"
    (candidate / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(project / "Support/Info.plist", candidate / "Contents/Info.plist")
    shutil.copy2(Path(binary_dir) / "applectl-native", candidate / "Contents/MacOS/applectl-native")
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", "com.jayden.applectl", str(candidate)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(candidate)], check=True)
    backup = destination / "AppleCtl.previous.app"
    if backup.exists():
        shutil.rmtree(backup)
    if app.exists():
        app.rename(backup)
    try:
        candidate.rename(app)
    except Exception:
        if backup.exists() and not app.exists():
            backup.rename(app)
        raise
    marker.write_text("Managed by the Jaaayden/applectl installer.\n")
launcher.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(project / "scripts/applectl.py", launcher)
os.chmod(launcher, 0o755)
print(f"Installed command: {launcher}")
print(f"Installed app: {app}")
print("Run applectl auth grant --all and allow the two macOS permission prompts.")
