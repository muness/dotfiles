"""Regression checks for portal detection alongside a working USB tether."""
import importlib.util
from pathlib import Path
import socket
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('portal', Path(__file__).with_name('captive-portal.py'))
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)
NM = portal.NM


class PortalTests(unittest.TestCase):
    def test_per_device_portal_and_window_lifecycle(self):
        state = NM.ConnectivityState.PORTAL
        process = SimpleNamespace(poll=lambda: None)
        launches = []
        device = SimpleNamespace(
            get_state=lambda: NM.DeviceState.ACTIVATED,
            get_connectivity=lambda family: state if family == socket.AF_INET else NM.ConnectivityState.LIMITED)
        watch = portal.PortalWatch(lambda: launches.append(True) or process)
        # An IPv4 portal must launch even with limited IPv6 and a separate
        # full-connectivity USB tether (no aggregate client state is consulted).
        watch.changed(device)
        watch.changed(device)
        self.assertEqual(len(launches), 1)
        process.poll = lambda: 0
        watch.changed(device)
        self.assertEqual(len(launches), 1)
        for state in (NM.ConnectivityState.NONE, NM.ConnectivityState.LIMITED, NM.ConnectivityState.FULL):
            watch.changed(device)
        self.assertEqual(len(launches), 1)
        state = NM.ConnectivityState.PORTAL
        watch.changed(device)
        self.assertEqual(len(launches), 2)

    def test_login_redirect_probed_on_wifi_and_passed_to_gui(self):
        url = 'http://172.24.0.1:8002/index.php?zone=freewifi'
        device = SimpleNamespace(get_iface=lambda: 'wld0')
        with patch.object(portal.subprocess, 'run', return_value=SimpleNamespace(stdout=url)) as probe:
            with patch.object(portal.subprocess, 'Popen') as gui:
                portal.launch_assistant(device, 'http://example.test/check')
        self.assertIn('--interface', probe.call_args.args[0])
        self.assertIn('wld0', probe.call_args.args[0])
        gui.assert_called_once_with(['/usr/bin/io.elementary.capnet-assist', '--url', url])


if __name__ == '__main__':
    unittest.main()
