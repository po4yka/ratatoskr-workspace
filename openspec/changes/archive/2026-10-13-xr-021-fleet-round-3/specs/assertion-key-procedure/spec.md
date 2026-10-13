## ADDED Requirements

### Requirement: The webhook creates the assertion key and derives its public half

`ratatoskr-telegram-webhook assertion-key generate <path>` SHALL create `<path>` exclusively with mode 0600 (an existing file is refused), write a new Ed25519 seed as 64 lowercase hexadecimal characters and one newline, and print the base64 (standard alphabet, padded) public key on one line. `assertion-key public <path>` SHALL read a seed file in the format the services read and print that same key and nothing else on stdout. Neither command SHALL print the seed on any stream. The known-answer vector is the RFC 8032 section 7.1 test 1: seed `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` has the public key `11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=`, which Platform's verifier and the V14 rule of its configuration accept.

#### Scenario: The RFC 8032 vector

- **WHEN** `assertion-key public` reads a file holding that seed
- **THEN** stdout is exactly that base64 string and a newline, verified by the webhook tests of `ratatoskr-telegram`, by the Edge deployment-profile test of `ratatoskr-platform`, and by flow F3 of the native smoke when it is run

### Requirement: The Edge example enables the assertion key and the procedure is documented

`platform/deploy/systemd/edge.conf.example` and its `.env.example` SHALL set `RATATOSKR__IDENTITY__ASSERTION_KEY=CHANGE-ME` as an active line with a comment that points at the webhook's command, so that following the shipped examples does not leave `telegram.mini_app` unavailable and `/v1/sessions/telegram` refusing with 401. `telegram/deploy/README.md` and `platform/deploy/README.md` SHALL give the procedure: generate on the host, install the seed at `/etc/ratatoskr/secrets/telegram-platform-signing-key` as `root:ratatoskr-telegram-secrets 0640`, and paste the printed public key into `/etc/ratatoskr/edge.conf`. The integration scripts `run-telegram-library.sh` and `run-telegram-notification.sh` SHALL call the command and SHALL NOT derive the key with `openssl genpkey` and `xxd`, which macOS's LibreSSL does not support reliably.

#### Scenario: A profile runner derives the key itself

- **WHEN** a Telegram runner contains `genpkey` or `xxd`
- **THEN** its contract test in `integration/tests/` fails
