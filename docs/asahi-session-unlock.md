# One-password session unlock

The login helper retrieves the existing GNOME keyring password from 1Password
and unlocks the existing `Default keyring` collection. Unlock 1Password after
boot and keep it running; the helper does not store its account password.

Run `/usr/bin/python3 scripts/linux/session-unlock/unlock.py --setup` to create
the vault reference, then `/usr/bin/python3 scripts/linux/session-unlock/install.py`
to install the login helper. Configuration lives in
`~/.config/session-unlock/config.json`, and the login entry lives in
`~/.config/autostart/session-unlock.desktop`.
