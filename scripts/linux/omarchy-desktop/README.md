# Omarchy alongside COSMIC

This local package uses Omarchy Mac commit `ba546a61f881c1fe9d79d75ec050eab048b8cb63` (4.0.3rc4). It supplies a Hyprland/Quickshell session while COSMIC Greeter, Arch repositories, Aurora, TLP and the existing memory protection remain managed independently.

It omits upstream system provisioning, migrations, pacman hooks, global environment changes, boot configuration and `/etc/skel` seeding. Most upstream system-management commands remain disabled. The menu offers monitor, keybinding and input configuration, plus Arch package installation and a full system package update using pacman and graphical polkit authentication. Read-only package and disk queries are also available. These controls do not run Omarchy migrations or manage Aurora's boot stack. Themes affect the Omarchy desktop and Foot, rather than browser/editor/COSMIC preferences. The microphone remapping is omitted.

The standard `omarchy` command router is available, including `omarchy plugin
add`, `list`, `enable`, `disable`, `update` and `remove`. It routes to the same
installed helpers; the restricted system-management helpers remain disabled.

The local package also renames the theme singleton to `ThemeColor`: Qt 6.12's built-in `QtQuick.Color` otherwise shadows the original `Color` singleton and leaves the shell unthemed. It includes `qt6-imageformats` for the shipped WebP backgrounds. Omarchy autostart explicitly finalizes UWSM before starting session services.

## Build and install

Obtain a clean checkout of the pinned source. `prepare.py` verifies its commit and working tree; it never runs the upstream installer.

```sh
mkdir -p ~/.cache/dotfiles/omarchy-desktop/build
cp ~/dotfiles/scripts/linux/omarchy-desktop/PKGBUILD ~/.cache/dotfiles/omarchy-desktop/build/
cd ~/.cache/dotfiles/omarchy-desktop/build
OMARCHY_DESKTOP_RECIPE="$HOME/dotfiles/scripts/linux/omarchy-desktop" \
OMARCHY_DESKTOP_SOURCE=/absolute/path/to/pinned/omarchy-mac \
  makepkg --nodeps --force
# Use the exact package path emitted by makepkg (compression follows makepkg.conf).
pkexec /usr/bin/python3 ~/dotfiles/scripts/linux/omarchy-desktop/install-host.py /absolute/path/to/package
python3 ~/dotfiles/scripts/linux/omarchy-desktop/configure-user.py
```

If upgrading the package during an active Omarchy session, reload Hyprland and
restart the shell after installation: `hyprctl reload && omarchy-restart-shell`.
Pacman temporarily replaces the shell's files during the upgrade; the running
shell can otherwise retain a failed configuration reload. Do not restart the
shell while the session is locked.

`install-host.py` takes a root Btrfs snapshot, performs a normal full Arch upgrade with the desktop dependencies, installs the local package and verifies the Aurora package versions, holds, boot image and Apple HID modules. `configure-user.py` backs up and replaces only `~/.config/{hypr,omarchy,foot}` and the Hyprland-specific UWSM environment, then seeds the initial theme. It does not copy the whole upstream user skeleton. Use it deliberately: rerunning resets those three config directories again.

Lock PAM services are staged as templates; installation preserves an existing service and creates only missing ones. In particular, the existing fingerprint service on this host predates this integration and is retained.

The separate `../omarchy-host-setup.py` adds fingerprint-first login with password fallback, supplies the previously absent COSMIC lock PAM service, adds early Apple input modules, selects TLP performance on AC/balanced on battery, and configures RAM-sized zram. It preserves existing governor settings, earlyoom, disk swap and package holds. Its root backups include the old initramfs. Do not rerun just to change a single setting; edit/reapply that setting independently.

## Login and verification

Log out normally and choose **Omarchy** at COSMIC Greeter. No greeter restart or forced logout is performed by these scripts. `Super+Return` opens Foot, `Super+B` the existing default browser, `Super+E` Nautilus, and `Super+Space` the Omarchy menu. Use the system menu to log out and select COSMIC again.

Check password and fingerprint authentication separately, including after resume. COSMIC login and lock offer fingerprint authentication before password; after three failed scans or a ten-second timeout, password authentication uses the original stack. Omarchy's lock has separate password/fingerprint flows. Fingerprint success does not supply a password to decrypt a password-protected login keyring.

The sleep-lock monitor starts only from Omarchy autostart, is stopped with `graphical-session.target`, and is not globally enabled. Verify that it and the Omarchy shell are stopped after returning to COSMIC. Test portals/screen sharing, notifications, built-in and external displays, charger changes and suspend/resume on the real session. Config parsing and nested UI checks do not qualify all these hardware paths.

The HID change needs a reboot to prevent the startup race. RAM-sized zram is a logical capacity, not reserved physical memory; zstd and priority 100 remain in use, ahead of the existing priority-10 disk swap. Earlyoom still intervenes independently of free swap.

`python3 scripts/linux/omarchy-desktop/check-shell.py` renders the shell and opens its menu on a private headless Sway server under bubblewrap. Home, process namespace, runtime directory and D-Bus are isolated from the active session. Its screenshot/log paths are printed; inspect the image as well as the error checks. Missing system services inside that test are intentional. It tests rendering and menu IPC, not Hyprland's real hardware session, portals or suspend. A native nested Hyprland test against COSMIC was blocked by a parent Wayland protocol-version mismatch.

On 2026-10-21, fingerprint authentication and account validation succeeded through the live `login` PAM service without collecting a password or starting a session. Password fallback configuration was checked structurally; actual greeter interaction and post-resume behavior remain physical-session checks.

## Rollback

The host backup lives under `/var/lib/dotfiles/backups/omarchy-host-TIMESTAMP`; restore the changed files from it as root and remove only the files listed in `originally-absent.txt` that belong to this change. The original initramfs is included. Reload systemd and TLP after restoring their settings. Restore the old zram configuration at next boot if it is currently in use.

The user setup enables window resizing by dragging borders without holding Super in `~/.config/hypr/looknfeel.lua`. Super + right-click drag also resizes windows; Super + left-click drag moves them.

Three-finger horizontal trackpad swipes switch workspaces, configured in `~/.config/hypr/input.lua`.

User configuration backups live under `~/.local/state/dotfiles/omarchy-backups/TIMESTAMP`. Restore the backed-up `hypr`, `omarchy`, `foot` and UWSM environment, removing newly created paths recorded in `originally-absent.json`. Preserve any new customizations first.

Select COSMIC before removing `omarchy-desktop-cosmic` with pacman. Its dependencies are ordinary repository packages; do not bulk-remove shared dependencies. The `pre-omarchy-desktop-*` root snapshot is a separate recovery option, not an automatic rollback of home or EFI. No reboot or snapshot restoration is automated here.

Desktop updates require rebuilding this pinned package after reviewing a new source revision. The upstream Omarchy updater is intentionally unavailable in this integration.
