## Context

Round 3 of changeset XR-021 is the third pass over the same repositories, cut from a contract document (`CONTRACTS.md`, sections R3-01 to R3-20) that lives in a local planning directory. Behaviour that more than one repository observes belongs in the store the fleet reads, so this design says how the round 3 sections map onto specs, why the workspace checks have the shape they do, and what the native smoke harness is and is not.

## Goals / Non-Goals

**Goals:**

- Each requirement can be checked from outside one repository, and each scenario names the layer that proves it.
- An inbox prefix, a contracts revision, a database role or a shared secret key that drifts on one side fails the workspace harness.
- No integration profile starts an unauthenticated broker.
- The native smoke exists as a script that can be run, and says plainly which of its flows have not been.

**Non-Goals:**

- Behaviour internal to one repository (the pump's connection lifecycle, the completeness gap taxonomy, Knowledge's `Outcome` classes, the executor's acquisition counters) stays in that repository's change: R3-05 and R3-07 to R3-10 appear here only as the boundary behaviour another repository can see.
- R3-13 (Edge readiness and diagnostics), R3-16 as a harness check beyond `contracts_pin.rs`, R3-17 (ports) and R3-19 (stale documentation) are not new specs: the first is single-repository and the rest are decisions or documentation.
- No CI job runs the native smoke.

## Decisions

- **Inbox check scans for a constant, not for a literal inside the call.** CONTRACTS R3-01 asked for the prefix inside a `custom_inbox_prefix(` call. Every service holds the literal as one `const` beside its durable names, as R3-01 also requires, and passes the constant to the call. `bus_acl.rs` therefore accepts the literal itself as the argument, or a `const NAME: &str = "<prefix>"` whose name is the argument of a call in the same crate (the nearest tracked `Cargo.toml` above the file). The crate boundary matters because both extractor identities name their constant `INBOX_PREFIX`; without it a call in the browser worker would satisfy the extractor. Test files never count. The scan proves the literal and the call exist together, not that the call sits on the connection the service opens; each service's real-broker test proves that.
- **Twelve vendored copies.** `FRAGMENTS` grows from six to twelve: X, Instagram, Threads, ChatGPT, Claude and Telegram carry a byte-equal `deploy/nats/identity.conf`, because the per-service real-broker test needs the stanza to run under. The existing equality test covers them without change.
- **One contracts revision is read from the changeset.** `workspace.toml` does not name a contracts revision, so `contracts_pin.rs` reads `contracts_sha` from the XR-021 changeset. The contracts repository's own lock is excluded: it holds the packages, not a dependency on them.
- **The PostgreSQL check reads the examples.** `postgres_roles.rs` takes every active database URL of a `deploy/systemd/*.conf.example` and requires `127.0.0.1:5432/ratatoskr` and a role that a checked-in file creates by a `create role` statement outside a comment. It cannot run the SQL, so whether the files really work is the native smoke's F0, which is manual.
- **The shared secrets check cannot compare values.** The four pairs of R3-18 are required to exist on both sides under the spelled key. Every example holds `CHANGE-ME`, so a mismatch of values cannot be seen by a text scan and the test says so. At the round 3 pins it passed on its first run: the four pairs were already consistent, so it guards against a rename and did not fail first. The commit says so.
- **`web-operational` renders the ACL for the Edge identity only.** It runs one broker and one service that publishes, so it follows the pattern of the export-agent profile: `render_nats_conf` for `EDGE`, the broker started with `-c`, and Edge's seed mounted read-only. `no_unauthenticated_broker_test.sh` treats a NATS image that runs `sleep` (the holder of a shared network namespace in the Telegram profiles) as not a broker.
- **The Telegram runners build the webhook binary on the host.** The profiles build their images inside Compose, but the runner needs the assertion key before Compose starts. It builds `ratatoskr-telegram-webhook` from the Telegram checkout under test into a directory under the runtime directory, calls `assertion-key generate` and `assertion-key public`, compares the two public keys and deletes the build directory. The Docker profiles still could not be run here; their contract tests ran with a stubbed `docker`.
- **The native harness was ported, not first run.** Round 2 left the harness undone because the by-hand scripts were not run in their committed form. Round 3 builds it from those scripts, with the findings applied (production ports, `max_file_store` kept, no `CARGO_PROFILE_RELEASE_DEBUG=0`, no `pkill`, the checked-in provisioning SQL, `render-nats-config`). The scripts that produced the recorded results are the by-hand ones; the committed flows have not been run through `run.sh`. The harness commit says so, `integration/native/README.md` says so for each flow, and the changeset records the Round 3 smoke results as reported by the by-hand runs. Its contract test checks what can be checked without starting a service, and was shown able to fail by mutation.
- **The checks stay red between the first child merge and the pin advance.** They read the pinned submodules, and the pinned commits are the point of the test.

## Risks / Trade-offs

- [The native flows may not pass on their first run] -> They meet the services for the first time there; a failed assertion is a defect in the owning repository (reported with its file and line) or a mistake in the flow (fixed here). Nothing in the changeset reports them as passed.
- [Claude's privacy-delete output was not inspected] -> F6's Claude legs assert database and stream effects and exit codes, not stdout.
- [The shared report subject is still one subject] -> R3-02 closes the cross-lane risk; X can still read every tenant's operation-report metadata through its extractor-reports durable, and per-producer subjects stay a contract change.
- [An unmapped-user 403 and a mapped-user 502 differ for the export agent] -> The agent keeps the pairing on a 401 that is not Platform's own verdict and treats a 403 on the archive routes as permanent (export-agent, R3-03 rule 4).
- [The profiles that need Docker did not run] -> The Docker daemon is not available on the machine that wrote this change; their contract tests ran with a stubbed `docker` and the changeset says so for each profile.
