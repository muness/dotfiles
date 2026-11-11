#!/usr/bin/python3
"""Warn about sustained power-event storms or discharge with USB power present."""
from collections import deque
from pathlib import Path
import selectors
import subprocess
import time

POWER = Path('/sys/class/power_supply')


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


class Detector:
    def __init__(self):
        self.events = deque()
        self.discharge_since = None
        self.last_warning = float('-inf')

    def event(self, now):
        self.events.append(now)

    def check(self, now, source, watts):
        while self.events and self.events[0] < now - 30:
            self.events.popleft()
        if source and watts is not None and watts <= -5:
            if self.discharge_since is None:
                self.discharge_since = now
        else:
            self.discharge_since = None
        storm = len(self.events) >= 80
        draining = self.discharge_since is not None and now - self.discharge_since >= 60
        if (storm or draining) and now - self.last_warning >= 600:
            self.last_warning = now
            return 'events' if storm else 'discharge'
        return None


def main():
    monitor = subprocess.Popen(['/usr/bin/udevadm', 'monitor', '--udev', '--subsystem-match=power_supply'],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(monitor.stdout, selectors.EVENT_READ)
    detector = Detector()
    pending = b''
    next_check = time.monotonic()
    try:
        while monitor.poll() is None:
            for key, _ in selector.select(max(0, next_check - time.monotonic())):
                chunk = key.fileobj.read(8192)
                if not chunk:
                    return 1
                pending += chunk
                lines = pending.split(b'\n')
                pending = lines.pop()
                now = time.monotonic()
                for line in lines:
                    if line.startswith(b'UDEV ') and (b'/macsmc-battery ' in line or b'/macsmc-ac ' in line):
                        detector.event(now)
            now = time.monotonic()
            if now < next_check:
                continue
            next_check = now + 5
            source = any(read(p / 'online') == '1' for p in POWER.glob('tps6598x-source-psy-*'))
            try:
                watts = int(read(POWER / 'macsmc-battery/power_now')) / 1_000_000
            except ValueError:
                watts = None
            reason = detector.check(now, source, watts)
            if reason:
                body = ('Power events are repeating unusually fast. Check the charger, cable and port.'
                        if reason == 'events' else
                        'USB power is detected but the battery is draining. Check the charger, cable and port.')
                subprocess.run(['/usr/bin/notify-send', '-u', 'critical', '-a', 'Power monitor',
                                'Power connection problem', body], check=False)
    finally:
        monitor.terminate()
        monitor.wait()
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
