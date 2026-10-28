# Workstation memory protection

The October 19, 2026 freeze recording showed available RAM falling from
20 GiB to less than 1 GiB in about a minute. Eleven parallel linkers held
roughly 17 GiB, alongside rustc and desktop apps. With no swap or early
memory-pressure intervention, reclaim and I/O stalls made the desktop
unresponsive. Earlier freezes were not recorded.

The shared Cargo config now defaults to two jobs per invocation. Project
configs, `CARGO_BUILD_JOBS`, and explicit `-j` flags can override this;
separate Cargo invocations each get their own job allowance.

On the Arch ARM workstation, `earlyoom` and `zram-generator` are installed.
The source files under `config/linux-memory/` are copied to:

- `earlyoom.conf`: `/etc/systemd/system/earlyoom.service.d/50-workstation-memory.conf`
- `zram-generator.conf`: `/etc/systemd/zram-generator.conf.d/50-workstation-memory.conf`

The zram generator provides compressed swap with logical capacity equal to
installed RAM (about 30.9 GiB on this host), using zstd. This was increased
from the initial 8 GiB cap on October 21, 2026 and is active now as well as
configured for boot. Pages consume RAM on demand; the logical capacity is
not a physical-memory reservation or disk swap.

This host also has a 16 GiB disk swapfile at `/swap/swapfile`, created with
`btrfs filesystem mkswapfile` in a separate `/swap` subvolume so it does not
block root snapshots. `/etc/fstab` enables it at boot with `pri=10,nofail`;
zram's priority is 100, so it is used first. The swapfile uses this Asahi
kernel's 16 KiB page size. Root snapshots do not include the swap subvolume;
a rollback must preserve or restore its path for disk swap to remain available.

`desktop-session.conf` is installed as
`/etc/systemd/system/session-.scope.d/50-desktop-priority.conf`. It gives login
session scopes CPU weight 1000 versus the default 100 and `MemoryLow=1G`.
On this COSMIC host the compositor and panel run in the login session scope,
while application/build scopes run under `user@1000.service`. This favors the
core desktop during CPU contention and memory reclaim; it is not a hard
reservation or guarantee against all stalls. The prefix drop-in applies to
future login scopes, including non-graphical sessions.

`desktop-memory-parent.conf` is installed under both
`user.slice.d/50-desktop-memory.conf` and
`user-1000.slice.d/50-desktop-memory.conf` in `/etc/systemd/system/` to provide
the ancestor memory protection budgets. The same properties were applied to
the live cgroups without restarting the desktop.

Earlyoom is enabled at boot. Below 10% available userspace memory it sends
SIGTERM to a selected process; below 5% it can use SIGKILL. Swap availability
does not delay intervention. Compiler/linker processes receive preference,
desktop apps receive avoidance, and root-owned processes are excluded.
Preferences are not guarantees: another user process can be selected when
necessary. A build may fail under pressure to keep the machine usable.

Check the active protection with:

```sh
systemctl status earlyoom.service
swapon --show
journalctl -u earlyoom.service
```

These system configs are applied on this workstation; the normal dotfiles
installer does not yet deploy them. Changes to these source files require
copying them to the paths above and reloading the system manager. Cargo's
config is already linked into the home directory.
