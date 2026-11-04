#!/usr/bin/python3
"""Per-Wi-Fi portal state, persistent tray action, and interface-bound Foyer."""
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import subprocess
import sys
from urllib.parse import urlsplit

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
import gi

gi.require_version('NM', '1.0')
from gi.repository import GLib, NM

BUS = 'org.omarchy.CaptivePortal'
PATH = '/StatusNotifierItem'
SNI = 'org.kde.StatusNotifierItem'
CONTROL = 'org.omarchy.CaptivePortal'
FOYER = Path.home() / '.local/libexec/foyer-0.1.0'


def launch_assistant(device, uri):
    """Bind all portal DNS and connections, not only the initial probe."""
    iface = device.get_iface()
    # Resolve the HTTP interception on Wi-Fi before opening Chrome. Most
    # portals then provide a real HTTPS login URL rather than a probe page.
    try:
        result = subprocess.run(['/usr/bin/curl', '--interface', iface, '--noproxy', '*',
                                 '--max-time', '5', '--silent', '--output', '/dev/null',
                                 '--write-out', '%{redirect_url}', uri],
                                capture_output=True, text=True, timeout=6, check=True)
        redirect = result.stdout.strip()
        if urlsplit(redirect).scheme in ('http', 'https') and urlsplit(redirect).netloc:
            uri = redirect
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    directory = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'omarchy-captive'
    directory.mkdir(mode=0o700, exist_ok=True)
    config = directory / f'{iface}.toml'
    dns_command = shlex.join(['/usr/bin/nmcli', '-g', 'IP4.DNS', 'device', 'show', iface])
    browser_command = shlex.join([str(Path.home() / '.local/libexec/omarchy-portal-browser'), uri])
    config.write_text(f'interface = {json.dumps(iface)}\nbind-device = true\n'
                      f'dhcp-dns = {json.dumps(dns_command)}\nstart-url = {json.dumps(uri)}\n'
                      f'browser = {json.dumps(browser_command)}\n')
    return subprocess.Popen([str(FOYER), '-config', str(config)], start_new_session=True)


def focus_assistant(process):
    """Focus only a window belonging to our Foyer process tree."""
    try:
        windows = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j'], text=True, timeout=2))
        for window in windows:
            pid = window['pid']
            while pid > 1 and pid != process.pid:
                stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
                pid = int(stat[1])
            if pid == process.pid:
                selector = json.dumps('address:' + window['address'])
                subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{ window = {selector} }})'], timeout=2)
                return
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        pass


class PortalWatch:
    def __init__(self, launch, updated=lambda: None, focus=focus_assistant):
        self.launch, self.updated, self.focus = launch, updated, focus
        self.pending = False
        self.connection = None
        self.assistant = None

    def open(self):
        if self.assistant is None or self.assistant.poll() is not None:
            try:
                self.assistant = self.launch()
            except OSError as error:
                print(f'Could not open Wi-Fi sign-in: {error}', flush=True)
        else:
            self.focus(self.assistant)

    def stop(self):
        if self.assistant is not None and self.assistant.poll() is None:
            try:
                os.killpg(self.assistant.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.assistant = None

    def changed(self, device, *_args):
        active = device.get_active_connection()
        key = active.get_path() if active else None
        if key != self.connection or device.get_state() != NM.DeviceState.ACTIVATED:
            self.pending = False
            self.stop()
        self.connection = key
        if key and device.get_state() == NM.DeviceState.ACTIVATED:
            states = [device.get_connectivity(f) for f in (socket.AF_INET, socket.AF_INET6)]
            if NM.ConnectivityState.PORTAL in states:
                if not self.pending:
                    self.pending = True
                    self.open()
            elif NM.ConnectivityState.FULL in states:
                self.pending = False
                self.stop()
            # Preserve pending across limited/unknown states and browser exit.
        self.updated()


class Tray(dbus.service.Object):
    def __init__(self, bus, watches):
        self.watches = watches
        self.bus = bus
        self.name = dbus.service.BusName(BUS, bus=bus, do_not_queue=True)
        super().__init__(self.name, PATH)
        bus.watch_name_owner('org.kde.StatusNotifierWatcher', self.register)

    def register(self, owner):
        if owner:
            try:
                watcher = self.bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher')
                watcher.RegisterStatusNotifierItem(BUS, dbus_interface='org.kde.StatusNotifierWatcher')
            except dbus.DBusException as error:
                print(f'Tray registration: {error}', flush=True)

    def pending(self):
        return [(device, watch) for device, (watch, _signals) in self.watches.items() if watch.pending]

    def properties(self):
        pending = self.pending()
        label = ', '.join(device.get_active_connection().get_id() for device, _watch in pending)
        title = 'Wi-Fi sign-in needed' + (f': {label}' if label else '')
        return {'Category': 'Communications', 'Id': 'omarchy-wifi-signin', 'Title': title,
                'Status': 'NeedsAttention' if pending else 'Passive', 'WindowId': dbus.UInt32(0),
                'IconName': 'network-wireless-no-route-symbolic',
                'AttentionIconName': 'network-wireless-no-route-symbolic',
                'ItemIsMenu': False, 'Menu': dbus.ObjectPath('/'),
                'ToolTip': dbus.Struct(('network-wireless-no-route-symbolic',
                    dbus.Array([], signature='(iiay)'), title, 'Click to open or reopen Wi-Fi sign-in.'))}

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return self.properties() if interface == SNI else {}

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        return self.GetAll(interface)[name]

    @dbus.service.signal(SNI, signature='s')
    def NewStatus(self, status):
        pass

    @dbus.service.signal(SNI)
    def NewToolTip(self):
        pass

    @dbus.service.signal(SNI)
    def NewTitle(self):
        pass

    def updated(self):
        self.NewStatus(self.properties()['Status'])
        self.NewToolTip()
        self.NewTitle()

    @dbus.service.method(SNI, in_signature='ii')
    def Activate(self, _x, _y):
        self.Open()

    @dbus.service.method(SNI, in_signature='ii')
    def SecondaryActivate(self, _x, _y):
        self.Open()

    @dbus.service.method(SNI, in_signature='ii')
    def ContextMenu(self, _x, _y):
        self.Open()

    @dbus.service.method(CONTROL)
    def Open(self):
        targets = self.pending()
        if not targets:
            # The app launcher is also a manual fallback for a missed portal.
            targets = [(d, w) for d, (w, _signals) in self.watches.items()
                       if d.get_state() == NM.DeviceState.ACTIVATED]
        for _device, watch in targets:
            states = [_device.get_connectivity(f) for f in (socket.AF_INET, socket.AF_INET6)]
            if watch.pending or NM.ConnectivityState.FULL not in states:
                watch.open()
            else:
                subprocess.Popen(['/usr/bin/notify-send', '--app-name=Wi-Fi Sign-in',
                                  'Wi-Fi is online',
                                  _device.get_active_connection().get_id() + ' has internet access. No sign-in is needed.'])

    @dbus.service.method(CONTROL, out_signature='s')
    def Status(self):
        return json.dumps([{'interface': d.get_iface(), 'connection': d.get_active_connection().get_id(),
                            'pending': True, 'browser_running': w.assistant is not None and w.assistant.poll() is None}
                           for d, w in self.pending()])


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    if len(sys.argv) > 1:
        service = bus.get_object(BUS, PATH)
        if sys.argv[1] == '--open':
            service.Open(dbus_interface=CONTROL)
        elif sys.argv[1] == '--status':
            print(service.Status(dbus_interface=CONTROL))
        else:
            raise SystemExit('Usage: omarchy-captive-portal [--open|--status]')
        return
    client = NM.Client.new(None)
    watches = {}
    tray = Tray(bus, watches)

    def added(_client, device):
        if not isinstance(device, NM.DeviceWifi) or device in watches:
            return
        uri = client.connectivity_check_get_uri() or 'http://nmcheck.gnome.org/check_network_status.txt'
        watch = PortalWatch(lambda: launch_assistant(device, uri), tray.updated)
        signals = [device.connect('notify::' + prop, watch.changed)
                   for prop in ('ip4-connectivity', 'ip6-connectivity', 'state', 'active-connection')]
        watches[device] = (watch, signals)
        watch.changed(device)

    def removed(_client, device):
        entry = watches.pop(device, None)
        if entry:
            entry[0].stop()
            for handler in entry[1]:
                device.disconnect(handler)
            tray.updated()

    def check():
        if any(watch.pending for watch, _signals in watches.values()):
            client.check_connectivity_async(None, checked, None)
        return GLib.SOURCE_CONTINUE

    def checked(client, result, _data):
        try:
            client.check_connectivity_finish(result)
        except GLib.Error as error:
            print(f'Connectivity recheck: {error}', flush=True)
        # Ignore the aggregate answer; each device's property is authoritative.
        for device, (watch, _signals) in list(watches.items()):
            watch.changed(device)

    client.connect('device-added', added)
    client.connect('device-removed', removed)
    for device in client.get_devices():
        added(client, device)
    GLib.timeout_add_seconds(10, check)
    print('Watching Wi-Fi portals; persistent tray action uses interface-bound Foyer.', flush=True)
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
