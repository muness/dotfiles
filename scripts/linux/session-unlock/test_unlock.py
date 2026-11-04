import unittest
from unittest.mock import patch

import unlock


class FakeKeyring:
    def __init__(self, locked=True, default='/collection/default'):
        self.is_locked, self.path = locked, default
        self.attempts = []

    def default(self):
        return self.path

    def locked(self, path):
        return self.is_locked

    def unlock(self, path, password):
        self.attempts.append((path, password))
        if password != b'correct-secret':
            raise unlock.UnlockError('Incorrect password')
        self.is_locked = False


class UnlockTests(unittest.TestCase):
    config = {'collection': '/collection/default', 'keyring_ref': 'op://vault/item/field'}

    def test_unlocked_keyring_never_reads_vault(self):
        with patch('unlock.read_secret') as reader:
            self.assertFalse(unlock.unlock(self.config, FakeKeyring(False), reader))
            reader.assert_not_called()

    def test_different_collection_never_receives_secret(self):
        with patch('unlock.read_secret') as reader:
            with self.assertRaises(unlock.UnlockError):
                unlock.unlock(self.config, FakeKeyring(default='/different'), reader)
            reader.assert_not_called()

    def test_cancelled_vault_access_never_attempts_unlock(self):
        keyring = FakeKeyring()
        def cancelled(_):
            raise unlock.UnlockError('Cancelled')
        with self.assertRaises(unlock.UnlockError):
            unlock.unlock(self.config, keyring, cancelled)
        self.assertEqual(keyring.attempts, [])

    def test_wrong_password_fails_without_retries(self):
        keyring = FakeKeyring()
        with self.assertRaises(unlock.UnlockError):
            unlock.unlock(self.config, keyring, lambda _: b'incorrect')
        self.assertEqual(len(keyring.attempts), 1)
        self.assertTrue(keyring.is_locked)

    def test_success(self):
        self.assertTrue(unlock.unlock(self.config, FakeKeyring(), lambda _: b'correct-secret'))

    def test_secret_only_in_stdin_and_desktop_auth_required(self):
        import subprocess
        with patch.dict('os.environ', {'OP_SERVICE_ACCOUNT_TOKEN': 'sensitive',
                                      'OP_SESSION_example': 'session', 'DISPLAY': ':1'}):
            with patch('unlock.subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'{}', b'')) as run:
                unlock.op(['item', 'create', '-'], b'secret-payload')
        args, kwargs = run.call_args
        self.assertNotIn('secret-payload', repr(args))
        self.assertEqual(kwargs['input'], b'secret-payload')
        self.assertEqual(kwargs['env']['OP_BIOMETRIC_UNLOCK_ENABLED'], 'true')
        self.assertNotIn('OP_SERVICE_ACCOUNT_TOKEN', kwargs['env'])
        self.assertNotIn('OP_SESSION_example', kwargs['env'])

    def test_cli_errors_do_not_disclose_payload(self):
        import subprocess
        with patch('unlock.subprocess.run', return_value=subprocess.CompletedProcess([], 1, b'', b'secret-payload')):
            with self.assertRaises(unlock.UnlockError) as caught:
                unlock.op(['item', 'create', '-'], b'secret-payload')
        self.assertNotIn('secret-payload', str(caught.exception))

    def test_reject_dynamic_references_and_empty_secrets(self):
        for ref in ['bad', 'op://v/i/f?attribute=otp']:
            with self.assertRaises(unlock.UnlockError):
                unlock.read_secret(ref)
        with patch('unlock.op', return_value=b''):
            with self.assertRaises(unlock.UnlockError):
                unlock.read_secret('op://v/i/f')


if __name__ == '__main__':
    unittest.main()
