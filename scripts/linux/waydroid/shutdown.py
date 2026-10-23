#!/usr/bin/python3
"""Stop Android and its system container; never report a cancelled stop as success."""
import subprocess
import sys


def shutdown(run=subprocess.run):
    def call(*args):
        return run(args, check=False).returncode

    if call('/usr/bin/python3', '/usr/bin/waydroid', 'session', 'stop'):
        raise RuntimeError('Could not stop the Android session.')
    state = call('/usr/bin/systemctl', 'is-active', '--quiet', 'waydroid-container.service')
    if state == 0:
        if call('/usr/bin/pkexec', '/usr/bin/systemctl', 'stop', 'waydroid-container.service'):
            raise RuntimeError('Android session stopped, but container shutdown failed or authentication was cancelled.')
    elif state != 3:
        raise RuntimeError('Could not determine whether the container service is stopped.')
    if call('/usr/bin/systemctl', 'is-active', '--quiet', 'waydroid-container.service') != 3:
        raise RuntimeError('Could not confirm that the container service is stopped.')


def main():
    try:
        shutdown()
    except (RuntimeError, OSError) as error:
        subprocess.run(['/usr/bin/notify-send', '--urgency=critical',
                        'Waydroid shutdown incomplete', str(error)], check=False)
        print(error, file=sys.stderr)
        return 1
    subprocess.run(['/usr/bin/notify-send', 'Waydroid shut down',
                    'Android and its container service are stopped.'], check=False)
    return 0


if __name__ == '__main__':
    sys.exit(main())
