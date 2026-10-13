# macOS + Fedora Asahi dual boot with a shared /Volumes/src

Runbook for a 1 TB / 32 GB M2 Max MacBook Pro. macOS and Fedora Asahi Remix
each keep their own system and home; source code lives once on an ext4
partition that both mount at `/Volumes/src`, with `~/src` pointing at it.

## Disk plan

| Partition | Size | Notes |
|---|---|---|
| macOS (APFS) | 300 GB | Asahi recommends leaving ≥ 40 GB free inside it for updates |
| Fedora Asahi (installer-made) | 200 GB | root + /home; flatpaks, containers, `~/.cache/cargo-target` |
| `src` (ext4) | rest, ~480 GB | shared; created by `src-partition.sh` |
| Asahi stub, EFI, Apple recovery | ~5 GB | the installer manages these; never touch them |

Why ext4 + Paragon extFS rather than OpenZFS: ext4 is in the Asahi kernel, so
nothing breaks on kernel updates. OpenZFS's dkms RPM still requires
`kernel-devel` where Asahi ships `kernel-16k-devel`
([openzfs/zfs#16429](https://github.com/openzfs/zfs/issues/16429)), and Asahi
offers no older kernel to fall back to. Paragon lists macOS 27 support. Either
choice needs Reduced Security on macOS, because both are kernel extensions.

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
   This installs Homebrew (and the Xcode Command Line Tools), the Brewfile,
   rustup, mise tools, and Claude Code, and stows the configs.
4. Open 1Password, sign in, and turn on **Settings → Developer → Use the SSH
   agent** and **Integrate with 1Password CLI**. Commit signing goes through
   1Password's `op-ssh-sign`.
5. `gh auth login`.

## 2. Install Fedora Asahi Remix

From macOS, in a terminal:

```bash
curl https://alx.sh | sh
```

- **Resize:** shrink macOS to **300GB**. The prompt asks for the size macOS
  *keeps*. Local Time Machine snapshots can block the resize; delete them with
  `tmutil deletelocalsnapshots /` if asked.
- **OS:** Fedora Asahi Remix **Minimal** (COSMIC gets installed by the
  dotfiles) or KDE if you want a fallback desktop.
- **Size for the new OS:** enter **200GB**, *not* `max`. Whatever you don't give
  it stays free for `src`.
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
   Zed, Obsidian, and Vesktop (Discord). Then it builds swamp from source,
   because swamp has no aarch64 Linux release. `--skip-unavailable` means a
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

- **Cargo:** `.zshenv` sets `CARGO_TARGET_DIR` per git checkout to
  `~/.cache/cargo-target/<path>`, so build output stays in each OS's home and
  concurrent builds in different repos don't block each other. A repo whose
  scripts expect `./target/release/…` can opt out with an `.envrc`:
  `export CARGO_TARGET_DIR=$PWD/target`. Known ones on the old Mac: swamp
  (`release-smoke.sh`, `linux-validation.sh`), homelab-infra
  (`build-assembler.sh`, `verify-uhc.sh`), repo-native-alignment
  (`prep-worktree.sh`).
- **Node and Python:** `node_modules/` and `.venv/` hold native code. After
  switching OS, run `pnpm install` / `uv sync` in a project before using it.
  Keep long-running services (launch agents, systemd units) pointed at venvs
  outside `/Volumes/src`.
- **Clean shutdown:** Paragon and ext4 both replay the journal, but a hard
  power-off in one OS means the next one mounts a dirty filesystem. Fedora
  runs fsck at boot (`0 2` in fstab); on macOS, use extFS's Verify if it
  refuses to mount.

## App availability on Fedora Asahi (aarch64)

| Need | macOS | Fedora Asahi |
|---|---|---|
| 1Password | cask | arm64 tarball in `/opt/1Password`; re-run `scripts/linux/1password.sh` to update (it does not self-update) |
| 1Password CLI | cask | RPM repo |
| Browser | Chrome, Edge | Chromium (dnf). Chrome and Edge ship no arm64 Linux builds. Brave and Vivaldi have aarch64 flatpaks |
| Discord | cask | Vesktop flatpak (official client is x86_64 only) |
| HQPlayer Desktop | manual | Debian 13 arm64 build in a distrobox: `scripts/linux/hqplayer-distrobox.sh <deb>`. Desktop 6 lists Debian 13 arm64; check your 5.x downloads for a Debian 12 arm64 build first. Or ask Signalyst for a Fedora aarch64 Desktop build (Embedded has one) |
| Tern | manual | no Linux build found |
| swamp | brew tap | built with `cargo install` |
| Slack, Zoom, Teams, WhatsApp | apps | browser |
| Roon, Qobuz | apps | none |
| yabai/skhd/centered master | brew | COSMIC tiling |

Launch agents to port to systemd user units later: caddy, cloudflared,
`swamp observe`, `slop-livin observe`, call-memory, ether-*, pit-history.
