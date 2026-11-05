#!/usr/bin/python3
"""Explicit vault-backed Android unlock; no global keyboard injection."""
import json
from pathlib import Path
import select
import subprocess
import sys
import time
import fcntl
import os
import argparse

from unlock import CONFIG, UnlockError, harden, read_secret
STAGE = 'initialization'


def fresh_fingerprint():
    # Reuse the installed bridge's device lifecycle without starting its HAL.
    sys.path.insert(0, str(Path.home() / '.local/lib/waydroid-fingerprint'))
    from daemon import FprintBackend
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    dialog = Gtk.Dialog(title='Unlock Android with Touch ID')
    dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG)
    dialog.set_resizable(False)
    dialog.set_keep_above(True)
    dialog.set_skip_taskbar_hint(True)
    dialog.add_button('Cancel', Gtk.ResponseType.CANCEL)
    dialog.set_default_size(440, 190)
    box = dialog.get_content_area()
    box.set_border_width(24)
    box.set_spacing(16)
    label = Gtk.Label(label='Preparing Touch ID…\n'
                      'Your saved PIN will be sent only to Android’s credential prompt.')
    label.set_line_wrap(True)
    box.add(label)
    spinner = Gtk.Spinner()
    spinner.start()
    box.add(spinner)
    outcomes = []
    def result(status, done=True):
        if done:
            outcomes.append(status)
            dialog.response(Gtk.ResponseType.OK)
    backend = FprintBackend(dbus.SystemBus())
    def timeout():
        outcomes.append('timeout')
        dialog.response(Gtk.ResponseType.CANCEL)
        return False
    timer = GLib.timeout_add_seconds(90, timeout)
    attempts = []
    def begin_scan():
        attempts.append(True)
        try:
            backend.start(result)
        except dbus.DBusException as error:
            backend.stop()
            if error.get_dbus_name() == 'net.reactivated.Fprint.Error.AlreadyInUse' and len(attempts) < 80:
                label.set_text('Waiting for the fingerprint reader…\n'
                               'Leave this window open. You can cancel at any time.')
                return True  # Device availability only; no failed match is retried.
            outcomes.append('reader-busy' if error.get_dbus_name().endswith('AlreadyInUse') else 'reader-unavailable')
            dialog.response(Gtk.ResponseType.CANCEL)
            return False
        except Exception:
            outcomes.append('reader-unavailable')
            dialog.response(Gtk.ResponseType.CANCEL)
            return False
        label.set_text('Lift your finger, then touch the fingerprint sensor.\n'
                       'This authorizes the saved PIN for Android’s credential prompt.')
        return False
    begin_timer = GLib.timeout_add(500, begin_scan)
    try:
        dialog.show_all()
        dialog.present()
        response = dialog.run()
        if response != Gtk.ResponseType.OK and not outcomes:
            outcomes.append('cancelled')
    finally:
        if GLib.MainContext.default().find_source_by_id(timer):
            GLib.source_remove(timer)
        if GLib.MainContext.default().find_source_by_id(begin_timer):
            GLib.source_remove(begin_timer)
        display = dialog.get_display()
        dialog.destroy()
        # The watcher blocks outside GTK between prompts. Send the Wayland
        # destroy requests before releasing the reader or waiting for Android.
        try:
            display.flush()
        finally:
            backend.stop()
    if not outcomes or outcomes[0] != 'verify-match':
        reason = outcomes[0] if outcomes else 'no result'
        raise UnlockError(f'Touch ID did not authorize unlock ({reason}). No PIN was submitted.')


def running():
    return subprocess.run(['/usr/bin/systemctl', 'is-active', '--quiet', 'waydroid-container.service']).returncode == 0


def main(watch=False):
    global STAGE
    harden()
    config = json.loads(CONFIG.read_text())
    source = Path(__file__).resolve().parent / 'android-probe.py'
    dex = Path.home() / '.cache/session-unlock/build/classes.dex'
    mode = '--watch' if watch else '--submit'
    root_helper = Path('/usr/local/libexec/asahi-session-unlock')
    command = (['/usr/bin/pkexec', str(root_helper), mode] if root_helper.exists() else
               ['/usr/bin/pkexec', '/usr/bin/python3', str(source), str(dex), mode])
    child = subprocess.Popen(command,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        STAGE = 'Android target check'
        if not select.select([child.stdout], [], [], 220 if watch else 120)[0]:
            raise UnlockError('Android authorization timed out; no PIN was submitted.')
        ready = child.stdout.readline().strip()
        if watch and (ready == b'NO_CREDENTIAL_UI' or not running()):
            return False
        if ready not in (b'READY keyguard-pin', b'READY systemui-credential'):
            raise UnlockError('A supported Android credential prompt is not active. No PIN was read.')
        # Read through desktop authorization, then require an additional fresh
        # sensor match even if the CLI approval was cached for this application.
        STAGE = 'vault read'
        pin = read_secret(config['android_ref'])
        if not pin.isdigit() or not 4 <= len(pin) <= 16:
            raise UnlockError('The saved Android PIN is invalid.')
        STAGE = 'fingerprint verification'
        print('Waiting for a fresh Touch ID match.', flush=True)
        fresh_fingerprint()
        STAGE = 'PIN submission'
        child.stdin.write(pin + b'\n')
        child.stdin.flush()
        child.stdin.close()
        STAGE = 'Android result verification'
        output = child.stdout.read()
        code = child.wait(timeout=30)
        if code or not {b'VERIFIED_DEVICE_UNLOCK', b'VERIFIED_CREDENTIAL_REQUEST'}.intersection(output.splitlines()):
            raise UnlockError('Android unlock was not verified. No retry was attempted.')
        print('Verified: Android accepted the saved PIN after a fresh fingerprint match.', flush=True)
        return True
    finally:
        if child.stdin and not child.stdin.closed:
            try:
                child.stdin.close()
            except BrokenPipeError:
                pass
        if child.poll() is None:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    child.terminate()
                except PermissionError:
                    # pkexec may already have changed uid. EOF makes the
                    # credential helper stop; its root-side timeout also bounds it.
                    pass


if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument('--watch', action='store_true')
        args = parser.parse_args()
        runtime = os.environ.get('XDG_RUNTIME_DIR')
        if not runtime:
            raise UnlockError('Run inside the desktop session.')
        with open(Path(runtime) / 'android-unlock.lock', 'w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                sys.exit(0)
            if args.watch:
                while running():
                    main(watch=True)
                    time.sleep(0.5)
            else:
                main()
    except Exception as error:
        message = str(error) if isinstance(error, UnlockError) else f'Android unlock failed during {STAGE} ({type(error).__name__}); no credentials were logged.'
        subprocess.run(['/usr/bin/notify-send', 'Android unlock', message], check=False)
        print(message, file=sys.stderr)
        sys.exit(1)
