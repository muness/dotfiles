# One-password session unlock

Log in to Linux with Touch ID, then unlock 1Password once after boot. Keep
1Password running: quitting or updating it requires its account password again.
These helpers never store the 1Password account password.

## Installed flow

- The login helper retrieves the existing keyring password from 1Password and
  unlocks the existing `Default keyring` collection through GNOME's private
  `UnlockWithMasterPassword` API. It does not create or rename a keyring.
- Opening Waydroid or Authenticator starts `session-unlock-android.service`.
  It waits for Android to boot and watches for supported platform PIN prompts.
- The Touch ID prompt is a centered floating overlay, rather than a tiled
  window. It waits for a busy reader to become available before starting a scan.
- A fresh fingerprint match authorizes submission of the saved Android PIN
  directly to the credential window. No host keyboard events or clipboard are
  used. Supported paths are the primary-user keyguard and SystemUI credential
  fallback. The existing weak biometric HAL remains installed for other checks.
- Cancellation or failed authentication stops the monitor without resubmitting
  the PIN. Opening Waydroid again explicitly starts it again. Failed matches
  are not automatically retried.
- Closing the Waydroid window leaves Android running. The full shutdown launcher
  stops the monitor first. The root helper exits with its user caller and cleans
  up its Android UI process, rather than leaving an orphaned observer behind.

## Credentials and boundaries

The `Asahi session unlock` Secure Note contains concealed keyring-password and
Android-PIN fields entered through a local masked form. Configuration at
`~/.config/session-unlock/config.json` contains only references and the collection
path, with permissions 0600. Edit the vault item when either credential changes.

Credentials travel in memory, local D-Bus for the keyring, and private pipes for
Android. They are never placed in argv, environment variables, temporary files,
clipboard contents, or logs. Python memory/core dumps are disabled. The host
account and root remain trusted; this is not phone-grade hardware-backed
biometric authentication and does not manufacture strong biometric tokens.

The root-owned `/usr/local/libexec/asahi-session-unlock` accepts only fixed
probe, submit and watch operations using its installed dex, not arbitrary code
paths or commands. A dedicated polkit action is granted only to the configured
active local desktop user. GNOME's private collection API and the inspected
Android 16 AuthSession completion evidence may need updates after OS changes.

## Installation

For a new setup, run `unlock.py --setup` once from this directory with the
system Python. It asks for a destination vault and the existing credentials.
It refuses to duplicate an already-configured vault item.

For updates, compile `CredentialUi.java` with Java 8 bytecode compatibility and
D8, then run:

```sh
pkexec /usr/bin/python3 scripts/linux/session-unlock/host-setup.py "$USER" \
  "$HOME/.cache/session-unlock/build/classes.dex"
/usr/bin/python3 scripts/linux/session-unlock/install.py
/usr/bin/python3 scripts/linux/waydroid/install-launchers.py
systemctl --user daemon-reload
```

User runtime files live in `~/.local/lib/session-unlock/`. The keyring login
entry is `~/.config/autostart/session-unlock.desktop`. The Android monitor is
started by the Waydroid wrapper, not continuously enabled at desktop login.
The floating-window rule is in `~/.config/hypr/looknfeel.lua`.

2026-11-04: the vault-backed keyring unlock, actual Android keyguard unlock,
and a platform strong-or-PIN credential request completed. Automatic cold launch
exposed a shared-reader conflict; reader availability handling and root-child
cleanup were subsequently corrected and installed. A full desktop boot and a
real Microsoft approval after these final fixes have not been independently
observed. No further synthetic prompts or test restarts are being run at the
user's request.

## Removal

Stop the monitor and remove its user unit, keyring autostart entry and local
helper files. Remove the following root-owned files with administrator
authentication:

- `/etc/polkit-1/rules.d/49-dotfiles-waydroid-credentials.rules`
- `/usr/share/polkit-1/actions/org.dotfiles.waydroid.credentials.policy`
- `/usr/local/libexec/asahi-session-unlock`
- `/usr/local/lib/asahi-session-unlock/`
- `/usr/local/share/asahi-session-unlock/`

The vault item, keyring, Android accounts and PIN, and host fingerprint
enrollments remain unchanged.
