#!/usr/bin/python3
"""Root-only Android credential prototype. Read-only unless --submit is explicit."""
import os
from pathlib import Path
import subprocess
import sys
import re
import time
import select
import ctypes
import signal
if Path(__file__).name == 'asahi-session-unlock':
    sys.path.insert(0, '/usr/local/lib/asahi-session-unlock')
from android_evidence import credential_confirmed

installed = Path(__file__).name == 'asahi-session-unlock'
if os.geteuid() != 0:
    raise SystemExit('Administrator execution is required.')
# Exit with the user monitor, even after pkexec changes uid. The user manager
# cannot signal root children directly, so the kernel delivers this signal.
parent = os.getppid()
if ctypes.CDLL(None).prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
    raise SystemExit('Could not bind helper lifetime to its caller.')
def caller_stopped(signum, frame):
    raise SystemExit(0)
signal.signal(signal.SIGTERM, caller_stopped)
if parent == 1 or os.getppid() != parent:
    raise SystemExit(0)
if installed:
    if len(sys.argv) != 2 or sys.argv[1] not in ('--probe', '--submit', '--watch'):
        raise SystemExit('Expected --probe, --submit, or --watch.')
    mode = sys.argv[1]
    source = Path('/usr/local/share/asahi-session-unlock/classes.dex')
else:
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] not in ('--submit', '--watch')):
        raise SystemExit('Expected a compiled dex path and optional --submit/--watch.')
    source = Path(sys.argv[1])
    mode = sys.argv[2] if len(sys.argv) == 3 else '--probe'
submit = mode != '--probe'
if not source.is_absolute() or not source.is_file():
    raise SystemExit('Expected the compiled prototype dex path.')
if subprocess.run(['/usr/bin/systemctl', 'is-active', '--quiet', 'waydroid-container.service']).returncode:
    raise SystemExit('Waydroid must already be running.')
sys.path.insert(0, '/usr/lib/waydroid')
from tools.helpers.lxc import android_env_attach_options
from types import SimpleNamespace
bare_attach = ['/usr/bin/lxc-attach', '-P', '/var/lib/waydroid/lxc', '-n', 'waydroid', '--clear-env', '--']
if mode == '--watch':
    for _ in range(120):
        boot = subprocess.run(bare_attach + ['/system/bin/getprop', 'sys.boot_completed'],
                              capture_output=True, timeout=3)
        if boot.stdout.strip() == b'1':
            break
        time.sleep(0.5)
    else:
        raise SystemExit('Android did not finish booting.')
attach = ['/usr/bin/lxc-attach', '-P', '/var/lib/waydroid/lxc', '-n', 'waydroid', '--clear-env',
          *android_env_attach_options(SimpleNamespace()), '--']
current_user = subprocess.run(attach + ['/system/bin/cmd', 'activity', 'get-current-user'],
                              capture_output=True, timeout=5).stdout.strip()
if current_user != b'0':
    raise SystemExit('Only the Android primary user is supported.')
# /data is mounted inside the container's namespace, not in the host rootfs.
destination = f'/data/local/tmp/session-unlock-{os.getpid()}.dex'
subprocess.run(attach + ['/system/bin/sh', '-c',
                         f'umask 077; cat > {destination}; chmod 400 {destination}'],
               input=source.read_bytes(), stdout=subprocess.DEVNULL,
               stderr=subprocess.DEVNULL, check=True, timeout=10)
child = None
try:
    if submit:
        policy = subprocess.run(attach + ['/system/bin/dumpsys', 'window', 'policy'],
                                capture_output=True, timeout=5).stdout
        if mode == '--watch' and b'mIsShowing=true' in policy:
            # Request the normal secure bouncer; this does not bypass a PIN.
            subprocess.run(attach + ['/system/bin/wm', 'dismiss-keyguard'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        before = subprocess.run(attach + ['/system/bin/logcat', '-d', '-v', 'brief', '-s', 'BiometricService/AuthSession'],
                                capture_output=True, timeout=5).stdout
        child = subprocess.Popen([
            *attach, '/system/bin/env', 'CLASSPATH=' + destination,
            '/system/bin/app_process', '/system/bin', 'CredentialUi', mode],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        if not select.select([child.stdout], [], [], 145)[0]:
            child.kill()
            child.wait()
            raise SystemExit('Android UI observation timed out.')
        ready = child.stdout.readline().strip()
        if ready not in (b'READY keyguard-pin', b'READY systemui-credential'):
            child.terminate()
            child.wait()
            print('NO_CREDENTIAL_UI', flush=True)
            raise SystemExit(0)
        print(ready.decode(), flush=True)
        try:
            output, _ = child.communicate(timeout=360)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
            raise SystemExit('Android credential helper timed out.')
        if child.returncode or b'SUBMITTED_REQUIRES_VERIFICATION' not in output.splitlines():
            print('ANDROID_SUBMISSION_FAILED', flush=True)
            raise SystemExit('Android refused submission; no retry was attempted.')
        if ready == b'READY systemui-credential':
            for _ in range(10):
                logs = subprocess.run(attach + ['/system/bin/logcat', '-d', '-v', 'brief', '-s', 'BiometricService/AuthSession'],
                                      capture_output=True, timeout=5).stdout
                state = subprocess.run(attach + ['/system/bin/dumpsys', 'biometric'],
                                       capture_output=True, timeout=5).stdout
                if credential_confirmed(before, logs, state):
                    print('VERIFIED_CREDENTIAL_REQUEST', flush=True)
                    raise SystemExit(0)
                time.sleep(0.5)
            raise SystemExit('Credential request success was not verified.')
        # A successful click is not authentication. For the cold-start case,
        # require Android to report both unlocked storage and hidden keyguard.
        for _ in range(10):
            state = subprocess.run(attach + ['/system/bin/dumpsys', 'window', 'policy'],
                                   capture_output=True, timeout=5).stdout
            users = subprocess.run(attach + ['/system/bin/dumpsys', 'user'],
                                   capture_output=True, timeout=5).stdout
            if b'mIsShowing=false' in state and re.search(rb'UserInfo\{0:[^\n]+\}[\s\S]{0,400}?State: RUNNING_UNLOCKED', users):
                print('VERIFIED_DEVICE_UNLOCK', flush=True)
                break
            time.sleep(0.5)
        else:
            raise SystemExit('Submission finished, but device unlock was not verified.')
        raise SystemExit(0)
    result = subprocess.run([
        *attach,
        '/system/bin/env', 'CLASSPATH=' + destination,
        '/system/bin/app_process', '/system/bin', 'CredentialUi', '--probe'],
        stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    # Only emit the deliberately restricted protocol, never ART diagnostic text.
    status = subprocess.run(attach + ['/system/bin/cat', '/data/local/tmp/session-unlock-probe-status'],
                            capture_output=True, timeout=5)
    found = False
    for line in status.stdout.decode(errors='replace').splitlines():
        if line in ('NO_CREDENTIAL_UI', 'ANDROID_HELPER_FAILED') or line.startswith(('READY ', 'RESOURCE com.android.', 'ACTION ')):
            found = True
            print(line)
    if result.returncode or not found:
        print('Android process exit:', result.returncode, 'protocol bytes:', len(status.stdout))
        # Probe mode has no credential input. Limit runtime diagnostics to this
        # pre-submission failure; never enable stderr forwarding for submit.
        for line in result.stderr.decode(errors='replace').splitlines():
            if any(word in line.lower() for word in ('fatal', 'error', 'failed', 'killed', 'exception', 'abort')):
                print(line[:500])
        raise SystemExit('Android probe failed; no credential was read or submitted.')
finally:
    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        except ProcessLookupError:
            pass
    subprocess.run(attach + ['/system/bin/rm', '-f', destination, '/data/local/tmp/session-unlock-probe-status'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
