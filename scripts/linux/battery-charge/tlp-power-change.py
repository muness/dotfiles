#!/usr/bin/python3
"""Apply TLP only when the actual AC state changes, not on every uevent."""
import fcntl
from pathlib import Path
import subprocess

AC = Path('/sys/class/power_supply/macsmc-ac/online')
STATE = Path('/run/dotfiles-tlp-ac-state')


def main():
    with STATE.open('a+') as state:
        fcntl.flock(state, fcntl.LOCK_EX)
        current = AC.read_text().strip()
        if current not in ('0', '1'):
            raise ValueError('Unexpected AC state')
        state.seek(0)
        if state.read().strip() == current:
            return
        subprocess.run(['/usr/bin/tlp', 'auto'], check=True)
        state.seek(0)
        state.truncate()
        state.write(current + '\n')
        state.flush()


if __name__ == '__main__':
    main()
