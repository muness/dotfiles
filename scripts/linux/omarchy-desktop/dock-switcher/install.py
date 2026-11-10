#!/usr/bin/env python3
"""Install the personal Omarchy dock and app switcher without resetting settings."""
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
PLUGINS = (
    ("macos.dock", "https://github.com/ifubaraboye/omarchy-dock.git"),
    ("zc.app-switcher", "https://github.com/charleszheng44/omarchy-alttab.git"),
)
BINDING = 'dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/zc.app-switcher/hyprland.lua")'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def apply_dock_patch(dock):
    patch = str(HERE / "dock.patch")
    def check(*args):
        return subprocess.run(["git", "apply", "--check", *args, patch], cwd=dock,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if check("--reverse"):
        print("Dock preferences already applied.", flush=True)
    elif check():
        run("git", "apply", patch, cwd=dock)
        print("Applied dock preferences.", flush=True)
    else:
        raise SystemExit("Dock source differs from the reviewed patch; no dock files were changed. "
                         "Review dock.patch against the installed plugin before enabling it.")


def main():
    if os.geteuid() == 0:
        raise SystemExit("Run as the desktop user, not root.")
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        raise SystemExit("Run from an active Omarchy session: enabling plugins requires its shell.")
    config = Path.home() / ".config"
    plugins = config / "omarchy/plugins"
    bindings = config / "hypr/bindings.lua"
    if not bindings.is_file():
        raise SystemExit(f"Omarchy bindings not found: {bindings}")
    for plugin_id, url in PLUGINS:
        if not (plugins / plugin_id).is_dir():
            run("omarchy", "plugin", "add", url, "--yes")
    apply_dock_patch(plugins / "macos.dock")
    text = bindings.read_text()
    if BINDING not in text.splitlines():
        with bindings.open("a") as output:
            output.write(("\n" if text.endswith("\n") else "\n\n") +
                         "-- Omarchy AltTab: app switching and current-app window cycling.\n" +
                         BINDING + "\n")
    for plugin_id, _ in PLUGINS:
        run("omarchy", "plugin", "enable", plugin_id)
    run("hyprctl", "reload")
    run("hyprctl", "configerrors")
    run("omarchy", "restart", "shell")


if __name__ == "__main__":
    main()
