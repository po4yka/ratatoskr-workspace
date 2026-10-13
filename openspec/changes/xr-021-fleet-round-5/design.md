## Context

Round 5 of changeset XR-021 is the fifth pass over the same repositories, cut from a contract document (`CONTRACTS.md`, sections R5-01 to R5-15) that lives in a local planning directory. Behaviour that more than one repository observes belongs in the store the fleet reads, so this design says how the Round 5 sections map onto specs, what the new workspace checks read and why, and what the native smoke evidence of this round is and is not.

## Goals / Non-Goals

**Goals:**

- Each requirement can be checked from outside one repository, and each scenario names the layer that proves it.
- A durable that Edge and a service name differently, a deletion producer without an acknowledgement durable, a non-Edge identity that can delete a stream message, an alert whose series does not exist, and a base URL with the wrong port each fail the workspace harness.
- The native harness runs: every flow F0 to F7 is run through `run.sh` as committed and the verdict is recorded as it is.
- The record says plainly which hops were faked, seeded or not exercised, and which Round 5 legs were not run against the Round 4 heads.

**Non-Goals:**

- Behaviour internal to one repository stays in that repository's change: the outbox columns, the ledger table layout, the reaper's batch internals and the provider adapters appear here only as the boundary behaviour another repository can see.
- R5-01 (ports: decision A for the fourth time, no S05 row changes) and R5-15 (decisions recorded without code) are not specs: they are decisions and the exclusions list, recorded in the changeset.
- No CI job runs the native smoke, and this change adds no Compose profile.

## Decisions

- **The deletion path is one capability.** Acknowledgement, re-send, the owner of a tombstone and the stream erasure are four rules of one mechanism, and a producer, Knowledge and Platform each implement a part. They are one capability, `fleet-deletion-delivery`, so a reader finds the whole chain in one place.
- **Requirements that did not exist are added, not modified.** The work order called the Telegram progress stream a modification of `content-capture-command` and the Instagram digest a modification of `social-capture-lifecycle`. Neither spec holds a requirement they restate (a MODIFIED delta replaces a block that must exist), so both are ADDED requirements in the existing capability. `channel-digest-chain` is the one real MODIFIED block: the run-report requirement carries a warning text that changes. It restates the Round 4 text, so `xr-021-fleet-round-3` must be archived before `xr-021-fleet-round-4`, and that before this change.
- **Two bus-topology requirements are modified though the work order did not list them.** The durable table and the "only Edge" requirement would otherwise say 18 durables and nothing about stream deletion, which the harness now checks. They are the minimal MODIFIED blocks.
- **The named filter constant is resolved, not waived.** Platform declares the five acknowledgement rows with `DELETION_ACKNOWLEDGED_SUBJECT`, so `bus_durables.rs` resolves a bare upper-case identifier through a `const NAME: &str` in the same text, instead of marking the rows as not scannable.
- **Invariant 7 allows one subject.** CONTRACTS says no stanza but EDGE has a publish allow starting with `$JS.API.STREAM.`. The EXTRACTOR_BROWSER_WORKER stanza holds `$JS.API.STREAM.INFO.KV_browser_worker_completions`, the read-only call a client makes to open its own KV bucket. The sanity run on the real file found it, so the check allows the stream info of a `KV_` bucket and nothing else under the prefix, and the spec says so.
- **The alert file is read by a line scan.** A YAML parser would be a new dependency of the harness, and `deny.toml` allows three licences and denies duplicate versions, so adding one means checking its whole tree against that policy first; the rule file is flat enough for a line scan. The scan fails loudly on a function it does not know, and flow F0 parses the file with a real YAML library.
- **The native smoke ran against the heads, which are the pins.** The flows were run with `RATATOSKR_SMOKE_REF=origin/main`, which exports the `origin/main` of each repository into the state directory with `git archive`. Those commits are the Round 5 pins this change lands, and the submodules stayed clean. The flows were not built from the pinned checkouts themselves.
- **RED evidence for the new legs was not collected.** The plan asked that each leg that tests a Round 5 fix be run first against the Round 4 head of its repository, to show that it fails for the stated reason. That was not done, so a leg here is not shown to fail without its fix. Task 6.2 stays open for it, and with it this change.
- **A fake is not a result.** OpenRouter, X, GitHub and the Telegram Bot API are loopback fakes; the Claude receiver is replaced by a 401 stand-in for one leg; principals and a few timers are set by SQL. The README and the changeset list each, and nothing a fake produced is reported as a live provider result.

## Risks / Trade-offs

- The text scans share one limit: they read files, not behaviour. Each module comment says what its scan cannot see and which test or flow covers it.
- The flows ran on one machine, once each. A pass shows the services and the harness agree on that machine; it is not a load, timing or Raspberry Pi result, and the 256 MiB upload timing is a laptop number.
- The Round 5 pins move fourteen gitlinks at once. The harness gate, `ws lock check` and the hosted checks of every child head were read before the pins were committed.

## Migration Plan

There is no data migration (development status). Pull the pins, recreate the extractor, Knowledge, ChatGPT, Claude, X, Instagram, Threads and channel-digests databases from the edited schema definitions, reload NATS (the ACL changed) and start Edge, which provisions the five new durables, then Knowledge, then the producers. Roll back by resetting the pins to the Round 4 heads recorded in the changeset and recreating the same databases from the reset schemas.
