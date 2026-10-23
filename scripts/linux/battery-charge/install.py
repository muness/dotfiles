#!/usr/bin/python3
"""Install the helper and extend the existing Omarchy menu/bar without resets."""
import datetime
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess

SOURCE = Path(__file__).resolve().parent
BEGIN = '  // BEGIN dotfiles battery charge\n'
END = '  // END dotfiles battery charge\n'


def extend_menu(text, executable):
    entries = {
        'battery-charge': {'icon': '󰁹', 'label': 'Battery charge limit', 'title': 'Charge limit'},
    }
    for limit, mode, icon in [('80', 'Home', ''), ('100', 'Travel', '')]:
        entries[f'battery-charge.{mode.lower()}'] = {
            'icon': icon, 'label': f'{mode} — {limit}%',
            'description': 'Save charge limit across restarts',
            'checked': f'test "$(cat /sys/class/power_supply/macsmc-battery/charge_control_end_threshold)" = {limit}',
            'action': f'{shlex.quote(str(executable))} {limit}',
        }
    block = BEGIN + ''.join(f'  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},\n' for key, value in entries.items()) + END
    if BEGIN in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ValueError('Unexpected battery menu markers')
        start, end = text.index(BEGIN), text.index(END) + len(END)
        return text[:start] + block + text[end:]
    # Insert first: works with JSONC comments/trailing commas and preserves user rows.
    start = re.search(r'^\s*\{', text)
    if not start:
        raise ValueError('Expected a JSONC object for the menu extension')
    position = text.index('{', start.start()) + 1
    return text[:position] + '\n' + block + text[position:]


def place_widget(layout, module):
    """Keep the cap in the indicator cluster, preserving all other bar entries."""
    for section, rows in layout.items():
        layout[section] = [row for row in rows if row.get('id') != module['id']]
    for anchor in ('omarchy.indicators', 'omarchy.clock'):
        for rows in layout.values():
            for index, row in enumerate(rows):
                if row.get('id') == anchor:
                    rows.insert(index, module)
                    return
    layout.setdefault('center', []).insert(0, module)


def main():
    home = Path.home()
    config = home / '.config/omarchy'
    shell = config / 'shell.json'
    menu = config / 'extensions/omarchy-menu.jsonc'
    executable = home / '.local/bin/battery-charge'
    data = json.loads(shell.read_text())
    layout = data['bar']['layout']
    widget = config / 'bar/modules/muness.battery-charge.qml'
    module = {'id': 'muness.battery-charge', 'type': 'qml'}
    place_widget(layout, module)
    updated_menu = extend_menu(menu.read_text() if menu.exists() else '{}\n', executable)
    if not Path('/sys/class/power_supply/macsmc-battery/charge_control_end_threshold').exists():
        raise SystemExit('This integration requires the Apple Silicon battery driver')
    # Authentication happens before any user configuration changes.
    helper = Path('/usr/local/libexec/dotfiles-set-charge-limit')
    trusted = helper.exists() and helper.stat().st_uid == 0 and not helper.stat().st_mode & 0o022
    if not trusted or helper.read_bytes() != (SOURCE / 'set-charge-limit.py').read_bytes():
        subprocess.run(['/usr/bin/pkexec', '/usr/bin/install', '-D', '-o', 'root', '-g', 'root', '-m', '0755',
                        str(SOURCE / 'set-charge-limit.py'), str(helper)], check=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = home / '.local/state/dotfiles/battery-charge' / stamp
    backup.mkdir(parents=True)
    for path in (shell, menu, executable, widget):
        if path.exists():
            shutil.copy2(path, backup / path.name)
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / 'battery-charge', executable)
    executable.chmod(0o755)
    widget.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / 'ChargeLimit.qml', widget)
    menu.parent.mkdir(parents=True, exist_ok=True)
    menu.write_text(updated_menu)
    shell.write_text(json.dumps(data, indent=2) + '\n')
    subprocess.run(['omarchy-menu', 'refresh'], check=True)
    print('Installed battery charge menu. Backups:', backup)


if __name__ == '__main__':
    main()
