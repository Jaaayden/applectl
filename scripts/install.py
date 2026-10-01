#!/usr/bin/env python3
"""Install from a source checkout or a prebuilt release without replacing unrelated apps."""
import os
from pathlib import Path
import shutil
import tempfile

from bundle import build_bundle, project_version, sign_bundle, verify_bundle


def install_targets(home):
    destination = home / "Library/Application Support/AppleCtl"
    launcher = home / ".local/bin/applectl"
    marker = destination / ".managed-by-applectl"
    if destination.is_symlink() or (destination.exists() and not marker.is_file()):
        raise ValueError("An unmanaged AppleCtl installation exists; it was preserved")
    if launcher.is_symlink() or (launcher.exists() and "Launch the signed local app" not in launcher.read_text(errors="replace")):
        raise ValueError("An unrelated applectl command exists; it was preserved")
    return destination, launcher, marker


def main():
    project = Path(__file__).resolve().parent.parent
    version = project_version(project)
    destination, launcher, marker = install_targets(Path.home())
    created_destination = not destination.exists()
    try:
        destination.mkdir(parents=True, exist_ok=True)
        launcher.parent.mkdir(parents=True, exist_ok=True)
        app = destination / "AppleCtl.app"
        prebuilt = project / "AppleCtl.app"
        with tempfile.TemporaryDirectory(prefix="applectl-install-", dir=destination) as staging:
            candidate = Path(staging) / "AppleCtl.app"
            if prebuilt.is_dir():
                verify_bundle(prebuilt, version)
                shutil.copytree(prebuilt, candidate, symlinks=True)
                sign_bundle(candidate)
                verify_bundle(candidate, version)
            else:
                with tempfile.TemporaryDirectory(prefix="applectl-build-") as scratch:
                    build_bundle(project, candidate, Path(scratch))
            descriptor, candidate_launcher = tempfile.mkstemp(prefix=".applectl-install-", dir=launcher.parent)
            os.close(descriptor)
            candidate_launcher = Path(candidate_launcher)
            shutil.copy2(project / "scripts/applectl.py", candidate_launcher)
            candidate_launcher.chmod(0o755)
            backup = destination / "AppleCtl.previous.app"
            if backup.exists():
                shutil.rmtree(backup)
            if app.exists():
                app.rename(backup)
            try:
                candidate.rename(app)
                candidate_launcher.replace(launcher)
                marker.write_text("Managed by the Jaaayden/applectl installer.\n")
            except Exception:
                if app.exists():
                    shutil.rmtree(app)
                if backup.exists():
                    backup.rename(app)
                raise
            finally:
                candidate_launcher.unlink(missing_ok=True)
    finally:
        if created_destination and not marker.is_file():
            try:
                destination.rmdir()
            except OSError:
                pass
    print(f"Installed applectl {version}: {launcher}")
    print(f"Installed app: {app}")
    print("Run applectl auth grant --all and allow the two macOS permission prompts.")


if __name__ == "__main__":
    main()
