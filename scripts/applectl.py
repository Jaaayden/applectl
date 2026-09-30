#!/usr/bin/env python3
"""Launch the signed local app so macOS grants AppleCtl its own TCC identity."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def fail(code, message):
    print(json.dumps({"ok": False, "error": {"code": code, "message": message},
                      "meta": {"version": "0.1.0", "command": " ".join(sys.argv[1:3]), "exitCode": 1}}, ensure_ascii=False))
    return 1


def main():
    app = Path.home() / "Library/Application Support/AppleCtl/AppleCtl.app"
    executable = app / "Contents/MacOS/applectl-native"
    if not executable.is_file():
        return fail("not_installed", "AppleCtl is not installed. Run scripts/install.py in the project.")
    arguments = sys.argv[1:]
    if "--result-file" in arguments:
        return fail("invalid_arguments", "--result-file is reserved for the launcher.")
    if not arguments or arguments in (["--help"], ["-h"], ["--version"]):
        return subprocess.call([str(executable), *arguments])
    # A fresh mode-0700 directory isolates each invocation and keeps private data off disk afterwards.
    with tempfile.TemporaryDirectory(prefix="applectl-") as directory:
        os.chmod(directory, 0o700)
        result_file = Path(directory) / "result.json"
        try:
            result = subprocess.run(
                ["/usr/bin/open", "-n", "-W", str(app), "--args", "--result-file", str(result_file), *arguments],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                timeout=600 if arguments[:2] == ["auth", "grant"] else 120,
            )
        except subprocess.TimeoutExpired:
            return fail("result_unconfirmed", "Command timed out. Read back the target before retrying a mutation.")
        except OSError as error:
            return fail("launch_failed", str(error))
        if not result_file.is_file():
            return fail("launch_failed", result.stderr.strip() or "AppleCtl exited without a result.")
        try:
            data = json.loads(result_file.read_text())
            exit_code = data["meta"]["exitCode"]
            if type(exit_code) is not int or not 0 <= exit_code <= 255 or data["ok"] is not (exit_code == 0):
                raise ValueError("Invalid result envelope")
        except (OSError, ValueError, TypeError, KeyError):
            return fail("invalid_result", "AppleCtl returned an invalid result envelope.")
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return exit_code


if __name__ == "__main__":
    sys.exit(main())
