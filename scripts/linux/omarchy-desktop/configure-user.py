#!/usr/bin/python3
"""Seed only this user's desktop configs, retaining a restorable copy."""
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    runtime = Path('/usr/share/omarchy')
    if not (runtime / 'desktop-source-revision').is_file():
        raise SystemExit('Install the desktop-only package first')
    home = Path.home()
    config, state = home / '.config', home / '.local/state'
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = state / 'dotfiles/omarchy-backups' / stamp
    backup.mkdir(parents=True, mode=0o700)
    absent = []
    targets = [config / name for name in ('hypr', 'omarchy', 'foot')]
    targets += [config / 'uwsm/env-hyprland', state / 'omarchy']
    for target in targets:
        relative = target.relative_to(home)
        if target.exists():
            dest = backup / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            if target.is_dir():
                shutil.copytree(target, dest, symlinks=True)
            else:
                shutil.copy2(target, dest, follow_symlinks=False)
        else:
            absent.append(str(relative))
    (backup / 'originally-absent.json').write_text(json.dumps(absent, indent=2))
    print('User backup:', backup, flush=True)
    # Native shell widgets replace these tray applets in Hyprland only.
    # Retain every existing desktop exclusion and leave other sessions alone.
    for name in ('blueman.desktop', 'nm-applet.desktop'):
        target = config / 'autostart' / name
        source = target if target.exists() else Path('/etc/xdg/autostart') / name
        if not source.exists():
            continue
        if target.exists():
            dest = backup / '.config/autostart' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, dest)
        lines = source.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.startswith('NotShowIn='):
                desktops = [entry for entry in line.split('=', 1)[1].split(';') if entry]
                if 'Hyprland' not in desktops:
                    desktops.append('Hyprland')
                lines[index] = 'NotShowIn=' + ';'.join(desktops) + ';'
                break
        else:
            lines.append('NotShowIn=Hyprland;')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('\n'.join(lines) + '\n')
    for name in ('hypr', 'omarchy', 'foot'):
        target = config / name
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        shutil.copytree(runtime / 'config' / name, target)
    hypr = config / 'hypr/hyprland.lua'
    text = hypr.read_text().replace('-- Load Omarchy defaults.', 'omarchy_preinstalled_bindings = false\n\n-- Load Omarchy defaults.')
    hypr.write_text(text)
    input_config = config / 'hypr/input.lua'
    input_config.write_text(input_config.read_text() + '''
-- Mac Spaces-style workspace navigation with a three-finger swipe.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
''')
    looknfeel = config / 'hypr/looknfeel.lua'
    looknfeel.write_text(looknfeel.read_text() + '''
-- Resize windows by dragging their borders without holding Super.
hl.config({
  general = {
    resize_on_border = true,
  },
})
''')
    (config / 'hypr/bindings.lua').write_text('''-- Existing applications, launched in UWSM application scopes.
o.bind("SUPER + Return", "Terminal", "omarchy-launch-terminal")
o.bind("SUPER + B", "Browser", "omarchy-launch-browser")
o.bind("SUPER + E", "Files", "uwsm-app -- cosmic-files")
''')
    # Retain the previously qualified internal-panel mode and scale.
    (config / 'hypr/monitors.lua').write_text('''hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.monitor({ output = "eDP-1", mode = "3024x1890@47.952", position = "0x0", scale = 1.5 })
''')
    env_file = config / 'uwsm/env-hyprland'
    env_file.parent.mkdir(parents=True, exist_ok=True)
    if env_file.is_symlink():
        env_file.unlink()
    env_file.write_text('''# Only the Hyprland session receives these defaults.
export OMARCHY_PATH=/usr/share/omarchy
export PATH="/usr/share/omarchy/bin:$PATH"
export TERMINAL=foot
export OMARCHY_SCREENSHOT_EDITOR=omarchy-capture-editor
''')
    toggles = state / 'omarchy/toggles/hypr'
    toggles.mkdir(parents=True, exist_ok=True)
    shutil.copy2(runtime / 'default/hypr/toggles/flags.lua', toggles / 'flags.lua')
    branding = config / 'omarchy/branding'
    branding.mkdir(parents=True, exist_ok=True)
    shutil.copy2(runtime / 'logo.txt', branding / 'screensaver.txt')
    shutil.copy2(runtime / 'icon.txt', branding / 'about.txt')
    env = os.environ.copy()
    env.update(OMARCHY_PATH=str(runtime), OMARCHY_THEME_HEADLESS='1',
               PATH=str(runtime / 'bin') + ':' + env['PATH'])
    subprocess.run([str(runtime / 'bin/omarchy-theme-set'), 'Tokyo Night'], env=env, check=True)
    subprocess.run([str(runtime / 'bin/omarchy-theme-set-foot')], env=env, check=True)
    subprocess.run(['/usr/bin/Hyprland', '--verify-config', '-c', str(hypr)], env=env, check=True)
    print('Omarchy configured. Select Omarchy at COSMIC Greeter after logging out.')


if __name__ == '__main__':
    main()
