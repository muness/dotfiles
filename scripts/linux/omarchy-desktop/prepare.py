#!/usr/bin/python3
"""Stage a desktop-only package from one reviewed, immutable source revision."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

REVISION = 'ba546a61f881c1fe9d79d75ec050eab048b8cb63'


def main(source, destination):
    source, destination = Path(source), Path(destination)
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
    if actual != REVISION or dirty:
        raise SystemExit('Requires a clean Omarchy Mac checkout at ' + REVISION)
    runtime = destination / 'usr/share/omarchy'
    runtime.mkdir(parents=True)
    for name in ('bin', 'config', 'default', 'themes', 'shell'):
        shutil.copytree(source / name, runtime / name)
    # Qt 6.12 introduces QtQuick.Color, which wins unqualified resolution over
    # this source's singleton. Without a unique name every theme surface is
    # undefined even though QML reports that the configuration loaded.
    for qml in (runtime / 'shell').rglob('*.qml'):
        text = qml.read_text()
        qml.write_text(re.sub(r'\bColor\b', 'ThemeColor', text))
    commons = runtime / 'shell/Commons'
    (commons / 'Color.qml').rename(commons / 'ThemeColor.qml')
    module = commons / 'qmldir'
    module.write_text(module.read_text().replace('singleton Color 1.0 Color.qml', 'singleton ThemeColor 1.0 ThemeColor.qml'))
    for name in ('version', 'LICENSE', 'logo.txt', 'logo.svg', 'icon.png', 'icon.txt'):
        shutil.copy2(source / name, runtime / name)
    # Theme helpers source this pure helper; provisioning scripts are omitted.
    (runtime / 'install').mkdir()
    shutil.copytree(source / 'install/helpers', runtime / 'install/helpers')
    disabled = []
    admin = re.compile(r'^omarchy-(?:apply|branch|channel|dev|dns|drive|hibernation|install|mac|migrate|pkg|plymouth|provision|reinstall|remove|setup|snapshot|sudo|update|upgrade)(?:-|$)')

    def write(path, text, mode=0o644):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(mode)

    def script(name, text):
        write(runtime / 'bin' / name, '#!/bin/bash\n' + text + '\n', 0o755)

    # Keep management paths from silently applying system changes. These are
    # disabled in the runtime tree too, so absolute-path calls cannot bypass it.
    for command in (runtime / 'bin').iterdir():
        if not command.is_file():
            continue
        command.chmod(0o755)
        text = command.read_text()
        if admin.match(command.name) or '# omarchy:requires-sudo=true' in text or re.search(r'\b(?:sudo|pkexec)\b', text):
            disabled.append(command.name)
            script(command.name, '# omarchy:summary=Unavailable in this desktop-only installation\nprintf "%s\\n" "This desktop is managed by dotfiles; use its reviewed installer for system changes." >&2\nexit 1')
    write(runtime / 'desktop-disabled-commands.txt', '\n'.join(sorted(disabled)) + '\n')
    write(runtime / 'desktop-source-revision', REVISION + '\n')

    # Restrict theme switching to the desktop and its own terminal, leaving
    # COSMIC, browser, editor and application preferences alone.
    theme = runtime / 'bin/omarchy-theme-set'
    text = theme.read_text()
    text, count = re.subn(r'post_theme_commands=\(.*?\n\)', 'post_theme_commands=(omarchy-restart-hyprctl omarchy-theme-set-foot)', text, flags=re.S)
    if count != 1:
        raise SystemExit('Theme command layout changed; review required')
    text = text.replace('omarchy-hook theme-set "$THEME_NAME" >/dev/null', ': # System/user theme hooks are not provisioned by this package.')
    theme.write_text(text)
    script('omarchy-powerprofiles-init', ': # TLP owns automatic AC/battery selection.')
    profile_set = runtime / 'bin/omarchy-powerprofiles-set'
    profile_set.write_text(profile_set.read_text().replace('powerprofilesctl set', 'tlpctl set'))
    profile_list = runtime / 'bin/omarchy-powerprofiles-list'
    profile_list.write_text(profile_list.read_text().replace('powerprofilesctl list', 'tlpctl list'))
    # The menu provider is the remaining powerprofilesctl caller.
    menu_qml = runtime / 'shell/plugins/menu/Menu.qml'
    menu_qml.write_text(menu_qml.read_text().replace('powerprofilesctl get', 'tlpctl get'))
    script('omarchy-desktop-session', 'exec uwsm start -g -1 -e -D Hyprland hyprland.desktop')
    script('omarchy-desktop-autostart', 'if [[ -n ${UWSM_FINALIZE_VARNAMES:-} ]]; then\n  uwsm finalize OMARCHY_PATH || exit\nfi\nsystemctl --user start omarchy-desktop-sleep-lock.service\nexec omarchy-launch-shell')
    script('omarchy-capture-editor', 'exec satty --filename "$1"')
    write(runtime / 'default/hypr/autostart.lua', '''hl.on("hyprland.start", function()
  hl.exec_cmd("omarchy-desktop-autostart")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))
  hl.exec_cmd(o.launch("udiskie --automount --no-notify --no-tray"))
end)
''')

    # Omit system provisioning menus; keep desktop themes, settings and apps.
    menu = runtime / 'default/omarchy/omarchy-menu.jsonc'
    lines = menu.read_text().splitlines()
    hidden = ('setup', 'install', 'remove', 'update')
    menu.write_text('\n'.join(line for line in lines if not any(re.match(r'\s*"' + key + r'(?:\.|\")', line) for key in hidden)) + '\n')
    config = json.loads((runtime / 'config/omarchy/shell.json').read_text())
    for section in config['bar']['layout'].values():
        section[:] = [item for item in section if item['id'] != 'omarchy.system-update']
    write(runtime / 'config/omarchy/shell.json', json.dumps(config, indent=2) + '\n')

    binaries = destination / 'usr/bin'
    binaries.mkdir(parents=True)
    for command in (runtime / 'bin').iterdir():
        if command.is_file():
            (binaries / command.name).symlink_to('/usr/share/omarchy/bin/' + command.name)
    write(destination / 'usr/share/wayland-sessions/omarchy.desktop', '''[Desktop Entry]
Name=Omarchy
Comment=Omarchy Mac desktop alongside COSMIC
Exec=/usr/bin/omarchy-desktop-session
TryExec=/usr/bin/uwsm
DesktopNames=Hyprland
Type=Application
''')
    write(destination / 'usr/lib/systemd/user/omarchy-desktop-sleep-lock.service', '''[Unit]
Description=Lock Omarchy before suspend
After=wayland-session-waitenv.service
PartOf=graphical-session.target
ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland
ConditionEnvironment=OMARCHY_PATH=/usr/share/omarchy
[Service]
ExecStart=/usr/bin/omarchy-system-sleep-monitor
Restart=always
RestartSec=2
''')
    # Stage templates instead of owning live PAM paths: this workstation may
    # already have a deliberately configured Omarchy fingerprint service.
    write(runtime / 'pam/omarchy-lock-password', '#%PAM-1.0\nauth include system-local-login\naccount include system-local-login\n')
    write(runtime / 'pam/omarchy-lock-fingerprint', '#%PAM-1.0\nauth required pam_fprintd.so max-tries=3 timeout=10\naccount include system-local-login\n')
    fonts = destination / 'usr/share/fonts/omarchy'
    fonts.mkdir(parents=True)
    shutil.copy2(source / 'default/fonts/omarchy/omarchy.ttf', fonts / 'omarchy.ttf')
    print('Staged desktop; disabled', len(disabled), 'management commands')


if __name__ == '__main__':
    main(*sys.argv[1:])
