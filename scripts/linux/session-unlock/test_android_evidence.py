import unittest
from android_evidence import credential_confirmed


class EvidenceTests(unittest.TestCase):
    before = b'existing log\n'
    event = b'E/BiometricService/AuthSession( 420): mTokenEscrow is null\n'
    state = b'CurrentSession: null\n'

    def test_fresh_success_branch(self):
        self.assertTrue(credential_confirmed(self.before, self.before + self.event, self.state))

    def test_stale_success_does_not_count(self):
        self.assertFalse(credential_confirmed(self.before + self.event, self.before + self.event, self.state))

    def test_cancellation_does_not_count(self):
        self.assertFalse(credential_confirmed(self.before, self.before + b'onCancelAuthSession\n', self.state))

    def test_missing_credential_attestation_does_not_count(self):
        self.assertFalse(credential_confirmed(self.before, self.before + b'credentialAttestation is null\n' + self.event, self.state))

    def test_unsettled_request_does_not_count(self):
        self.assertFalse(credential_confirmed(self.before, self.before + self.event, b'CurrentSession: State: 9'))

    def test_log_rotation_fails_closed(self):
        self.assertFalse(credential_confirmed(self.before, self.event, self.state))


if __name__ == '__main__':
    unittest.main()
