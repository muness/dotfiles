"""Portal lifecycle regressions: tether success must not retire Wi-Fi sign-in."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import tomllib
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('portal', Path(__file__).with_name('captive-portal.py'))
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)
NM = portal.NM


class Device:
    def __init__(self):
        self.key = '/connection/1'
        self.state = NM.DeviceState.ACTIVATED
        self.ip4 = NM.ConnectivityState.PORTAL
        self.ip6 = NM.ConnectivityState.LIMITED

    def get_active_connection(self):
        return SimpleNamespace(get_path=lambda: self.key, get_id=lambda: 'Airport') if self.key else None

    def get_state(self):
        return self.state

    def get_connectivity(self, family):
        return self.ip4 if family == socket.AF_INET else self.ip6

    def get_iface(self):
        return 'wld0'


class PortalTests(unittest.TestCase):
    def setUp(self):
        self.device = Device()
        self.process = Mock(pid=12345)
        self.process.poll.return_value = None
        self.launch = Mock(return_value=self.process)
        self.focus = Mock()
        self.watch = portal.PortalWatch(self.launch, focus=self.focus)

    def test_closed_browser_remains_reopenable_during_limited_and_unknown(self):
        self.watch.changed(self.device)
        self.process.poll.return_value = 0
        for state in (NM.ConnectivityState.PORTAL, NM.ConnectivityState.LIMITED,
                      NM.ConnectivityState.UNKNOWN, NM.ConnectivityState.NONE):
            self.device.ip4 = state
            self.watch.changed(self.device)
            self.assertTrue(self.watch.pending)
        self.launch.assert_called_once()
        self.watch.open()
        self.assertEqual(self.launch.call_count, 2)

    def test_repeated_activation_focuses_owned_browser_without_duplicates(self):
        self.watch.changed(self.device)
        self.watch.changed(self.device)
        self.watch.open()
        self.launch.assert_called_once()
        self.focus.assert_called_once_with(self.process)

    def test_other_connection_full_does_not_clear_portal_even_if_ipv6_full(self):
        # There is deliberately no global client connectivity input to this state machine.
        self.device.ip6 = NM.ConnectivityState.FULL
        self.watch.changed(self.device)
        self.assertTrue(self.watch.pending)
        self.device.ip4 = NM.ConnectivityState.FULL
        with patch.object(portal.os, 'killpg') as kill:
            self.watch.changed(self.device)
        self.assertFalse(self.watch.pending)
        kill.assert_called_once_with(self.process.pid, portal.signal.SIGTERM)

    def test_connection_switch_and_disconnect_retire_old_pending_state(self):
        self.watch.changed(self.device)
        self.device.key = '/connection/2'
        self.device.ip4 = NM.ConnectivityState.LIMITED
        with patch.object(portal.os, 'killpg'):
            self.watch.changed(self.device)
        self.assertFalse(self.watch.pending)
        self.device.ip4 = NM.ConnectivityState.PORTAL
        self.watch.changed(self.device)
        self.assertTrue(self.watch.pending)
        self.device.state = NM.DeviceState.DISCONNECTED
        with patch.object(portal.os, 'killpg'):
            self.watch.changed(self.device)
        self.assertFalse(self.watch.pending)

    def test_launch_failure_preserves_retry_action(self):
        self.launch.side_effect = FileNotFoundError('foyer')
        self.watch.changed(self.device)
        self.assertTrue(self.watch.pending)
        self.watch.open()
        self.assertEqual(self.launch.call_count, 2)

    def test_config_binds_browser_and_dns_to_wifi_instead_of_default_interface(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_RUNTIME_DIR=directory):
            with patch.object(portal.subprocess, 'Popen') as popen, patch.object(
                    portal.subprocess, 'run', return_value=SimpleNamespace(stdout='')):
                portal.launch_assistant(self.device, 'http://example.test/check?x="quoted"')
            args = popen.call_args.args[0]
            config = tomllib.loads(Path(args[2]).read_text())
        self.assertEqual(config['interface'], 'wld0')
        self.assertTrue(config['bind-device'])
        self.assertEqual(config['dhcp-dns'], '/usr/bin/nmcli -g IP4.DNS device show wld0')
        self.assertEqual(config['start-url'], 'http://example.test/check?x="quoted"')
        self.assertIn('omarchy-portal-browser', config['browser'])
        self.assertTrue(popen.call_args.kwargs['start_new_session'])

    def test_captive_redirect_is_resolved_on_wifi_before_browser_launch(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_RUNTIME_DIR=directory):
            with patch.object(portal.subprocess, 'Popen') as popen, patch.object(
                    portal.subprocess, 'run', return_value=SimpleNamespace(stdout='https://portal.test/login')) as probe:
                portal.launch_assistant(self.device, 'http://probe.test')
            config = tomllib.loads(Path(popen.call_args.args[0][2]).read_text())
        self.assertIn('wld0', probe.call_args.args[0])
        self.assertEqual(config['start-url'], 'https://portal.test/login')
        self.assertIn('https://portal.test/login', config['browser'])

    def test_tray_retains_click_action_after_browser_exit_and_hides_after_wifi_success(self):
        tray = portal.Tray.__new__(portal.Tray)
        tray.watches = {self.device: (self.watch, [])}
        self.watch.changed(self.device)
        self.process.poll.return_value = 0
        self.assertEqual(tray.properties()['Status'], 'NeedsAttention')
        self.assertIn('Airport', tray.properties()['Title'])
        tray.Activate(0, 0)
        self.assertEqual(self.launch.call_count, 2)
        self.assertTrue(json.loads(tray.Status())[0]['pending'])
        self.device.ip4 = NM.ConnectivityState.FULL
        self.watch.changed(self.device)
        self.assertEqual(tray.properties()['Status'], 'Passive')
        self.assertEqual(json.loads(tray.Status()), [])

    def test_manual_launcher_can_open_when_detection_missed_a_portal(self):
        tray = portal.Tray.__new__(portal.Tray)
        tray.watches = {self.device: (self.watch, [])}
        self.device.ip4 = NM.ConnectivityState.LIMITED
        self.watch.changed(self.device)
        tray.Open()
        self.launch.assert_called_once()
        self.assertFalse(self.watch.pending)

    def test_manual_launcher_reports_online_instead_of_opening_probe_page(self):
        tray = portal.Tray.__new__(portal.Tray)
        tray.watches = {self.device: (self.watch, [])}
        self.device.ip4 = NM.ConnectivityState.FULL
        self.watch.changed(self.device)
        with patch.object(portal.subprocess, 'Popen') as notify:
            tray.Open()
        self.launch.assert_not_called()
        self.assertIn('Wi-Fi is online', notify.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
