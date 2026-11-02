import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import importlib.util

from core import Challenge, Enrollment, FailureBudget, Operation
from protocol import empty_auth_token, sensor_props, read_hat, read_int, typed, i64, i32


class Backend:
    def __init__(self, fail=False):
        self.stopped = 0
        self.started = 0
        self.retries = 0
        self.fail = fail

    def start(self, callback):
        self.started += 1
        self.callback = callback
        if self.fail:
            raise RuntimeError("No sensor")

    def again(self):
        self.retries += 1

    def stop(self):
        self.stopped += 1


class LifecycleTests(unittest.TestCase):
    def test_oneway_cancellation_accepts_missing_pid_only_on_cancellation_capability(self):
        import daemon
        from types import SimpleNamespace
        bridge = SimpleNamespace(allowed=lambda req: False)
        cancellation = object.__new__(daemon.Cancellation)
        cancellation.bridge = bridge
        ordinary = object.__new__(daemon.BinderObject)
        ordinary.bridge = bridge
        req = SimpleNamespace(sender_euid=lambda: 1000, sender_pid=lambda: 0)
        self.assertTrue(cancellation.authorized(req, 1, 1))
        self.assertFalse(ordinary.authorized(req, 1, 1))
        self.assertFalse(cancellation.authorized(req, 4, 1))
        self.assertFalse(cancellation.authorized(req, 1, 0))
        req.sender_euid = lambda: 10001
        self.assertFalse(cancellation.authorized(req, 1, 1))

    def test_startup_waits_for_binder_permission_without_opening_hal(self):
        import daemon
        for error in (FileNotFoundError(), PermissionError(), OSError()):
            with patch.object(daemon.os, 'open', side_effect=error):
                self.assertFalse(daemon.binder_accessible())
        with patch.object(daemon.os, 'open', return_value=42), patch.object(daemon.os, 'close') as close:
            self.assertTrue(daemon.binder_accessible())
            close.assert_called_once_with(42)

    def test_backend_reactivates_fprintd_after_idle_exit(self):
        import daemon
        device = MagicMock()
        device.ListEnrolledFingers.return_value = ['right-thumb']
        manager = MagicMock()
        manager.GetDefaultDevice.return_value = '/device'
        bus = MagicMock()
        running = [False]
        def activate(name):
            running[0] = True
        def owner(name):
            if not running[0]:
                raise RuntimeError('fprintd exited while idle')
            return ':1.42'
        bus.start_service_by_name.side_effect = activate
        bus.get_name_owner.side_effect = owner
        bus.get_object.side_effect = lambda name, path: device if path == '/device' else manager
        with patch.object(daemon.dbus, 'Interface', side_effect=lambda obj, interface: obj):
            for _ in range(2):
                running[0] = False
                backend = daemon.FprintBackend(bus)
                backend.start(lambda *args: None)
                self.assertTrue(backend.verifying)
                backend.stop()
                self.assertFalse(backend.claimed)
        self.assertEqual(bus.start_service_by_name.call_count, 2)
        self.assertEqual(device.VerifyStart.call_count, 2)
        self.assertEqual(device.Release.call_count, 2)

    def test_software_credential_token_zero_signature_is_structurally_valid(self):
        class Reader:
            def __init__(self, data):
                self.data, self.offset = data, 0
            def read_int32(self):
                value = struct.unpack_from('<i', self.data, self.offset)[0]
                self.offset += 4
                return True, value
            def read_int64(self):
                value = struct.unpack_from('<q', self.data, self.offset)[0]
                self.offset += 8
                return True, value
            def bytes_read(self):
                return self.offset
            def read_byte_array(self):
                _, size = self.read_int32()
                value = self.data[self.offset:self.offset + size]
                self.offset += size
                return value
        def token(user=1, kind=1):
            return typed(i64(456) + i64(user) + i64(0) + i32(kind)
                         + typed(i64(123)) + i32(32) + bytes(32))
        self.assertEqual(read_hat(Reader(token())), (456, 123))
        for data in (token(user=0), token(kind=2)):
            with self.assertRaises(ValueError):
                read_hat(Reader(data))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.enrollment = Enrollment(Path(self.temp.name) / "enrollment.json")
        self.enrollment.save(123)
        self.backend = Backend()
        self.events = []

    def operation(self, mode="authenticate", **kwargs):
        op = Operation(self.backend, lambda *event: self.events.append(event), self.enrollment, mode, **kwargs)
        op.start()
        return op

    def test_fresh_match_only_and_release(self):
        op = self.operation()
        self.assertEqual(self.events, [])
        op.status("verify-match", True)
        self.assertEqual(self.events, [("success", 123)])
        self.assertEqual(self.backend.stopped, 1)
        op.status("verify-match", True)
        self.assertEqual(len(self.events), 1)

    def test_cancel_rejects_late_match(self):
        op = self.operation()
        op.cancel()
        op.status("verify-match", True)
        self.assertEqual(self.events, [("error", 5)])
        self.assertEqual(self.backend.stopped, 1)

    def test_cancellation_before_idle_start(self):
        op = Operation(self.backend, lambda *e: self.events.append(e), self.enrollment, "authenticate")
        op.cancel()
        op.start()
        self.assertEqual(self.backend.started, 0)
        self.assertEqual(self.events, [("error", 5)])

    def test_timeout_rejects_late_match(self):
        op = self.operation()
        op.timeout()
        op.status("verify-match", True)
        self.assertEqual(self.events, [("error", 3)])

    def test_no_match_never_succeeds_and_restarts_scan(self):
        op = self.operation()
        op.status("verify-no-match", True)
        self.assertEqual(self.events, [("failed",)])
        self.assertEqual(self.backend.retries, 1)

    def test_lockout_cannot_be_reset_by_new_session(self):
        budget = FailureBudget()
        for _ in range(5):
            op = self.operation(budget=budget)
            op.status("verify-no-match", True)
            op.cancel()
        self.events.clear()
        op = self.operation(budget=budget)
        self.assertEqual(self.events[0][0], "lockout")
        op.status("verify-match", True)
        self.assertFalse(any(e[0] == "success" for e in self.events))

    def test_crypto_request_never_reaches_sensor(self):
        op = self.operation(operation_id=42)
        self.assertEqual(self.events, [("error", 2)])
        self.assertEqual(self.backend.started, 0)
        op.status("verify-match", True)
        self.assertNotIn(("success", 123), self.events)

    def test_daemon_loss_and_unknown_results_fail_closed(self):
        for status in ("daemon-disconnected", "verify-disconnected", "unknown", "verify-match"):
            self.events.clear()
            op = self.operation()
            op.status(status, status != "verify-match")
            op.status("verify-match", True)
            self.assertEqual(self.events, [("error", 1)])

    def test_claim_failure_cleans_up(self):
        self.backend.fail = True
        with self.assertLogs('waydroid-fingerprint', level='ERROR'):
            self.operation()
        self.assertEqual(self.events, [("error", 1)])
        self.assertEqual(self.backend.stopped, 1)

    def test_no_android_enrollment_fails_closed(self):
        self.enrollment.save(0)
        self.operation()
        self.assertEqual(self.events, [("error", 1)])
        self.assertEqual(self.backend.started, 0)

    def test_enrollment_requires_real_match_and_persists(self):
        self.enrollment.save(0)
        op = self.operation("enroll")
        self.assertEqual(json.loads(self.enrollment.path.read_text())["enrollment"], 0)
        op.status("verify-match", True)
        self.assertEqual(self.events[0][0], "enrolled")
        self.assertGreater(Enrollment(self.enrollment.path).identifier, 0)
        self.assertEqual(self.enrollment.path.stat().st_mode & 0o777, 0o600)

    def test_detect_does_not_enroll_or_authenticate(self):
        op = self.operation("detect")
        op.status("verify-match", True)
        self.assertEqual(self.events, [("interaction",)])

    def test_challenge_is_fresh_single_use_and_expires(self):
        c = Challenge()
        value = c.generate()
        self.assertTrue(c.consume(value))
        self.assertFalse(c.consume(value))
        c.generate()
        c.expires = 0
        self.assertFalse(c.consume(c.value))

    def test_wrong_challenge_invalidates_attempt(self):
        c = Challenge()
        value = c.generate()
        self.assertFalse(c.consume(value + 1))
        self.assertFalse(c.consume(value))

    def test_declared_sensor_is_weak_not_strong(self):
        data = sensor_props()
        # array count, typed marker, SensorProps size, CommonProps marker,
        # CommonProps size, sensor ID, sensor strength.
        self.assertEqual(struct.unpack_from("<i", data, 24)[0], 1)

    def test_no_fabricated_signed_auth_token(self):
        self.assertNotIn(b"\xff", empty_auth_token())
        self.assertEqual(empty_auth_token()[-4:], b"\0" * 4)  # zero-length MAC

    def test_install_remove_preserves_unrelated_files_and_refuses_symlinks(self):
        spec = importlib.util.spec_from_file_location("host_setup", Path(__file__).with_name("host-setup.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        base = Path(self.temp.name) / "overlay"
        base.mkdir()
        unrelated = base / "keep"
        unrelated.write_text("existing configuration")
        module.apply(base)
        module.apply(base)
        module.apply(base, True)
        self.assertEqual(unrelated.read_text(), "existing configuration")
        target = base / next(iter(module.FILES))
        target.symlink_to(unrelated)
        with self.assertRaises(RuntimeError):
            module.apply(base)
        self.assertEqual(unrelated.read_text(), "existing configuration")

    def test_installer_refuses_existing_unowned_declaration(self):
        spec = importlib.util.spec_from_file_location("host_setup", Path(__file__).with_name("host-setup.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        base = Path(self.temp.name) / "overlay"
        target = base / next(iter(module.FILES))
        target.parent.mkdir(parents=True)
        target.write_text("existing configuration")
        with self.assertRaises(RuntimeError):
            module.apply(base)
        self.assertEqual(target.read_text(), "existing configuration")

    def test_caller_filter_rejects_host_process_and_root(self):
        import daemon
        import os

        class Request:
            def sender_pid(self):
                return os.getpid()

            def sender_euid(self):
                return 1000

        self.assertFalse(daemon.Bridge.allowed(Request()))
        Request.sender_euid = lambda self: 0
        self.assertFalse(daemon.Bridge.allowed(Request()))


if __name__ == "__main__":
    unittest.main()
