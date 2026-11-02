#!/usr/bin/python3
"""Install/remove only bridge-owned additive Waydroid overlay declarations."""
import argparse
import configparser
import os
from pathlib import Path
import subprocess

MARKER = "waydroid-fprintd-bridge managed file"
FILES = {
    "system/etc/permissions/waydroid-fprintd.xml": f'''<?xml version="1.0" encoding="utf-8"?>
<!-- {MARKER} -->
<permissions><feature name="android.hardware.fingerprint" /></permissions>
''',
    "vendor/etc/vintf/manifest/waydroid-fprintd.xml": f'''<?xml version="1.0" encoding="utf-8"?>
<!-- {MARKER} -->
<manifest version="1.0" type="device">
  <hal format="aidl">
    <name>android.hardware.biometrics.fingerprint</name>
    <version>1</version>
    <fqname>IFingerprint/default</fqname>
  </hal>
</manifest>
''',
}


def apply(base, remove=False):
    base = Path(base)
    for relative, content in FILES.items():
        path = base / relative
        for parent in (path, *path.parents):
            if parent.is_symlink():
                raise RuntimeError(f"Refusing symlink: {parent}")
        if path.exists() and MARKER not in path.read_text():
            raise RuntimeError(f"Refusing to replace unowned file: {path}")
    for relative, content in FILES.items():
        path = base / relative
        if remove:
            path.unlink(missing_ok=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            temp = path.with_suffix(".tmp")
            if temp.exists() or temp.is_symlink():
                raise RuntimeError(f"Unexpected temporary file: {temp}")
            with open(temp, "x") as stream:
                stream.write(content)
            temp.chmod(0o644)
            temp.replace(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Run with pkexec /usr/bin/python3 /absolute/path/to/host-setup.py")
    if not args.remove:
        config = configparser.ConfigParser()
        config.read("/var/lib/waydroid/waydroid.cfg")
        if config.get("waydroid", "mount_overlays", fallback="False") != "True":
            raise SystemExit("Waydroid overlays must already be enabled")
        result = subprocess.run(
            ["/usr/bin/python3", "/usr/bin/waydroid", "shell", "getenforce"],
            capture_output=True, text=True, timeout=10)
        if result.returncode or result.stdout.strip() not in ("Disabled", "Permissive"):
            raise SystemExit("Unsupported Android SELinux state; no files installed")
    apply("/var/lib/waydroid/overlay", args.remove)
