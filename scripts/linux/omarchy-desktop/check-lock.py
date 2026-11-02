#!/usr/bin/python3
"""Exercise real lock/unlock/relock on a private, isolated Wayland compositor."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


DRIVER = '''import json, subprocess, time

def ipc(method):
    return subprocess.check_output(['omarchy-shell', 'lock', method], text=True, timeout=2).strip()

def wait_for(predicate):
    deadline = time.monotonic() + 8
    last = None
    while time.monotonic() < deadline:
        try:
            last = json.loads(ipc('status'))
            if predicate(last):
                return last
        except (subprocess.SubprocessError, ValueError):
            pass
        time.sleep(0.1)
    raise AssertionError(last)

try:
    wait_for(lambda s: s['passwordPam'])
    for cycle in range(3):
        # Exercise the exact pre-suspend helper with its normal 4-second budget.
        # This requests a lock only; it does not request suspend.
        subprocess.run(['omarchy-system-sleep-lock', '4000'], check=True, timeout=6)
        # Repeated requests must be harmless and not restart the stabilization timer.
        assert ipc('lock') == 'ok'
        state = wait_for(lambda s: s['secure'])
        assert state['locked'] and state['requested'] and state['sessionLocked'], state
        assert ipc('testUnlock') == 'ok'
        state = wait_for(lambda s: not s['secure'] and not s['sessionLocked'] and not s['requested'])
        assert not state['locked'], ('stale lock status after unlock', state)
        assert ipc('isLocked') == 'false'
        print('Lock/unlock cycle', cycle + 1, 'passed', flush=True)
    print('PASS: secure lock acquired three times, including after unlock', flush=True)
except Exception:
    import traceback
    traceback.print_exc()
    raise
'''


def main():
    source = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('/usr/share/omarchy/shell')
    trial = Path(tempfile.mkdtemp(prefix='omarchy-lock-check-'))
    home, runtime, staged = trial / 'home', trial / 'run', trial / 'shell'
    home.mkdir()
    runtime.mkdir(mode=0o700)
    shutil.copytree(source, staged)
    service = staged / 'plugins/lock/Service.qml'
    text = service.read_text()
    anchor = '    function lock(): string {'
    assert text.count(anchor) == 1
    # This authentication bypass exists only in the disposable test copy.
    # Neither its IPC socket nor its compositor is reachable from the real session.
    service.write_text(text.replace(anchor, '''    function testUnlock(): string {
      root.finishUnlock()
      return "ok"
    }

''' + anchor))
    (staged / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "plugins/lock" as Lock
ShellRoot {
  Lock.Service { omarchyPath: "/usr/share/omarchy" }
}
''')
    (home / 'driver.py').write_text(DRIVER)
    # Helpers may operate hardware; keep all of those outside this lock test.
    commands = home / 'bin'
    commands.mkdir()
    for name, body in {
        'omarchy-system-wake': 'exit 0',
        'omarchy-brightness-keyboard': 'exit 0',
        'omarchy-brightness-display': 'exit 0',
        'omarchy-hyprland-session-locked': 'exit 1',
        'fprintd-list': 'exit 1',
    }.items():
        path = commands / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)
    visible_home = Path.home()
    command = ('quickshell -n -p /usr/share/omarchy/shell & '
               + 'python3 ' + shlex.quote(str(visible_home / 'driver.py'))
               + '; swaymsg exit')
    (home / 'sway.conf').write_text('output * mode 1280x800\nexec /bin/sh -c ' + shlex.quote(command) + '\n')
    env = os.environ.copy()
    env.update(OMARCHY_PATH='/usr/share/omarchy', QT_QPA_PLATFORM='wayland',
               QT_QUICK_BACKEND='software', XDG_CURRENT_DESKTOP='sway',
               WLR_BACKENDS='headless', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1',
               PATH=str(visible_home / 'bin') + ':/usr/share/omarchy/bin:' + env['PATH'])
    for key in ('DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run([
        '/usr/bin/timeout', '40', '/usr/bin/bwrap', '--ro-bind', '/', '/',
        '--ro-bind', str(staged), '/usr/share/omarchy/shell',
        '--bind', str(home), str(visible_home), '--bind', str(runtime), env['XDG_RUNTIME_DIR'],
        '--tmpfs', '/tmp', '--tmpfs', '/run/dbus', '--proc', '/proc', '--dev', '/dev',
        '--unshare-pid', '--unshare-net', '--die-with-parent',
        '/usr/bin/dbus-run-session', '--', '/usr/bin/sway', '-c', str(visible_home / 'sway.conf'),
    ], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = trial / 'lock.log'
    log.write_text(result.stdout)
    print('Log:', log)
    print('\n'.join(line for line in result.stdout.splitlines() if any(
        word in line for word in ('cycle', 'PASS:', 'AssertionError', 'Error:', 'omarchy lock'))))
    assert result.returncode == 0 and 'PASS: secure lock acquired three times' in result.stdout


if __name__ == '__main__':
    main()
