"""Credential completion evidence for the inspected Android 16 AuthSession."""
import re


def credential_confirmed(before, after, state):
    if not after.startswith(before) or b'CurrentSession: null' not in state:
        return False
    fresh = after[len(before):]
    if b'credentialAttestation is null' in fresh:
        return False
    if re.search(rb'Dismissed! [^\n]*User: 0[^\n]*Reason: 7, Error: 0', fresh):
        return True
    # This build filters verbose events. In AOSP android16-release
    # AuthSession.onDialogDismissed, this exact message is emitted on the
    # successful credential/biometric branch immediately before invoking
    # mClientReceiver.onAuthenticationSucceeded. For this path our helper has
    # just submitted the credential UI; a null credential HAT is rejected above.
    return bool(re.search(rb'E/BiometricService/AuthSession\([^\n]*\): mTokenEscrow is null', fresh))
