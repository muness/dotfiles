#!/usr/bin/python3
"""Open the portal assistant once per captive connection in the desktop session."""
import subprocess

import gi

gi.require_version('NM', '1.0')
from gi.repository import GLib, NM


class PortalWatch:
    def __init__(self, launch=None):
        self.launch = launch or (lambda: subprocess.Popen(
            ['/usr/bin/io.elementary.capnet-assist']))
        self.portal = False
        self.assistant = None

    def changed(self, client, *_args):
        portal = client.get_connectivity() == NM.ConnectivityState.PORTAL
        if portal and not self.portal:
            # Repeated notifications must not create more login windows.
            if self.assistant is None or self.assistant.poll() is not None:
                self.assistant = self.launch()
                print('Captive portal detected; opened login assistant.', flush=True)
        self.portal = portal


def main():
    client = NM.Client.new(None)
    watch = PortalWatch()
    client.connect('notify::connectivity', watch.changed)
    watch.changed(client)  # Also handle a portal already present at login.
    print('Watching NetworkManager for captive portals.', flush=True)
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
