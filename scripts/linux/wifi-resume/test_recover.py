import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('recover', Path(__file__).with_name('recover.py'))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        for name, value in [('supported', True), ('wifi', 'wld0'), ('allowed', True),
                            ('state', 30), ('rejects', 0)]:
            mocked = patch.object(helper, name, return_value=value)
            mocked.start()
            self.addCleanup(mocked.stop)
        for name, value in [('GRACE', 2), ('RECONNECT', 2)]:
            mocked = patch.object(helper, name, value)
            mocked.start()
            self.addCleanup(mocked.stop)
        for name in ('sleep',):
            mocked = patch.object(helper.time, name)
            mocked.start()
            self.addCleanup(mocked.stop)
        self.reload = patch.object(helper, 'reload_driver').start()
        self.addCleanup(patch.stopall)

    def test_healthy_connection_never_reloads(self):
        helper.state.return_value = 100
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_not_called()

    def test_force_mode_skips_detection_wait_and_reloads_immediately(self):
        helper.state.return_value = 100
        self.assertEqual(helper.recover(force=True), 0)
        self.reload.assert_called_once()
        helper.rejects.assert_not_called()
        helper.time.sleep.assert_not_called()

    def test_disabled_or_deliberately_disconnected_never_reloads_even_forced(self):
        helper.allowed.return_value = False
        self.assertEqual(helper.recover(force=True), 0)
        self.reload.assert_not_called()

    def test_no_network_available_does_not_reset_idle_radio(self):
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_not_called()

    def test_slow_dhcp_is_not_mistaken_for_broken_authentication(self):
        helper.state.return_value = 70
        helper.rejects.return_value = 2  # Earlier retries, before authentication succeeded.
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_not_called()

    def test_repeated_authentication_failures_reload_and_wait_for_connection(self):
        helper.rejects.return_value = 2
        helper.state.side_effect = [50, 20, 100]
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_called_once()

    def test_stuck_connecting_without_journal_signature_recovers_after_grace(self):
        helper.state.side_effect = [50, 50, 50, 100]
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_called_once()

    def test_single_transient_reject_followed_by_connection_does_not_reload(self):
        helper.rejects.return_value = 1
        helper.state.side_effect = [50, 100]
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_not_called()

    def test_persistent_first_reject_recovers_without_waiting_for_second(self):
        helper.rejects.return_value = 1
        helper.state.side_effect = [50, 50, 50, 50, 100]
        with patch.object(helper, 'GRACE', 25):
            self.assertEqual(helper.recover(), 0)
        self.reload.assert_called_once()
        self.assertEqual(helper.state.call_count, 5)

    def test_radio_disabled_during_wait_cancels_recovery(self):
        helper.allowed.side_effect = [True, True, False]
        self.assertEqual(helper.recover(), 0)
        self.reload.assert_not_called()

    def test_failed_reconnection_is_not_reported_as_success(self):
        helper.rejects.return_value = 2
        with self.assertRaisesRegex(RuntimeError, 'did not reconnect'):
            helper.recover()

    def test_unsupported_hardware_is_untouched(self):
        helper.supported.return_value = False
        self.assertEqual(helper.recover(force=True), 0)
        self.reload.assert_not_called()


class HardwareAndReloadTests(unittest.TestCase):
    def test_bcm4388_is_supported_but_other_broadcom_devices_are_not(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            device = root / '0000:01:00.0'
            device.mkdir()
            (device / 'vendor').write_text('0x14e4\n')
            (device / 'device').write_text('0x4434\n')
            (device / 'driver').symlink_to('/sys/bus/pci/drivers/brcmfmac')
            with patch.object(helper, 'PCI', root), patch.object(helper.platform, 'machine', return_value='aarch64'):
                self.assertTrue(helper.supported())
                (device / 'device').write_text('0x43a0\n')
                self.assertFalse(helper.supported())

    def test_partial_unload_failure_still_attempts_to_restore_driver(self):
        fail = subprocess.CalledProcessError(1, 'modprobe')
        with patch.object(helper, 'command', side_effect=['', fail, '']) as command, \
             patch.object(helper, 'state', return_value=10), \
             patch.object(helper, 'supplicant_attached', return_value=False), \
             patch.object(helper, 'restore_management') as restore:
            with self.assertRaises(subprocess.CalledProcessError):
                helper.reload_driver('wld0')
            self.assertEqual(command.call_args_list[-1].args, ('/usr/bin/modprobe', 'brcmfmac'))
            restore.assert_called_once()

    def test_attached_supplicant_prevents_module_unload_and_restores_management(self):
        with patch.object(helper, 'command') as command, \
             patch.object(helper, 'state', return_value=10), \
             patch.object(helper, 'supplicant_attached', return_value=True), \
             patch.object(helper.time, 'sleep'), \
             patch.object(helper, 'restore_management') as restore:
            with self.assertRaisesRegex(RuntimeError, 'refusing an unsafe'):
                helper.reload_driver('wld0')
            self.assertFalse(any('modprobe' in call.args[0] for call in command.call_args_list))
            restore.assert_called_once()

    def test_module_unload_only_after_supplicant_detaches(self):
        events = []
        def run(*args):
            events.append(args)
        def attached(interface):
            events.append(('detached', interface))
            return False
        with patch.object(helper, 'command', side_effect=run), \
             patch.object(helper, 'state', return_value=10), \
             patch.object(helper, 'supplicant_attached', side_effect=attached), \
             patch.object(helper, 'restore_management') as restore:
            helper.reload_driver('wld0')
        self.assertEqual(events[:3], [
            ('/usr/bin/nmcli', 'device', 'set', 'wld0', 'managed', 'no'),
            ('detached', 'wld0'),
            ('/usr/bin/modprobe', '-r', 'brcmfmac_wcc', 'brcmfmac')])
        restore.assert_called_once()

    def test_recovery_cannot_hold_start_job_or_wait_minutes_on_shutdown(self):
        unit = Path(__file__).with_name('dotfiles-wifi-resume.service').read_text()
        self.assertIn('Type=exec\n', unit)
        self.assertIn('TimeoutStopSec=5\n', unit)
        self.assertIn('RuntimeMaxSec=90\n', unit)

    def test_only_current_interface_authentication_timeouts_count(self):
        log = '\n'.join(['wld0: CTRL-EVENT-ASSOC-REJECT status_code=16',
                         'wlan1: CTRL-EVENT-ASSOC-REJECT status_code=16',
                         'wld0: CTRL-EVENT-ASSOC-REJECT status_code=1'])
        with patch.object(helper, 'command', return_value=log):
            self.assertEqual(helper.rejects('now', 'wld0'), 1)


if __name__ == '__main__':
    unittest.main()
