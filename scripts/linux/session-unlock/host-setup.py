#!/usr/bin/python3
"""Install the reviewed root helper and a single scoped local-user permission."""
import json
import os
from pathlib import Path
import pwd
import re
import sys
import tempfile
import signal

MARKER = 'dotfiles-session-unlock managed'
BASE = Path('/usr/local/share/asahi-session-unlock')
HELPER = Path('/usr/local/libexec/asahi-session-unlock')
POLICY = Path('/usr/share/polkit-1/actions/org.dotfiles.waydroid.credentials.policy')
RULE = Path('/etc/polkit-1/rules.d/49-dotfiles-waydroid-credentials.rules')


def permission_rule(user):
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', user):
        raise ValueError('Unsupported username')
    return f'''// {MARKER}
polkit.addRule(function(action, subject) {{
  if (action.id == "org.dotfiles.waydroid.credentials" &&
      subject.user == {json.dumps(user)} && subject.active && subject.local) {{
    return polkit.Result.YES;
  }}
}});
'''


def install(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.session-unlock-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content if isinstance(content, bytes) else content.encode())
            os.fchmod(stream.fileno(), mode)
            os.fchown(stream.fileno(), 0, 0)
        Path(name).replace(path)
    finally:
        Path(name).unlink(missing_ok=True)


def stop_previous_helpers():
    """Retire only this helper's old process trees during an authorized upgrade."""
    processes = {}
    roots = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            fields = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
            pid = int(proc.name)
            processes[pid] = (int(fields[1]), fields[19])
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            if args[:2] == [b'/usr/bin/python3', str(HELPER).encode()] and args[2:3] == [b'--watch']:
                roots.add(pid)
        except (OSError, ValueError, IndexError):
            continue
    family = set(roots)
    while True:
        children = {pid for pid, (parent, _) in processes.items() if parent in family}
        if children <= family:
            break
        family |= children
    for pid in sorted(family - roots, reverse=True) + sorted(roots):
        try:
            current = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
            if current[19] == processes[pid][1]:
                os.kill(pid, signal.SIGTERM)
        except (OSError, IndexError):
            pass


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3:
        raise SystemExit('Usage: pkexec /usr/bin/python3 host-setup.py DESKTOP_USER COMPILED_DEX')
    user, dex = sys.argv[1], Path(sys.argv[2])
    rule = permission_rule(user)
    if pwd.getpwnam(user).pw_uid != 1000:
        raise SystemExit('This integration targets the existing primary desktop user.')
    source = Path(__file__).resolve().parent
    if not dex.read_bytes().startswith(b'dex\n'):
        raise SystemExit('Expected a compiled Android dex file.')
    for path in (HELPER, POLICY, RULE):
        if path.exists() and MARKER not in path.read_text():
            raise SystemExit(f'Refusing to overwrite an unmanaged file: {path}')
    if BASE.exists() and not (BASE / '.managed').exists():
        raise SystemExit('Refusing to overwrite an unmanaged helper directory.')
    stop_previous_helpers()
    install(BASE / '.managed', MARKER)
    install(BASE / 'classes.dex', dex.read_bytes(), 0o444)
    install(Path('/usr/local/lib/asahi-session-unlock/android_evidence.py'),
            (source / 'android_evidence.py').read_bytes())
    helper = (source / 'android-probe.py').read_text().replace(
        '#!/usr/bin/python3\n', '#!/usr/bin/python3\n# ' + MARKER + '\n', 1)
    install(HELPER, helper, 0o755)
    install(POLICY, f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- {MARKER} -->
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.dotfiles.waydroid.credentials">
    <description>Use the scoped Waydroid credential helper</description>
    <message>Authenticate to use the Waydroid credential helper</message>
    <defaults><allow_any>no</allow_any><allow_inactive>no</allow_inactive><allow_active>auth_admin</allow_active></defaults>
    <annotate key="org.freedesktop.policykit.exec.path">{HELPER}</annotate>
  </action>
</policyconfig>
''')
    # Write the permission last; every executable dependency is root-owned first.
    install(RULE, rule)
    print('Installed the root-owned Android helper and scoped active-local-user permission.')


if __name__ == '__main__':
    main()
