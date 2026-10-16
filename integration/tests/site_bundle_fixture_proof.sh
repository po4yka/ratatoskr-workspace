#!/usr/bin/env bash
# SITE-028: the genuine synthetic SDK site bundle, signed by the pinned reusable workflow.
# Server storage/activation and disposable resource checks remain separate gates.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export RATATOSKR_PROOF_ROOT="$root"
exec python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

root = Path(os.environ['RATATOSKR_PROOF_ROOT'])
out = Path(os.environ.get('RATATOSKR_EVIDENCE_DIR', root / 'evidence/site028-site-fixture')).resolve()
out.mkdir(parents=True, exist_ok=True)
oras = shutil.which(os.environ.get('RATATOSKR_ORAS_BIN', 'oras'))
gh = shutil.which(os.environ.get('RATATOSKR_GH_BIN', 'gh'))
if not oras or not gh:
    raise SystemExit('Install the approved gh and oras versions before this manual probe.')
env = {
    'PATH': '/usr/bin:/bin',
    'GH_CONFIG_DIR': str(out / 'gh-config'),
    'XDG_CONFIG_HOME': str(out / 'config'),
    'XDG_CACHE_HOME': str(out / 'cache'),
    'XDG_STATE_HOME': str(out / 'state'),
}
registry = out / 'registry.json'
registry.write_text('{}\n')
repository = 'po4yka/ratatoskr-site-sdk'
commit = '009afe32df0d5e10aaef79ae3e6bd6ecb3a989c9'
signer = 'po4yka/ratatoskr-site-sdk/.github/workflows/reusable-site-bundle.yml'
signer_commit = '89331e6aa0b845c3565c1d9785b0dd5038e2de81'
image = 'ghcr.io/' + repository


def run(name, arguments):
    result = subprocess.run(arguments, env=env, cwd=out, capture_output=True, text=True, timeout=120)
    (out / (name + '.json')).write_text(json.dumps({
        'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
    }, indent=2) + '\n')
    return result


def registry_call(name, arguments):
    result = run(name, [oras, *arguments, '--registry-config', str(registry)])
    if result.returncode:
        raise SystemExit(name + ' failed; inspect the local evidence.')
    return result.stdout


def checked_digest(value):
    if not re.fullmatch('sha256:[0-9a-f]{64}', value):
        raise SystemExit('The registry returned an invalid digest.')
    return value


def digest(path):
    return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()


if not run('gh-version', [gh, '--version']).stdout.startswith('gh version 2.102.0 '):
    raise SystemExit('The probe requires gh 2.102.0.')
if run('oras-version', [oras, 'version']).stdout.splitlines()[0].split() != ['Version:', '1.3.0']:
    raise SystemExit('The probe requires oras 1.3.0.')
artifact_digest = checked_digest(registry_call('resolve', ['resolve', image + ':sha-' + commit]).strip())
reference = image + '@' + artifact_digest
manifest = out / 'manifest.json'
registry_call('manifest-fetch', ['manifest', 'fetch', reference, '--output', str(manifest)])
if digest(manifest) != artifact_digest:
    raise SystemExit('The raw manifest does not match the OCI digest.')
referrers = json.loads(registry_call('discover', ['discover', '--format', 'json', reference]))
proofs = [r for r in referrers['referrers'] if r.get('artifactType') == 'application/vnd.dev.sigstore.bundle.v0.3+json']
if len(proofs) != 1:
    raise SystemExit('The fixed artifact must have exactly one Sigstore proof.')
proof_manifest = out / 'proof-manifest.json'
proof_manifest_digest = checked_digest(proofs[0]['digest'])
registry_call('proof-manifest-fetch', ['manifest', 'fetch', image + '@' + proof_manifest_digest, '--output', str(proof_manifest)])
if digest(proof_manifest) != proof_manifest_digest:
    raise SystemExit('The proof manifest digest does not match.')
proof_metadata = json.loads(proof_manifest.read_text())
if proof_metadata['subject']['digest'] != artifact_digest or len(proof_metadata['layers']) != 1:
    raise SystemExit('The proof has an unexpected subject or layer count.')
layer = proof_metadata['layers'][0]
if not 0 < layer['size'] <= 1024 * 1024:
    raise SystemExit('The proof exceeds the metadata bound.')
proof = out / 'proof.json'
registry_call('proof-fetch', ['blob', 'fetch', image + '@' + checked_digest(layer['digest']), '--output', str(proof)])
if proof.stat().st_size != layer['size'] or digest(proof) != layer['digest']:
    raise SystemExit('The proof bytes do not match their descriptor.')
policy = [
    '--bundle', str(proof), '--repo', repository, '--source-digest', commit,
    '--signer-workflow', signer, '--signer-digest', signer_commit,
    '--deny-self-hosted-runners', '--format', 'json',
    '--custom-trusted-root', str(root / 'deploy/ansible/roles/sites_verifier/files/trusted-root.jsonl'),
    '--cert-oidc-issuer', 'https://token.actions.githubusercontent.com',
    '--predicate-type', 'https://slsa.dev/provenance/v1', '--digest-alg', 'sha256',
]
original = run('verify-original', [gh, 'attestation', 'verify', str(manifest), *policy])
if original.returncode:
    raise SystemExit('Credential-free verification failed; do not change the trust policy.')
verified = json.loads(original.stdout)
certificates = [v['verificationResult']['signature']['certificate'] for v in verified]
if not any(c['sourceRepositoryIdentifier'] == '1420131953' and c['sourceRepositoryURI'] == 'https://github.com/' + repository for c in certificates):
    raise SystemExit('The verified certificate lacks the expected immutable repository identity.')
changed = out / 'changed-manifest.json'
changed.write_bytes(manifest.read_bytes() + b' ')
mutated = run('verify-changed', [gh, 'attestation', 'verify', str(changed), *policy])
if mutated.returncode == 0:
    raise SystemExit('The verifier accepted a changed manifest.')
summary = {
    'repository': repository, 'commit': commit, 'artifact_digest': artifact_digest,
    'signer_workflow': signer, 'signer_commit': signer_commit,
    'original_exit': original.returncode, 'changed_exit': mutated.returncode,
    'credential_environment': sorted(env), 'passed': True,
    'boundary': 'Real site-bundle proof; server storage/activation and ARM64 resource gates remain pending.',
}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print('Real site-bundle OCI proof: PASS; changed manifest: refused; no token or inherited tool configuration.')
PY
