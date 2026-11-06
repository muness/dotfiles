#!/usr/bin/python3
"""Render shell/menu on a private headless Wayland server, without the live desktop."""
import os
import re
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile


def main():
    staged = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('/usr/share/omarchy')
    trial = Path(tempfile.mkdtemp(prefix='omarchy-wayland-shell-check-'))
    userhome, runtime = trial / 'home', trial / 'run'
    userhome.mkdir()
    runtime.mkdir(mode=0o700)
    # New upstream overlays wait for a Hyprland monitor/scale acknowledgement.
    # This isolated Sway rendering test supplies its one 1x test monitor only;
    # the installed shell and the live compositor are never modified.
    shell = trial / 'shell'
    shutil.copytree(staged / 'shell', shell)
    overlay = shell / 'Ui/OverlayWindow.qml'
    if overlay.exists():
        text = overlay.read_text()
        marker = '    return null\n  }'
        assert text.count(marker) == 1
        text = text.replace(marker, '    return targetScreen ? ({ name: targetScreen.name, scale: 1 }) : null\n  }', 1)
        text = re.sub(r'  readonly property bool contentReady:.*?\n  property bool contentRevealed:',
                      '  readonly property bool contentReady: shown\n  property bool contentRevealed:', text, flags=re.S)
        overlay.write_text(text)
    for relative in ('.config/omarchy', '.local/state/omarchy'):
        target = userhome / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(Path.home() / relative, target, symlinks=True)
    config = userhome / 'sway-test.conf'
    image_path = shlex.quote(str(Path.home() / 'shell.png'))
    config.write_text('''output * mode 1280x800
exec /bin/sh -c 'dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP; quickshell --no-color -p /usr/share/omarchy/shell'
exec /bin/sh -c 'sleep 4; omarchy-menu summon root; sleep 3; grim IMAGE_PATH; swaymsg exit'
'''.replace('IMAGE_PATH', image_path))
    env = os.environ.copy()
    env.update(OMARCHY_PATH='/usr/share/omarchy', PATH='/usr/share/omarchy/bin:' + env['PATH'],
               QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               XDG_CURRENT_DESKTOP='sway', WLR_BACKENDS='headless',
               WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')
    for name in ('DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(name, None)
    command = ['/usr/bin/timeout', '15', '/usr/bin/bwrap', '--ro-bind', '/', '/',
               '--ro-bind', str(staged), '/usr/share/omarchy',
               '--ro-bind', str(shell), '/usr/share/omarchy/shell',
               '--bind', str(userhome), str(Path.home()), '--bind', str(runtime), env['XDG_RUNTIME_DIR'],
               '--tmpfs', '/tmp', '--tmpfs', '/run/dbus', '--proc', '/proc', '--dev', '/dev',
               '--unshare-pid', '--unshare-net', '--die-with-parent',
               '/usr/bin/dbus-run-session', '--', '/usr/bin/sway', '-c', str(Path.home() / 'sway-test.conf')]
    result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = trial / 'startup.log'
    log.write_text(result.stdout)
    print('Log:', log)
    print('Screenshot:', userhome / 'shell.png')
    errors = [line for line in result.stdout.splitlines() if any(token in line for token in
              ('TypeError:', 'ReferenceError:', 'Failed to load configuration', 'caused by @', 'Configuration Loaded'))]
    print('\n'.join(errors))
    assert result.returncode == 0, result.returncode
    assert 'Configuration Loaded' in result.stdout
    assert not any('TypeError:' in line or 'ReferenceError:' in line for line in errors)
    assert (userhome / 'shell.png').is_file()


if __name__ == '__main__':
    main()
