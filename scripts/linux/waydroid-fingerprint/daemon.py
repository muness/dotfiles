#!/usr/bin/python3
"""Host fingerprint AIDL HAL. Only weak, non-cryptographic authentication."""
import argparse
import getpass
import logging
import os
from pathlib import Path
import signal
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
import gbinder
from gi.repository import GLib

from core import Challenge, Enrollment, FailureBudget, Operation
from protocol import (CALLBACK, CANCEL, COMMON_HASH, FINGERPRINT, FINGERPRINT_HASH,
                      GET_HASH, GET_VERSION, SENSOR_ID, SESSION, empty_auth_token,
                      i32, i64, int_array, read_hat, read_int, sensor_props)

LOG = logging.getLogger("waydroid-fingerprint")


def append_bytes(message, data):
    message.init_writer().append_bytes(data, len(data))


class FprintBackend:
    def __init__(self, bus):
        self.bus, self.device, self.owner = bus, None, None
        self.subscription = None
        self.owner_subscription = None
        self.claimed = False
        self.verifying = False
        self.callback = None

    def start(self, callback):
        self.callback = callback
        self.owner = self.bus.get_name_owner("net.reactivated.Fprint")
        manager = dbus.Interface(self.bus.get_object(self.owner, "/net/reactivated/Fprint/Manager"),
                                 "net.reactivated.Fprint.Manager")
        path = manager.GetDefaultDevice(timeout=3)
        self.device = dbus.Interface(self.bus.get_object(self.owner, path), "net.reactivated.Fprint.Device")
        if not self.device.ListEnrolledFingers(getpass.getuser(), timeout=3):
            raise RuntimeError("No fingerprint enrolled in Linux")
        self.device.Claim(getpass.getuser(), timeout=3)
        self.claimed = True
        self.subscription = self.device.connect_to_signal("VerifyStatus", self.status)
        self.owner_subscription = self.bus.add_signal_receiver(
            self.owner_changed, signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus", bus_name="org.freedesktop.DBus",
            path="/org/freedesktop/DBus", arg0="net.reactivated.Fprint")
        self.again()

    def owner_changed(self, name, old, new):
        if old == self.owner:
            self.callback("daemon-disconnected", True)

    def status(self, result, done):
        if self.verifying:
            LOG.info("Fingerprint status: %s", result)
            self.callback(str(result), bool(done))

    def again(self):
        if self.verifying:
            self.device.VerifyStop(timeout=3)
            self.verifying = False
        self.device.VerifyStart("any", timeout=3)
        self.verifying = True

    def stop(self):
        # Remove subscriptions before remote cleanup can produce late signals.
        for subscription in (self.subscription, self.owner_subscription):
            if subscription is not None:
                subscription.remove()
        self.subscription = self.owner_subscription = None
        if self.verifying:
            self.verifying = False
            try:
                self.device.VerifyStop(timeout=3)
            except dbus.DBusException:
                LOG.warning("Fingerprint verification already stopped")
        if self.claimed:
            self.claimed = False
            try:
                self.device.Release(timeout=3)
            except dbus.DBusException:
                LOG.warning("Fingerprint device already released")


class BinderObject:
    def __init__(self, bridge, interface, interface_hash=FINGERPRINT_HASH):
        self.bridge, self.interface, self.interface_hash = bridge, interface, interface_hash
        self.obj = bridge.sm.new_local_object(interface, self.handle)
        self.obj.set_stability(0x3f)

    def handle(self, req, code, flags):
        try:
            if not self.bridge.allowed(req):
                LOG.warning("Rejected Binder caller uid=%s pid=%s", req.sender_euid(), req.sender_pid())
                return None, -13
            interface = req.interface()
            if isinstance(interface, bytes):
                interface = interface.decode()
            if interface != self.interface:
                return None, -22
            reply = self.obj.new_reply()
            reply.append_int32(0)  # AIDL EX_NONE
            if code == GET_VERSION:
                reply.append_int32(1)
            elif code == GET_HASH:
                reply.append_string16(self.interface_hash)
            else:
                if not self.dispatch(req.init_reader(), code, reply):
                    return None, -74
            return reply, 0
        except Exception:
            LOG.exception("Rejected malformed or failed transaction %s", code)
            return None, -22

    def dispatch(self, reader, code, reply):
        return False


class Cancellation(BinderObject):
    def __init__(self, session, operation):
        self.session, self.operation = session, operation
        super().__init__(session.bridge, CANCEL, COMMON_HASH)

    def dispatch(self, reader, code, reply):
        if code == 1:
            self.operation.cancel()
            return True
        return False


class Session(BinderObject):
    def __init__(self, bridge, callback):
        self.callback = callback
        self.client = gbinder.Client(callback, CALLBACK)
        self.operation = None
        self.cancellations = []
        self.closed = False
        self.challenge = bridge.challenge
        super().__init__(bridge, SESSION)
        self.death_handler = callback.add_death_handler(self.died)

    def notify(self, code, data=b""):
        if self.closed and code != 16:
            return
        request = self.client.new_request()
        append_bytes(request, data)
        self.client.transact(code, 0, request, self.callback_result, None)

    def callback_result(self, reply, status):
        if status:
            LOG.warning("Android callback failed: %s", status)
            self.died()

    def died(self, *args):
        self.closed = True
        if self.operation:
            self.operation.cancel()

    def emit(self, event, *args):
        if self.closed:
            return
        LOG.info("Android operation: %s", event)
        codes = {"error": (4, lambda v: i32(v) + i32(0)),
                 "lockout": (8, i64), "failed": (7, lambda: b""),
                 "interaction": (11, lambda: b""),
                 "enrolled": (5, lambda v: i32(v) + i32(0)),
                 "success": (6, lambda v: i32(v) + empty_auth_token())}
        code, encode = codes[event]
        if event == "lockout":
            GLib.timeout_add(30010, self.clear_lockout)
        self.notify(code, encode(*args))

    def clear_lockout(self):
        if not self.closed and not self.bridge.budget.remaining():
            self.notify(10)
        return False

    def start(self, mode, reply, operation_id=0):
        if self.operation:
            self.operation.cancel()
        self.operation = Operation(FprintBackend(self.bridge.bus), self.emit,
                                   self.bridge.enrollment, mode, operation_id,
                                   self.bridge.budget)
        cancellation = Cancellation(self, self.operation)
        self.cancellations.append(cancellation)
        reply.append_local_object(cancellation.obj)
        operation = self.operation

        def begin():
            if self.closed or operation is not self.operation:
                return False
            operation.start()
            if operation.active:
                GLib.timeout_add(30000, operation.timeout)
            return False

        GLib.idle_add(begin)

    def dispatch(self, reader, code, reply):
        if self.closed:
            return False
        if code == 1:
            self.notify(1, i64(self.challenge.generate()))
        elif code == 2:
            challenge = read_int(reader, 64)
            self.challenge.value = 0
            self.notify(2, i64(challenge))
        elif code == 3:
            try:
                challenge, timestamp = read_hat(reader)
                if not self.challenge.consume(challenge):
                    raise ValueError("Expired or incorrect enrollment challenge")
            except ValueError as error:
                LOG.warning("Enrollment rejected: %s", error)
                # Report through the HAL callback, never a transport error which
                # the framework enrollment worker may not handle safely.
                self.start("rejected", reply, operation_id=1)
            else:
                self.start("enroll", reply)
        elif code == 4:
            self.start("authenticate", reply, read_int(reader, 64))
        elif code == 5:
            self.start("detect", reply)
        elif code == 6:
            ids = [self.bridge.enrollment.identifier] if self.bridge.enrollment.identifier else []
            self.notify(12, int_array(ids))
        elif code == 7:
            count = read_int(reader)
            if not 0 <= count <= 1:
                raise ValueError("Invalid enrollment removal list")
            ids = [read_int(reader) for _ in range(count)]
            if self.operation:
                self.operation.cancel()
            if self.bridge.enrollment.identifier in ids:
                self.bridge.enrollment.save(0)
            self.notify(13, int_array(ids))
        elif code in (8, 9):
            # Weak sensors cannot authorize key use. ID is for framework bookkeeping.
            self.notify(14 if code == 8 else 15, i64(self.bridge.enrollment.identifier))
        elif code == 10:
            # A request cannot bypass the host's timed lockout.
            if self.bridge.budget.remaining():
                self.notify(8, i64(self.bridge.budget.remaining()))
            else:
                self.notify(10)
        elif code == 11:
            if self.operation:
                self.operation.cancel()
            self.notify(16)
            self.closed = True
        elif code in (12, 13, 14):
            pass  # Rear sensor has no display interaction to handle.
        else:
            return False
        return True


class Bridge(BinderObject):
    def __init__(self, state):
        DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()
        # Activate fprintd before using its unique bus owner.
        self.bus.start_service_by_name("net.reactivated.Fprint")
        self.sm = gbinder.ServiceManager("/dev/binder", "aidl6", "aidl3")
        self.enrollment = Enrollment(state)
        self.budget = FailureBudget()
        # Enrollment can span HAL sessions while Android confirms the PIN.
        # Only primary user 0 is supported, so this is sensor/user-scoped.
        self.challenge = Challenge()
        self.sessions = []
        super().__init__(self, FINGERPRINT)

    @staticmethod
    def allowed(req):
        if req.sender_euid() != 1000:
            return False
        try:
            process = Path("/proc") / str(req.sender_pid())
            # Restrict access to the actual container system_server. Linux user
            # compromise is outside this host-trusted bridge's security boundary.
            return (process.joinpath("comm").read_text().strip() == "system_server"
                    and "waydroid" in process.joinpath("cgroup").read_text())
        except OSError:
            return False

    def dispatch(self, reader, code, reply):
        if code == 1:
            append_bytes(reply, sensor_props())
        elif code == 2:
            sensor, user = read_int(reader), read_int(reader)
            if sensor != SENSOR_ID or user != 0:
                raise ValueError("Only the primary Android user is supported")
            callback = reader.read_object()
            if callback.is_dead():
                raise ValueError("Missing or dead Android callback")
            for session in self.sessions:
                if not session.closed:
                    session.died()
            session = Session(self, callback)
            self.sessions.append(session)
            reply.append_local_object(session.obj)
        else:
            return False
        return True

    def presence(self):
        if self.sm.is_present():
            result = self.sm.add_service_sync(FINGERPRINT + "/default", self.obj)
            LOG.info("HAL registration status: %s", result)
            if result:
                raise RuntimeError("HAL registration failed; check VINTF declaration")
        else:
            for session in self.sessions:
                session.died()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", default=str(Path.home() / ".local/state/waydroid-fingerprint/enrollment.json"))
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    os.umask(0o077)
    bridge = Bridge(args.state)
    loop = GLib.MainLoop()
    bridge.sm.add_presence_handler(bridge.presence)
    bridge.presence()

    def stop(*unused):
        for session in bridge.sessions:
            session.died()
        loop.quit()

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    loop.run()


if __name__ == "__main__":
    main()
