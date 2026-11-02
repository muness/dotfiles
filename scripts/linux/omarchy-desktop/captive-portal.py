#!/usr/bin/python3
"""Open the portal assistant once per captive connection in the desktop session."""
import subprocess
import socket
from urllib.parse import urlsplit

import gi

gi.require_version('NM', '1.0')
from gi.repository import GLib, NM


def launch_assistant(device, uri):
    # A working USB tether can own the default route. Obtain the redirect on
    # the captive interface, then give the assistant the actual login URL.
    url = uri
    try:
        result = subprocess.run(
            ['/usr/bin/curl', '--interface', device.get_iface(), '--noproxy', '*',
             '--max-time', '8', '--silent', '--output', '/dev/null',
             '--write-out', '%{redirect_url}', uri],
            capture_output=True, text=True, timeout=10, check=True)
        redirect = result.stdout.strip()
        if urlsplit(redirect).scheme in ('http', 'https') and urlsplit(redirect).netloc:
            url = redirect
    except (OSError, subprocess.SubprocessError):
        pass
    return subprocess.Popen(['/usr/bin/io.elementary.capnet-assist', '--url', url])


class PortalWatch:
    def __init__(self, launch=None):
        self.launch = launch
        self.portal = False
        self.assistant = None

    def changed(self, device, *_args):
        portal = (device.get_state() == NM.DeviceState.ACTIVATED and any(
            device.get_connectivity(family) == NM.ConnectivityState.PORTAL
            for family in (socket.AF_INET, socket.AF_INET6)))
        if portal and not self.portal:
            # Repeated notifications must not create more login windows.
            if self.assistant is None or self.assistant.poll() is not None:
                self.assistant = self.launch()
                print('Captive portal detected; opened login assistant.', flush=True)
        self.portal = portal


def main():
    client = NM.Client.new(None)
    watches = {}

    def added(_client, device):
        if not isinstance(device, NM.DeviceWifi) or device in watches:
            return
        uri = client.connectivity_check_get_uri() or 'http://nmcheck.gnome.org/check_network_status.txt'
        watch = PortalWatch(lambda: launch_assistant(device, uri))
        signals = [device.connect('notify::' + prop, watch.changed)
                   for prop in ('ip4-connectivity', 'ip6-connectivity', 'state')]
        watches[device] = (watch, signals)
        watch.changed(device)

    def removed(_client, device):
        entry = watches.pop(device, None)
        if entry:
            for handler in entry[1]:
                device.disconnect(handler)

    client.connect('device-added', added)
    client.connect('device-removed', removed)
    for device in client.get_devices():
        added(client, device)
    print('Watching each Wi-Fi device for captive portals.', flush=True)
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
