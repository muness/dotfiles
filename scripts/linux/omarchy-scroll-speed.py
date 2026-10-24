#!/usr/bin/env python3
"""Keep full touchpad scroll speed in the user's Hyprland Lua overrides."""
import datetime
import os
from pathlib import Path
import shutil


BEGIN = '-- BEGIN dotfiles touchpad scroll speed'
END = '-- END dotfiles touchpad scroll speed'
OVERRIDE = f'''{BEGIN}
-- Omarchy defaults to 0.4; restore full touchpad scroll speed.
hl.config({{ input = {{ touchpad = {{ scroll_factor = 1.0 }} }} }})
{END}
'''


def configure(path):
    text = path.read_text()
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError('Malformed managed scroll override; repair it before rerunning')
    if BEGIN in text:
        start = text.index(BEGIN)
        end = text.index(END)
        if end < start:
            raise ValueError('Managed scroll override markers are reversed')
        stop = end + len(END)
        updated = text[:start] + OVERRIDE.rstrip('\n') + text[stop:]
    else:
        updated = text.rstrip('\n') + '\n\n' + OVERRIDE
    if updated == text:
        return None
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = path.with_name(path.name + '.before-scroll-speed-' + stamp)
    shutil.copy2(path, backup)
    path.write_text(updated)
    return backup


def main():
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    path = config / 'hypr/input.lua'
    if not path.is_file():
        raise SystemExit(f'No Hyprland Lua input configuration at {path}')
    backup = configure(path)
    print(f'Backup: {backup}' if backup else 'Scroll override already configured')
    print('Run hyprctl reload, then hyprctl getoption input:touchpad:scroll_factor')


if __name__ == '__main__':
    main()
