# Framed Omarchy authentication dialog

Personal clone of `omarchy.polkit` from Omarchy Mac commit `ba546a61f881c1fe9d79d75ec050eab048b8cb63` (local desktop package 4.0.3rc4-2). Upstream MIT license retained.

The change is presentation only: one framed card with a heading, action description, fingerprint/password status, Cancel, and an explicit password Authorize button. Fingerprint and password modes retain one consistent width. Long descriptions wrap. Colors and controls inherit the installed Omarchy theme, including `[polkit]` overrides. The frame remains visible even when a theme suppresses ordinary surface borders.

The original PAM parsing, lid detection, Polkit flow, password submission/clearing, error feedback, and Escape cancellation are preserved. Passwords are never logged. No PAM or authorization policies were changed. `manifest.json` declares `omarchy.clonedFrom`, so enabling this clone disables the built-in agent; disabling the clone restores it.

## Install / rollback

Run `./install-local.sh` in the Omarchy session. Existing local clones are refused to preserve edits. A shell.json backup is created before activation. The shell must be unlocked; installation restarts only the shell so registration completes cleanly.

Rollback without deleting source:

```sh
omarchy-shell shell setPluginEnabled muness.polkit false
omarchy-restart-shell
```

Allow the agent a moment to register before using pkexec. Shell ping being available does not mean the Polkit plugin has registered yet.

## Verification — 2026-10-21

`/usr/bin/python3 preview.py` renders fingerprint, password, and failure states under private headless Sway with mock flow state. It registers no real agent and receives no credentials. All three states rendered without QML loading/type/reference errors; previews were visually inspected. The design detector reported no findings. Live `pkexec /usr/bin/true` succeeded after agent registration. Real failed-fingerprint/password-entry scenarios have not been deliberately induced; those states were previewed with mocks. Manual Cancel/Escape remains a user acceptance check.
