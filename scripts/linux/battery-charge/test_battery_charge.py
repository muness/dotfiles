import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).parent


def load(name, file):
    loader = importlib.machinery.SourceFileLoader(name, str(HERE / file))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


helper = load('helper', 'set-charge-limit.py')
installer = load('installer', 'install.py')
client = load('client', 'battery-charge')


class ChargeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.config = root / 'charge.conf'
        self.threshold = root / 'threshold'
        self.original = '# retain tuning\nSTOP_CHARGE_THRESH_BAT0=80\nOTHER=1\n'
        self.config.write_text(self.original)
        self.threshold.write_text('80\n')
        for name, value in [('CONFIG', self.config), ('THRESHOLD', self.threshold)]:
            p = patch.object(helper, name, value)
            p.start()
            self.addCleanup(p.stop)

    def test_both_modes_persist_and_apply(self):
        def apply(command, check):
            limit = self.config.read_text().split('STOP_CHARGE_THRESH_BAT0=')[1].splitlines()[0]
            self.threshold.write_text(limit)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(helper.subprocess, 'run', side_effect=apply):
            for limit in ('100', '80'):
                helper.set_limit(limit)
                self.assertEqual(self.threshold.read_text(), limit)
                self.assertEqual(self.config.read_text(), self.original.replace('=80', '=' + limit))

    def test_failed_apply_restores_config_and_runtime(self):
        def fail(command, check):
            if check:
                self.threshold.write_text('100')  # partial hardware write before failure
                raise subprocess.CalledProcessError(1, command)
            self.assertEqual(command, ['/usr/bin/tlp', 'setcharge', '80', '80'])
            self.threshold.write_text('80')
        with patch.object(helper.subprocess, 'run', side_effect=fail):
            with self.assertRaises(subprocess.CalledProcessError):
                helper.set_limit('100')
        self.assertEqual(self.config.read_text(), self.original)
        self.assertEqual(self.threshold.read_text(), '80')

    def test_discarded_hardware_write_is_failure(self):
        with patch.object(helper.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                helper.set_limit('100')
            self.assertEqual(run.call_count, 2)
        self.assertEqual(self.config.read_text(), self.original)

    def test_invalid_or_ambiguous_config_does_not_run_tlp(self):
        with patch.object(helper.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                helper.set_limit('99; reboot')
            self.config.write_text(self.original + 'STOP_CHARGE_THRESH_BAT0=100\n')
            with self.assertRaises(ValueError):
                helper.set_limit('100')
            run.assert_not_called()

    def test_cancel_authentication_does_not_retry_or_notify(self):
        with patch.object(client.sys, 'argv', ['battery-charge', '100']), \
             patch.object(client.subprocess, 'run', return_value=subprocess.CompletedProcess([], 126)) as run:
            self.assertEqual(client.main(), 126)
            run.assert_called_once_with(['/usr/bin/pkexec', '/usr/local/libexec/dotfiles-set-charge-limit', '100'])

    def test_menu_preserves_user_content_and_is_idempotent(self):
        for original in ('{}\n', '{\n // user notes\n "custom": {"label": "Custom"}\n}\n'):
            once = installer.extend_menu(original, Path('/home/user name/.local/bin/battery-charge'))
            self.assertEqual(once, installer.extend_menu(once, Path('/home/user name/.local/bin/battery-charge')))
            self.assertEqual(once.count('"battery-charge.home"'), 1)
            if 'user notes' in original:
                self.assertIn('// user notes', once)
                self.assertIn('"custom": {"label": "Custom"}', once)
            stripped = '\n'.join(line for line in once.splitlines() if not line.strip().startswith('//'))
            import re
            data = json.loads(re.sub(r',\s*}', '}', stripped))
            self.assertIn("'/home/user name/.local/bin/battery-charge'", data['battery-charge.travel']['action'])


if __name__ == '__main__':
    unittest.main()
