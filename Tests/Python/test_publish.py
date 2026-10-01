"""Verify draft recovery and refuse unsafe or incomplete publication."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import publish_release


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for arch in ("arm64", "x86_64"):
            (self.root / f"applectl-0.1.0-macos-{arch}.tar.gz").write_bytes(arch.encode())
        self.notes = self.root / "notes.md"
        self.notes.write_text("Release notes")
        self.assets = publish_release.local_assets("v0.1.0", self.root)
        self.draft = {"id": 42, "tag_name": "v0.1.0", "draft": True, "assets": [
            {"name": name, "state": "uploaded", "size": asset["size"], "digest": asset["digest"]}
            for name, asset in self.assets.items()
        ]}

    def tearDown(self):
        self.directory.cleanup()

    def publish(self):
        publish_release.publish("owner/repo", "v0.1.0", self.root, self.notes)

    def test_existing_draft_is_verified_and_published_by_id(self):
        published = dict(self.draft, draft=False, html_url="https://github.com/owner/repo/releases/tag/v0.1.0")
        with patch.object(publish_release, "api", side_effect=[[[self.draft]], self.draft, published]) as api, patch.object(publish_release, "gh") as gh:
            self.publish()
        self.assertEqual(gh.call_args.args[:3], ("release", "upload", "v0.1.0"))
        self.assertEqual(api.call_args.args, ("repos/owner/repo/releases/42",))
        self.assertEqual(api.call_args.kwargs["body"], {"draft": False, "make_latest": "true"})
        self.assertTrue(all("/releases/tags/" not in call.args[0] for call in api.call_args_list))

    def test_new_release_stays_draft_until_assets_are_verified(self):
        published = dict(self.draft, draft=False, html_url="https://github.com/owner/repo/releases/tag/v0.1.0")
        with patch.object(publish_release, "api", side_effect=[[[]], [[self.draft]], self.draft, published]) as api, patch.object(publish_release, "gh") as gh:
            self.publish()
        self.assertEqual(gh.call_args_list[0].args[:3], ("release", "create", "v0.1.0"))
        self.assertIn("--verify-tag", gh.call_args_list[0].args)
        self.assertIn("--draft", gh.call_args_list[0].args)
        self.assertEqual(gh.call_args_list[1].args[:3], ("release", "upload", "v0.1.0"))
        self.assertEqual(api.call_args.args, ("repos/owner/repo/releases/42",))

    def test_published_release_is_never_modified(self):
        release = dict(self.draft, draft=False)
        with patch.object(publish_release, "api", return_value=[[release]]), patch.object(publish_release, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "already published"):
                self.publish()
            gh.assert_not_called()

    def test_unrelated_draft_assets_are_preserved(self):
        release = copy.deepcopy(self.draft)
        release["assets"].append({"name": "user-upload.zip"})
        with patch.object(publish_release, "api", return_value=[[release]]), patch.object(publish_release, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "unrelated"):
                self.publish()
            gh.assert_not_called()

    def test_remote_digest_mismatch_cannot_publish(self):
        bad = copy.deepcopy(self.draft)
        bad["assets"][0]["digest"] = "sha256:" + "0" * 64
        with patch.object(publish_release, "api", side_effect=[[[self.draft]], bad]) as api, patch.object(publish_release, "gh"):
            with self.assertRaisesRegex(ValueError, "checksum"):
                self.publish()
            self.assertEqual(api.call_count, 2)
            self.assertTrue(all("body" not in call.kwargs for call in api.call_args_list))

    def test_missing_architecture_fails_before_remote_changes(self):
        (self.root / "applectl-0.1.0-macos-x86_64.tar.gz").unlink()
        with patch.object(publish_release, "api") as api, patch.object(publish_release, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "Both matching"):
                self.publish()
            api.assert_not_called()
            gh.assert_not_called()


if __name__ == "__main__":
    unittest.main()
