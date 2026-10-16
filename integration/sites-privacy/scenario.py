"""Publish the source privacy vault through real Notes, Sites and Edge APIs."""
import json
from pathlib import Path
import re
import urllib.parse


def run(call, connection, eventually, digest, owner_token, sites_context):
    root = Path(sites_context, 'fixtures/privacy-vault/vault')
    files = {path.relative_to(root).as_posix(): path.read_bytes()
             for path in sorted(root.rglob('*')) if path.is_file()}
    assert files and 'home.md' in files and 'img/plan.png' in files
    # Read the committed canaries from their source bytes, including the excluded image.
    canaries = sorted(set(re.findall(rb'zq7[a-z0-9]+', b'\n'.join(files.values()))))
    assert len(canaries) >= 21, 'the privacy fixture lost its negative controls'
    cid = connection(files, 'privacy-fixture')
    site = '/v1/sites/privacy-fixture'
    manifest = (b'site_id = "privacy-fixture"\nhostname = "privacy.example.test"\n'
                b'publications = ["privacy"]\n'
                b'capabilities = ["pages.read", "assets.read", "search.publication"]\n')
    call(site + '/manifest', 'PUT', manifest, token=owner_token, expected=(200, 201))
    call(site + '/publications/privacy', 'PUT', {
        'connection_id': cid, 'mode': 'all', 'release_mode': 'manual',
        'included_folders': [], 'excluded_folders': ['private'],
        'included_tags': [], 'frontmatter_allow': []}, token=owner_token, expected=(200, 201))
    call(site + '/manifest/approval', 'POST', {'manifest_sha256': digest(manifest)},
         token=owner_token, expected=(200, 201, 202))
    call(site + '/releases', 'POST', token=owner_token, expected=(202,))
    release = eventually(lambda: call(site + '/content/release'), 'privacy first release')

    def private_bytes_absent(data):
        assert b'zq7' not in data.lower(), 'private canary in an anonymous response'
        assert b'owner-marker@example.test' not in data, 'unapproved frontmatter in a release'

    private_bytes_absent(json.dumps(release).encode())
    assert release['pages'] and release['assets'], 'both page and asset controls must be present'
    for page in release['pages']:
        body, _ = call(site + '/content/pages/' + urllib.parse.quote(page['slug'], safe=''), raw=True)
        private_bytes_absent(body)
        assert digest(body) == page['page_sha256'], 'the served page is not the release page'
    for asset in release['assets']:
        body, _ = call(site + '/content/assets/' + asset['sha256'], raw=True)
        private_bytes_absent(body)
        assert digest(body) == asset['sha256'] and len(body) == asset['size_bytes']
    positive = call(site + '/content/search?q=target')
    assert [item['slug'] for item in positive['results']] == ['other'], positive
    private_bytes_absent(json.dumps(positive).encode())
    for canary in canaries:
        answer = call(site + '/content/search?q=' + canary.decode())
        private_bytes_absent(json.dumps(answer).encode())
        assert answer == {'results': [], 'has_more': False}, canary.decode()
    return {'pages': len(release['pages']), 'assets': len(release['assets']),
            'negative_searches': len(canaries)}
