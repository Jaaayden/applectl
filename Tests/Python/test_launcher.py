"""Verify the local app result transport without requesting access to user data."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("applectl_launcher", Path(__file__).resolve().parents[2] / "scripts/applectl.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.home = Path(self.directory.name)
        binary = self.home / "Library/Application Support/AppleCtl/AppleCtl.app/Contents/MacOS/applectl-native"
        binary.parent.mkdir(parents=True)
        binary.touch()
        self.result_directories = []

    def tearDown(self):
        self.directory.cleanup()

    def invoke(self, arguments, action):
        output = io.StringIO()
        with patch.object(launcher.Path, "home", return_value=self.home), patch.object(launcher.sys, "argv", ["applectl", *arguments]), \
             patch.object(launcher.subprocess, "run", side_effect=action) as run, contextlib.redirect_stdout(output):
            code = launcher.main()
        self.assertEqual(run.call_count, 1, "The launcher must never automatically retry")
        for directory in self.result_directories:
            self.assertFalse(directory.exists(), "Private command results must be removed")
        return code, json.loads(output.getvalue())

    def result(self, value):
        def write(argv, **options):
            self.assertEqual(argv[:3], ["/usr/bin/open", "-n", "-W"])
            target = Path(argv[argv.index("--result-file") + 1])
            self.assertEqual(target.parent.stat().st_mode & 0o777, 0o700)
            self.result_directories.append(target.parent)
            target.write_text(json.dumps(value))
            return subprocess.CompletedProcess(argv, 0, stderr="")
        return write

    def test_successful_json_and_private_cleanup(self):
        code, result = self.invoke(["auth", "status"], self.result({"ok": True, "data": {"calendar": "not-determined"}, "meta": {"exitCode": 0}}))
        self.assertEqual(code, 0)
        self.assertEqual(result["data"]["calendar"], "not-determined")

    def test_operation_error_is_preserved(self):
        expected = {"ok": False, "error": {"code": "not_found", "message": "Not found"}, "meta": {"exitCode": 1}}
        code, result = self.invoke(["events", "get", "--id", "missing"], self.result(expected))
        self.assertEqual(code, 1)
        self.assertEqual(result, expected)

    def test_timeout_reports_unconfirmed_without_retry(self):
        code, result = self.invoke(["events", "add"], subprocess.TimeoutExpired("open", 120))
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "result_unconfirmed")

    def test_bad_result_is_structured_error(self):
        code, result = self.invoke(["auth", "status"], self.result({"ok": True, "meta": {"exitCode": "broken"}}))
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_result")

    def test_launch_error_is_structured_error(self):
        code, result = self.invoke(["auth", "status"], OSError("Cannot start Launch Services"))
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "launch_failed")


if __name__ == "__main__":
    unittest.main()
