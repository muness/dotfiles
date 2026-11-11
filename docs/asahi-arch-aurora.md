# Arch Linux ARM + Aurora + COSMIC on the M2 Max

Target: MacBook Pro 14-inch (2023), **J414C / T6021 / M2 Max**. Install a
fresh Arch ARM system, then use Aurora's published kernel, m1n1, device trees
and libfprint together. COSMIC remains the desktop. Omarchy's Hyprland setup
is optional; it is not needed to use the Aurora packages.

As of 2026-10-22, the dotfiles wrapper pins
[`aurora-2026.10.17.20`](https://github.com/omacom/linux-aurora/releases/tag/aurora-2026.10.17.20)
and its installer checksum. Hardware profiles remain experimental. Package
availability does not demonstrate reliable USB4 or Touch ID on J414C.

The 2026-10-18 trial of `.20` was reverted after freezes and a subsequent login
failure. The 2026-10-22 retry keeps the idle fabric governor disabled and makes
the GRUB entry **Previous kernel - Aurora .18 (known working)** select the saved
Aurora `.18` kernel and initramfs, rather than the older pre-Aurora kernel.
The governor trial was followed by a suspected display freeze; its cause is
unproven. Rollback packages, modules and the `.18` boot bundle remain preserved
under `/var/lib/aurora-upgrade-20261018`; the module restoration service supports
booting `.18` after an upgrade removes its installed module files.

## Keep Fedora during the trial

Triple boot is possible: macOS, the working Fedora installation, and the new
Arch installation. Each Linux installation needs its **own APFS boot stub and
internal EFI partition**. Aurora updates must target Arch's EFI partition.
The current Fedora root, stub and EFI remain a recovery path. An old GRUB
entry within one installation does not isolate its shared m1n1/DTB bundle.
See [Asahi's boot documentation](https://asahilinux.org/docs/alt/boot-process-guide/).

Current layout, measured 2026-10-14:

| Partition | Purpose | Size |
|---|---|---|
| nvme0n1p1 | Apple system recovery | 500 MiB |
| nvme0n1p2 | macOS | 326 GiB |
| nvme0n1p3 | Fedora APFS stub | 2.3 GiB |
| nvme0n1p4 | Fedora EFI | 500 MiB |
| nvme0n1p5 | Fedora /boot | 1 GiB |
| nvme0n1p6 | Fedora root + home | 322.1 GiB |
| nvme0n1p7 | Shared ext4 src | 274.4 GiB; 2.2 GiB used |
| nvme0n1p8 | Apple recovery | 5 GiB |

Suggested allocation: shrink **src from its end** by 100 GiB, leaving about
174.4 GiB for source and a 100 GiB gap before Apple recovery. Arch's installer
uses that gap for its own stub, EFI and root. Its usable root will be smaller
than 100 GiB because the boot partitions are included. All sizes are a plan,
not completed disk changes. Partition numbers can change after installation;
identify the source filesystem by label/UUID, not its old number.

## Prepare before resizing or reinstalling

1. Back up macOS and source to independent storage. Fedora home is a convenient
   working copy, but it is on the same physical disk and is not that backup.
   Preserve untracked files and unpushed commits as well as remote repositories.
2. Back up COSMIC settings privately, outside the public repo and outside src:
   ```bash
   mkdir -p "$HOME/.local/state/dotfiles/reinstall"
   scripts/linux/cosmic-settings.sh backup \
     "$HOME/.local/state/dotfiles/reinstall/cosmic-settings.tar.gz"
   ```
   Copy that archive to the independent backup. Settings can contain personal
   paths and desktop history; they are not stowed into this public repo.
3. Preserve `~/.gitconfig.local`, SSH configuration, app data and credentials,
   private systemd configuration, and anything else living only in Fedora home.
   The shared source partition holds repositories, not those files.
4. Save a partition-table backup and the working Fedora boot bundle onto the
   independent backup. Record Fedora's EFI UUID and Arch's EFI UUID separately.
5. Copy this repo to Fedora home for the maintenance session. Close programs
   using `/Volumes/src`, move all shells and agents out of it, then unmount it.
   Use `fuser -vm /Volumes/src` to identify busy processes. Do not force or lazily
   unmount a filesystem that is about to be resized.

## Shrink src offline

This operation needs a maintenance session with src unmounted. Fedora itself
can remain booted because its root is on a different partition.

Order matters:

1. Identify the source partition by its `src` label, verify that it is ext4,
   and record its exact start/end, logical sector size, filesystem UUID and
   partition GUID. Save the GPT using `sgdisk --backup`.
2. Run `e2fsck -f` on the unmounted source partition. Resolve any errors before
   proceeding.
3. Use `resize2fs` to shrink the filesystem to slightly smaller than the intended
   partition (for this proposed allocation, **170 GiB** fits within 174.4 GiB).
4. Shrink only the partition's **end boundary**, preserving its start, GUID,
   type and label. On the recorded layout, freeing exactly 100 GiB gives end
   sector **216751150** with **4096-byte logical sectors**; remeasure before
   using that number. Linux sysfs `start`/`size` are in 512-byte sectors even
   on this disk, so they cannot be passed to a partition tool without conversion.
5. If the running kernel cannot reread the table because other partitions on
   the disk are mounted, reboot before using the new geometry. Do not enlarge
   the filesystem against the old in-kernel partition size.
6. Check the filesystem again and grow it to fill its new partition, using
   `resize2fs` without a size. Verify that its Paragon-compatible ext4 features
   and its UUID are preserved. Mount it and compare against the backup.
7. Boot macOS and confirm the shared source mount and new unallocated gap.

The existing `src-partition.sh` creates a new filesystem; it must **not** be
used to resize or recreate this one. See
[Asahi's partitioning guide](https://asahilinux.org/docs/sw/partitioning-cheatsheet/).

## Fresh Arch ARM base

From macOS, use the
[Asahi Alarm installer](https://asahi-alarm.org/), select
**Asahi Alarm Minimal (BTRFS)** and install into the new unallocated gap.
Confirm its proposed partitions match that gap. Complete the new OS's Apple
boot-policy setup. The existing Fedora stub/EFI must not be reused.

Boot Arch, connect to Wi-Fi, and create your regular user before running
dotfiles. Minimal images may initially log in as root:

```bash
nmtui
# Connect to Wi-Fi first; the following package command needs internet access.
pacman -Syu --needed sudo git networkmanager
systemctl enable --now NetworkManager
# Replace <user> with your existing short username.
useradd -m -G wheel -s /bin/bash <user>
passwd <user>
EDITOR=vi visudo
# Enable: %wheel ALL=(ALL:ALL) ALL
```

Log in as that user. Keep the image's Asahi Alarm repositories and signing
keys. Use full-system updates; avoid `pacman -Sy <package>` partial upgrades.

```bash
git clone https://github.com/muness/dotfiles.git ~/dotfiles
~/dotfiles/install.sh --profile asahi --aurora
```

This installs the Arch packages, COSMIC, Flatpaks, 1Password, shared mise tools,
shell/editor configuration and services; then Aurora's **complete published
stack** is installed with **SEP writes disabled**. The kernel and boot bundle
are still changed by `--aurora`. Upstream's installer supplies its own backup,
checksums, calibration extraction and bootloader hooks.

The dotfiles installer can also run on an image that already has Aurora:

```bash
~/dotfiles/install.sh --profile asahi
```

Arch ARM and Aurora are detected automatically on native Apple Silicon;
the explicit profile also supports preparing an ARM VM. The Aurora step
refuses a VM, Fedora, and non-Apple hardware. It does not repartition the disk.

The 1Password CLI is installed by mise. Its desktop app uses the vendor ARM64
tarball. Chrome, ChatGPT desktop (including Codex), Claude Desktop and BrowserOS neo are
installed by `scripts/linux/vendor-apps.sh`: it reads the vendors' HTTPS Debian
package indexes, selects the native stable builds, verifies the advertised SHA256 and
repackages the official binaries as local pacman packages. Debian maintainer
scripts are not run. This adds no AUR helper, third-party repository, or extra
package manager. Icons and launchers are included; Chrome and ChatGPT use native
Wayland on COSMIC with user overrides in `~/.config/chrome-flags.conf` and
`~/.config/chatgpt-flags.conf` (one flag per line; no shell expansion).

Update them separately from repository packages:

```bash
~/dotfiles/scripts/linux/vendor-apps.sh --check  # preview vendor package changes
~/dotfiles/scripts/linux/vendor-apps.sh         # full Arch upgrade, newer vendor apps
~/dotfiles/scripts/linux/vendor-apps.sh chrome  # update only Chrome
~/dotfiles/scripts/linux/vendor-apps.sh codex   # update only Codex CLI
~/dotfiles/scripts/linux/check-desktop-updates.sh  # vendors, Tether, Aurora and Omarchy source
```

Codex CLI is also included in vendor checks and updates as `openai-codex-bin`.
It uses the latest stable official `openai/codex` GitHub release, verifies the
asset SHA256, and preserves the complete native bundle and its helper binaries
on ARM64 and x86_64. It is separate from the ChatGPT desktop package.

The updater builds as your user, then uses pkexec for pacman with graphical
polkit authentication. Cached archives,
generated recipes and built packages live in
`~/.cache/dotfiles/vendor-apps/`. The installed names are `google-chrome`,
`openai-codex-desktop`, `claude-desktop` and `browseros-neo-bin`; remove them with pacman normally. Anthropic supports its Linux beta on Debian and Ubuntu, so Arch is an unsupported repackaging. Upstream changes are
discovered on each updater/installer run and by the weekly user-app timer,
which notifies when vendor updates are available. Installing these root-owned
packages still uses the interactive updater and graphical authentication;
the Debian/RPM app updater does not manage them. BrowserOS installer versions
are read from asset filenames, including maintenance builds under older tags.
`--force` rebuilds/reinstalls a current version. `--build-only` builds
without installing (Arch build/runtime dependencies must already be present).
`--download-only` verifies archives without installing and also runs on Fedora.

Aurora remains held as a coordinated kernel, boot and fingerprint stack. Run
`~/dotfiles/scripts/linux/aurora.sh --check` to compare the reviewed release
with the latest upstream release. When it changes, review its release notes,
assets and recovery steps before updating the release and checksum in the
wrapper and testing the full stack. The custom Omarchy package likewise requires
review and rebuilding when its source changes; the check above reports that.

Fresh-Arch application launch/login and COSMIC screen sharing remain acceptance
items. The binaries are native; packaging does not by itself qualify the whole
desktop integration.

## Restore COSMIC and mount source

From a console before the first COSMIC login:

```bash
~/dotfiles/scripts/linux/cosmic-settings.sh restore /path/to/cosmic-settings.tar.gz
sudo ~/dotfiles/scripts/dualboot/src-mount-linux.sh
```

The source mount helper maps the macOS file owner to this installation's user;
Arch need not use Fedora's numeric UID. Every OS must unmount src cleanly
before booting another. Set up 1Password's SSH agent, `gh auth login` and
`sudo tailscale up` as on Fedora. The greeter must offer the COSMIC session.

## Acceptance and Touch ID

First qualify cold boot, the built-in screen, speakers, Wi-Fi, direct Mac HDMI,
the direct Microsoft Surface Thunderbolt 4 Dock, Ethernet, input devices,
same-port reconnect several times, and actual suspend/resume. Check that both
macOS and Fedora still boot. Save named package versions and logs; VM results
do not qualify these hardware paths.

Touch ID requires a deliberate transition out of read-only mode. Aurora's
installer preserves an earlier read-only setting. Read its SEP/xART notes and
confirm recovery before removing the read-only module options. Then:

```bash
~/dotfiles/scripts/linux/aurora.sh --enable-touchid
# After deliberately clearing the upstream read-only setting and rebooting:
aurora-touchid-setup
```

Verify enrollment, matching, logout/login, cold reboot, suspend/resume and macOS
Touch ID. COSMIC PAM/greeter integration is a separate acceptance item; Aurora's
Omarchy lock-screen setup does not establish fingerprint login in COSMIC.

For updates, run `sudo pacman -Syu` and keep Aurora's package holds/hooks under
its installer's control. Update the release and checksum in `aurora.sh` together
after reviewing the upstream release, then rerun the same mode. Never swap only
the kernel or only the DTBs. Keep Fedora until the new installation meets the
acceptance checks.

## CI kernel trial prepared 2026-11-01

**Current status, 2026-11-03:** the user reports the CI kernel and staged
boot image working well, with no observed regression. The GRUB entry is now
**Aurora CI 7.2.11 - known working**, and `GRUB_DEFAULT` selects its existing
ID `aurora-ci-41324776125`. The `.20` entry is labeled
**Aurora .20 - fallback (7.1.12)**. This update changes the menu labels and
default selection only; it does not rebuild the boot image or change the
persistent DTB package selection. The dated notes below record the trial's
history, including earlier defaults and rollback states.

**2026-11-02: rolled back after USB dock failure.** The user reported the
Microsoft Surface USB4 dock failed under both 7.2.11 and the `.20` menu entry.
Both were still using the CI DTB bundle, so this did not establish a failure
of the original complete `.20` setup. Restored `.20` as the default, its
original `update-m1n1` package selection, and the exact pre-trial `boot.bin`
(SHA-256 `8fb48d6342492b422fcf19c2bd58cabee6a6e5370020506a89a1542e24588da2`).
The original and restored bundle hashes match. Current-boot logs and module
and USB inventories are under
`~/.local/state/aurora-ci-diagnostics/20261102T141751Z`.
The running CI kernel remains active until shutdown. A full shutdown and
dock power cycle followed by a default `.20` boot is needed to retest the
original configuration. Recovery of the dock has not yet been confirmed.
The adoption description below records the previous trial, not current state.

**Cold-boot follow-up, 2026-11-02:** the user reports the Surface dock working
again. This is a new boot (`516f4b60-58e9-4dbc-b841-db80aa7ae7c9`), but the running
kernel is **7.2.11-14-1.536-ARCH**, not `.20`. The original `.20` boot bundle
remains on disk. USB enumeration shows the Intel and Microsoft hub links at
10 Gb/s, the Microsoft LAN device on a 5 Gb/s USB link, and the Logitech BRIO
on a 5 Gb/s link; a Thunderbolt DP tunnel is established. This demonstrates
that 7.2.11 can operate the dock after a cold boot with the restored bundle;
it does not distinguish device-tree changes from controller/dock power-cycle
recovery. Do not record this as a successful `.20` kernel retest.

**Warm-reboot follow-up, 2026-11-02:** the user reports another successful
7.2.11 boot without power-cycling the dock. New boot ID
`6c71fd4a-556a-48f2-9168-33bf44c62d30`; the original `.20` bundle hash still
matches, and the CI-only `apple,pciec-kernel-init` property is absent from the
live tunnel-0 device tree. Hub links remain at 10 Gb/s, Ethernet and BRIO USB
links at 5 Gb/s, and both Thunderbolt display tunnels are established. No
pipehandler failure or USB3-PHY-setup failure appears in this boot's log.
This strengthens the case for retaining the older bundle with 7.2.11 during
testing, but does not prove which changed component caused the earlier failure.

**Controlled DTB comparison staged, 2026-11-02:** after docked clamshell and
one actual suspend/resume also recovered the dock on 7.2.11 with the older
bundle, the user requested a newer-tree retest. Staged a fresh bundle from
`linux-aurora-ci`'s 115 DTBs and the same installed m1n1/U-Boot binaries.
Verified the complete DTB prefix and decompressed U-Boot payload before
activation. Per-trial backups and baseline logs are in a `dtb-trial-*`
directory under `/var/lib/aurora-ci-test/41324776125`. Persistent DTB package
selection remains `.20`, as does GRUB's default. For this test select 7.2.11
manually and warm-reboot without power-cycling the dock. Result pending.
Use `pkexec /usr/local/sbin/aurora-ci-restore-boot` and reboot to return to
the older bundle if the dock fails. The recent resume used the re-enabled
Wi-Fi recovery helper, so it is not additional unassisted Wi-Fi evidence.

The J414C has a parallel trial of kernel `7.2.11-14-1.536-ARCH`, from
[successful upstream CI run 41324776125](https://github.com/omacom/linux-aurora/actions/runs/41324776125)
at commit `4fdd0fc5c931ef9f14474942b37c3d451e97fc04`. The downloaded kernel and
headers were repackaged as `linux-aurora-ci` and `linux-aurora-ci-headers` so
the released `.20` packages, headers and module tree remain installed. Kernel
code was not rebuilt. Binder and `alsa_bridge` were rebuilt through DKMS.

The initial trial used **Aurora CI test - 7.2.11 (2026-11-01)** in GRUB, with
`.20` as the default and no one-time override. It was subsequently adopted as
the default as described below. Confirm the
test kernel with `uname -r`, then check accelerated graphics, Wi-Fi, audio,
Waydroid, dock hotplug and suspend/resume. The test entry requests
`cfg80211.ieee80211_regdom=US`; the candidate J414C device tree retains the
previously disabled PMP. No M3-only sleep-power settings were enabled.

The shared Arch m1n1 `boot.bin` now contains the candidate's matching device
trees, using the existing m1n1/U-Boot binaries. Selecting `.20` alone does not
restore its old device trees. For a complete return to its original bundle:

```bash
pkexec /usr/local/sbin/aurora-ci-restore-boot
# Then reboot normally into the default .20 kernel.
```

The original bundle is also on Arch's EFI partition at
`m1n1/boot.bin.before-ci-41324776125`, for restoration from another OS if the
boot chain fails before GRUB. Identify Arch's EFI partition by PARTUUID
`667de9ee-cc3d-425e-97a9-d29dab9c99a5`; do not change Fedora's EFI partition.
The root snapshot, full EFI backup, original configuration and checksum
records are under `/var/lib/aurora-ci-test/41324776125`. Downloads, repackaging
recipe and preparation scripts are under
`~/.cache/dotfiles/aurora-ci/41324776125`.

After a successful desktop boot and an unassisted Wi-Fi resume, the user
adopted this kernel as default on 2026-11-01. GRUB now defaults to the stable
entry ID `aurora-ci-41324776125`, labeled **Aurora 7.2.11 - default**. A separate
top-level **Aurora .20 - fallback (7.1.12)** entry uses ID `aurora20-fallback`.
Both package pairs and the larger 36-pixel GRUB font are retained.

`/etc/default/update-m1n1` now selects only `linux-aurora-ci`'s package-owned
device trees, so routine hooks retain the adopted kernel's DTBs. Regenerating
with this selection verified the same m1n1 binary, ordered DTBs and decompressed
U-Boot payload as the tested bundle; their container ordering differs. The
currently tested boot file was retained unchanged during adoption.
`aurora-ci-restore-boot` now restores all three: `.20` as GRUB default, the
original package selection for DTBs, and the original `.20` boot bundle.
Selection of the fallback menu entry alone still uses the shared CI DTBs.
The pre-adoption configuration is backed up under the state's `adopt-before`
directory. Broader dock, audio and sleep reliability acceptance remains open;
automatic Wi-Fi resume recovery is disabled during continued testing.
