# Spec Delta

## Purpose

Defines the static bundle that a site repository publishes for a commit, how a consumer verifies it,
who may deploy it, and how the host stores, activates and rolls back a site's deploys.

## ADDED Requirements

### Requirement: A bundle carries a manifest that lists every file

A site bundle SHALL be a tar archive whose root holds `ratatoskr-bundle.json`, valid against `sites/bundle-manifest.v1`. The manifest SHALL name the site id, the repository, the full commit SHA, the entry document, whether the entry fallback is on, and every file with its path, size, SHA-256 and a flag that marks it as content-hashed. The archive SHALL hold no file that the manifest does not list.

#### Scenario: A bundle holds a file that the manifest omits

- **WHEN** `crates/deploys/tests/receipt.rs::an_unlisted_file_is_refused` uploads a bundle whose archive holds `extra.js` and whose manifest does not list it
- **THEN** the deploy is refused with the stable code `sites.bundle.unlisted_file` and nothing is stored

#### Scenario: A file differs from its manifest digest

- **WHEN** `crates/deploys/tests/receipt.rs::a_digest_mismatch_names_the_path` uploads a bundle in which one byte of a listed file changed after the manifest was written
- **THEN** the deploy is refused with `sites.bundle.digest_mismatch`, and the response names the path

### Requirement: Bundle paths are confined and static

Every path in a bundle SHALL be relative, normalised to NFC, and free of `..`, absolute prefixes, symbolic links, hard links and device entries. No path SHALL start with `_r/`, which the gateway reserves for forwarding. A path under `.ratatoskr/`, the reserved path for SDK pages, SHALL be accepted. The total size SHALL NOT exceed the configured bundle limit.

#### Scenario: A bundle tries to escape its directory

- **WHEN** `crates/deploys/tests/receipt.rs::an_unsafe_path_writes_nothing` uploads a bundle with an entry `../../etc/passwd` or a symbolic link
- **THEN** the deploy is refused with `sites.bundle.unsafe_path` before any byte is written to disk

#### Scenario: A bundle shadows the forwarding prefix

- **WHEN** `crates/sites-contracts/tests/bundle_manifest.rs::a_path_under_the_forwarding_prefix_is_refused` validates a manifest that lists `_r/v1/sites/x/content`
- **THEN** validation fails, and the receipt refuses such a bundle with `sites.bundle.reserved_path`

#### Scenario: A bundle ships the SDK pages

- **WHEN** `crates/deploys/tests/receipt.rs::the_reserved_sdk_path_is_accepted` uploads a bundle built from the SDK template that lists `.ratatoskr/sign-in/index.html`
- **THEN** the deploy is stored with that file

### Requirement: A site repository publishes an attested bundle per commit

A site repository that uses the reusable bundle workflow of `ratatoskr-site-sdk` SHALL publish, for a commit, one OCI artifact tagged `sha-<full commit SHA>` with media type `application/vnd.ratatoskr.site-bundle.v1`, and a build-provenance attestation that binds its digest to the repository, the workflow and the commit. A published tag SHALL NOT move to another digest.

#### Scenario: The workflow runs again for a commit

- **WHEN** `packages/site-sdk/test/bundle-workflow.test.ts` "keeps an existing tag" runs the publish step for a commit whose tag already exists
- **THEN** the existing tag and digest stay unchanged and the step reports that the artifact exists

#### Scenario: The manifest names another commit

- **WHEN** `packages/site-sdk/test/bundle-manifest.test.ts` "fails when the manifest commit differs from GITHUB_SHA" builds a manifest for a commit other than the one being built
- **THEN** the step fails and nothing is published

### Requirement: The deploy command verifies before it uploads

`ratatoskr-site deploy` SHALL pull the artifact, verify its attestation against the site repository, and check every file against the manifest, all on the machine where it runs, before it uploads any byte to Ratatoskr. It SHALL refuse a bundle whose manifest site id differs from the site named in the command.

#### Scenario: An artifact was changed after publication

- **WHEN** `packages/site-sdk/test/deploy.test.ts` "refuses an artifact without a valid attestation before any request" runs the command with a fake `gh` that rejects the digest
- **THEN** the command exits non-zero, names the failed check, and the stub Edge records no request

#### Scenario: A bundle is deployed to the wrong site

- **WHEN** `packages/site-sdk/test/deploy.test.ts` "refuses a bundle for another site" deploys to site `b` a bundle whose manifest names site `a`
- **THEN** the command refuses before upload, and `crates/deploys/tests/receipt.rs::a_site_mismatch_is_refused` shows that the sites service also refuses such an upload with `sites.bundle.site_mismatch`

### Requirement: A deploy reaches only an approved site through the deploy class

`POST /v1/sites/{site}/deploys` and `POST /v1/sites/{site}/deploys/{commit}/activate` SHALL be routes of the class `deploy` that `site-route-classes` defines. The sites service SHALL store or activate a deploy only for a site that its approval projection marks as approved, and SHALL answer 404 `sites.site_not_found` for any other site.

#### Scenario: A deploy to a site that is not approved

- **WHEN** `crates/deploys/tests/receipt.rs::a_deploy_to_an_unapproved_site_is_refused` uploads a valid bundle for a site whose approval was withdrawn
- **THEN** the response is 404 with `sites.site_not_found` and nothing is stored

### Requirement: A deployer device is paired by the owner for one site

A device of kind `site_deployer` SHALL be paired only through a pairing code that a primary session with the live `platform.owner` grant created with the expected kind `site_deployer` and one site id (Platform ADR-0016). The owner SHALL be able to list and revoke it like every other registered device.

#### Scenario: A pairing code without a site

- **WHEN** `crates/identity/tests/site_deployer_pairing.rs::a_site_deployer_code_requires_a_site` requests a pairing code with the expected kind `site_deployer` and no site id
- **THEN** the request is refused with a contract error and no code is created

#### Scenario: A revoked deployer device

- **WHEN** `crates/identity/tests/site_deployer_pairing.rs::a_revoked_site_deployer_cannot_refresh` revokes a `site_deployer` device and then presents its refresh token
- **THEN** the refresh is refused and no session is issued

### Requirement: A deploy is idempotent on site and commit

A deploy SHALL be idempotent on the pair of site id and commit. A second upload of a commit that is already stored SHALL return the existing deploy and store nothing.

#### Scenario: The same commit is deployed twice

- **WHEN** `crates/deploys/tests/receipt.rs::a_second_deploy_of_the_same_commit_returns_the_first` uploads commit `c` to a site where a verified deploy of `c` already exists
- **THEN** the response returns the existing deploy id and the site holds one directory for `c`

### Requirement: Activation switches the current deploy atomically

Activating a deploy SHALL make it the site's current deploy in one atomic step. A request that the gateway serves SHALL see either the complete previous deploy or the complete new deploy, never a mix. The previous deploy SHALL stay stored, so that activating it again needs no download.

#### Scenario: Requests run while a deploy is activated

- **WHEN** `crates/deploys/tests/activation.rs::activation_switches_current_and_previous_atomically` runs readers that resolve `current` in a loop while commit `b` is activated over commit `a`
- **THEN** each reader sees a complete directory of `a` or of `b`, and `previous` points to `a` afterwards

#### Scenario: The owner rolls back

- **WHEN** `crates/deploys/tests/activation.rs::activating_previous_needs_no_download` activates the deploy of commit `a` after commit `b` was current
- **THEN** `current` points to `a` and the sites service makes no outbound request

### Requirement: Old deploys are retained within a bound

The sites service SHALL keep the current deploy and at least the previous one for each site. It SHALL remove older deploys beyond the configured count, and it SHALL NOT remove the current deploy or the previous deploy.

#### Scenario: A sixth deploy arrives with a retention count of five

- **WHEN** `crates/deploys/tests/activation.rs::retention_keeps_current_and_previous` activates a sixth deploy on a site with five stored deploys and a retention count of five
- **THEN** the oldest deploy that is neither current nor previous is removed, and five remain
