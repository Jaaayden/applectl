"""Verify release boundaries without building or accessing EventKit."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import bundle
import install
import package_release


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_unmanaged_application_is_preserved(self):
        destination = self.root / "Library/Application Support/AppleCtl"
        destination.mkdir(parents=True)
        sentinel = destination / "user-file"
        sentinel.write_text("keep")
        with self.assertRaises(ValueError):
            install.install_targets(self.root)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_unrelated_command_and_symlink_are_preserved(self):
        launcher = self.root / ".local/bin/applectl"
        launcher.parent.mkdir(parents=True)
        launcher.write_text("unrelated command")
        with self.assertRaises(ValueError):
            install.install_targets(self.root)
        launcher.unlink()
        target = self.root / "other-command"
        target.write_text("Launch the signed local app")
        launcher.symlink_to(target)
        with self.assertRaises(ValueError):
            install.install_targets(self.root)
        self.assertTrue(launcher.is_symlink())

    def test_failed_first_build_does_not_leave_unmanaged_installation(self):
        with patch.object(install.Path, "home", return_value=self.root), patch.object(install, "build_bundle", side_effect=RuntimeError("Build failed")):
            with self.assertRaises(RuntimeError):
                install.main()
        self.assertFalse((self.root / "Library/Application Support/AppleCtl").exists())
        self.assertFalse((self.root / ".local/bin/applectl").exists())

    def test_tag_and_swift_version_must_match(self):
        (self.root / "VERSION").write_text("0.1.0")
        swift = self.root / "Sources/AppleCore/ToolVersion.swift"
        swift.parent.mkdir(parents=True)
        swift.write_text('public static let current = "0.1.0"')
        self.assertEqual(package_release.validate_tag(self.root, "v0.1.0"), "0.1.0")
        with self.assertRaises(ValueError):
            package_release.validate_tag(self.root, "v0.2.0")
        swift.write_text('public static let current = "0.2.0"')
        with self.assertRaises(ValueError):
            bundle.project_version(self.root)

    def test_wrong_binary_architecture_is_rejected(self):
        app = self.root / "AppleCtl.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        import plistlib
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle.BUNDLE_ID, "CFBundleExecutable": "applectl-native",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "0.1.0",
        }))
        with patch.object(bundle.subprocess, "check_output", return_value="x86_64\n"), self.assertRaises(ValueError):
            bundle.verify_bundle(app, "0.1.0", architecture="arm64")

    def test_release_copy_excludes_private_and_build_files(self):
        for name in package_release.RELEASE_FILES:
            (self.root / name).write_text("public")
        for name in package_release.RELEASE_SCRIPTS:
            path = self.root / "scripts" / name
            path.parent.mkdir(exist_ok=True)
            path.write_text("public")
        for name in ("licenses/MIT.txt", "assets/icon.svg", "assets/icon.png", "skills/example/SKILL.md", "skills/example/__pycache__/private.pyc",
                     ".env", "scripts/private-token.txt", "personal-calendar.json", ".build/private-file"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("not a release file" if "private" in name else "public")
        destination = self.root / "output"
        destination.mkdir()
        package_release.copy_release_contents(self.root, destination)
        self.assertTrue((destination / "scripts/install.py").is_file())
        self.assertTrue((destination / "licenses/MIT.txt").is_file())
        self.assertFalse((destination / ".env").exists())
        self.assertFalse((destination / "scripts/private-token.txt").exists())
        self.assertFalse((destination / "personal-calendar.json").exists())
        self.assertFalse((destination / ".build").exists())
        self.assertFalse((destination / "skills/example/__pycache__").exists())


if __name__ == "__main__":
    unittest.main()
