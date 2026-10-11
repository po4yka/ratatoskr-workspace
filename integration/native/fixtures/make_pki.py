"""Throwaway CA and one server leaf (IP SAN 127.0.0.1) for the loopback fake X API. The CA certificate goes to X's EXTRA_CA_FILE (the one documented TLS seam, R3-15); the keys never leave the smoke directory. usage: make_pki.py OUTDIR

Writes ca.pem, ca.key, leaf.pem, leaf.key (keys mode 0600). Uses the cryptography package because the macOS openssl is LibreSSL."""
import datetime
import ipaddress
import pathlib
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)


def name(common_name: str) -> x509.Name:
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])


def write_key(path: pathlib.Path, key) -> None:
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    path.chmod(0o600)


ca_key = ec.generate_private_key(ec.SECP256R1())
ca = (
    x509.CertificateBuilder()
    .subject_name(name("Ratatoskr smoke throwaway CA"))
    .issuer_name(name("Ratatoskr smoke throwaway CA"))
    .public_key(ca_key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - datetime.timedelta(minutes=5))
    .not_valid_after(now + datetime.timedelta(days=2))
    .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
    .add_extension(x509.KeyUsage(digital_signature=False, content_commitment=False, key_encipherment=False, data_encipherment=False, key_agreement=False, key_cert_sign=True, crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
    .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
    .sign(ca_key, hashes.SHA256())
)
leaf_key = ec.generate_private_key(ec.SECP256R1())
leaf = (
    x509.CertificateBuilder()
    .subject_name(name("127.0.0.1"))
    .issuer_name(ca.subject)
    .public_key(leaf_key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - datetime.timedelta(minutes=5))
    .not_valid_after(now + datetime.timedelta(days=2))
    .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), critical=False)
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False, data_encipherment=False, key_agreement=False, key_cert_sign=False, crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
    .sign(ca_key, hashes.SHA256())
)
(out / "ca.pem").write_bytes(ca.public_bytes(serialization.Encoding.PEM))
(out / "leaf.pem").write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
write_key(out / "ca.key", ca_key)
write_key(out / "leaf.key", leaf_key)
