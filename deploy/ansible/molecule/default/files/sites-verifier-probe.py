"""Real public proof under the Sites memory budget. No credentials or fake tool output."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

phase, fixture_name, working_name = sys.argv[1:]
fixture = Path(fixture_name)
working = Path(working_name)
working.mkdir(mode=0o700, parents=True, exist_ok=True)
policy = json.loads((fixture / 'identity.json').read_text())
tools = Path('/usr/lib/ratatoskr-sites/verifier')
env = {
    'PATH': '/usr/bin:/bin', 'GH_CONFIG_DIR': str(working / 'gh'),
    'XDG_CONFIG_HOME': str(working / 'config'), 'XDG_CACHE_HOME': str(working / 'cache'),
    'XDG_STATE_HOME': str(working / 'state'), 'GH_HOST': 'github.com',
    'GH_PROMPT_DISABLED': '1',
}
registry = working / 'registry.json'
registry.write_text('{}\n')
image = 'ghcr.io/' + policy['repository']
reference = image + '@' + policy['artifact_digest']


def run(arguments):
    return subprocess.run(arguments, env=env, cwd=working, capture_output=True, timeout=120)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(65536):
            result.update(block)
    return 'sha256:' + result.hexdigest()


if phase == 'fetch':
    manifest = working / 'manifest.json'
    result = run([str(tools / 'oras'), 'manifest', 'fetch', reference, '--output', str(manifest),
                  '--registry-config', str(registry)])
    assert result.returncode == 0, 'anonymous manifest fetch failed'
    assert digest(manifest) == policy['artifact_digest']
    metadata = json.loads(manifest.read_text())
    assert metadata['artifactType'] == 'application/vnd.ratatoskr.site-bundle.v1'
    assert len(metadata['layers']) == 1
    layer = metadata['layers'][0]
    assert layer['mediaType'] == 'application/vnd.ratatoskr.site-bundle.v1.tar'
    assert 0 < layer['size'] <= 80 * 1024 * 1024
    archive = working / 'bundle.tar'
    result = run([str(tools / 'oras'), 'blob', 'fetch', image + '@' + layer['digest'],
                  '--output', str(archive), '--registry-config', str(registry), '--no-tty'])
    assert result.returncode == 0, 'anonymous archive fetch failed'
    assert archive.stat().st_size == layer['size'] and digest(archive) == layer['digest']
    print('anonymous immutable manifest and archive: PASS')
elif phase == 'verify':
    manifest = working / 'manifest.json'
    assert digest(manifest) == policy['artifact_digest']
    arguments = [str(tools / 'gh'), 'attestation', 'verify', str(manifest),
                 '--bundle', str(fixture / 'proof.json'),
                 '--custom-trusted-root', str(tools / 'trusted-root.jsonl'),
                 '--repo', policy['repository'], '--source-digest', policy['commit'],
                 '--signer-workflow', policy['signer_workflow'], '--signer-digest', policy['signer_commit'],
                 '--deny-self-hosted-runners', '--cert-oidc-issuer', 'https://token.actions.githubusercontent.com',
                 '--predicate-type', 'https://slsa.dev/provenance/v1', '--digest-alg', 'sha256', '--format', 'json']
    result = run(arguments)
    assert result.returncode == 0, 'offline signature verification failed'
    assert len(result.stdout) <= 1024 * 1024
    certificates = [item['verificationResult']['signature']['certificate'] for item in json.loads(result.stdout)]
    assert any(item['sourceRepositoryIdentifier'] == '1420131953' for item in certificates)
    changed = working / 'changed.json'
    changed.write_bytes(manifest.read_bytes() + b' ')
    arguments[3] = str(changed)
    assert run(arguments).returncode != 0, 'changed manifest accepted'
    print('offline signature, immutable repository ID and changed-byte refusal: PASS')
else:
    raise ValueError('unknown probe phase')

# The parent unit/container includes both the probe and every tool subprocess in this bound.
cgroup = Path('/sys/fs/cgroup') / Path('/proc/self/cgroup').read_text().strip().split('::', 1)[1].lstrip('/')
limit = (cgroup / 'memory.max').read_text().strip()
peak = int((cgroup / 'memory.peak').read_text())
swap_limit = (cgroup / 'memory.swap.max').read_text().strip()
assert swap_limit == '0', 'the verifier may use swap'
assert limit == '536870912' and peak <= 536870912, 'the 512 MiB verifier budget is not enforced'
print(json.dumps({'memory_max_bytes': int(limit), 'memory_peak_bytes': peak, 'swap_max_bytes': int(swap_limit), 'environment_keys': sorted(env)}))
