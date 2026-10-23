#!/usr/bin/python3
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('shutdown', Path(__file__).with_name('shutdown.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ShutdownTests(unittest.TestCase):
    def runner(self, statuses):
        return Mock(side_effect=[subprocess.CompletedProcess([], status) for status in statuses])

    def test_running_container_requires_privileged_stop_and_confirmation(self):
        run = self.runner([0, 0, 0, 3])
        module.shutdown(run)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ('/usr/bin/python3', '/usr/bin/waydroid', 'session', 'stop'))
        self.assertEqual(commands[2], ('/usr/bin/pkexec', '/usr/bin/systemctl', 'stop', 'waydroid-container.service'))
        self.assertEqual(commands[3][1:3], ('is-active', '--quiet'))

    def test_already_stopped_needs_no_authentication(self):
        run = self.runner([0, 3, 3])
        module.shutdown(run)
        self.assertFalse(any(call.args[0][0] == '/usr/bin/pkexec' for call in run.call_args_list))

    def test_cancelled_authentication_does_not_report_success(self):
        with self.assertRaisesRegex(RuntimeError, 'cancelled'):
            module.shutdown(self.runner([0, 0, 126]))

    def test_service_remaining_active_does_not_report_success(self):
        with self.assertRaisesRegex(RuntimeError, 'confirm'):
            module.shutdown(self.runner([0, 0, 0, 0]))

    def test_failed_session_stop_does_not_escalate(self):
        run = self.runner([1])
        with self.assertRaisesRegex(RuntimeError, 'session'):
            module.shutdown(run)
        self.assertEqual(run.call_count, 1)

    def test_bus_error_is_not_treated_as_stopped(self):
        with self.assertRaisesRegex(RuntimeError, 'determine'):
            module.shutdown(self.runner([0, 1]))


if __name__ == '__main__':
    unittest.main()
