## 1. Dependency review

- [x] 1.1 Record upstream advisories, identity, license, Rust minimum, published-source review and candidate lock differences. Read-only review has no behavioral RED.
- [x] 1.2 Record owner approval for the major ZIP dependency update before production edits.

## 2. Repository gates

- [x] 2.1 RED ChatGPT: observe the existing zip 8.6.0 advisory gate failure and retain the log.
- [x] 2.2 GREEN ChatGPT: apply the reviewed targeted update, preserve archive safety, pass every local gate and independent review, publish and wait for CI.
- [x] 2.3 RED Claude: observe the existing zip 8.6.0 advisory gate failure and retain the log.
- [x] 2.4 GREEN Claude: apply the reviewed targeted update, preserve archive safety, pass every local gate and independent review, publish and wait for CI.
- [x] 2.5 RED Instagram: observe the existing zip 8.6.0 advisory gate failure and retain the log.
- [x] 2.6 GREEN Instagram: apply the reviewed targeted update, preserve archive safety, pass every local gate and independent review, publish and wait for CI.
- [x] 2.7 RED Threads: observe the existing zip 8.6.0 advisory gate failure and retain the log.
- [x] 2.8 GREEN Threads: apply the reviewed targeted update, preserve archive safety, pass every local gate and independent review, publish and wait for CI.

## 3. Filename API compatibility

- [x] 3.1 RED ChatGPT: add a malformed UTF-8 name regression against the existing reader before the dependency and name-accessor edits; retain the exact observed result.
- [x] 3.2 GREEN ChatGPT: map the fallible name accessor to a typed refusal and keep all valid-name behavior.
- [x] 3.3 RED Claude: add a malformed UTF-8 name regression against the existing reader before the dependency and name-accessor edits; retain the exact observed result.
- [x] 3.4 GREEN Claude: map the fallible name accessor to a typed refusal and keep all valid-name behavior.
- [x] 3.5 RED Instagram: add a malformed UTF-8 name regression against the existing reader before the dependency and name-accessor edits; retain the exact observed result.
- [x] 3.6 GREEN Instagram: map the fallible name accessor to a typed refusal and keep all valid-name behavior.
- [x] 3.7 RED Threads: add a malformed UTF-8 name regression against the existing reader before the dependency and name-accessor edits; retain the exact observed result.
- [x] 3.8 GREEN Threads: map the fallible name accessor to a typed refusal and keep all valid-name behavior.

If a reader already refuses that fixture, its regression starts green because no behavior fix is needed; record the reason and treat its accessor edit as a refactor after that green check.

- [x] 3.9 RED ChatGPT legacy decoding: add an unflagged filename with bytes that are valid UTF-8 and assert its previous CP437 name; observe the current ZIP 9 reader selects a different name.
- [x] 3.10 GREEN ChatGPT legacy decoding: use the approved decoder implementation, retain flagged UTF-8 refusal and valid Unicode extra fields, and pass focused tests, full gates, source review and exact-commit CI.
- [x] 3.11 RED Threads legacy decoding: add the same unflagged ambiguity case at the public inspector and observe its changed name before implementation.
- [x] 3.12 GREEN Threads legacy decoding: use the approved decoder implementation, retain all existing archive defenses, and pass focused tests, full gates, source review and exact-commit CI.

## 4. Standalone fuzz graph

- [x] 4.1 RED Instagram graph: run locked metadata for `fuzz/Cargo.toml` before editing its stale lock; observe exit 101 because the lock needs an update. This is a configuration compatibility check, not a behavioral test.
- [x] 4.2 GREEN Instagram graph: synchronize the approved contracts pin and vetted ZIP 9.0.0, complete the owner-approved D5 audit corrections through Instagram change `align-fuzz-security`, pass locked metadata and both full dependency policies, and add both fuzz commands to CI and DEVELOPMENT. The child change records the pre-fix full audit failure. Configuration and generated lock data have no separate behavioral RED.

## 5. Snapshot acceptance

- [x] 5.1 Join the four CI-green commits into OBS-029. Run its combined integration and provisioning checks, deterministic lock checks and full workspace gates. Pin and generated metadata have no separate RED.
- [x] 5.2 Publish the verified workspace and record successful CI, exact revisions and the security follow-up result.
