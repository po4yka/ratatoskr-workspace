#!/usr/bin/env python3
# verify_sums.py <artifact dir>: every file SHA256SUMS names matches it, and SHA256SUMS names every
# binary in the directory. Python rather than sha256sum/shasum, so the controller may be Linux or
# macOS. Exit 1 names each mismatch.
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
listed = {}
for line in (root / "SHA256SUMS").read_text().splitlines():
    digest, name = line.split(maxsplit=1)
    listed[name.strip()] = digest
errors = []
for name, digest in sorted(listed.items()):
    path = root / name
    if not path.is_file():
        errors.append(f"{name}: listed in SHA256SUMS and missing")
    elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        errors.append(f"{name}: does not match SHA256SUMS")
present = {p.name for p in root.iterdir() if p.is_file()}
for name in sorted(present - set(listed) - {"SHA256SUMS", "sbom.spdx.json", ".attested"}):
    errors.append(f"{name}: in the artifact and not in SHA256SUMS")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"{len(listed)} binaries match SHA256SUMS")
