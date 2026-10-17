#!/usr/bin/env python3
"""Prepare pinned public ARM64 tools for a disposable integration container."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MAX_ARCHIVE = 64 * 1024 * 1024


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def prepare(destination):
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    policy = json.loads((ROOT / 'deploy/ansible/group_vars/all/sites-verifier.json').read_text())['ratatoskr_sites_verifier']
    for name in ['gh', 'oras']:
        tool = policy[name]
        archive = destination / (name + '.tar.gz')
        request = urllib.request.Request(tool['url'], headers={'User-Agent': 'Ratatoskr-integration'})
        with urllib.request.urlopen(request, timeout=60) as response, archive.open('wb') as output:
            total = 0
            while chunk := response.read(64 * 1024):
                total += len(chunk)
                if total > MAX_ARCHIVE:
                    raise ValueError('tool archive exceeds its bound')
                output.write(chunk)
        if sha256(archive) != tool['arm64_sha256']:
            raise ValueError('tool archive checksum does not match: ' + name)
        with tarfile.open(archive, 'r:gz') as source:
            for member_name, target in [(tool['binary'], name), (tool['license_path'], name + '.LICENSE')]:
                member = source.getmember(member_name)
                if not member.isfile() or member.size > MAX_ARCHIVE:
                    raise ValueError('tool archive member is not a bounded regular file')
                stream = source.extractfile(member)
                if stream is None:
                    raise ValueError('tool archive member is absent')
                with stream, (destination / target).open('wb') as output:
                    shutil.copyfileobj(stream, output, length=64 * 1024)
        if sha256(destination / name) != tool['binary_sha256']:
            raise ValueError('tool binary checksum does not match: ' + name)
        archive.unlink()
    source = ROOT / 'deploy/ansible/roles/sites_verifier/files/trusted-root.jsonl'
    if sha256(source) != policy['trusted_root_sha256']:
        raise ValueError('trust-root checksum does not match')
    shutil.copyfile(source, destination / 'trusted-root.jsonl')
    (destination / 'identity.json').write_text(json.dumps({
        'signer_commit': policy['signer_commit'],
        'tools': {name: policy[name]['binary_sha256'] for name in ['gh', 'oras']},
        'trusted_root_sha256': policy['trusted_root_sha256'],
    }, indent=2) + '\n')


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
