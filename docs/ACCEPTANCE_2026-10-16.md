# Sites and Obsidian acceptance, 2026-10-16

## Decisions and scope

The owner accepted an explicit exception for OBS-024 tasks 14.1 and 14.2 and SITE-026 task 10.8.
The original test-before-implementation order was missed. Retrospective tests and mutation tests
show that the checks detect the fault, but cannot prove that original order. The task records keep
this violation. No Git history was changed to hide it.

The owner chose server-side GitHub provenance verification for site bundles, with one approved
repository per site. That choice is a target, not implemented acceptance: the current SDK verifies
provenance before it uploads a raw tar archive; the Sites server does not verify the provenance.
The follow-up must close that server trust boundary before the binding can be marked complete.

The owner requested only available local Obsidian checks. No Sync login, MFA or vault password,
production host operation, personal vault access or support message was performed.

## Observed checks

| Check | Result | Boundary |
| --- | --- | --- |
| OBS-024 14.1 retrospective assertions | Four intended failures on pre-write Platform/Notes; the same four pass after write-back | Reconstructed tests; original test-first order is not proved |
| OBS-024 14.2 first-write runtime probe | Ready old Notes leaves an accepted command pending; current Notes delivers it and applies exactly once after ACK | Real Edge, Notes, PostgreSQL and NATS; synthetic device; narrower than the full integration scenario |
| Current sites integration | Published workspace `059aff9`, all eight checks green, including the 11-scenario profile, privacy fixture and Molecule | Synthetic Sync tree/device, disposable host; no live Sync or production host |
| Obsidian link rewriting | All 14 fresh Obsidian 1.14.4 recordings match pinned Notes outputs byte for byte | Dedicated profile and synthetic vault |
| Real CLI adapter move | Production adapter moves into a missing nested folder, preserves bytes and reports the correct SHA-256 | Official signed installer/engine 1.14.4; synthetic Notes HTTP peer |
| CLI metadata survey | 180 initial calls and 176 bounded retries; 81 answered link/backlink comparisons match after excluding the CLI's explicit unresolved-link display | Twelve command results remain empty; full metadata CLI acceptance is not closed |
| Export-agent local gate | Six DEVELOPMENT commands, eight fleet steps, offline Zizmor, OpenSpec 1.10.0 (26 active items and nine archived changes), independent review pass | 307 tests: 306 pass, one existing opt-in Keychain test skipped; 16 existing SwiftLint warnings |

The full current workspace gate is [run 38919743597](https://github.com/po4yka/ratatoskr-workspace/actions/runs/38919743597).
The Sites and Platform commits are `3860ddca89a7a7851c623bd6186e390e0ce85f29` and
`becf91ebae27c9c1352336da679c7352426aabe0`. Their CI is separate from live acceptance.

## Retrospective procedure

An isolated detached workspace at `57547dc` received only the missing assertions from
`bus_acl.rs` and `bus_durables.rs`. With Platform `6df9717` and Notes `810edd8`, one ACL test
and three durable tests failed on the intended assertions. The same test files passed with
Platform `f76005e` and Notes `496e9c1`. No baseline source was edited.

The runtime probe built old Notes from exact source `810edd8` because its OCI artifact was absent.
With the current Edge and rendered deployed ACL, old Notes was ready and served read/blob requests;
Edge accepted the write. NATS showed `pending=1`, `delivered=0`; revision and event counts stayed
`[1,1]`. Current Notes `e16068a` delivered the device operation, and the ACK changed those counts
to `[2,2]`. Both disposable Compose projects and their volumes were removed after the checks.
The full current integration profile remains a separate, broader GREEN proof.

SITE-026 10.8 keeps its previous absent-tree failure after implementation, the independent wrong-host
and wrong-port mutation refusals, and the full converge, zero-change idempotence and verify result.
The owner exception closes the process gap; it does not change any of those observations.

## Real Obsidian defect and fix

The official signed Obsidian 1.14.4 app was copied to a temporary directory and run with a separate
user-data directory. The installed personal application and shell PATH were not changed. Signature
verification passed for Dynalist Inc., team `6JSW4SJWN9`.

A real CLI move to a missing folder returned exit zero with an `ENOENT` error and left the source
in place. The old adapter did not create the folder. A fake CLI that created it had hidden this
failure. A new regression test uses only `mv`, fails on the old adapter, then passes after the
adapter creates the validated destination parent before calling Obsidian. The file still moves
through Obsidian so its normal link updates run.

Export-agent `e4be3b4fd54d17f85e9952097f1ded38f031d801` contains this fix; all four CI checks passed ([run 38928393687](https://github.com/po4yka/ratatoskr-export-agent/actions/runs/38928393687)). A standalone harness
linked the production `NotesChannelClient`, `ObsidianCLIApply` and `ProcessObsidianCLIRunner` to
the real CLI. The queue/result HTTP peer alone used the existing test server. The nested move
returned `applied`, preserved file bytes and sent the correct hash. The new regression had an
observed RED before implementation; no exception applies to this fix.

## Local evidence

Untracked evidence is retained in the task workspace at `evidence/site-remaining-20261016/`:

- `historical-14.1-reconstruction.diff`, `historical-{acl,durables}-{red,green}.log`;
- `historical-write-{red,green}.{json,log}`, `retrospective-cleanup.json` and Compose logs;
- `obsidian-recheck.json`, the 14-case recording and `obsidian-recording.log`;
- `obsidian-cli-version.json`, `cli-missing-parent-observation.json`, `RealCliAcceptance.swift`;
- `obsidian-cli-metadata.json`, `obsidian-cli-metadata-retried.json`, `cli-metadata-comparison.json`.

Export-agent logs remain under `/tmp/ratatoskr-obsidian-move-{red,green}.log`,
`/tmp/ratatoskr-real-obsidian-cli-acceptance.log`, `/tmp/ratatoskr-export-acceptance-*` and
`/tmp/ratatoskr-export-move-parent-review.{txt,json}`. These local files are not CI artifacts.
No account secret was used in these fixtures.

## Open acceptance

- OBS-023 3.1/3.3 and OBS-024 6.7 need an isolated real Sync account, MFA, an empty encrypted vault
  and the stated duration/resource checks. The owner deferred this environment; local fixtures
  cannot close it. The frozen production host remains outside scope.
- OBS-023 3.5 still needs the physical iOS and protected credential-store checks.
- OBS-023 3.4 and ADR-0010 require the five written support answers in the existing terms spike.
  A public maintainer statement does not replace those answers. No support message was sent.
- GitHub binding needs the cross-repository contract and runtime verifier work. The approved policy
  alone does not make the current raw-tar endpoint enforce it.
- The existing opt-in Keychain test and twelve unanswered CLI metadata commands remain unverified.
- OBS-024 contracts tasks 3.13–3.16 still wait for a coordinated fleet contracts revision.
