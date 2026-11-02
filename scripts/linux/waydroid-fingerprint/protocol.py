"""Frozen fingerprint AIDL v1 parcel layout (Android 16 accepts older versions)."""
import struct

FINGERPRINT = "android.hardware.biometrics.fingerprint.IFingerprint"
SESSION = "android.hardware.biometrics.fingerprint.ISession"
CALLBACK = "android.hardware.biometrics.fingerprint.ISessionCallback"
CANCEL = "android.hardware.biometrics.common.ICancellationSignal"
FINGERPRINT_HASH = "3621eefdbae063097dad0037cd1f111792ff12ec"
COMMON_HASH = "9ad0b938db247283c4a8c1bf7e4218a420019024"
GET_VERSION = 16777215
GET_HASH = 16777214
SENSOR_ID = 71


def i32(value):
    return struct.pack("<i", value)


def i64(value):
    return struct.pack("<q", value)


def parcel(body):
    return i32(len(body) + 4) + body


def typed(body):
    return i32(1) + parcel(body)


def int_array(values):
    return i32(len(values)) + b"".join(i32(v) for v in values)


def sensor_props():
    # CommonProps: WEAK=1, one enrollment, empty component metadata.
    common = typed(i32(SENSOR_ID) + i32(1) + i32(1) + i32(0))
    # REAR=1; empty locations; navigation=false, detection=true, display flags=false.
    sensor = typed(common + i32(1) + i32(0) + i32(0) + i32(1) + i32(0) + i32(0))
    return i32(1) + sensor


def empty_auth_token():
    # Weak biometric: no signed token, key release, or fabricated cryptographic claim.
    timestamp = typed(i64(0))
    return typed(i64(0) * 3 + i32(0) + timestamp + i32(0))


def read_int(reader, bits=32):
    ok, value = reader.read_int64() if bits == 64 else reader.read_int32()
    if not ok:
        raise ValueError("Truncated Binder argument")
    return value


def read_hat(reader):
    """Parse an enrollment HAT; caller/challenge checks are done separately.

    Zero-filled signatures are allowed: observed on this image. This does not claim to validate its HMAC. Only system_server is allowed to
    enroll, after Android's own credential verification, with our fresh challenge.
    """
    if read_int(reader) != 1:
        raise ValueError("Missing enrollment token")
    start = reader.bytes_read()
    size = read_int(reader)
    if not 48 <= size <= 1024:
        raise ValueError("Invalid enrollment token size")
    challenge, user, auth_id = (read_int(reader, 64) for _ in range(3))
    auth_type = read_int(reader)
    if read_int(reader) != 1:
        raise ValueError("Missing timestamp")
    stamp_size = read_int(reader)
    if stamp_size != 12:
        raise ValueError("Invalid timestamp size")
    timestamp = read_int(reader, 64)
    mac = bytes(reader.read_byte_array())
    if reader.bytes_read() - start != size:
        raise ValueError("Enrollment token size does not match payload")
    if user == 0 or auth_type != 1 or len(mac) != 32:
        raise ValueError(f"Invalid credential token: user_present={user != 0}, type={auth_type}, mac_length={len(mac)}, mac_present={any(mac)}")
    return challenge, timestamp
