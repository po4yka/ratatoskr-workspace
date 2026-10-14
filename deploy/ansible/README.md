# Single-host provisioning

This playbook takes the one Ratatoskr host from a clean Debian 12 arm64 install to a running
deployment. A second run changes nothing. It does what the deploy guides of `ratatoskr-platform`,
`ratatoskr-extractor` and `ratatoskr-telegram` describe, and it keeps their order. The order matters:
`01-database-and-roles.sql` runs first, then Edge starts and becomes ready (Edge applies
`schema.sql`), then `02-grants.sql` runs, and each other service's `role.sql` runs before that
service first starts. The decision is ADR-0009, and the behaviour is the openspec capabilities
`host-provisioning` and `release-artifacts`.

> **The host is frozen.** While `docs/DEPLOYMENT_TARGET.md` says so, the playbook refuses the real
> host before its first change. Only the Molecule stand-in below is exempt. The owner lifts the
> freeze by editing that document. No command-line flag lifts it.

## What it installs, and from where

- **Child files.** Every unit, `ratatoskr.target`, SQL file, config example, logrotate and tmpfiles
  file, and the NATS configuration is read from the submodule under `repos/`, at the commit that
  `workspace.lock` pins. Preflight refuses a submodule at another commit, or one with local edits
  under `deploy/`. Nothing is copied into this directory. The harness test `deploy_inventory.rs`
  fails if a child file is copied here.
- **Binaries.** Binaries come only from the artifact that each repository publishes for its pinned
  commit, `ghcr.io/po4yka/<repository>:sha-<commit>`. The controller pulls it with `oras` and checks
  its attestation with `gh attestation verify --signer-workflow
  po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml`. It also checks every
  binary against `SHA256SUMS` on every run. Nothing is compiled on the host. The host needs no
  network access to ghcr.io.
- **Configuration.** Each config example is rendered on the host. The values are the settings in
  `group_vars/all/services.json` and the database password, which is read from the host file it was
  generated into. The render refuses a file that still holds `CHANGE-ME` or `REPLACE_ME`.

## Secrets

| Secret | Where it comes from | Leaves the host? |
|---|---|---|
| PostgreSQL role passwords | generated on the host, `/etc/ratatoskr/secrets/postgres/<role>.password` | no; set through psql's standard input |
| nkey seeds (all fourteen identities) | `nk -gen user -pubout` on the host, `/etc/ratatoskr/<identity>.nkey` | no; only the public keys go into `ratatoskr.conf` |
| Telegram signing key | `ratatoskr-telegram-webhook assertion-key generate` on the host | no; only its public key goes into `edge.conf` |
| Telegram webhook secret, channel-digests service secret | generated on the host | no |
| Knowledge's secrets shared with GitHub (README endpoint) and channel-digests (manifest source, recap result reader) | generated on the host, readable by `ratatoskr-knowledge` | no |
| Telegram bot token, owner user id | the operator's vault file | copied once, with `no_log` |
| OpenRouter API key of Knowledge | the operator's vault file | copied once, with `no_log` |

The vault file is outside the repository, at `~/.config/ratatoskr/secrets.vault.yml` by default
(`ratatoskr_secrets_file`):

```yaml
# ansible-vault create ~/.config/ratatoskr/secrets.vault.yml
ratatoskr_operator_secrets:
  telegram_bot_token: "<token from @BotFather>"
  openrouter_api_key: "<OpenRouter API key for Knowledge>"
ratatoskr_telegram_owner_user_id: "<numeric Telegram user id>"
```

## Running it

The controller needs Python 3.11 or later, `ansible-core`, `oras` and `gh` (logged in) on `PATH`,
and the workspace checked out with `git submodule update --init`.

```bash
cd deploy/ansible
RATATOSKR_HOST=<host> ansible-playbook site.yml --ask-vault-pass
```

PostgreSQL is the `shared-postgres` container that already runs on the host. The playbook checks
that it is running, and it does not create it. The monitoring role edits three things in the stack
at `ratatoskr_monitoring_dir`: Platform's scrape job, Platform's bus alert rule file, and
`extra_hosts` on the `victoriametrics` service. It skips them when that stack is absent.

## Enrolling a service

A service is deployed once its repository ships `deploy/systemd/ratatoskr-<role>.service` that
joins `ratatoskr.target`, and once that repository publishes its artifact through the reusable
workflow. Then add one entry to `ratatoskr_services` in `group_vars/all/services.json`, and add its
user to `ratatoskr_users` in `group_vars/all/host.yml`. Its database role and its nkey are already
provisioned. `deploy_inventory.rs` fails while a pinned unit has no entry, and while an entry names a
unit, binary or example that the pinned repository lacks.

## Testing it

```bash
cd deploy/ansible
molecule test
```

The scenario builds a Debian 12 arm64 container with systemd as PID 1 and its own Docker daemon.
It starts `shared-postgres` (pgvector, because Knowledge's `role.sql` creates the extension) and a
loopback Bot API stand-in. Then it converges, runs the playbook again, which must change nothing,
and runs the verify cases in `molecule/default/verify.yml`:

- the host facts;
- units byte-identical to their pinned sources;
- the broker with one public key per identity and correct seed modes;
- every service ready;
- the monitoring lines;
- the provisioning order;
- a role file that fails;
- no restart on a rerun;
- the freeze guard;
- a pin that disagrees with the lock;
- a tampered artifact cache;
- no secret in a verbose run's output;
- `systemctl stop ratatoskr.target` stopping every service while PostgreSQL and NATS stay up.

The workspace CI job `molecule` runs the same scenario on a native arm64 runner. A run needs about
8 GB of free disk for the image, the inner Docker images and the artifacts.

## What it does not do

- It does not deploy the services that ship no unit yet (github, vault, channel-digests, chatgpt,
  claude, x, instagram, threads). It provisions their database roles and nkeys, so that enrolling
  them later is one entry. Knowledge is enrolled (OBS-023): its operator listener answers `/ready`,
  not `/health/ready`, so its entry sets `ready_path`, and the secrets it shares with GitHub and
  channel-digests are readable by its group only until those peers are enrolled.
- It does not install Platform's backup units (`deploy/backup/`). Their own README covers them.
- It does not serve the web client. Where that bundle is served is still an open decision in
  `DEPLOYMENT_TARGET.md`.
