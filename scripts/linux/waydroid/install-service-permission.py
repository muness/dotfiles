#!/usr/bin/python3
"""Grant one active local user start/stop access to the Waydroid system unit."""
import argparse
import json
import os
from pathlib import Path
import pwd
import re
import tempfile

MARKER = 'dotfiles Waydroid service control'


def rule(username):
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', username):
        raise ValueError('Invalid desktop username')
    return '''// %s
polkit.addRule(function(action, subject) {
    if (action.id === "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") === "waydroid-container.service" &&
        (action.lookup("verb") === "start" || action.lookup("verb") === "stop") &&
        subject.user === %s && subject.local === true && subject.active === true) {
        return polkit.Result.YES;
    }
});
''' % (MARKER, json.dumps(username))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('username')
    args = parser.parse_args()
    content = rule(args.username)
    if os.geteuid() != 0:
        raise SystemExit('Run this installer with pkexec /usr/bin/python3')
    if pwd.getpwnam(args.username).pw_uid < 1000:
        raise SystemExit('Expected a desktop user, not a system account')
    target = Path('/etc/polkit-1/rules.d/49-dotfiles-waydroid.rules')
    if target.is_symlink() or (target.exists() and MARKER not in target.read_text()):
        raise SystemExit('Refusing to overwrite an unrelated polkit rule')
    descriptor, name = tempfile.mkstemp(prefix='.waydroid-', dir=target.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(content)
        temporary.chmod(0o644)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print('Installed start/stop permission for ' + args.username)


if __name__ == '__main__':
    main()
