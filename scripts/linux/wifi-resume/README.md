# Apple Silicon Wi-Fi resume recovery

Installed on the M2 Max on 2026-10-29 to recover BCM4388 Wi-Fi after sleep
without rebooting. Logs showed repeated `ASSOC-REJECT status_code=16` after
resume, while radio toggles and a supplicant restart did not clear the failure.
Based on [Omarchy's recovery approach](https://github.com/omacom/omarchy-mac/pull/255),
whose original hardware filter did not include BCM4388 (`14e4:4434`). This is a
recovery workaround, not a firmware fix.

The system service now runs a full driver reload **immediately after every
resume** (`--force`), at the user's request to reduce reconnect latency on this
machine, where every wake has failed. This removes the roughly nine-second
detection delay measured in the second wake test. The driver reload and normal
NetworkManager reconnect still take time; approximately eight seconds were
measured in that test. This mode also reloads a connection that could otherwise
have recovered normally. Disabled Wi-Fi and deliberately disconnected devices
are still left alone.

On 2026-11-01, a retained crash from 2026-10-31 showed that this immediate
reload could overlap the supplicant's Wi-Fi Direct interface creation. The
kernel dereferenced NULL in `brcmf_fweh_p2pdev_setup` while `brcmfmac_wcc` was
unloading. The old `Type=oneshot` unit then remained in its start transaction,
and systemd explicitly rejected poweroff/reboot transactions that conflicted
with that pending start job. A subprocess timeout could not recover that
kernel-side failure.

The revised helper first makes the Wi-Fi device temporarily unmanaged and
checks both NetworkManager's unmanaged state and the supplicant's D-Bus
interface list. It refuses to unload modules until the supplicant has detached.
NetworkManager management is restored even if detaching or unloading fails.
This addresses the observed overlapping operations; it is not a kernel fix.

The unit now uses `Type=exec`: its start job finishes at exec, rather than
holding the sleep transaction open until reconnection. Recovery has a
90-second runtime limit and a five-second stop timeout. A harmless test worker
verified it has no pending start job while running and can be stopped. This
does not guarantee shutdown can recover from an arbitrary kernel crash.

The revised installed service was manually started on 2026-11-01 at 18:47:38
EST: its start job finished immediately, both interface owners detached before
module removal, and automatic reconnection completed at 18:47:49. IPv4 and IPv6
HTTPS passed afterward. Rapid lid-close/reopen with this revision still needs
verification. Crash evidence and the guarded reload log are saved under
`~/.local/state/wifi-diagnostics/2026-11-01/`.

The helper's default mode (without `--force`) allows 25 seconds for normal recovery,
reloads earlier after two new authentication timeouts or one that remains
unrecovered for three seconds, and otherwise reloads
only if authentication failed or a connection attempt is still stuck. It
unloads **both** `brcmfmac_wcc` and `brcmfmac`, then loads `brcmfmac` and waits
up to 40 seconds for NetworkManager to reconnect. Healthy connections, disabled
Wi-Fi, deliberately disconnected devices, and an idle disconnected interface
without authentication failures are left alone. It only supports the ARM64
BCM4378/4387/4388 PCI devices using brcmfmac. USB tethering is unaffected.

Install or update, from this directory:

```sh
pkexec /usr/bin/python3 "$PWD/install.py"
```

Inspect recovery decisions:

```sh
journalctl -b -u dotfiles-wifi-resume.service
```

Manual recovery (briefly interrupts Wi-Fi):

```sh
pkexec /usr/local/libexec/dotfiles-wifi-resume --force
```

Remove:

```sh
pkexec /usr/bin/python3 "$PWD/install.py" --remove
```

Verification on installation: automated guard/failure tests, systemd unit
validation, real full module reload and automatic reconnection to `217` with
no BSSID lock. A lid-close/wake test is required to verify the complete suspend
path; installation and a successful manual reload alone do not establish that.

First lid-close test on 2026-10-29: resumed at 14:42:58 EDT, detected repeated
authentication timeouts, reloaded at 14:43:18, reconnected at 14:43:32, service
finished successfully at 14:43:33. IPv4 and IPv6 HTTPS both passed afterward.
The user confirmed touching the Wi-Fi slider; the desktop shell requested a
brief radio off/on at 14:43:26, so this run did not establish recovery without
interaction. The first version
waited for a second rejection; the revised conditional mode allows three seconds
after the first rejection, to shorten that delay while tolerating transient
authentication retries. Driver removal briefly makes Wi-Fi disappear from the
desktop UI.

Second lid-close test, with the shorter detection interval: resumed at
14:47:03 EDT, first authentication timeout at 14:47:08, full module reload at
14:47:12, connected at 14:47:20, recovery service finished successfully at
14:47:21. No manual radio-control requests appeared during this cycle. IPv4
and IPv6 HTTPS both returned HTTP 200 afterward. This verifies automatic
recovery for one real suspend/resume cycle, approximately 18 seconds after wake;
it does not fix the underlying driver/firmware resume defect or establish
long-term reliability across all sleep durations.

```sh
/usr/bin/python3 -m unittest discover -s . -p 'test_*.py'
```
