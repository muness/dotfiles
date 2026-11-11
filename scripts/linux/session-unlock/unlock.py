#!/usr/bin/python3
"""Unlock the existing GNOME collection using a desktop-authorized 1Password read."""
import argparse
import ctypes
import fcntl
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

CONFIG = Path.home() / '.config/session-unlock/config.json'
OP = '/usr/local/bin/op'
SERVICE = 'org.freedesktop.Secret.Service'
COLLECTION = 'org.freedesktop.Secret.Collection'
INTERNAL = 'org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface'


class UnlockError(Exception):
    pass


def harden():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if ctypes.CDLL(None).prctl(4, 0, 0, 0, 0) != 0:  # PR_SET_DUMPABLE
        raise UnlockError('Could not disable process memory dumps.')


def op(args, payload=None):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('OP_')}
    env['OP_BIOMETRIC_UNLOCK_ENABLED'] = 'true'
    try:
        result = subprocess.run([OP, *args], input=payload, capture_output=True,
                                timeout=180, env=env)
    except (OSError, subprocess.TimeoutExpired):
        raise UnlockError('1Password was unavailable or timed out.') from None
    if result.returncode:
        # CLI errors can echo input or sensitive context: never forward them.
        raise UnlockError('1Password did not authorize the operation. Unlock the app and try again.')
    return result.stdout


def read_secret(reference):
    if not isinstance(reference, str) or not reference.startswith('op://') or '?' in reference:
        raise UnlockError('Expected a plain 1Password secret reference.')
    value = op(['read', '--no-newline', reference])
    if not value or len(value) > 4096 or b'\0' in value:
        raise UnlockError('The stored credential is empty or invalid.')
    return value


class Keyring:
    def __init__(self):
        import dbus
        self.dbus = dbus
        self.bus = dbus.SessionBus()
        self.root = self.bus.get_object('org.freedesktop.secrets', '/org/freedesktop/secrets')
        self.service = dbus.Interface(self.root, SERVICE)

    def default(self):
        path = str(self.service.ReadAlias('default'))
        if path == '/':
            raise UnlockError('No default keyring exists; no collection was created or changed.')
        return path

    def locked(self, path):
        return bool(self.dbus.Interface(
            self.bus.get_object('org.freedesktop.secrets', path),
            'org.freedesktop.DBus.Properties').Get(COLLECTION, 'Locked'))

    def unlock(self, path, password):
        # GNOME's private interface is required for a named, non-login keyring.
        # The secret travels over the local session bus, never argv or disk.
        _, session = self.service.OpenSession('plain', self.dbus.String('', variant_level=1))
        try:
            secret = self.dbus.Struct((self.dbus.ObjectPath(session),
                                      self.dbus.ByteArray(b''),
                                      self.dbus.ByteArray(password),
                                      'text/plain; charset=utf8'), signature='oayays')
            self.dbus.Interface(self.root, INTERNAL).UnlockWithMasterPassword(path, secret)
        finally:
            self.dbus.Interface(self.bus.get_object('org.freedesktop.secrets', session),
                                'org.freedesktop.Secret.Session').Close()
        if self.locked(path):
            raise UnlockError('The keyring did not unlock. Check its saved password.')


def unlock(config, keyring=None, reader=read_secret):
    keyring = keyring or Keyring()
    path = config['collection']
    if keyring.default() != path:
        raise UnlockError('The default keyring changed; run setup again.')
    if not keyring.locked(path):
        return False
    password = reader(config['keyring_ref'])
    keyring.unlock(path, password)
    return True


def setup():
    if CONFIG.exists():
        raise UnlockError('Setup already exists; edit the existing vault item instead of creating duplicates.')
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
    keyring = Keyring()
    collection = keyring.default()
    vaults = json.loads(op(['vault', 'list', '--format=json']))
    if not vaults:
        raise UnlockError('No writable vault was found.')
    dialog = Gtk.Dialog(title='Set up one-password session unlock')
    dialog.add_button('Cancel', Gtk.ResponseType.CANCEL)
    dialog.add_button('Save in 1Password', Gtk.ResponseType.OK)
    dialog.set_default_size(560, -1)
    box = dialog.get_content_area()
    box.set_spacing(12)
    box.set_border_width(20)
    label = Gtk.Label(label='Enter your EXISTING credentials. This does not change them.\n'
                      'They will be saved as concealed fields in a new 1Password item.\n'
                      'Your 1Password master password is not requested or stored here.')
    label.set_line_wrap(True)
    box.add(label)
    vault = Gtk.ComboBoxText()
    for entry in vaults:
        vault.append(entry['id'], entry['name'])
    vault.set_active(0)
    box.add(Gtk.Label(label='Destination vault'))
    box.add(vault)
    fields = []
    for caption in ('Current GNOME Keyring password',):
        box.add(Gtk.Label(label=caption))
        widget = Gtk.Entry()
        widget.set_visibility(False)
        widget.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        box.add(widget)
        fields.append(widget)
    dialog.show_all()
    try:
        if dialog.run() != Gtk.ResponseType.OK:
            return False
        password = fields[0].get_text()
        vault_id = vault.get_active_id()
        if not password:
            raise UnlockError('Provide the existing keyring password.')
        item = {'title': 'Asahi session unlock', 'category': 'SECURE_NOTE',
                'fields': [
                    {'id': 'keyring_password', 'label': 'Keyring password',
                     'type': 'CONCEALED', 'value': password}]}
        payload = json.dumps(item).encode()
        for entry in fields:
            entry.set_text('')
        dialog.hide()
        created = json.loads(op(['item', 'create', '--vault', vault_id,
                                 '--format=json', '-'], payload))
        item_id = created['id']
        config = {'collection': collection,
                  'keyring_ref': f'op://{vault_id}/{item_id}/keyring_password'}
        CONFIG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(str(CONFIG) + '.new', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(config, stream, indent=2)
            stream.write('\n')
        Path(str(CONFIG) + '.new').replace(CONFIG)
        return True
    finally:
        for entry in fields:
            entry.set_text('')
        dialog.destroy()


def main():
    harden()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--setup', action='store_true')
    parser.add_argument('--startup', action='store_true')
    args = parser.parse_args()
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if not runtime:
        raise UnlockError('Run inside the desktop session.')
    with open(Path(runtime) / 'session-unlock.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if args.setup:
            if setup():
                print('Created the vault item and saved secret references. Android integration is not enabled.')
        else:
            config = json.loads(CONFIG.read_text())
            if args.startup and Keyring().locked(config['collection']):
                subprocess.Popen(['/opt/1Password/1password'], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
            if unlock(config):
                print('Unlocked the desktop keyring.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, UnlockError) else 'Session unlock failed; no credentials were logged.'
        subprocess.run(['/usr/bin/notify-send', 'Session unlock', message], check=False)
        print(message, file=sys.stderr)
        sys.exit(1)
