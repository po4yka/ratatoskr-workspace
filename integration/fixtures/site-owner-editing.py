#!/usr/bin/env python3
"""Real HTTP/bus/DB scenario. Device, Sync tree and Knowledge inputs are synthetic fixtures."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

PROJECT, PROFILE = sys.argv[1:]
BASE = os.environ['RATATOSKR_SITE027_URL']
EVIDENCE = Path(os.environ['RATATOSKR_EVIDENCE_DIR'])
def uuid7():
    millis = int(time.time() * 1000)
    return uuid.UUID(int=(millis << 80) | (7 << 76) | (secrets.randbits(12) << 64)
                     | (2 << 62) | secrets.randbits(62))


OWNER, OTHER, DEVICE = (str(uuid7()) for _ in range(3))
OWNER_TOKEN, DEVICE_TOKEN = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
HOST = 'garden.example.test'
SITE = '/v1/sites/site-a'
COMPOSE = ['docker', 'compose', '--project-name', PROJECT, '--file', PROFILE]
RESULTS = []


def sql(statement):
    result = subprocess.run(COMPOSE + ['exec', '-T', 'postgres', 'psql', '-XAt', '-v',
                                      'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'ratatoskr'],
                            input=statement, text=True, capture_output=True, check=False)
    if result.returncode:
        raise AssertionError('fixture SQL failed: ' + result.stderr)
    return result.stdout.strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def call(path, method='GET', body=None, token=None, cookie=None, expected=(200,), raw=False, site_origin=False):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if cookie:
        headers['Cookie'] = cookie
    if cookie or site_origin:
        headers.update({'Origin': 'https://' + HOST, 'X-Ratatoskr-Site-Request': '1'})
    if body is not None:
        if isinstance(body, bytes):
            headers['Content-Type'] = 'application/octet-stream'
        else:
            headers['Content-Type'] = 'application/json'
            body = json.dumps(body).encode()
    if method != 'GET':
        headers['Idempotency-Key'] = str(uuid7())
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=150)
    except urllib.error.HTTPError as error:
        response = error
    data = response.read()
    assert response.status in expected, (method, path, response.status, data.decode(errors='replace'))
    if raw:
        return data, response.headers
    return json.loads(data) if data else {}


def eventually(fn, description, seconds=90):
    end, last = time.monotonic() + seconds, None
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (AssertionError, OSError, ValueError) as error:
            last = str(error)
        time.sleep(0.5)
    raise AssertionError('Timed out: ' + description + '; last=' + str(last))


def passed(name):
    RESULTS.append(name)
    print(name + ': PASS', flush=True)


def upload(connection, data, media_type="text/markdown"):
    path = '/v1/notes/connections/' + connection + '/blobs'
    opened = call(path, 'POST', {'declared_size_bytes': len(data), 'media_type': media_type,
                  'digest': {'algorithm': 'sha256', 'hex': digest(data)},
                  'chunk_size_bytes': 65536}, token=DEVICE_TOKEN, expected=(201,))
    token = opened['resumption_token']
    call(path + '/' + token + '/chunks/0', 'PUT', data, token=DEVICE_TOKEN)
    return call(path + '/' + token + '/finalize', 'POST', {'resumption_token': token},
                token=DEVICE_TOKEN)['blob_ref']


def connection(files, name):
    connected = call('/v1/notes/connections', 'POST', {'channel': 'plugin', 'vault_key': name,
                     'vault_display_name': name}, token=DEVICE_TOKEN, expected=(201, 202))
    cid = connected['connection']['connection_id']
    for path, data in files.items():
        upload(cid, data, 'image/png' if path.endswith('.png') else 'text/markdown')
    call('/v1/notes/connections/' + cid + '/manifest', 'POST', {'entries': [
        {'path': path, 'sha256': digest(data), 'length_bytes': len(data)}
        for path, data in files.items()]}, token=DEVICE_TOKEN)
    call('/v1/notes/connections/' + cid + '/write-mode', 'PUT', {'write_mode': 'on'}, token=OWNER_TOKEN, expected=(202,))
    return cid


def queue_item(cid, operation):
    def find():
        items = call('/v1/notes/connections/' + cid + '/device-operations', token=DEVICE_TOKEN)['operations']
        return next((item for item in items if item['operation_id'] == operation), None)
    return eventually(find, 'device delivery ' + operation)


def ack(cid, operation, content_hash, rewrites=None):
    return call('/v1/notes/connections/' + cid + '/device-operations/' + operation + '/result', 'POST',
                {'outcome': 'applied', 'sha256': content_hash, 'rewrites': rewrites or []}, token=DEVICE_TOKEN)


def counts(cid):
    value = sql("select json_build_array((select count(*) from notes.revisions r join notes.files f using(file_id) "
                f"where f.connection_id='{cid}'),(select count(*) from notes.outbox where event_type="
                f"'notes.file.changed.v1' and payload->'payload'->>'connection_id'='{cid}'))")
    return json.loads(value)


def write(cid, operation):
    return call('/v1/notes/connections/' + cid + '/writes', 'POST', {'operation': operation},
                token=OWNER_TOKEN, expected=(202,))['operation_id']


class Events:
    """A real Edge SSE stream. Reader failures become assertions in the main scenario."""
    def __init__(self, cookie=None):
        self.items = queue.Queue()
        self.connected = threading.Event()
        self.error = None
        self.stop = False
        self.response = None
        def read():
            try:
                headers = {'Accept': 'text/event-stream'}
                if cookie:
                    headers['Cookie'] = cookie
                request = urllib.request.Request(BASE + SITE + '/events', headers=headers)
                self.response = urllib.request.urlopen(request, timeout=120)
                self.connected.set()
                data = []
                while not self.stop:
                    line = self.response.readline().decode().rstrip('\r\n')
                    if line.startswith('data:'):
                        data.append(line[5:].strip())
                    elif not line and data:
                        self.items.put(json.loads('\n'.join(data)))
                        data = []
            except Exception as error:  # Carry reader errors to the assertion thread.
                if not self.stop:
                    self.error = repr(error)
                self.connected.set()
        self.thread = threading.Thread(target=read, daemon=True)
        self.thread.start()
        assert self.connected.wait(30), 'SSE handshake timed out'
        assert not self.error, self.error

    def expect(self, kind, operation=None, seconds=90, different_release=None):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            assert not self.error, self.error
            try:
                item = self.items.get(timeout=0.5)
                if (item['type'] == kind and (operation is None or item['payload']['operation_id'] == operation)
                        and (different_release is None or item['payload']['release_id'] != different_release)):
                    return item
            except queue.Empty:
                pass
        raise AssertionError('SSE did not emit ' + kind + ' for ' + str(operation))

    def close(self):
        self.stop = True
        # The reader is daemonized. Teardown closes the server; do not block on a pending read.


def seed():
    sql(f"""
insert into identity.users(user_id,status,created_at,updated_at) values
('{OWNER}','active',now(),now()),('{OTHER}','active',now(),now());
insert into identity.registered_devices(device_id,user_id,kind,display_name,secret_hash,created_at)
values('{DEVICE}','{OWNER}','obsidian_plugin','fixture plugin',decode('{digest(secrets.token_bytes(32))}','hex'),now());
insert into identity.sessions(session_id,user_id,kind,device_id,audience,issued_at,expires_at,token_hash) values
('{uuid7()}','{OWNER}','browser',null,'edge',now(),now()+interval '1 hour',decode('{digest(OWNER_TOKEN.encode())}','hex')),
('{uuid7()}','{OWNER}','device','{DEVICE}','edge',now(),now()+interval '1 hour',decode('{digest(DEVICE_TOKEN.encode())}','hex'));
insert into identity.grants(grant_id,user_id,capability,granted_at) values
('{uuid7()}','{OWNER}','platform.owner',now());
""")


def seed_knowledge():
    ids = []
    for tenant, title in [(OWNER, 'marker owner'), (OTHER, 'marker foreign')]:
        source, document, search, output = (str(uuid7()) for _ in range(4))
        ids.append(document)
        blob = json.dumps({'owner_service': 'fixture-owner', 'digest': {'algorithm': 'sha256', 'hex': 'a'*64},
                           'media_type': 'application/json', 'length_bytes': 128})
        sql(f"""insert into knowledge.source_refs(source_ref_id,tenant_ref,owner_context,source_document_id,
content_digest_algorithm,content_digest_hex,source_blob)
values('{source}','user:{tenant}','fixture-owner','{document}','sha256','{'a'*64}','{blob}');
insert into knowledge.search_documents(search_document_id,source_ref_id,latest_output_id,tenant_ref,
owner_context,document_id,title,lead,body,updated_at) values('{search}','{source}','{output}',
'user:{tenant}','fixture-owner','{document}','{title}','marker text','marker body',now());""")
    return ids


def verified_bundle_repository_boundary():
    """Use a real workflow-signed SDK artifact; mutations must never store or activate it."""
    fixture = Path(__file__).resolve().parents[1] / 'fixtures/site028-real-proof'
    identity = json.loads((fixture / 'identity.json').read_text())
    proof = json.loads((fixture / 'proof.json').read_text())
    path = '/v1/sites/provenance-fixture'
    binding = {'repository': 'po4yka/ratatoskr-site-sdk', 'repository_id': '1420131953'}
    manifest = ('site_id = "provenance-fixture"\nhostname = "provenance.example.test"\n'
                'publications = ["bundle"]\ncapabilities = ["pages.read"]\n[github_repository]\n'
                'repository = "po4yka/ratatoskr-site-sdk"\nrepository_id = "1420131953"\n').encode()
    call(path + '/manifest', 'PUT', manifest, token=OWNER_TOKEN, expected=(200, 201))
    approval = call(path + '/manifest/approval', 'POST', {'manifest_sha256': digest(manifest)},
                    token=OWNER_TOKEN, expected=(200, 201, 202))
    assert approval['github_repository'] == binding, approval
    eventually(lambda: sql("select state from sites.approval_projection where site_id='provenance-fixture'") == 'approved', 'repository approval projection')
    request = {'commit': identity['commit'], 'artifact_sha256': identity['artifact_digest'].removeprefix('sha256:'),
               'attestation_bundle': proof}
    target = '/data/site-deploys/provenance-fixture/bundles/' + request['commit']

    def absent():
        result = subprocess.run(COMPOSE + ['exec', '-T', 'sites', 'test', '!', '-e', target], check=False)
        assert result.returncode == 0, 'a refused proof stored a deploy'

    unsigned = dict(request, attestation_bundle={})
    call(path + '/deploys', 'POST', unsigned, token=OWNER_TOKEN, expected=(422,))
    absent()
    changed = dict(request, artifact_sha256='a' * 64)
    call(path + '/deploys', 'POST', changed, token=OWNER_TOKEN, expected=(422,))
    absent()
    foreign = manifest.replace(b'repository_id = "1420131953"', b'repository_id = "999999"')
    call(path + '/manifest', 'PUT', foreign, token=OWNER_TOKEN, expected=(200, 201))
    call(path + '/manifest/approval', 'POST', {'manifest_sha256': digest(foreign)}, token=OWNER_TOKEN, expected=(200, 201, 202))
    eventually(lambda: sql("select github_repository->>'repository_id' from sites.approval_projection where site_id='provenance-fixture'") == '999999', 'foreign repository approval')
    call(path + '/deploys', 'POST', request, token=OWNER_TOKEN, expected=(422,))
    absent()
    call(path + '/manifest', 'PUT', manifest, token=OWNER_TOKEN, expected=(200, 201))
    call(path + '/deploys', 'POST', request, token=OWNER_TOKEN, expected=(404, 409, 422))
    absent()
    call(path + '/manifest/approval', 'POST', {'manifest_sha256': digest(manifest)}, token=OWNER_TOKEN, expected=(200, 201, 202))
    eventually(lambda: sql("select github_repository->>'repository_id' from sites.approval_projection where site_id='provenance-fixture'") == '1420131953', 'restored repository approval')
    stored = call(path + '/deploys', 'POST', request, token=OWNER_TOKEN)
    assert stored['created'] is True, stored
    retry = call(path + '/deploys', 'POST', request, token=OWNER_TOKEN)
    assert retry['created'] is False, retry
    active = call(path + '/deploys/' + request['commit'] + '/activate', 'POST', token=OWNER_TOKEN)
    assert active['current_commit'] == request['commit'], active
    measured = subprocess.check_output(COMPOSE + ['exec', '-T', 'sites', 'sh', '-ec',
        'cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max /sys/fs/cgroup/memory.peak'], text=True).splitlines()
    maximum, swap, peak = map(int, measured)
    assert maximum == 512 * 1024 * 1024 and swap == 0, measured
    assert 0 < peak <= maximum, measured
    EVIDENCE.joinpath('verifier-memory.json').write_text(json.dumps({
        'memory_max_bytes': maximum, 'memory_swap_max_bytes': swap, 'memory_peak_bytes': peak,
        'scope': 'Sites service and its actual gh/oras children in one disposable ARM64 container',
    }, indent=2) + '\n')
    passed('verified_bundle_repository_boundary')


def main():
    eventually(lambda: call('/v1/status'), 'Edge startup', seconds=120)
    # The shipped grants run only after Edge has created its schema.
    grants = Path(os.environ['RATATOSKR_PLATFORM_CONTEXT'], 'deploy/postgres/02-grants.sql').read_text()
    sql(grants)
    for schema in ['notes', 'sites', 'knowledge']:
        eventually(lambda s=schema: sql(f"select exists(select 1 from information_schema.schemata where schema_name='{s}')") == 't', schema + ' schema')
    seed()
    verified_bundle_repository_boundary()
    eventually(lambda: call('/v1/notes/connections', token=OWNER_TOKEN), 'Notes API ready')
    notes_write_back()
    privacy_path = Path(__file__).resolve().parents[1] / 'sites-privacy/scenario.py'
    spec = importlib.util.spec_from_file_location('sites_privacy', privacy_path)
    privacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(privacy)
    privacy_counts = privacy.run(call, connection, eventually, digest, OWNER_TOKEN,
                                 os.environ['RATATOSKR_SITES_CONTEXT'])
    passed('sites_privacy_anonymous_pages_assets_search')
    old, new = b'# Start\nold text\n', b'# Start\nnew text\n'
    cid = connection({'Start.md': old}, 'site-fixture')
    manifest = ('site_id = "site-a"\nhostname = "' + HOST + '"\npublications = ["garden"]\n'
                'capabilities = ["pages.read", "live.release", "draft.read", "notes.edit", "library.read", "knowledge.search"]\n'
                '[github_repository]\nrepository = "po4yka/ratatoskr-site-sdk"\nrepository_id = "1420131953"\n').encode()
    call(SITE + '/manifest', 'PUT', manifest, token=OWNER_TOKEN, expected=(200, 201))
    call(SITE + '/publications/garden', 'PUT', {'connection_id': cid, 'mode': 'all', 'release_mode': 'manual',
         'included_folders': [], 'excluded_folders': [], 'included_tags': [], 'frontmatter_allow': []}, token=OWNER_TOKEN, expected=(200, 201))
    call(SITE + '/manifest/approval', 'POST', {'manifest_sha256': digest(manifest)}, token=OWNER_TOKEN, expected=(200, 201, 202))
    call(SITE + '/releases', 'POST', token=OWNER_TOKEN, expected=(202,))
    page = eventually(lambda: call(SITE + '/content/pages/start'), 'first public release')
    assert 'old text' in json.dumps(page), page
    _, release_headers = call(SITE + '/content/release', raw=True)
    old_release = release_headers['ETag'].strip(chr(34))
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    code = call(SITE + '/sign-in-codes', 'POST', {'challenge': challenge, 'return_path': '/notes/start'}, token=OWNER_TOKEN, expected=(201,))
    assert code['redirect_url'] == 'https://' + HOST + '/.ratatoskr/sign-in/?code=' + code['code']
    body, headers = call(SITE + '/sessions', 'POST', {'code': code['code'], 'verifier': verifier},
                         site_origin=True, expected=(201,), raw=True)
    assert json.loads(body)['return_path'] == '/notes/start'
    cookie = headers['Set-Cookie'].split(';', 1)[0]
    assert cookie.startswith('__Host-ratatoskr-site=')
    attrs = headers['Set-Cookie'].lower()
    assert all(value in attrs for value in ['secure', 'httponly', 'samesite=strict']) and 'domain=' not in attrs
    passed('consent_sign_in')
    owner_events = Events(cookie)
    draft = call(SITE + '/drafts/pages/start', cookie=cookie)
    source = draft['source_ref']
    uploaded = call(SITE + '/drafts/sources/' + source + '/blobs', 'POST', new, cookie=cookie, expected=(201,))
    def edit(base):
        return call(SITE + '/edits', 'POST', {'source_ref': source, 'base_hash': base,
                    'content_blob': uploaded['content_blob'], 'content_hash': uploaded['content_hash'],
                    'idempotency_key': str(uuid7())}, cookie=cookie, expected=(202,))['operation_id']
    before = counts(cid)
    stale = edit('0'*64)
    owner_events.expect('edit.conflicted', stale)
    assert counts(cid) == before, 'a stale write changed revisions/events'
    assert sql(f"select count(*) from notes.conflicts where operation_id='{stale}'") == '1'
    assert sql(f"select count(*) from notes.outbox where event_type='notes.conflict.raised.v1' and payload->'payload'->>'connection_id'='{cid}' and payload->'payload'->>'operation_id'='{stale}'") == '1'
    passed('edit_conflicted')
    current = edit(draft['revision'])
    delivered = queue_item(cid, current)
    assert delivered['expected_sha256'] == digest(new), delivered
    assert counts(cid) == before, 'write was indexed before device acknowledgement'
    fetched, _ = call('/v1/notes/connections/' + cid + '/device-operations/' + current + '/content', token=DEVICE_TOKEN, raw=True)
    assert fetched == new
    ack(cid, current, digest(new))
    owner_events.expect('edit.completed', current)
    after = counts(cid)
    assert after == [before[0]+1, before[1]+1], (before, after)
    ack(cid, current, digest(new))
    assert counts(cid) == after, 'a repeated acknowledgement duplicated a revision/event'
    passed('edit_completed')
    assert call(SITE + '/content/pages/start') == page, 'manual mode changed the published release'
    passed('manual_release_retains_old_text')
    public_events = Events()
    call(SITE + '/releases', 'POST', body=b'', cookie=cookie, expected=(202,))
    event = public_events.expect('release.published', different_release=old_release)
    assert set(event['payload']) <= {'release_id', 'published_at'}, event
    eventually(lambda: 'new text' in json.dumps(call(SITE + '/content/pages/start')), 'new public release')
    passed('release_published_public_sse')
    owned, foreign = seed_knowledge()
    for route in ['/library?q=marker', '/knowledge/search?q=marker']:
        result = call(SITE + route, cookie=cookie)
        assert result['items'] and owned in json.dumps(result), result
        assert foreign not in json.dumps(result) and 'marker foreign' not in json.dumps(result), result
    passed('knowledge_search_holds_only_owner_documents')
    owner_events.close()
    public_events.close()
    EVIDENCE.joinpath('.scenario-result.json').write_text(json.dumps({'passed': RESULTS, 'privacy': privacy_counts, 'revisions': {name: os.environ['RATATOSKR_'+name+'_REVISION'] for name in ['PLATFORM', 'SITES', 'NOTES', 'KNOWLEDGE']},
        'fixtures': ['seeded primary/device sessions', 'fake device acknowledgements', 'fake Sync working tree',
                     'seeded Knowledge search projection'],
        'not_exercised': ['Obsidian Sync network', 'browser rendering', 'gateway TLS', 'production host permissions']}, indent=2)+'\n')


def notes_write_back():
    cid = connection({'A.md': b'# A\n', 'Index.md': b'See [[A]].\n'}, 'sync-fixture')
    property_blob = upload(cid, b'true', 'application/json')
    tree = '/mnt/nvme/ratatoskr/notes/trees/' + cid
    for name, data in [('A.md', b'# A\n'), ('Index.md', b'See [[A]].\n')]:
        subprocess.run(COMPOSE + ['exec', '-T', 'notes', 'sh', '-c', 'mkdir -p "$1"; cat > "$1/$2"', 'fixture', tree, name], input=data, check=True)
    sql(f"update notes.connections set channel='sync',device_id=null,logged_in_at=now(),write_mode='on' where connection_id='{cid}'")
    before = counts(cid)
    write(cid, {'rename': {'path': 'A.md', 'base_hash': digest(b'# A\n'), 'target_path': 'B.md'}})
    eventually(lambda: counts(cid) == [before[0]+1, before[1]+2], 'Sync rename and grouped link rewrite acknowledged')
    data = subprocess.check_output(COMPOSE + ['exec', '-T', 'notes', 'cat', tree+'/Index.md'])
    assert data == b'See [[B]].\n', data
    passed('notes_write_back_sync_rename_rewrites_links')
    before = counts(cid)
    property_op = write(cid, {'set_property': {'path': 'B.md', 'base_hash': digest(b'# A\n'),
                      'property_key': 'publish', 'property_change': {'set': property_blob}}})
    eventually(lambda: sql(f"select state from notes.writes where operation_id='{property_op}'") == 'succeeded', 'Sync property acknowledgement')
    data = subprocess.check_output(COMPOSE + ['exec', '-T', 'notes', 'cat', tree+'/B.md'])
    assert b'publish: true' in data and b'# A' in data, data
    assert counts(cid) == [before[0]+1, before[1]+1]
    assert sql(f"select revision from notes.files where connection_id='{cid}' and path='B.md'") == digest(data)
    passed('notes_write_back_sync_property_is_indexed_after_ack')
    # A refused device write creates neither a new revision nor a file.changed event.
    device_cid = connection({'A.md': b'# A\n'}, 'device-refusal-fixture')
    blob = upload(device_cid, b'# changed\n')
    before = counts(device_cid)
    op = write(device_cid, {'update': {'path': 'A.md', 'base_hash': digest(b'# A\n'), 'blob': blob}})
    queue_item(device_cid, op)
    call('/v1/notes/connections/'+device_cid+'/device-operations/'+op+'/result', 'POST',
         {'outcome': 'failed', 'code': 'notes.write.unsupported'}, token=DEVICE_TOKEN)
    assert counts(device_cid) == before, 'refused device write changed revisions/events'
    passed('notes_write_back_refused_device_has_no_revision_or_event')
    # One device result reports the rename and both link rewrites. A refused member is a conflict.
    for data in [b'[[A]]\n', b'See [[A]] too.\n', b'[[B]]\n']:
        upload(device_cid, data)
    call('/v1/notes/connections/'+device_cid+'/manifest', 'POST', {'entries': [
         {'path': path, 'sha256': digest(data), 'length_bytes': len(data)}
         for path, data in [('A.md', b'# A\n'), ('X.md', b'[[A]]\n'), ('Y.md', b'See [[A]] too.\n')]]}, token=DEVICE_TOKEN)
    before = counts(device_cid)
    rename = write(device_cid, {'rename': {'path': 'A.md', 'base_hash': digest(b'# A\n'), 'target_path': 'B.md'}})
    delivered = queue_item(device_cid, rename)
    assert {member['path'] for member in delivered['rewrites']} == {'X.md', 'Y.md'}, delivered
    ack(device_cid, rename, digest(b'# A\n'), [
        {'path': 'X.md', 'outcome': 'applied', 'sha256': digest(b'[[B]]\n')},
        {'path': 'Y.md', 'outcome': 'base_mismatch', 'local_sha256': digest(b'local edit\n')}])
    eventually(lambda: sql(f"select exists(select 1 from notes.outbox where event_type='platform.operation.reported.v1' and payload->'payload'->>'operation_id'='{rename}' and payload->'payload'->'error'->>'code'='notes.write.partially_applied')") == 't', 'grouped rename partial failure')
    current = json.loads(sql(f"select json_object_agg(path,revision) from notes.files where connection_id='{device_cid}' and state='present'"))
    assert 'A.md' not in current and current['B.md'] == digest(b'# A\n'), current
    assert current['X.md'] == digest(b'[[B]]\n') and current['Y.md'] == digest(b'See [[A]] too.\n'), current
    assert counts(device_cid) == [before[0]+1, before[1]+2]
    assert sql(f"select count(*) from notes.outbox where event_type='notes.conflict.raised.v1' and payload->'payload'->>'connection_id'='{device_cid}'") == '1'
    passed('notes_write_back_grouped_rename_partial_application_has_one_conflict')


if __name__ == '__main__':
    main()
