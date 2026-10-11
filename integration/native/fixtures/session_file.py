"""Writes an XChaCha20-Poly1305 provider session file and its key (mode 0600) the way channel-digests src/session.rs reads them: nonce (24 bytes) then ciphertext, additional data ratatoskr-channel-digests-session-v1. The plaintext is a syntactically valid PersistedSession whose data-centre option points at a closed loopback port, so the worker's MTProto connection fails (the smoke has no credentials) and the worker logs provider_unavailable while its bus intake keeps working. usage: session_file.py OUTDIR"""
import os, struct, sys, json
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

def rotl(v, n): return ((v << n) & 0xFFFFFFFF) | (v >> (32 - n))
def qr(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & 0xFFFFFFFF; s[d] = rotl(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & 0xFFFFFFFF; s[b] = rotl(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & 0xFFFFFFFF; s[d] = rotl(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & 0xFFFFFFFF; s[b] = rotl(s[b] ^ s[c], 7)
def hchacha20(key, nonce16):
    s = list(struct.unpack("<4I", b"expand 32-byte k")) + list(struct.unpack("<8I", key)) + list(struct.unpack("<4I", nonce16))
    for _ in range(10):
        qr(s,0,4,8,12); qr(s,1,5,9,13); qr(s,2,6,10,14); qr(s,3,7,11,15)
        qr(s,0,5,10,15); qr(s,1,6,11,12); qr(s,2,7,8,13); qr(s,3,4,9,14)
    return struct.pack("<8I", *(s[0:4] + s[12:16]))
def xseal(key, nonce24, pt, aad):
    sub = hchacha20(key, nonce24[:16])
    return ChaCha20Poly1305(sub).encrypt(b"\0\0\0\0" + nonce24[16:], pt, aad)

out = sys.argv[1]
key = os.urandom(32); nonce = os.urandom(24)
plaintext = json.dumps({"home_dc": 2, "dc_options": [{"id": 2, "ipv4": "127.0.0.1:57999", "ipv6": "[::1]:57999", "auth_key": None}], "peer_infos": []}).encode()
ct = xseal(key, nonce, plaintext, b"ratatoskr-channel-digests-session-v1")
for name, data in (("session.key", key), ("session.enc", nonce + ct)):
    fd = os.open(os.path.join(out, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f: f.write(data)
