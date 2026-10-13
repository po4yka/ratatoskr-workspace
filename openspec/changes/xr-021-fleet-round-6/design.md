## Context

Round 6 is cut from the contract sections R6-01 to R6-05 of a local planning file, as Round 5 was. Behaviour that more than one repository observes belongs in the store the fleet reads, so this design says which Round 6 rule becomes which requirement, what the workspace changed in its own harness, and what the native evidence of this round does and does not show.

## Goals / Non-Goals

**Goals:**

- Each requirement can be checked from outside one repository, and each scenario names the layer that proves it.
- A fleet map that says a port, method or wiring status is false where the port table and the pinned source say otherwise is a defect; it is corrected, not softened.
- Two F1 assertions pass only for the behaviour their names claim.
- The record says plainly which hops were faked, seeded or not exercised, and which new legs were not run against the previous heads.

**Non-Goals:**

- Behaviour internal to one repository (the pump's candidate selection, the disposition enum of the repository handler, the sweep batch) appears here only as the boundary behaviour another repository can see; each child records the rest in its own `xr-021-r6-*` change.
- R6-05 is a list of decisions and exclusions, recorded in the changeset, not a spec.
- No CI job runs the native smoke and this change adds no Compose profile.

## Decisions

- **Three ADDED blocks, no MODIFIED block.** Round 5 is not archived, so the capabilities `knowledge-ingest-limits` and `fleet-deletion-delivery` exist only as Round 5 deltas, and `channel-digest-chain`'s run-report requirement is a Round 5 MODIFIED block. Every Round 6 requirement has a new name, so the deltas validate and archive in either order.
- **The wait, not a re-queue.** The repository family now behaves like the documents, social and AI-archive families for the two failures an operator can fix: Knowledge redelivers at every delivery and never settles a failed fact. GitHub is unchanged, because a request is `pending` from dispatch until a terminal fact and nothing in GitHub ages it. A re-queue would have needed a second state machine and a second terminal path. A plain transient fault still closes the request after five deliveries; that stays open (the GitHub re-queue sweep).
- **A manifest is one hashed text.** Withdrawal of one post minimizes the whole manifest, because one post cannot be cut out of a text whose digest is stored and verified. The cost is that an earlier digest becomes unavailable for the rest of its life once any of its posts is deleted upstream; that is accepted and recorded.
- **The retention key is the run's window start.** A manifest never keeps a body longer than the revisions it was built from, because every source was published at or after the window start.
- **The row lock is per row and short.** The pump takes `for update skip locked` on one row at a time and holds it for the JetStream request timeout, set to 5 s, so it never waits on a lock and cannot take part in a deadlock; a deletion waits for the pump at most that long.
- **One residual remains.** A process crash between the broker's acknowledgement and the commit of its sequence, followed by a republish after the 120 s duplicate window, leaves one stream copy that no record names. It ages out at 7 days or 1 GiB. Closing it needs a contract addition (a message id on the erasure command) and an Edge lookup, which the owner did not approve.
- **The fleet map follows the table.** Where `docs/DEPLOYMENT_TARGET.md` and a child disagreed, the map was corrected to the table and the disagreement reported; the owner reconciled the table and the map in a separate commit while this round was running, and the two edits were merged.
- **The new native legs ran against the Round 6 heads, not through the pins.** The F4, F6 and F7 legs were run with `RATATOSKR_SMOKE_REF=origin/main` from clones that held the children's Round 6 heads, because the harness resolves a ref from the submodule object stores and the pins had not moved. Only the F7 wait leg was shown to fail on the Round 5 pin. The F4 manifest leg and the F6 in-flight leg were not run against the Round 5 heads, so they are not shown to fail without their fixes. The F6 leg asserts the end state and does not force the race; the deterministic proof is the repository tests of R6-03.
- **A fake is not a result.** OpenRouter is a loopback fake, archives are synthetic, principals and one recap row are seeded by SQL, and the manifest retention leg rewinds a run's window by SQL. The changeset lists each.

## Risks / Trade-offs

- The crash window above, a plain transient fault closing a request after five deliveries, a withdrawal minimizing a whole manifest, and Knowledge's stored manifest copy (a Knowledge-owned copy under the fleet-wide erasure transport, which is out of scope) are accepted and named in the changeset.
- The flows ran on one machine, once each. A pass shows the services and the harness agree on that machine; it is not a load, timing or Raspberry Pi result.

## Migration Plan

There is no data migration (development status). Pull the pins, recreate the channel-digests, ChatGPT and Claude databases from the edited schemas, start channel-digests, then Knowledge, then the two importers. Roll back by resetting the five pins to the Round 5 heads recorded in the changeset and recreating the same databases from the reset schemas.
