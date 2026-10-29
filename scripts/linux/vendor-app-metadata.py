#!/usr/bin/env python3
"""Resolve stable native binaries from the vendors' HTTPS Debian indexes."""

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

VENDORS = {
    "claude": (
        "https://downloads.claude.ai/claude-desktop/apt/stable",
        "claude-desktop",
        "claude-desktop",
    ),
    "chatgpt": (
        "https://persistent.oaistatic.com/codex-app-prod/linux/deb",
        "chatgpt",
        "openai-codex-desktop",
    ),
    "chrome": (
        "https://dl.google.com/linux/chrome/deb",
        "google-chrome-stable",
        "google-chrome",
    ),
}
ARCHES = {"aarch64": "arm64", "x86_64": "amd64"}


def resolve_browseros(architecture, index):
    if architecture != "aarch64":
        raise ValueError("The local BrowserOS package currently supports aarch64 only")
    releases = json.loads(index)
    matches = []
    for release in releases:
        tag = release.get("tag_name", "")
        m = re.fullmatch(r"browserclaw/v(\d+(?:\.\d+)+)", tag)
        if not m or release.get("draft") or release.get("prerelease"):
            continue
        version = m.group(1)
        name = f"BrowserOS_neo_v{version}_arm64.deb"
        for asset in release.get("assets", []):
            if asset.get("name") != name:
                continue
            digest = asset.get("digest") or ""
            url = asset.get("browser_download_url", "")
            expected = f"https://github.com/browseros-ai/BrowserOS/releases/download/{tag}/{name}"
            size = asset.get("size")
            if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest) or url != expected or not isinstance(size, int) or size <= 0:
                raise ValueError("Invalid BrowserOS release asset metadata")
            matches.append(dict(app="browseros", package="browseros-neo-bin", architecture=architecture,
                                version=version, pkgver=version, pkgrel="1", url=url,
                                sha256=digest[7:].lower(), size=size))
    if not matches:
        raise ValueError("No stable BrowserOS ARM64 Debian release in the first 100 releases")
    return max(matches, key=lambda r: tuple(map(int, r["version"].split("."))))


def resolve(app, architecture, index):
    base, deb_package, package = VENDORS[app]
    deb_arch = ARCHES[architecture]
    releases = []
    for stanza in re.split(r"\n\s*\n", index.replace("\r\n", "\n")):
        fields = {}
        for line in stanza.splitlines():
            if line and not line[0].isspace() and ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value
        if fields.get("Package") != deb_package or fields.get("Architecture") != deb_arch:
            continue
        version = fields.get("Version", "")
        # Both feeds use numeric versions. Refuse new formats instead of silently
        # sorting them incorrectly or interpolating unchecked data into a recipe.
        if not re.fullmatch(r"\d+(?:\.\d+)+(?:-\d+)?", version):
            raise ValueError(f"Unexpected vendor version: {version!r}")
        digest = fields.get("SHA256", "")
        filename = fields.get("Filename", "")
        path = PurePosixPath(filename)
        if not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            raise ValueError("Missing or invalid vendor SHA256")
        if (
            not filename.startswith("pool/")
            or not filename.endswith(f"_{deb_arch}.deb")
            or not re.fullmatch(r"[A-Za-z0-9_./+\-]+", filename)
            or path.is_absolute()
            or ".." in path.parts
        ):
            raise ValueError(f"Unexpected vendor filename: {filename!r}")
        size = fields.get("Size", "")
        if not size.isdigit() or int(size) <= 0:
            raise ValueError("Missing or invalid download size")
        pkgver, separator, revision = version.partition("-")
        releases.append(
            {
                "app": app,
                "package": package,
                "architecture": architecture,
                "version": version,
                "pkgver": pkgver,
                "pkgrel": revision if separator else "1",
                "url": f"{base}/{filename}",
                "sha256": digest.lower(),
                "size": int(size),
            }
        )
    if not releases:
        raise ValueError(f"No stable {deb_package} release for {deb_arch}")
    return max(releases, key=lambda release: tuple(int(n) for n in re.split(r"[.\-]", release["version"])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", choices=[*VENDORS, "browseros"])
    parser.add_argument("architecture", choices=ARCHES)
    parser.add_argument("--index-file", type=Path, help="Use a saved vendor index for inspection")
    parser.add_argument("--tsv", action="store_true")
    args = parser.parse_args()
    if args.index_file:
        index = args.index_file.read_text()
    else:
        if args.app == "browseros":
            url = "https://api.github.com/repos/browseros-ai/BrowserOS/releases?per_page=100"
        else:
            base = VENDORS[args.app][0]
            url = f"{base}/dists/stable/main/binary-{ARCHES[args.architecture]}/Packages"
        index = subprocess.check_output(
            ["curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
             "--max-time", "30", "--proto", "=https", "--proto-redir", "=https", url],
            text=True,
        )
    release = resolve_browseros(args.architecture, index) if args.app == "browseros" else resolve(args.app, args.architecture, index)
    if args.tsv:
        print("\t".join(str(release[k]) for k in ("package", "version", "pkgver", "pkgrel", "url", "sha256", "size")))
    else:
        print(json.dumps(release, indent=2))


if __name__ == "__main__":
    main()
