# Touch ID for Waydroid App Lock

Experimental host-trusted fingerprint service for the Android 16 Asahi image.
It implements the frozen fingerprint AIDL v1 HAL through the distribution's
`python-gbinder`, so no Android executable or replacement image is needed.
Its backend uses existing Linux `fprintd` enrollments. Raw fingerprint data and
the Android PIN are neither read nor stored.

## Boundaries

- The sensor reports **weak** strength. Nonzero cryptographic operation IDs are
  rejected. No KeyMint/Gatekeeper keys or authentication tokens are fabricated.
- Only the container's primary-user `system_server` may call the HAL. The host
  desktop user and host root remain trusted; this is not phone-equivalent
  isolation, Android biometric certification, or hardware-backed key release.
- Android fingerprint enrollment creates a bridge-local enrollment after a
  fresh fingerprint match. It does not add/remove Linux fingerprint templates.
- Each authentication claims the Linux device temporarily, requires a new
  match, and releases the device on success, failure, cancellation or timeout.
  The broker does not accept external success messages.
- Five mismatches lock this service out for 30 seconds across Android sessions.
  PIN fallback and Android's own post-reboot/strong-auth restrictions remain.
- The current Asahi image has SELinux disabled. Enforcing Android images are
  not supported by this integration; do not disable enforcement to install it.
- Ordinary Authenticator App Lock accepts weak biometrics on the inspected
  version (6.2609.6214). Other MFA/passkey operations can request strong or
  cryptographic authentication and are outside scope.

## Install

Prerequisites: Waydroid with overlays enabled, uid 1000 desktop user,
`python-gbinder`, `python-dbus`, `python-gobject`, and a functioning `fprintd`
enrollment. The daemon currently binds `/dev/binder` using `aidl6`/`aidl3`, matching
this Asahi installation. Other users, profiles and Binder layouts need adaptation.

Run the checks using the distribution's Python:

```sh
/usr/bin/python3 -m unittest discover -s scripts/linux/waydroid-fingerprint -p 'test_*.py'
```

Copy `core.py`, `protocol.py`, and `daemon.py` into
`~/.local/lib/waydroid-fingerprint/`, and the included service into
`~/.config/systemd/user/`. Then install the additive declarations:

```sh
pkexec /usr/bin/python3 /absolute/path/to/host-setup.py
waydroid session stop
systemctl --user daemon-reload
systemctl --user enable --now waydroid-fingerprint.service
```

Launch Android normally. In Android Settings, enroll a fingerprint using your
Android PIN and touches on the Mac's existing Touch ID sensor. The PIN may still
be required after an Android reboot before biometrics become eligible.

Observe the service with `journalctl --user -u waydroid-fingerprint.service`.
The service never logs a PIN, fingerprint template, or one-time code.

## Remove

```sh
systemctl --user disable --now waydroid-fingerprint.service
pkexec /usr/bin/python3 /absolute/path/to/host-setup.py --remove
waydroid session stop
```

Restart Android normally. Optionally delete the host service, copied scripts,
and `~/.local/state/waydroid-fingerprint/` afterward. Linux fingerprints and
Authenticator accounts are unchanged. The installer refuses to overwrite
unowned declarations and removes only its two marked XML files.

## Protocol sources

Pinned source: Android hardware/interfaces `android16-release`, commit
`5688f7eb1e117ed26e642a695de300b7683acb87`:

- `biometrics/fingerprint/aidl/aidl_api/android.hardware.biometrics.fingerprint/1`
- `biometrics/common/aidl/aidl_api/android.hardware.biometrics.common/1`
- `keymaster/aidl/aidl_api/android.hardware.keymaster/1`

For the feasibility evidence and inspected APK hashes, see
`~/.local/state/waydroid-fingerprint-audit/`. Unit tests alone do not establish
Android wire compatibility or real App Lock success; both require runtime checks.

## Verified on this workstation — 2026-11-02

Android recognized the weak sensor, a real fprintd match registered an enrollment,
and the user confirmed Touch ID unlocked Microsoft Authenticator. The service
is enabled at login. The setup screen did not advance cleanly after the first
match despite recording it; future enrollment progress needs correction.
Enrollment MAC bytes are zero-filled on this image; they are not used as proof.
The bridge trusts the restricted Android caller and its fresh enrollment challenge,
and always requires an actual Linux fingerprint match.

## Lifecycle fixes — 2026-11-02

The host daemon now waits for Binder access instead of crash-looping before
Waydroid starts. Each scan activates fprintd before resolving its unique D-Bus
owner, because fprintd can exit while idle. One-way cancellation calls may have
PID zero; they are accepted only on the cancellation capability issued to the
verified system_server, only from uid 1000, and only for the cancel transaction.
Authentication and enrollment retain their full caller checks. Backend startup
exceptions and numeric HAL errors are logged without token or credential data.
