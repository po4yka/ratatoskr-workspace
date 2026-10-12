"""Minimal NATS client over the raw protocol with nkey auth (stdlib plus cryptography; nk, nsc and the nats CLI are not installed).

Two jobs. First, READ the broker through the JetStream API as the EDGE identity so a flow can observe the facts on the streams. Second, the deliberate probes of flow F0 and F5 under another identity's real seed: a subscription outside the identity's own inbox prefix, a publish outside its allow list, a consumer-info request for an owned durable, and one well-formed operation report published as a given producer. A refused subscribe or publish shows up as a Permissions Violation in the server log; the client sees an -ERR line for a subscription and nothing for a publish.

usage:
  natsprobe.py stream SEED STREAM [FILTER]                       print the stream state
  natsprobe.py messages SEED STREAM SUBJECT                      one JSON line per message on that exact subject: producer, tenant, aggregate
  natsprobe.py acl SEED PREFIX FOREIGN_PREFIX STREAM DURABLE  F0 inbox and publish probes (STREAM and DURABLE may be empty), prints one JSON line
  natsprobe.py tombstone EDGE_SEED SEED PREFIX PRODUCER TENANT ARCHIVE_ID CONVERSATION_ID   publish one conversation tombstone envelope
  natsprobe.py report SEED PREFIX TENANT OPERATION_ID PRODUCER   publish one platform.operation.reported.v1 with that envelope producer; TENANT is user:<uuid>
  natsprobe.py oversize SEED SUBJECT BYTES                    declare a publish of BYTES bytes (the header only, no payload follows) and print whether the broker refused it as a Maximum Payload Violation"""
import base64, json, socket, time, uuid
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

def _crc16(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc

def _seed_bytes(seed_text):
    s = seed_text.strip(); s += "=" * (-len(s) % 8)
    raw = base64.b32decode(s)
    assert _crc16(raw[:-2]) == int.from_bytes(raw[-2:], "little"), "bad seed checksum"
    return raw[2:-2]

def _pub(seed32):
    pub = Ed25519PrivateKey.from_private_bytes(seed32).public_key().public_bytes_raw()
    raw = bytes([20 << 3]) + pub
    raw += _crc16(raw).to_bytes(2, "little")
    return base64.b32encode(raw).decode().rstrip("=")

class Client:
    def __init__(self, seed_path, host="127.0.0.1", port=4222, inbox="_INBOX"):
        self.inbox = inbox
        seed = _seed_bytes(open(seed_path).read())
        self.s = socket.create_connection((host, port), timeout=10)
        self.f = self.s.makefile("rwb", buffering=0)
        info = json.loads(self.f.readline().decode().split(" ", 1)[1])
        sig = Ed25519PrivateKey.from_private_bytes(seed).sign(info["nonce"].encode())
        conn = {"verbose": False, "pedantic": False, "protocol": 1, "echo": True, "headers": True, "no_responders": True,
                "nkey": _pub(seed), "sig": base64.urlsafe_b64encode(sig).decode().rstrip("="), "lang": "smoke", "version": "0"}
        self.f.write(b"CONNECT " + json.dumps(conn).encode() + b"\r\nPING\r\n")
        line = self.f.readline().decode().strip()
        if line.startswith("-ERR"):
            raise PermissionError(line)
        assert line == "PONG", line
        self.sid = 0

    def sub(self, subject):
        self.sid += 1
        self.f.write(f"SUB {subject} {self.sid}\r\nPING\r\n".encode())
        return self.sid

    def pub(self, subject, payload=b"", reply=None):
        r = f" {reply}" if reply else ""
        self.f.write(f"PUB {subject}{r} {len(payload)}\r\n".encode() + payload + b"\r\n")

    def read_msg(self, timeout=5):
        """Return (subject, payload) or raise on -ERR / timeout. PONG/PING/+OK are skipped."""
        self.s.settimeout(timeout)
        while True:
            line = self.f.readline().decode().strip()
            if not line:
                raise TimeoutError("no data")
            if line.startswith("-ERR"):
                raise PermissionError(line)
            if line == "PING":
                self.f.write(b"PONG\r\n"); continue
            if line in ("PONG", "+OK") or line.startswith("INFO"):
                continue
            parts = line.split(" ")
            if parts[0] == "MSG":
                n = int(parts[-1]); data = self.f.read(n + 2)[:-2]
                return parts[1], data
            if parts[0] == "HMSG":
                total, hdr = int(parts[-1]), int(parts[-2]); data = self.f.read(total + 2)[:-2]
                return parts[1], data[hdr:]

    def request(self, subject, payload=b"", timeout=5):
        inbox = f"{self.inbox}.{uuid.uuid4().hex}"
        self.sub(inbox)
        self.pub(subject, payload, reply=inbox)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                _, data = self.read_msg(max(0.2, deadline - time.time()))
            except TimeoutError:
                break
            if data == b"" :  # no responders
                raise LookupError("no responders")
            return json.loads(data)
        raise TimeoutError(subject)

    def close(self):
        try: self.s.close()
        except OSError: pass

def stream_subjects(seed_path, stream="ratatoskr_events", filt=">"):
    c = Client(seed_path)
    try:
        return c.request(f"$JS.API.STREAM.INFO.{stream}", json.dumps({"subjects_filter": filt}).encode())
    finally:
        c.close()

def stream_messages(seed_path, stream, first_seq, last_seq):
    c = Client(seed_path); out = []
    try:
        for seq in range(first_seq, last_seq + 1):
            r = c.request(f"$JS.API.STREAM.MSG.GET.{stream}", json.dumps({"seq": seq}).encode())
            if "message" in r:
                m = r["message"]; out.append({"seq": m["seq"], "subject": m["subject"], "data": base64.b64decode(m.get("data", "")).decode(errors="replace")})
    finally:
        c.close()
    return out

def subscription_refused(seed_path, subject, inbox):
    """True when the broker answers a SUB on `subject` with a permissions error."""
    c = Client(seed_path, inbox=inbox)
    try:
        c.sid += 1
        c.f.write(f"SUB {subject} {c.sid}\r\nPING\r\n".encode())
        c.s.settimeout(3)
        for _ in range(4):
            line = c.f.readline().decode().strip()
            if line.startswith("-ERR"):
                return "ermission" in line
            if line == "PONG":
                return False
        return False
    except (OSError, TimeoutError):
        return False
    finally:
        c.close()


def consumer_info_ok(seed_path, inbox, stream, durable):
    c = Client(seed_path, inbox=inbox)
    try:
        r = c.request(f"$JS.API.CONSUMER.INFO.{stream}.{durable}", b"")
        return "config" in r and r["config"].get("durable_name") == durable
    except (OSError, TimeoutError, LookupError, PermissionError):
        return False
    finally:
        c.close()


def publish_refused(seed_path, subject, inbox):
    """A refused publish is invisible to the client (CONTRACTS S03 invariant 6); the server log carries the violation. Returns True when the call completed without error."""
    c = Client(seed_path, inbox=inbox)
    try:
        c.pub(subject, b"{}")
        c.f.write(b"PING\r\n")
        c.s.settimeout(3)
        return c.f.readline().decode().strip() in ("PONG", "-ERR 'Permissions Violation for Publish to \"%s\"'" % subject)
    except OSError:
        return False
    finally:
        c.close()


def oversize_refused(seed_path, subject, size):
    """The broker checks the declared size when it parses the PUB line, so the header alone shows whether `size` is above its max_payload; no payload is sent, which the flow labels."""
    c = Client(seed_path)
    try:
        c.f.write(f"PUB {subject} {size}\r\n".encode())
        c.s.settimeout(3)
        try:
            line = c.f.readline().decode().strip()
        except OSError:
            line = ""
        return {"refused": "Maximum Payload" in line, "reply": line}
    finally:
        c.close()


def _uuid7():
    raw = bytearray(uuid.uuid4().bytes)
    raw[0:6] = int(time.time() * 1000).to_bytes(6, "big")
    raw[6] = (raw[6] & 0x0F) | 0x70
    raw[8] = (raw[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(raw)))


def publish_report(seed_path, prefix, tenant, operation_id, producer, status="running", stage="capture_queued"):
    """Publishes one well-formed platform.operation.reported.v1 envelope (contracts core/event-envelope shape) under the given envelope producer, through the connection of the identity whose seed is given. Platform accepts it only when the tenant owns the operation and the producer is the lane the operation was dispatched to (R3-02)."""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    event_id = _uuid7()
    envelope = {"event_id": event_id, "event_type": "platform.operation.reported.v1", "occurred_at": now, "producer": producer,
                "aggregate_id": f"operation:{operation_id}", "correlation_id": f"operation:{operation_id}",
                "tenant_id": tenant, "schema_version": 1,
                "payload": {"operation_id": operation_id, "status": status, "stage": stage}}
    c = Client(seed_path, inbox=prefix)
    try:
        c.pub("evt.platform.operation.reported.v1", json.dumps(envelope).encode())
        c.f.write(b"PING\r\n")
        c.s.settimeout(3)
        c.f.readline()
        return event_id
    finally:
        c.close()


def publish_tombstone(edge_seed, seed_path, prefix, producer, tenant, archive_id, conversation_id, provider="chatgpt"):
    """Publishes one well-formed evt.ai_archive.subject.tombstoned.v1 (a conversation tombstone, contracts fixture shape) under the given producer and tenant, through the connection of the identity whose seed is given. Flow F6 uses it to deliver a tombstone while PostgreSQL is down, and to publish a tombstone that names another tenant's subject."""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    event_id = _uuid7()
    owner = tenant.split(":", 1)[1] if tenant.startswith("user:") else tenant
    # The aggregate and correlation reference formats are copied from a real archive fact on the stream, so the envelope is well formed without this probe guessing a namespace.
    state = stream_subjects(edge_seed, "ratatoskr_events", "evt.ai_archive.archive.imported.v1").get("state", {})
    template = next(iter(m for m in stream_messages(edge_seed, "ratatoskr_events", state.get("first_seq", 1), state.get("last_seq", 0)) if m["subject"] == "evt.ai_archive.archive.imported.v1"), None)
    if template is None:
        raise SystemExit("no archive.imported fact on the stream to copy the envelope format from")
    base = json.loads(template["data"])
    envelope = {"event_id": event_id, "event_type": "ai_archive.subject.tombstoned.v1", "occurred_at": now, "producer": producer,
                "aggregate_id": base["aggregate_id"], "correlation_id": f"event:{event_id}", "tenant_id": tenant, "schema_version": 1,
                "payload": {"ai_archive_id": archive_id, "provider": provider, "owner": f"user:{owner}",
                            "subject": {"subject_kind": "conversation", "ai_conversation_id": conversation_id},
                            "reason": "provider_deletion_event",
                            "evidence_ref": {"owner_service": producer, "digest": {"algorithm": "sha256", "hex": "0" * 63 + "1"}, "media_type": "application/json", "length_bytes": 2},
                            "observed_at": now}}
    c = Client(seed_path, inbox=prefix)
    try:
        c.pub("evt.ai_archive.subject.tombstoned.v1", json.dumps(envelope).encode())
        c.f.write(b"PING\r\n")
        c.s.settimeout(3)
        c.f.readline()
        return event_id
    finally:
        c.close()


if __name__ == "__main__":
    import sys
    cmd = sys.argv[1]
    if cmd == "stream":
        info = stream_subjects(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else ">")
        print(json.dumps(info.get("state", info), indent=1)[:3000])
    elif cmd == "acl":
        seed, prefix, foreign, stream, durable = (sys.argv[2:7] + [""] * 5)[:5]
        out = {
            "shared_inbox_refused": subscription_refused(seed, "_INBOX.>", prefix),
            "foreign_inbox_refused": subscription_refused(seed, foreign + ".>", prefix),
            "own_inbox_allowed": not subscription_refused(seed, prefix + ".>", prefix),
            "owned_consumer_info_ok": consumer_info_ok(seed, prefix, stream, durable) if durable else None,
            "publish_outside_list_sent": publish_refused(seed, "evt.f0.probe.v1", prefix),
        }
        print(json.dumps(out))
    elif cmd == "messages":
        seed, stream, subject = sys.argv[2:5]
        state = stream_subjects(seed, stream, subject).get("state", {})
        for m in stream_messages(seed, stream, state.get("first_seq", 1), state.get("last_seq", 0)):
            if m["subject"] == subject:
                try:
                    envelope = json.loads(m["data"])
                    print(json.dumps({"seq": m["seq"], "subject": subject, "producer": envelope.get("producer"), "tenant_id": envelope.get("tenant_id"), "aggregate_id": envelope.get("aggregate_id")}))
                except json.JSONDecodeError:
                    print(json.dumps({"seq": m["seq"], "subject": subject, "unparsed": True}))
    elif cmd == "tombstone":
        print(publish_tombstone(*sys.argv[2:9]))
    elif cmd == "report":
        print(publish_report(*sys.argv[2:7]))
    elif cmd == "oversize":
        print(json.dumps(oversize_refused(sys.argv[2], sys.argv[3], int(sys.argv[4]))))
    else:
        raise SystemExit(__doc__)
