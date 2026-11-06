# Omarchy with COSMIC Greeter

This local package follows the newest release of `omacom/omarchy`, including
release candidates. `update.py` resolves the release on every update; there is
no hardcoded source revision. It supplies a Hyprland/Quickshell session while
COSMIC Greeter, Arch repositories, Aurora, TLP and memory protection remain
managed independently.

It omits upstream system provisioning, migrations, pacman hooks, global environment changes, boot configuration and `/etc/skel` seeding. Most upstream system-management commands remain disabled. The menu offers monitor, keybinding and input configuration, plus Arch package installation and a full system package update using pacman and graphical polkit authentication. Read-only package and disk queries are also available. These controls do not run Omarchy migrations or manage Aurora's boot stack. Themes affect the Omarchy desktop and Foot, rather than browser/editor/COSMIC preferences. The microphone remapping is omitted.

The standard `omarchy` command router is available, including `omarchy plugin
add`, `list`, `enable`, `disable`, `update` and `remove`. It routes to the same
installed helpers; the restricted system-management helpers remain disabled.

Ordinary dependency installation works through `omarchy pkg add PACKAGE` and
`omarchy pkg aur add PACKAGE`, including calls from shell plugins. Repository
installs use pacman with graphical polkit authentication. AUR installs use yay
as the session user and pkexec only for its pacman transactions, with normal
package review and confirmation prompts. No agent or reviewed custom installer
is required to install an app. Omarchy OS provisioning and migrations remain
disabled because this is an additional desktop on the existing Arch system.

The local package also renames the theme singleton to `ThemeColor`: Qt 6.12's built-in `QtQuick.Color` otherwise shadows the original `Color` singleton and leaves the shell unthemed. It includes `qt6-imageformats` for the shipped WebP backgrounds. Omarchy autostart explicitly finalizes UWSM before starting session services.

The scratchpad uses Hyprland's `workspace.created` event to launch the configured agent when an empty scratchpad is first opened, replacing the deprecated `on_created_empty` workspace rule.

The lock service avoids a stale `WlSessionLock.locked` binding in Quickshell
0.3.2. Lock requests consult the current request and compositor acknowledgement,
so unlocking cannot cause a later pre-suspend lock to be skipped. The sleep
monitor still requires `secure=true` before declaring the screen locked.
`python3 scripts/linux/omarchy-desktop/check-lock.py` exercises three real
lock/unlock cycles on an isolated headless Sway compositor, without affecting
the active session. Its temporary authentication bypass exists only in that
private test copy; no test IPC method is installed in the desktop shell.

## Build and install

Run as the desktop user:

```sh
/usr/bin/python3 ~/dotfiles/scripts/linux/omarchy-desktop/update.py
# Or use Omarchy > Update > Omarchy & System Packages.
# Preview: update.py --check. Build without installing: update.py --build-only.
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

Public Wi-Fi sign-in uses upstream [Foyer](https://github.com/tektum/foyer)
plus the user-owned `omarchy-captive-portal.service`. Foyer is installed from a
latest checksum-verified Linux ARM64/AMD64 release into `~/.local/libexec`. It launches
an isolated incognito Chrome/Chromium window through a local SOCKS proxy.
Both DNS and portal connections bind to the selected Wi-Fi interface, leaving
system DNS, routes, and the normal browser profile alone.

The listener watches each Wi-Fi device separately. A working USB tether cannot
hide a detected portal or complete Wi-Fi sign-in. A pinned tray icon titled
**Wi-Fi sign-in needed: NETWORK** stays available after closing the browser and
through temporary limited/unknown connectivity. Clicking it focuses the existing
window or opens another after it has closed. It clears when that Wi-Fi has full
connectivity with no family still reporting a portal, disconnects, or changes
active connection. While pending, NetworkManager is asked to recheck every ten
seconds; its machine-wide answer is not used to retire the Wi-Fi warning.

The **Wi-Fi Sign-in** app launcher also opens the active Wi-Fi's sign-in window
manually, including when automatic detection missed a portal. If Wi-Fi already
has full connectivity, it reports that no sign-in is needed instead of opening
a raw probe page. CLI equivalents:

```sh
~/.local/libexec/omarchy-captive-portal --open
~/.local/libexec/omarchy-captive-portal --status
```

To install or update without resetting desktop configuration:

```sh
/usr/bin/python3 ~/dotfiles/scripts/linux/omarchy-desktop/install-captive-portal.py
systemctl --user status omarchy-captive-portal.service
```

Installation downloads and verifies Foyer before changing the listener. It adds
only the Wi-Fi sign-in tray pin to the existing shell layout, keeping a
`shell.json.before-wifi-signin` backup. It starts via Hyprland XDG autostart and
stops with the graphical session. No root authentication or shell restart is
needed. Dependencies: `python-gobject`, `python-dbus`, `libnm`, NetworkManager,
and an installed Chromium-family browser (Google Chrome on this machine).
Listener and Foyer logs: `journalctl --user -u omarchy-captive-portal.service`.

Regression checks:

```sh
/usr/bin/python3 -m unittest discover -s scripts/linux/omarchy-desktop -p test_captive_portal.py -v
```

Verified on 2026-11-04: Foyer's real proxy returned HTTP/HTTPS 204 through
`wld0`; syscall tracing showed DNS to the airport resolver and outbound sockets
bound to Wi-Fi. A negative check bound to `lo` timed out despite working system
internet, rejecting a proxy that silently falls back to the default interface.
Real Chrome launch, repeat-click focus without duplicate windows, and clean
window closure were exercised. A later browser-content regression exposed
Chrome 157 blocking the proxy itself under Foyer's DNS rule, followed by an
HTTPS-only interstitial for the HTTP probe. The disposable browser wrapper now
excludes `127.0.0.1` from the DNS rule and disables HTTPS upgrading/Incognito
HTTPS-first only for that temporary profile. Certificate verification remains
in effect. A real headless Chrome run through the installed Foyer wrapper
verified rendered probe content with neither error. The listener resolves
portal redirects on Wi-Fi before launching, preferring the actual login URL. The current airport session was already
authenticated; a fresh Boingo consent flow with USB tethering still needs a
live captive-network check. Tests cover pending state despite unrelated full
connectivity, browser exit/reopening, limited/unknown states, and connection
switches.

Log out normally and choose **Omarchy** at COSMIC Greeter. No greeter restart or forced logout is performed by these scripts. `Super+Return` opens Foot, `Super+B` the existing default browser, `Super+E` Nautilus, and `Super+Space` the Omarchy menu. The COSMIC desktop is not installed; COSMIC Greeter remains the login screen.

Check password and fingerprint authentication separately, including after resume. COSMIC Greeter offers fingerprint authentication before password; after three failed scans or a ten-second timeout, password authentication uses the original stack. Omarchy's lock has separate password/fingerprint flows. Fingerprint success does not supply a password to decrypt a password-protected login keyring.

The sleep-lock monitor starts only from Omarchy autostart, is stopped with `graphical-session.target`, and is not globally enabled. Test portals/screen sharing, notifications, built-in and external displays, charger changes and suspend/resume on the real session. Config parsing and nested UI checks do not qualify all these hardware paths.

The HID change needs a reboot to prevent the startup race. RAM-sized zram is a logical capacity, not reserved physical memory; zstd and priority 100 remain in use, ahead of the existing priority-10 disk swap. Earlyoom still intervenes independently of free swap.

`python3 scripts/linux/omarchy-desktop/check-shell.py` renders the shell and opens its menu on a private headless Sway server under bubblewrap. Home, process namespace, runtime directory and D-Bus are isolated from the active session. Its screenshot/log paths are printed; inspect the image as well as the error checks. Missing system services inside that test are intentional. It tests rendering and menu IPC, not Hyprland's real hardware session, portals or suspend. A native nested Hyprland test against COSMIC was blocked by a parent Wayland protocol-version mismatch.

On 2026-10-21, fingerprint authentication and account validation succeeded through the live `login` PAM service without collecting a password or starting a session. Password fallback configuration was checked structurally; actual greeter interaction and post-resume behavior remain physical-session checks.

## Rollback

The host backup lives under `/var/lib/dotfiles/backups/omarchy-host-TIMESTAMP`; restore the changed files from it as root and remove only the files listed in `originally-absent.txt` that belong to this change. The original initramfs is included. Reload systemd and TLP after restoring their settings. Restore the old zram configuration at next boot if it is currently in use.

The user setup enables window resizing by dragging borders without holding Super in `~/.config/hypr/looknfeel.lua`. Super + right-click drag also resizes windows; Super + left-click drag moves them.

Three-finger horizontal trackpad swipes switch workspaces, configured in `~/.config/hypr/input.lua`.

User configuration backups live under `~/.local/state/dotfiles/omarchy-backups/TIMESTAMP`. Restore the backed-up `hypr`, `omarchy`, `foot` and UWSM environment, removing newly created paths recorded in `originally-absent.json`. Preserve any new customizations first.

Install or select another working desktop session before removing `omarchy-desktop-cosmic` with pacman. Its dependencies are ordinary repository packages; do not bulk-remove shared dependencies. The `pre-omarchy-desktop-*` root snapshot is a separate recovery option, not an automatic rollback of home or EFI. No reboot or snapshot restoration is automated here.

The installed `omarchy update` and Update menu resolve, build and install the
newest upstream release, and run the normal pacman system upgrade. Personal
configuration is preserved. The recipe and updater ship inside the package,
so future releases do not require editing dotfiles or changing a revision.
The weekly updater notifies about new Omarchy releases. Plain `pacman -Syu`
updates repository dependencies but cannot fetch/rebuild this local Git package;
use `omarchy update` for both. Upstream OS provisioning and migrations remain
excluded from this desktop integration.
