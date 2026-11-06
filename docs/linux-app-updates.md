# Linux application updates and pin audit

Run `bash ~/dotfiles/scripts/linux/vendor-apps.sh` for the default manual app
installation/update path. `--check` reports candidates without installing;
append app names to select a subset. Bootstrap and weekly update checks use
this same entry point. Installers resolve upstream builds on every invocation.

| App | Update source and installation |
| --- | --- |
| ChatGPT, Chrome, Claude Desktop | Current vendor package indexes; native binaries repackaged for pacman on Arch. Fedora uses ChatGPT/Chrome vendor RPM repositories. |
| Codex | Latest stable upstream native bundle, repackaged for pacman. |
| BrowserOS neo | Highest stable native ARM64 installer build, including maintenance installers published under an older release tag. |
| Tether | Latest compatible stable GitHub AppImage with upstream SHA-256; refreshes its user service and launcher. |
| 1Password | Stable vendor tarball on Arch/ARM64; stable RPM repository on Fedora x86_64. Tarball checks compare the vendor ETag to the last successfully installed build. An existing installation without a recorded ETag reports that it needs refreshing, not that a newer version is proven available. |
| Zed | Latest stable native release and upstream SHA-256, installed with the vendor's integration script. |
| Bazecor | Latest stable upstream source, built natively for ARM64 or x64 using that release's lockfile and CI-declared Node major (latest patch). No x64 AppImage on ARM64. |
| HQPlayer Desktop 5 | Current native vendor download for the licensed **product 5**. Resolves the vendor download form, including package revision; does not switch to the separately licensed product 6. |
| HQPlayer Embedded | Newest native RPM in the vendor's Fedora 44 ABI feed; repackaged for pacman, preserves configuration and service state. ARM64 uses the actual aarch64 build. |
| Hyprmoncfg | Latest stable native GitHub release with upstream SHA-256, repackaged for pacman. |
| Omarchy desktop | Installed desktop release updater, preserving personal configuration; includes upstream release candidates as in the existing desktop policy. |
| Foyer | Latest stable native GitHub release with upstream SHA-256; stable executable link avoids a version in the portal listener. |
| Wine/FEX, DXVK, VKD3D, Mono, Gecko | Existing publisher `lacamar/wine-arm64ec-rpm`, `arch-repo` feed. Native aarch64 packages are verified against GitHub release SHA-256 and installed together. The publisher now supplies `-git` names for several installed packages; the check prints those name/channel migrations explicitly. |

The specialized Bazecor, HQPlayer, Hyprmoncfg, Foyer, Omarchy and Wine/FEX paths join the
no-argument default when their installations are detected. Named selections can
install them explicitly. They are not imposed on every fresh workstation.

The weekly job checks the same default app set and notifies about available
updates. It installs updates only for existing user-owned Tether, Zed and Foyer
through `vendor-apps.sh --user-only`. System-wide installs use graphical polkit
authentication. Flatpak and mise retain their own weekly updates. A cancelled
polkit prompt stops the manual updater before another app can request it again.

Signalyst does not publish a checksum index for these downloads. HQPlayer comes
from validated HTTPS vendor URLs; the updater computes and records a local
SHA-256 for packaging. That checksum checks local integrity, not an independent
vendor signature. The 1Password tarball likewise retains its vendor HTTPS trust
model; its ETag identifies a build, not a cryptographic authenticity guarantee.

## Pin audit — 2026-11-05

Remaining fixed hardware/source inputs:

- `scripts/linux/aurora.sh`: `aurora-2026.10.17.20` and installer checksum.
  `aurora.sh --check` currently finds the same latest published stable release.
  This installer manages kernel, bootloader and Touch ID components.
- `/etc/pacman.conf`: upstream Aurora exclusions for `linux-aurora`,
  `linux-aurora-headers`, `libfprint`, `m1n1-aurora`. Ordinary pacman upgrades
  deliberately do not replace this bundle. The desktop installer preserves
  those exclusions. Update the reviewed Aurora installer as a coherent stack.
- `scripts/linux/waydroid/PKGBUILD`: binder source commit
  `4d68f90e11992601e8072bcbf6dcd6ca603364a9`, with local compatibility patches.
  `check-desktop-updates.sh` checks its upstream HEAD, which currently matches.
- `scripts/linux/waydroid.sh`: initial Asahi Android images from
  `23.2_2026-05-30`, with system/vendor checksums. These apply only when
  initializing an installation; rerunning preserves existing Android data.
- Installed `linux-aurora-ci`/headers: separately installed CI snapshot
  `7.2.11.aurora14-1.536`; not a floating feed or part of ordinary app updates.
  `aurora-touchid` is also part of the separately managed hardware integration.

`scripts/linux/hqplayer-distrobox.sh` selects Debian 13 as a compatibility base
image and accepts an explicitly supplied vendor package; this is a runtime OS
constraint, not a selected HQPlayer application version. Android Binder protocol
hashes and API numbers likewise describe compatibility, not update channels.

Foyer's former hardcoded 0.1.0 application pin was removed. Its current upstream
release happens to remain 0.1.0. Other app versions shown in caches and desktop
launchers record installations; they are not update selection pins.

All entries in the shared mise config track `latest`, except Java's floating
`temurin` vendor channel. Rust tracks `stable`. Neither user nor system Flatpak
has update masks. `flatpak pin` prevents unused-runtime removal; it does not
freeze an application's version. Pacman's `HoldPkg = pacman glibc` protects
removal, not upgrades.

System packages update through pacman/dnf, Flatpaks through Flatpak, and portable
CLI tools through mise/uv/npm/cargo or their own installers. The cross-platform
CLI bootstrap remains separate from desktop applications. Source dependency
lockfiles and protocol/ABI identifiers are not application release pins.
