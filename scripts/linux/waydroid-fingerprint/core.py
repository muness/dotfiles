"""Authentication lifecycle, independent of D-Bus and Binder for failure testing."""
import json
import logging
import os
from pathlib import Path
import secrets
import tempfile
import time


class Enrollment:
    def __init__(self, path):
        self.path = Path(path)
        self.identifier = 0
        if self.path.exists():
            value = json.loads(self.path.read_text())
            self.identifier = int(value["enrollment"])
            if not 0 <= self.identifier < 2**31:
                raise ValueError("Invalid enrollment state")

    def save(self, identifier):
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor, name = tempfile.mkstemp(prefix=".enrollment-", dir=self.path.parent)
        temp = Path(name)
        try:
            with os.fdopen(descriptor, "w") as stream:
                json.dump({"enrollment": identifier}, stream)
                stream.flush()
                os.fsync(stream.fileno())
            temp.replace(self.path)
        finally:
            temp.unlink(missing_ok=True)
        self.identifier = identifier


class FailureBudget:
    def __init__(self):
        self.failures = 0
        self.until = 0

    def remaining(self):
        if self.until and time.monotonic() >= self.until:
            self.until = 0
            self.failures = 0
        return max(0, int((self.until - time.monotonic()) * 1000))

    def miss(self):
        self.failures += 1
        if self.failures >= 5:
            self.until = time.monotonic() + 30
            return True
        return False


class Operation:
    """Only the active operation's backend may deliver a fresh match."""
    def __init__(self, backend, emit, enrollment, mode, operation_id=0, budget=None):
        self.backend, self.emit, self.enrollment, self.mode = backend, emit, enrollment, mode
        self.active = False
        self.failures = 0
        self.operation_id = operation_id
        self.budget = budget or FailureBudget()
        self.terminal = False

    def start(self):
        if self.terminal:
            return
        if self.budget.remaining():
            self.terminal = True
            self.emit("lockout", self.budget.remaining())
            return
        if self.operation_id != 0:
            self.terminal = True
            self.emit("error", 2)  # Never satisfy a cryptographic operation.
            return
        if self.mode == "authenticate" and not self.enrollment.identifier:
            self.terminal = True
            self.emit("error", 1)
            return
        self.active = True
        try:
            self.backend.start(self.status)
        except Exception:
            logging.getLogger("waydroid-fingerprint").exception("Fingerprint backend could not start")
            self.finish("error", 1)

    def status(self, status, done=True):
        if not self.active:
            return
        if status == "verify-match" and done:
            self.budget.failures = 0
            if self.mode == "enroll":
                identifier = self.enrollment.identifier or secrets.randbelow(2**30) + 1
                try:
                    self.enrollment.save(identifier)
                except Exception:
                    self.finish("error", 2)
                    return
                self.finish("enrolled", identifier)
            elif self.mode == "detect":
                self.finish("interaction")
            else:
                self.finish("success", self.enrollment.identifier)
        elif status == "verify-no-match":
            if self.budget.miss():
                self.finish("lockout", 30000)
            else:
                self.emit("failed")
                if done:
                    try:
                        self.backend.again()
                    except Exception:
                        self.finish("error", 1)
        elif status in ("verify-retry-scan", "verify-swipe-too-short", "verify-finger-not-centered", "verify-remove-and-retry"):
            if done:
                self.finish("error", 2)
        else:
            self.finish("error", 1)

    def finish(self, event, *args):
        if not self.active:
            return
        self.active = False  # Invalidate before cleanup, which may dispatch signals.
        self.terminal = True
        try:
            self.backend.stop()
        finally:
            self.emit(event, *args)

    def cancel(self):
        if not self.active and not self.terminal:
            self.terminal = True
            self.emit("error", 5)
            return
        self.finish("error", 5)

    def timeout(self):
        self.finish("error", 3)
        return False


class Challenge:
    def __init__(self):
        self.value = 0
        self.expires = 0

    def generate(self):
        self.value = secrets.randbits(62) + 1
        self.expires = time.monotonic() + 120
        return self.value

    def consume(self, value):
        valid = self.value != 0 and value == self.value and time.monotonic() < self.expires
        self.value = 0
        return valid
