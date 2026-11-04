import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('android_flow', Path(__file__).with_name('android-unlock.py'))
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)


class RecordingPipe(io.BytesIO):
    def close(self):
        self.sent = self.getvalue()
        super().close()


class AndroidFlowTests(unittest.TestCase):
    def run_flow(self, ready=b'READY keyguard-pin', result=b'VERIFIED_DEVICE_UNLOCK\n', failure=None):
        child = Mock()
        child.stdin = RecordingPipe()
        child.stdout = io.BytesIO(ready + b'\n' + result)
        child.poll.return_value = 0
        child.wait.return_value = 0
        config = Mock()
        config.read_text.return_value = json.dumps({'android_ref': 'op://vault/item/android_pin'})
        events = []
        def fingerprint():
            events.append('fingerprint')
            if failure:
                raise flow.UnlockError(failure)
        original_write = child.stdin.write
        def write(data):
            events.append('write')
            return original_write(data)
        child.stdin.write = write
        with patch.object(flow, 'CONFIG', config), patch.object(flow, 'harden'), \
             patch.object(flow.select, 'select', return_value=([child.stdout], [], [])), \
             patch.object(flow.subprocess, 'Popen', return_value=child) as spawn, \
             patch.object(flow, 'read_secret', return_value=b'123456') as reader, \
             patch.object(flow, 'fresh_fingerprint', side_effect=fingerprint):
            error = None
            try:
                flow.main()
            except flow.UnlockError as caught:
                error = caught
        return child, spawn, reader, events, error

    def test_pin_only_in_pipe_after_match(self):
        child, spawn, reader, events, error = self.run_flow()
        self.assertIsNone(error)
        self.assertEqual(events, ['fingerprint', 'write'])
        self.assertEqual(child.stdin.sent, b'123456\n')
        self.assertNotIn('123456', repr(spawn.call_args))

    def test_wrong_target_does_not_read_pin(self):
        child, _, reader, events, error = self.run_flow(ready=b'NO_CREDENTIAL_UI')
        self.assertIsNotNone(error)
        reader.assert_not_called()
        self.assertEqual(child.stdin.sent, b'')
        self.assertEqual(events, [])

    def test_cancel_does_not_submit_or_retry(self):
        child, _, _, events, error = self.run_flow(failure='Cancelled')
        self.assertEqual(str(error), 'Cancelled')
        self.assertEqual(events, ['fingerprint'])
        self.assertEqual(child.stdin.sent, b'')

    def test_click_without_authentication_is_not_success(self):
        _, _, _, _, error = self.run_flow(result=b'SUBMITTED_REQUIRES_VERIFICATION\n')
        self.assertIsNotNone(error)

    def test_strong_credential_result(self):
        _, _, _, events, error = self.run_flow(ready=b'READY systemui-credential',
                                             result=b'VERIFIED_CREDENTIAL_REQUEST\n')
        self.assertIsNone(error)
        self.assertEqual(events, ['fingerprint', 'write'])


if __name__ == '__main__':
    unittest.main()
