# Omarchy dock and app switcher

From an active Omarchy session, run:

```sh
python3 ~/dotfiles/scripts/linux/omarchy-desktop/dock-switcher/install.py
```

This installs the current upstream `macos.dock` and `zc.app-switcher` plugins
when missing, enables them, and adds the switcher's Hyprland bindings without
replacing existing bindings. Alt-Tab switches apps; Alt-` cycles windows of
the current app. Shift reverses either direction. The dock's own competing
switcher bindings are disabled. Dock magnification, launch bounce, sliding,
and layout animations are disabled; the dock's existing pins and settings
are preserved. The shell restarts to load the changes.

The dock has no settings for these choices. `dock.patch` records the local
changes against the reviewed upstream source. The installer applies it only
when it cleanly matches, recognizes an already applied patch, and stops on
other changes rather than silently overriding them. Rerunning it is safe.
If a new upstream version changes the affected code, review and refresh the
patch before enabling the dock; a plugin update may also refuse to proceed
while its checkout contains these local modifications. Back up any additional
local edits before updating. Plugin updates are not automated by this installer.
