# Touch ID for Waydroid App Lock

## Aim and scope

Unlock Microsoft Authenticator App Lock with a fresh Linux fingerprint match.
Expose only a weak Android biometric, preserve device PIN fallback and existing
accounts, and leave KeyMint, Gatekeeper, app binaries and host PAM unchanged.
The host libgbinder service implements the frozen fingerprint AIDL v1 interface;
Android receives additive fingerprint feature and VINTF declarations.

## Execution checks

- [ ] Publish sensor properties and enumerate an enrollment through Android.
- [ ] Complete a real App Lock request only after a fresh fprintd match.
- [x] Reject nonzero cryptographic operation IDs (unit test; no pretend strong biometric).
- [x] Reject callers other than the container's system_server (unit test; runtime check pending).
- [x] Reject stale/unsolicited match, cancel, timeout, fprintd restart and failure (unit tests).
- [x] Release the fingerprint device on every terminal path (lifecycle tests; real device pending).
- [ ] No authentication callbacks after cancellation or callback death.
- [ ] PIN fallback works and no credential or account data is modified.
- [ ] Service and declarations survive a normal Waydroid restart.
- [x] Uninstall removes only bridge-owned files (temporary-tree tests; runtime rollback pending).

The tempting shortcut is to relay simulated virtual-HAL success or cache a
previous match. Neither is permitted. A unit test must demonstrate that each
failure path cannot produce success. Android registration/serialization must be
validated with the real framework, not only a mock client. The actual Touch ID
match and user-visible App Lock result require the user's physical interaction.

## Invalidation and stop conditions

Stop if App Lock requires a cryptographic token, requires claiming strong sensor
strength, or installation requires changing account keys, storing a PIN, or
disabling existing protection. Do not replace the current Android image to make
the bridge work. Use reversible overlay declarations and a host user service.

## Accepted limits

This is a host-trusted experimental biometric bridge, not Android biometric
certification or hardware-backed key release. Strong MFA/passkey paths remain
out of scope. The installed Android image already reports SELinux disabled;
the installer must refuse enforcing images until policy support is implemented.

## Current execution status

2026-11-02: Android sees sensor 71 at WEAK strength (255). A real fprintd
verify-match produced an enrollment, and the user confirmed that Touch ID
unlocked Microsoft Authenticator. The user service is enabled at login.
20 automated tests pass. No PIN, account data, host PAM, Gatekeeper or KeyMint
was changed.

Runtime corrections: enrollment HATs on this image contain a zero-filled MAC;
the parser accepts that shape but does not claim to verify it. Trusted caller,
credential type, expiry and challenge checks remain. The enrollment challenge
is sensor/user-scoped across Binder sessions. Rejected enrollment now reports
a normal HAL callback error instead of a transport exception, which previously
restarted Android's system_server.

Known limitation: the setup UI did not advance after the first matched touch,
even though Android recorded the enrollment. App Lock unlock is confirmed;
future enrollment UI progress still needs adjustment. Do not delete the working
enrollment solely to test that UI. Fresh-start sensor registration was verified;
full login startup and repeated container restart behavior remain untested.

## Review

Aim achieved for the installed user: a fresh Touch ID match unlocks App Lock,
with weak sensor strength and PIN fallback retained. Runtime wire compatibility,
actual enrollment and unlock are verified. Cancellation, failures, stale results,
lockout and cryptographic request rejection are covered by lifecycle tests.
Physical nonmatching-finger/timeout UX, rollback on the live image, login startup
and repeated restart checks remain follow-up verification; no equivalent
phone-grade biometric security or strong-key-release support is claimed.
