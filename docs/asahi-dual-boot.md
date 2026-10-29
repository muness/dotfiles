# macOS + Fedora Asahi dual boot with a shared /Volumes/src

Runbook for a 1 TB / 32 GB M2 Max MacBook Pro. macOS and Fedora Asahi Remix
each keep their own system and home; source code lives once on an ext4
partition that both mount at `/Volumes/src`, with `~/src` pointing at it.

For a fresh Arch ARM/Aurora installation with COSMIC, including keeping this
Fedora install as a third-boot fallback, see [the Arch/Aurora runbook](asahi-arch-aurora.md).

## Disk plan

| Partition | Size | Notes |
|---|---|---|
| macOS (APFS) | 350 GB | Linux is the primary OS; the old Mac used 381 GB, so keep big SDKs and models on one side. Asahi wants ≥ 40 GB free inside it |
| Fedora Asahi (installer-made) | 350 GB | root + /home: its own toolchains and SDKs, flatpaks, containers, `~/.cache/cargo-target` |
| `src` (ext4) | rest, ~290 GB | shared git clones only; builds go to each OS's `~/.cache`. The old Mac's `~/src` was 14 GB including build output |
| Asahi stub, EFI, Apple recovery | ~5 GB | the installer manages these; never touch them |

Why ext4 + Paragon extFS rather than OpenZFS: ext4 is in the Asahi kernel, so
nothing breaks on kernel updates. OpenZFS's dkms RPM still requires
`kernel-devel` where Asahi ships `kernel-16k-devel`
([openzfs/zfs#16429](https://github.com/openzfs/zfs/issues/16429)), and Asahi
offers no older kernel to fall back to. Paragon lists macOS 27 support. Either
choice needs Reduced Security on macOS, because both are kernel extensions.

**Pick the sizes carefully; changing them later is awkward.** The partitions
sit back to back in this order: macOS, Asahi stub, Fedora (EFI, boot, root),
`src`, Apple recovery. A filesystem can only grow into free space right after
it, so:

- Fedora's root can't grow without shrinking `src` from the front, which ext4
  can't do. In practice you delete `src` and recreate it smaller.
- `src` has nothing after it but Apple's recovery partition, so it can't grow.
  It **can shrink from its end while unmounted** to leave a gap for another
  Linux installation. That preserves its start and the existing Fedora layout.
- macOS can't reclaim space either, because the Asahi stub sits after it.
- None of this can be done from macOS: `diskutil` can't resize Fedora's btrfs
  root or the ext4 partition. It has to happen from Fedora.

Recreating `src` is the realistic escape hatch, and it's cheap because it
only holds git clones: push everything, delete it, rerun
`src-partition.sh`, then clone again.

## 1. macOS first boot

1. Create your user. **Use the same short name you will use on Fedora**: the
   home paths differ (`/Users/x` vs `/home/x`), but matching names keeps
   scripts and ssh config simple. macOS makes the first user uid 501, gid 20.
2. Install macOS updates.
3. Clone over HTTPS (no SSH keys yet) and install:
   ```bash
   git clone https://github.com/muness/dotfiles.git ~/dotfiles
   ~/dotfiles/install.sh
   ```
   This runs the `mac` profile: Homebrew (and the Xcode Command Line Tools), the
   Brewfile, the mise CLI set and runtimes, rustup, and Claude Code, and stows the configs.
4. Open 1Password, sign in, and turn on **Settings → Developer → Use the SSH
   agent** and **Integrate with 1Password CLI**. Commit signing goes through
   1Password's `op-ssh-sign`.
5. `gh auth login`.

## 2. Install Fedora Asahi Remix

From macOS, in a terminal:

```bash
curl https://alx.sh | sh
```

- **Resize:** shrink macOS to **350GB**. The prompt asks for the size macOS
  *keeps*. Local Time Machine snapshots can block the resize; delete them with
  `tmutil deletelocalsnapshots /` if asked.
- **OS:** Fedora Asahi Remix **Minimal** (COSMIC gets installed by the
  dotfiles) or KDE if you want a fallback desktop.
- **Size for the new OS:** at "How much space should be allocated to the new
  OS?", type **350GB**. Pressing Enter accepts the default, `max`, which takes
  all the free space and leaves nothing for `src`. The installer then confirms
  how much it is leaving free; that figure should be ~290 GB.
- Follow the installer's instructions to the letter: shut down, hold the power
  button until startup options appear, pick the new Fedora entry, and finish
  the boot-policy step in recoveryOS. This only changes the security policy
  for the Linux stub; macOS keeps Full Security until step 5.

## 3. Fedora first boot

1. Initial setup creates your user (uid 1000). Same short name as macOS.
2. Update, then reboot:
   ```bash
   sudo dnf upgrade --refresh -y && sudo reboot
   ```
3. Clone and install:
   ```bash
   git clone https://github.com/muness/dotfiles.git ~/dotfiles
   ~/dotfiles/install.sh
   ```
   On Fedora this adds the mise, Tailscale and 1Password repos; installs the
   CLI set, COSMIC (with `cosmic-greeter` if no display manager exists),
   Chromium, KeePassXC, Syncthing, the 1Password arm64 tarball, and flatpaks for
   Obsidian and Vesktop (Discord), and installs Zed's native build. Then it builds swamp and Satty from
   source, because neither has an aarch64 Linux release. `--skip-unavailable` means a
   missing package is reported, not fatal; read the dnf output.
4. Reboot into COSMIC. Open 1Password and turn on the SSH agent and CLI
   integration, as on macOS.
5. Point SSH at 1Password's Linux socket. `~/.ssh/config` is not in this
   (public) repo, so add this to it by hand:
   ```
   Host *
     IdentityAgent ~/.1password/agent.sock
   ```
   The macOS config uses `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`.
6. `gh auth login`, `sudo tailscale up`.

## 4. Create and mount the shared partition (Fedora)

```bash
cd ~/dotfiles
sudo scripts/dualboot/src-partition.sh          # dry run: prints the layout and plan
sudo scripts/dualboot/src-partition.sh --yes    # creates the partition and ext4
sudo scripts/dualboot/src-mount-linux.sh        # fstab entry, mount, ownership check
scripts/dualboot/src-doctor.sh
```

`src-partition.sh` takes the largest free block (it refuses anything under
100 GiB), creates a GPT partition labelled `src`, re-sorts the partition table
(Apple's tools dislike unsorted tables), and formats ext4 **without**
`metadata_csum`, `metadata_csum_seed`, or `orphan_file`. Fedora enables those
by default, and Paragon extFS cannot mount them.

### uid mismatch

macOS writes files as 501:20; Fedora's user is 1000:1000. ext4 stores the raw
numbers, so each OS would see the other's files as a stranger's.

`src-mount-linux.sh` fixes this on the Linux side with an **idmapped mount**:

```
LABEL=src /Volumes/src ext4 defaults,noatime,nofail,X-mount.idmap=u:501:1000:1\040g:20:1000:1 0 2
```

Inside `/Volumes/src` the Linux user sees its own files as 1000:1000, and they
are stored on disk as 501:20, which is what macOS expects. Nothing about the
Linux account changes. The script proves it works by creating a file through
the mapped mount and reading its owner through a second, unmapped mount.

Limits: root writes into the mapped mount fail (root is outside the map), and
files with any other owner show as `nobody`. `src-doctor.sh` lists those, and
`sudo scripts/dualboot/src-doctor.sh --fix-ownership` re-owns them on disk.

**uid fallback.** If the idmapped mount ever misbehaves, renumber the Linux user
instead. From a text console (Ctrl+Alt+F3), logged in as root, with your user
logged out:

```bash
usermod -u 501 <user>
groupmod -g 501 <user>          # 20 is taken by "games" on Fedora; keep a private group
echo 'UID_MIN 500' >> /etc/login.defs   # greeters hide users below UID_MIN
```

Then remove `X-mount.idmap=…` from the fstab line. Files will show group 20
(`games`) on Linux, which is harmless with a 022 umask.

## 5. Mount it on macOS

1. One trip to recoveryOS (hold power → Options) covers both kernel-level
   needs:
   - **Startup Security Utility** → macOS volume → **Reduced Security** +
     **Allow user management of kernel extensions from identified developers**
     (Paragon extFS).
   - For yabai's scripting addition: `csrutil enable --without fs --without debug --without nvram`.
2. Back in macOS: open **extFS for Mac** (installed by the Brewfile), approve
   its kernel extension under **System Settings → Privacy & Security**, and
   reboot. If macOS 26+ asks, add `extfsd` from
   `/Library/Application Support/Paragon Software` to **Full Disk Access**.
3. For yabai: `sudo nvram boot-args=-arm64e_preview_abi` and reboot.
4. Once `src` shows up at `/Volumes/src`:
   ```bash
   ~/dotfiles/scripts/dualboot/src-macos.sh
   ```
   This turns on ownership (external volumes ignore it by default and would
   write files as uid 99), disables Spotlight on the volume, links
   `~/src → /Volumes/src`, and runs the doctor.

Paragon's install sets up auto-mount; enable it in the extFS app if the volume
does not appear after reboots.

## 6. Clone repositories

Clone fresh into `~/src` (which is `/Volumes/src`) from either OS. Run
`src-doctor.sh` afterwards if you cloned as root or from a tool that might
have set odd ownership.

## Living on a shared tree

- **Cargo:** `~/.cargo/config.toml` sets
  `build.build-dir = "{cargo-cache-home}/build/{workspace-path-hash}"`, so the
  bulk of every build (dependencies, incremental state) lives in each OS's own
  `~/.cargo/build/`, keyed by the checkout's path. `./target` keeps only final
  binaries, so scripts that run `target/release/…` keep working. Cargo
  re-copies those binaries on every build, even a no-op one, so the first
  `cargo build` after switching OS replaces the other OS's binary.
- **Disk cleanup:** swamp observes every 15 minutes on both OSes and links each
  `~/.cargo/build/<hash>` directory back to its project. Clean up from
  `swamp report --view reclaim` or the `swamp` TUI; no separate cleanup job.
- **Node and Python:** `node_modules/` and `.venv/` hold native code. After
  switching OS, run `pnpm install` / `uv sync` in a project before using it.
  Keep long-running services (launch agents, systemd units) pointed at venvs
  outside `/Volumes/src`.
- **Clean shutdown:** Paragon and ext4 both replay the journal, but a hard
  power-off in one OS means the next one mounts a dirty filesystem. Fedora
  runs fsck at boot (`0 2` in fstab); on macOS, use extFS's Verify if it
  refuses to mount.

## Touch ID experiment: rolled back 2026-10-14

**Revisit around November 4, 2026, only if relevant updates have landed.**
Keep Touch ID disabled in the meantime.

Machine: MacBook Pro 14-inch (2023), **M2 Max / J414C / T6021**, Fedora 44
Asahi Remix; working stock kernel `7.1.13-402.asahi.fc44.aarch64+16k`.

We built Aurora's experimental 16 KiB-page kernel
`7.1.12-touchid-asahi-16k`, stage-two m1n1 and device trees, plus Fedora
libfprint with the Apple SEP driver. Calibration was extracted privately.
The diagnostic boot had `xart_writes=0` and `provision_keybag=0`; no
fingerprint enrollment or SEP writes were enabled.

**Outcome:** kernel panics with every kernel tried. Restoring
`boot.bin.touchid-original` recovered Fedora. Exact panic cause was not
determined. The fallback plan was inadequate: m1n1 and device trees live in
the shared EFI `m1n1/boot.bin`, so selecting an older kernel did not isolate
it from the experiment. A one-shot GRUB entry did not protect that shared
boot path.

Rollback was completed and checked: original boot bundle restored
byte-for-byte, stock m1n1 configuration/DTB link/default kernel restored,
experimental kernel/service/fprintd drop-in removed, and Fedora libfprint
restored. Updates no longer select the experimental m1n1.

### Updates to check before retrying

- **Fedora/Asahi packages and support:** updated `m1n1` and `kernel-16k`,
  official SEP/Touch ID status, and Fedora-compatible installation support.
  A new release number or an Arch installer alone is insufficient.
- **Exact-board reports:** J414C/T6021 success with named kernel, m1n1,
  DTB and firmware versions; fixes or explanations for boot panics; cold
  boot, stock-kernel fallback, suspend/resume and macOS dual boot tested.
  Enrollment, matching and persistence after reboot should be demonstrated.
- **Aurora changes:** check the
  [M2 MacBook Pro thread](https://github.com/aurora-silicon/linux/discussions/106),
  [SEP reboot/persistence work](https://github.com/aurora-silicon/linux/pull/69),
  [m1n1 history](https://github.com/aurora-silicon/m1n1/commits/aurora-wip/),
  and [Fedora libfprint packaging](https://github.com/aurora-silicon/aurora-sep-userspace).
  Failed source pins were kernel `d588f760941edaa2cbf4a0a9ec12a47027581535`
  and m1n1 `f3ac615eb1376d3bbba24cd84c414b9e41892adb`.
  Check integration of the patched bindgen/layout fixes and the missing
  `dwc3_event_buffers_cleanup` export needed for our modular USB build.
- **SEP write safety:** reread the current
  [xART safety notes](https://github.com/aurora-silicon/linux/blob/aurora-wip/tools/aurora-sep/XART-SAFETY.md).
  Our read-only APFS inspection passed, but that does not prove writes are
  safe. Back up macOS/FileVault data; restoring a raw iBoot image cannot
  necessarily reverse SEP anti-replay state.

On a retry, verify recovery of the **whole original EFI boot bundle**, record
firmware versions and capture the first panic for diagnosis. Start read-only
again; consider provisioning only after boot and enclave diagnostics work.
Keep password login until fingerprint matching survives a cold reboot.

Local evidence, backups and build provenance:
`~/.local/state/touchid-research/`; build logs: `~/.cache/touchid-build/`.
Do not rerun the historical installer unchanged. Keep calibration, iBoot
images and SEP state out of this repo.

## Screenshots on Fedora

Bind `shot-annotate` in **Settings → Keyboard → Custom shortcuts**: capture a
region, annotate in Satty, Enter to save and copy, Escape to discard. Files land
in `~/Pictures/Screenshots`. `shot-share [file]` uploads one to the homelab and
copies the link; it works on macOS too. Configure it once per machine in
`~/.config/shots/env`:

```
SHOT_UPLOAD_TARGET=homelab:/srv/shots   # scp target
SHOT_BASE_URL=https://shots.<your-tailnet-host>
```

The homelab side needs a directory the web server serves read-only. Links use
a random 18-character name, so anyone with the link can view it; there is no
listing.

## App availability on Fedora Asahi (aarch64)

| Need | macOS | Fedora Asahi |
|---|---|---|
| 1Password | cask | arm64 tarball in `/opt/1Password`; re-run `scripts/linux/1password.sh` to update (it does not self-update) |
| 1Password CLI | cask | mise (same vendor CLI on Arch ARM) |
| Browser | Chrome, Edge | Chrome (official arm64 RPM since July 2026, installed by `install_chrome`; updates via dnf) and Chromium. Edge has not been checked for arm64. Brave and Vivaldi have aarch64 flatpaks |
| Discord | cask | Vesktop flatpak (official client is x86_64 only) |
| HQPlayer Desktop | manual | Debian 13 arm64 build in a distrobox: `scripts/linux/hqplayer-distrobox.sh <deb>`. Desktop 6 lists Debian 13 arm64; check your 5.x downloads for a Debian 12 arm64 build first. Or ask Signalyst for a Fedora aarch64 Desktop build (Embedded has one) |
| Tern | manual | no Linux build found |
| ChatGPT (includes Codex) | cask | OpenAI's official Linux app (public preview, Aug 2026): RPM installed by `install_chatgpt`, updates via dnf. Wayland support is experimental; if windows misbehave, quit it and run `chatgpt --ozone-platform=wayland` |
| Claude desktop | cask | Official Linux beta repackaged for Arch by `vendor-apps.sh`; Anthropic supports Debian and Ubuntu. Fedora is not configured by this installer. |
| Beeper | cask | not on Flathub; check Beeper's own AppImage |
| Fork | cask | none; `gitg` or `meld` are in dnf, or use `gh` and the CLI |
| tectonic | brew | not in mise or dnf; typst (mise) covers most of it |
| adb, fastboot | `android-platform-tools` cask | `android-tools` (dnf), verified on aarch64: adb 1.0.41, fastboot 37.0.0 |
| Android SDK `cmdline-tools` (sdkmanager, avdmanager) | cask | not checked for aarch64; adb and fastboot do not need it |
| Raycast, Homerow, Maccy, BetterTouchTool, Mountain Duck, OpenMTP, macFUSE | casks | no Linux version; COSMIC's launcher, clipboard and tiling cover the first four |
| Tuple | cask | none |
| Screenshots (Screendrop, ScreenshotX) | apps | `cosmic-screenshot` (dnf) to capture, Satty to annotate. Satty has no RPM, Flathub or aarch64 release, so `install_satty` builds it with `cargo install` |
| swamp | brew tap | built with `cargo install` |
| Slack, Zoom, Teams, WhatsApp | apps | browser |
| Roon, Qobuz | apps | none |
| yabai/skhd/centered master | brew | COSMIC tiling |

## Launch agents on Linux

The dotfiles own only the generic services; the installer stows `systemd/` and
enables these user units. Each has a `ConditionPathExists` on its config, so it
stays idle until you create that file. Headless (`server`) hosts also get
`loginctl enable-linger`, so the units run without a login session.

| Mac launch agent | On Linux |
|---|---|
| `homebrew.mxcl.caddy` | `caddy.service`, reads `~/.config/caddy/Caddyfile` (yours is `:8443 { reverse_proxy 127.0.0.1:8082 }`; copy it over by hand) |
| `homebrew.mxcl.cloudflared` | `cloudflared.service`, runs `cloudflared tunnel run` with `~/.cloudflared/config.yml`. On the Mac it runs with no arguments and exits 1, so it was not working there either |
| `swamp.observe` | already handled: `swamp schedule --collector` installs swamp's own user units |
| `com.call-memory.*`, `ether-*`, `pit-history`, `agent-surface`, `tdongle-diagnostic-receiver`, `apk-server`, `cliproxyapi`, `slop-livin.observe` | not ported here. They hardcode `/Users/...` or Codex worktree paths and belong to their own repos; the call-memory ones are tied to the HiDock USB device and `mac_transcribe.py`. Port each in its repo when you move it, ideally to the homelab |

