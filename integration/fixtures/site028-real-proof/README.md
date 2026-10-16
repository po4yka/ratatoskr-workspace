# Real SDK bundle proof

This fixture is public signed evidence from
[SDK run 38951611259](https://github.com/po4yka/ratatoskr-site-sdk/actions/runs/38951611259).
It contains no vault data or credentials. `identity.json` records the immutable source commit,
OCI digest and trusted workflow revision. `manifest.json` is the exact OCI manifest; `proof.json`
is its Sigstore bundle, fetched by descriptor digest. Do not reformat either signed input.

`integration/tests/site_bundle_fixture_proof.sh` retrieves this evidence with an empty tool
configuration and no token. It verifies the signature against the reviewed local trust-root
snapshot and refuses a changed manifest. The Molecule `sites_verifier` case repeats this with the
pinned Linux ARM64 tools inside 512 MiB and verifies the local proof without network access.
A valid tool proof does not prove server storage, approval races or activation.
