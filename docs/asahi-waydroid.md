# Waydroid on Arch ARM / Asahi

Optional Android setup for the native Apple Silicon workstation. Run as the
desktop user, after installing the running kernel's matching headers:

```bash
scripts/linux/waydroid.sh --check
scripts/linux/waydroid.sh
```

The installer elevates individual steps with graphical polkit authentication.
Use `--sudo` for terminal authentication instead. It does not refresh pacman's
databases; update the host normally before installing if its package databases
are stale. A kernel update requires booting that kernel and matching headers
before building Binder. It does not replace the Aurora kernel or boot stack.
Existing Waydroid configuration, images and Android data are preserved; no
forced initialization or image upgrade is performed.

## Open and fully shut down Android

Open **Waydroid** from the app launcher. To stop Android and its system container,
choose **Shut Down Waydroid**. Normal starts and stops need no sudo, Touch ID,
or password after the one-time service-permission installation. The
Waydroid launcher also has a **Shut Down Completely** desktop action, where
supported by the launcher. Closing the Android window with the window manager
only hides it; the explicit shutdown launcher performs the complete stop.

To install or refresh only these user controls, without touching Android:

```bash
scripts/linux/waydroid.sh --launchers-only
```

For an existing installation, install the service permission and refresh the
launchers (one graphical authentication prompt):

```bash
scripts/linux/waydroid.sh --service-controls-only
```

The polkit rule grants only the selected active local desktop user permission
to start and stop `waydroid-container.service`. It does not grant permission for
other services or for enabling/disabling units. The full installer includes this
step. To revoke the permission, remove
`/etc/polkit-1/rules.d/49-dotfiles-waydroid.rules` with administrator privileges.

The installed `~/.local/bin/waydroid` wrapper and desktop launcher explicitly use
`/usr/bin/python3`, because mise's Python cannot import the distribution's
`dbus`, `gi` and `gbinder` modules. The wrapper also supports ordinary commands
such as `waydroid status`. Launch commands ensure the container service is
started before starting Android. The shutdown control stops the session, uses
the scoped service permission to stop `waydroid-container.service`, and checks
that the service is inactive before showing a success notification. A denied or failed stop produces
an error notification. It does not disable the service at boot.

## Pinned inputs and prerequisites

The kernel requires Binder; this Aurora build did not enable it. The included
DKMS recipe derives from [binder_linux-dkms in AUR](https://aur.archlinux.org/packages/binder_linux-dkms)
7.1-3, using [choff/anbox-modules](https://github.com/choff/anbox-modules)
commit `4d68f90e11992601e8072bcbf6dcd6ca603364a9`. The former PR 29 compatibility
patch is incorporated upstream. The archive hash is checked by makepkg. Review and update the recipe if a
future kernel requires changes. Builds use matching kernel headers and `lld`;
without `lld`, compilation finishes but linking fails with `ld.lld: command not
found`. Package hooks may warn about a failed DKMS build without failing pacman,
so setup checks the build, module loading and all three Binder device nodes.

Standard ARM images are insufficient for this 16 KB-page host. The installer
uses the community [HLM319 Asahi Android 16 images, release 23.2_2026-05-30](https://github.com/HLM319/waydroid_asahi_patches/releases/tag/23.2_2026-05-30).
These are experimental community images; their publisher describes unreviewed
AI-generated patches. They are not official Waydroid images. No Google Apps
or app-compatibility guarantees are added by this setup.

| Archive | SHA256 |
| --- | --- |
| system.img.tar.zst | `8d5beb8afb75db3a0bfbf5e0e587ea18025da6e82d3025e7b11241ca24262602` |
| vendor.img.tar.zst | `f828df7dd4d86ec1687725a9d830095e9f4675b72d34ef95f8c079b79ee82fae` |

Archives and extracted images remain under `~/.cache/dotfiles/waydroid`, outside
Git. Allow several GB for cached/extracted images plus the installed copies.
Both archives are verified and extracted before root installs complete image
files and initializes Android. Never start Android during image extraction:
a partial image produced `EXT4-fs: bad geometry` during the initial manual setup.

## Observed working — 2026-10-23

On Arch Linux ARM / Omarchy, Aurora kernel
`7.1.12-2-20261017.20-sep-ARCH`, 16 KB pages, Mesa 26.2.5 and Waydroid 1.6.3:

- Binder DKMS built and loaded, exposing binder, hwbinder and vndbinder.
- Android 16 completed boot (`sys.boot_completed=1`), UI opened, and outbound
  networking worked.
- The user confirmed the Roon Android app worked and discovered Roon Core.
- Shared storage mounted. App downloads and general app writes on Btrfs were
  not independently tested; a mount alone does not prove those work. Investigate
  app-specific write failures before considering an ext4 data migration.
- Touch ID succeeded through polkit on retry. Earlier capture errors were
  transient; no PAM, polkit policy, or fingerprint changes were made.

Verification for the repository changes:

```bash
/usr/bin/python3 scripts/linux/waydroid/test_shutdown.py
bash -n scripts/linux/waydroid.sh scripts/linux/waydroid/launch
shellcheck scripts/linux/waydroid.sh scripts/linux/waydroid/launch
```

A fresh end-to-end installation and an interactive shutdown remain manual
acceptance checks. The repository checks must not interrupt an active Android
session just to exercise its shutdown control.

## Ika trial on Asahi (2026-11-05)

[Ika 261101](https://github.com/DesktopECHO/ika/releases/tag/261101) was tried
alongside Waydroid as a possible replacement for Microsoft Authenticator. Its
native Arch ARM64 packages booted Android in a Cuttlefish VM on the 16 KiB
Aurora kernel `7.2.11-14-1.536-ARCH`. The installer enables
`cuttlefish-host-resources.service` and adds the user to `kvm`, `render`,
and `cvdnetwork`. A new login session needs those groups before launch.

- The host rebooted abruptly during installation. The first `ika start` had
  already exited because the groups were missing from the active session.
  The install log ended shortly after loading `vhost_net` and `vhost_vsock`.
  No panic trace survived, so the cause is unknown.
- The next start found an incomplete VM disk. Moving it aside allowed a fresh
  VM to boot, and the old directory was later moved to Trash.
- Google sign-in attempts coincided with repeated host-side `run_cvd`
  aborts while Linux stayed up. A run using `guest_swiftshader` also aborted
  after opening Play Store. The first failing component is unknown, and
  Authenticator was never validated in Ika.
- During the trial, the ChatGPT desktop window repeatedly reloaded. A kernel
  trace caught a Chromium realtime audio thread receiving `SIGKILL`. The
  leading explanation was that Cuttlefish's login rule let desktop processes
  request realtime priority even though they had a zero realtime CPU budget.
  Ika was removed, and the inherited realtime privilege was cleared from
  affected desktop processes. See [Fix ChatGPT Linux GUI restarts](thread://01a1ac70-884e-7cd3-9ce0-80537055f337?hostId=local).
- The [release history](https://github.com/DesktopECHO/ika/releases) and
  [GitHub Actions](https://github.com/DesktopECHO/ika/actions) had no newer
  Arch ARM64 package or downloadable CI build at the time. No public issue
  or PR confirmed a fix for this crash.

Keep using Waydroid for Authenticator and revisit Ika after a newer Arch ARM64
release. Try Google sign-in before moving any Authenticator accounts. If the
VM aborts again, copy `~/ika/cuttlefish/instances/cvd-1/logs/launcher.log`
before restarting so the next launch does not overwrite the failing run.

### Realtime scheduling on the next trial

Inspect the new host package for `/etc/security/limits.d/1_cuttlefish.conf`.
If it still grants `rtprio` to `@cvdnetwork`, omit those two lines from the
package before installing. Keep the group and its `nofile` limits. Treat an
upgrade as a fresh check since it could restore the login rule.

Try Ika with ordinary scheduling first. After a fresh login, check
`/proc/<pid>/limits` for the ChatGPT and Chrome processes. A positive
`Max realtime priority` alongside a zero `Max realtime timeout` is the
combination to avoid. If the VM actually needs realtime scheduling, grant
priority and a finite CPU-time budget only to its host processes through a
system service that runs them as an unprivileged user. Verify the limits
on the actual VM processes and on the desktop apps before using that setup.
