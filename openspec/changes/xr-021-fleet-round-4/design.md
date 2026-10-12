## Context

Round 4 of changeset XR-021 is the fourth pass over the same repositories, cut from a contract document (`CONTRACTS.md`, sections R4-01 to R4-13) that lives in a local planning directory. Behaviour that more than one repository observes belongs in the store the fleet reads, so this design says how the round 4 sections map onto specs, why the two new workspace checks have the shape they do, and what the native smoke evidence of this round is and is not.

## Goals / Non-Goals

**Goals:**

- Each requirement can be checked from outside one repository, and each scenario names the layer that proves it.
- A migration-style `ALTER TABLE ... ADD COLUMN` in a `schema.sql`, or a service that states an ack wait other than the one Edge provisions, fails the workspace harness.
- The native harness stops failing assertions that were wrong, and stops passing assertions that were weak.
- The record says plainly which native flows have been run through `run.sh` as committed (none) and which smoke evidence is by hand.

**Non-Goals:**

- Behaviour internal to one repository stays in that repository's change: Claude's snapshot table layout, Knowledge's `Outcome` classes, the channel-digests checkpoint states and Telegram's persistence appear here only as the boundary behaviour another repository can see.
- R4-01 (ports: decision A for the third time, no S05 row changes), R4-09 (GitHub operator commands honour the configured provider origin), R4-11 (Platform documents that nothing raises a notification) and R4-13 (decisions recorded without code) are not new specs: they are decisions, a single-repository fix or documentation.
- No CI job runs the native smoke, and this change adds no Compose profile.

## Decisions

- **The new requirements go where the behaviour lives.** The two ChatGPT and Claude deletion rules and the Claude knowledge-file rule extend `ai-archive-import-completeness` because that spec already owns what an import records and what a deletion keeps. The Knowledge redelivery rule is a new capability, `fleet-ingest-redelivery`, because no existing spec owns how a consumer settles a failed delivery of an ingest family.
- **MODIFIED requirements restate the round 3 text.** `channel-digest-chain` and `social-capture-lifecycle` change a requirement that round 3 also modified. A MODIFIED requirement replaces the whole block, so round 4 carries the round 3 wording with its own sentences added. The consequence is an order: `xr-021-fleet-round-3` must be archived before this change, or its later archive would replace round 4's text. Round 3 has an open task (its flows were never run through `run.sh`), so both changes stay open until that is true; the tasks say so.
- **The schema scan flags every column addition.** `schema_in_place.rs` reports an `ALTER TABLE` whose clause is `ADD` followed by anything other than a constraint keyword, wherever it stands, and never an `ADD CONSTRAINT`. CONTRACTS R4-10 said "not inside a `DO` block that adds a constraint"; the simpler rule gives the same answer on every schema at the round 4 pins (X, Instagram and Vault close foreign key cycles with constraints only) and does not need to parse dollar quoting. Its module comment records the sanity run: seven findings in ChatGPT at the round 3 pin, none in X, Instagram and Vault.
- **The ack wait scan reads the row, not the constant.** `bus_durables.rs` finds the ack wait of each durable in the text of Edge's row (a `.with_ack_wait_seconds(N)` call, else the standard 30) and compares it with the constant each service states and with the value CONTRACTS S04 fixes. The Telegram notification durable is declared through two named constants, so its row is found through the `TELEGRAM_NOTIFICATION_CONSUMERS` array. The check fails before Telegram states `NOTIFICATION_ACK_WAIT_SECONDS`, and a mutation test changes one literal in a copy of each side.
- **Contracts do not move.** The contracts repository gained one commit after the round 3 pin, `460057a`, which updates a CI action and changes no contract file. Its pin stays at `5426cf3`; the round 4 smokes ran against `460057a`, which differs in that workflow line only.
- **The native smoke evidence of round 4 is by hand and is labelled so.** The round 4 smokes were run from scripts outside this repository, as in round 3. Nothing was run through `integration/native/run.sh`, so no flow row of the README says otherwise. The harness fixes are checked by `native_smoke_contract_test.sh`, which starts no service; each fix was shown failing before its fix. The legs that the flow files gained (F0, F3, F5, F7) have never met a service, and the legs that the plan lists for F1, F2, F4, F5 and F6 are not written. The README and the changeset list both groups.
- **A fake is not a result.** The repository-analysis family of `fake_openrouter.py` produces a schema-valid analysis grounded in the README the prompt carries so that the GitHub loop can close with a completed fact; nothing it returns is reported as a provider result, and the failed closure is a separate leg that switches the fake to 401.

## Risks / Trade-offs

- The legs of F0, F3, F5 and F7 are untested scripts. Their assertions, such as the table names they query, follow the schemas at the pins and the by-hand smokes; the first run may show a mistake in the flow. That is a harness finding, not a service defect, and the README says so.
- The by-hand smokes reached services the committed harness would also reach, but with their own configuration. A pass there says the services work; it does not say the committed flow files do.
- Round 4 moves nine pins at once. The harness gate, `ws lock check` and the hosted checks of every child head were read before the pins were committed.

## Migration Plan

There is no data migration (development status). Pull the pins, recreate the Claude, ChatGPT and Knowledge databases from the edited schema definitions, reload NATS before Edge, start Edge, then the services. Roll back by resetting the pins to the round 3 heads recorded in the changeset and recreating the same databases from the reset schemas.
