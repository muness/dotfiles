# BrowserOS neo alongside Chrome on Asahi

BrowserOS neo provides a persistent Chromium browser that external agents drive
over MCP. This recipe pins the official Linux ARM64 build to **0.51.2.3** and
verifies its SHA-256. It installs a separate browser/profile without changing the
default browser or importing Chrome's passwords, cookies, or history.

## Build and install on Arch Linux ARM

Use a machine with the normal Arch packaging tools (`base-devel`). Build as your
regular user, then elevate only the package installation:

```sh
mkdir -p ~/.cache/dotfiles/browseros-neo
cp ~/dotfiles/scripts/linux/vendor-packages/browseros-neo.PKGBUILD \
  ~/.cache/dotfiles/browseros-neo/PKGBUILD
cd ~/.cache/dotfiles/browseros-neo
makepkg --force
# Use the exact package filename printed by makepkg; compression is host-specific.
pkexec /usr/bin/pacman -U /absolute/path/to/browseros-neo-bin-VERSION-aarch64.pkg.tar.xz
```

The recipe retains the vendor sandbox and installs root-owned files through
pacman. It adds a **BrowserOS neo** launcher using native Wayland. Open that
launcher and review its additional terms yourself. Its profile is stored in
`~/.config/browser-claw`. Chrome remains separately installed.

## Connect Codex

In neo's new-tab dashboard, open **MCP** and use **Connect** beside Codex. This
registers the endpoint and may install the upstream browser skill. Alternatively,
copy the exact endpoint shown by that running build and register it manually:

```sh
codex mcp add browseros-neo --url http://127.0.0.1:PORT/mcp
codex mcp get browseros-neo
```

Replace `PORT` with the displayed port. On the qualified installation the
one-click setup registered `9010`; its backend also listened on `9210`. Do not
assume those ports on another build. Restart Codex to load the tools, keep neo
running, and verify that an agent can list tabs and read a harmless page. A
configured MCP entry or installed skill alone does not prove tools are loaded
in an existing chat.

## 1Password desktop integration

Install the official [1Password extension](https://chromewebstore.google.com/detail/aeblfdkhhhdcdjpifhhbdiojplfjncoa)
in neo, confirming **Add extension** in the browser. A working 1Password desktop
installation is required for desktop/fingerprint unlocking.

Follow [1Password's additional-browser instructions](https://support.1password.com/additional-browsers/):
quit neo, add `browserclaw` on its own line in
`/etc/1password/custom_allowed_browsers`, preserving existing entries, and restart
and unlock 1Password. The narrowly scoped helper backs up the allowlist before
adding the entry, requires a root-owned system browser, and is safe to rerun:

```sh
pkexec /usr/bin/python3 ~/dotfiles/scripts/linux/trust-browseros-1password.py
```

Neo also needs the native messaging manifest. If Chrome's existing 1Password
desktop integration works, copy only its host manifest (not its profile):

```sh
mkdir -p ~/.config/browser-claw/NativeMessagingHosts
cp -n ~/.config/google-chrome/NativeMessagingHosts/com.1password.1password.json \
  ~/.config/browser-claw/NativeMessagingHosts/
```

If that source is absent, locate the manifest installed by your 1Password
package. Its `path` must point at the installed `1Password-BrowserSupport` helper;
on this host that is `/opt/1Password/1Password-BrowserSupport`. Reopen neo and test
unlocking from the extension. Do not copy vault data or sign-in secrets into
this repository.

## Verified behavior and updates

On 2026-10-23, the ARM64 package launched on Asahi/Arch with Hyprland 0.56.2.
MCP initialization and tab listing succeeded. The 1Password helper logged
successful browser verification and a desktop-app connection, and the user
confirmed unlocking worked. This did not establish a speed advantage over Chrome.

Updates are manual: review a new official release, update the recipe's version
and SHA-256, rebuild and install with pacman. Do not rely on a browser self-updater
to replace system-owned files. To remove the package, use
`pkexec /usr/bin/pacman -R browseros-neo-bin`; retain or remove the profile
separately. Use `codex mcp remove browseros-neo` to remove the Codex connection.
Remove only the `browserclaw` line from 1Password's allowlist if it is no longer
needed.
