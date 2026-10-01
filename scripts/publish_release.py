#!/usr/bin/env python3
"""Publish verified native assets by release ID, with safe recovery of a draft."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def gh(*arguments, input=None):
    return subprocess.run(
        ["gh", *arguments], input=input, text=True, stdout=subprocess.PIPE, check=True
    ).stdout


def api(endpoint, *arguments, body=None, method="PATCH"):
    if body is None:
        return json.loads(gh("api", endpoint, *arguments))
    return json.loads(gh("api", endpoint, "--method", method, "--input", "-", input=json.dumps(body)))


def local_assets(tag, directory):
    match = re.fullmatch(r"v((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))", tag)
    if match is None:
        raise ValueError("Expected a stable vX.Y.Z release tag")
    expected = {f"applectl-{match[1]}-macos-{arch}.tar.gz" for arch in ("arm64", "x86_64")}
    files = sorted(directory.glob("*.tar.gz"))
    if {file.name for file in files} != expected:
        raise ValueError("Both matching release architectures are required")
    checksums = [(file, hashlib.sha256(file.read_bytes()).hexdigest()) for file in files]
    manifest = directory / "SHA256SUMS"
    manifest.write_text("".join(f"{digest}  {file.name}\n" for file, digest in checksums))
    files.append(manifest)
    return {
        file.name: {"path": file, "size": file.stat().st_size,
                    "digest": "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()}
        for file in files
    }


def find_release(repo, tag):
    pages = api(f"repos/{repo}/releases?per_page=100", "--paginate", "--slurp")
    matches = [release for page in pages for release in page if release["tag_name"] == tag]
    if len(matches) > 1:
        raise ValueError("Ambiguous release tag; preserved existing releases")
    return matches[0] if matches else None


def require_draft(release, names):
    if release.get("draft") is not True:
        raise ValueError("Release is already published; preserved its assets")
    if any(asset["name"] not in names for asset in release.get("assets", [])):
        raise ValueError("Draft contains unrelated assets; preserved it")


def publish(repo, tag, directory, notes):
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo) is None:
        raise ValueError("Expected an owner/repository name")
    assets = local_assets(tag, directory)
    release = find_release(repo, tag)
    if release is None:
        reference = api(f"repos/{repo}/git/ref/tags/{tag}")
        if reference.get("ref") != "refs/tags/" + tag:
            raise ValueError("Release tag was not verified")
        release = api(f"repos/{repo}/releases", method="POST", body={
            "tag_name": tag, "name": "AppleCtl " + tag,
            "body": notes.read_text(), "draft": True, "prerelease": False,
        })
        if release.get("tag_name") != tag:
            raise ValueError("Created draft tag differs; no upload attempted")
    require_draft(release, assets)
    release_id = release["id"]
    existing = {asset["name"]: asset for asset in release.get("assets", [])}
    for name, asset in assets.items():
        previous = existing.get(name)
        if previous is not None:
            if previous.get("state") == "uploaded" and previous.get("size") == asset["size"] and previous.get("digest") == asset["digest"]:
                continue
            gh("api", f"repos/{repo}/releases/assets/{previous['id']}", "--method", "DELETE")
        gh("api", f"https://uploads.github.com/repos/{repo}/releases/{release_id}/assets?name={name}",
           "--method", "POST", "--header", "Content-Type: application/octet-stream", "--input", str(asset["path"]))
    verified = api(f"repos/{repo}/releases/{release_id}")
    require_draft(verified, assets)
    remote_assets = verified.get("assets", [])
    if verified["tag_name"] != tag or len(remote_assets) != len(assets) or {a["name"] for a in remote_assets} != set(assets):
        raise ValueError("Incomplete release assets; left the release as a draft")
    for remote in remote_assets:
        local = assets[remote["name"]]
        if remote.get("state") != "uploaded" or remote.get("size") != local["size"] or remote.get("digest") != local["digest"]:
            raise ValueError("Uploaded asset checksum or size differs; left the release as a draft")
    published = api(f"repos/{repo}/releases/{release_id}", body={"draft": False, "make_latest": "true"})
    if published.get("draft") is not False or published.get("tag_name") != tag:
        raise ValueError("Publication was not confirmed; inspect the release before retrying")
    print("Published " + published["html_url"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", type=Path, default=Path("dist"))
    parser.add_argument("--notes", type=Path, default=Path("RELEASE_NOTES.md"))
    args = parser.parse_args()
    publish(args.repo, args.tag, args.directory, args.notes)


if __name__ == "__main__":
    main()
