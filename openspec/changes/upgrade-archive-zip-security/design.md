## Context

The full ChatGPT test suite passed on its contracts pin change, then cargo-deny refused zip 8.6.0. All four affected locks hold that version. Upstream advisories describe privileged permission preservation, out-of-root symlinks and permission changes through symlinks in library bulk extraction. Ratatoskr source uses bounded entry reads and private staging instead of those library bulk helpers; the policy finding still blocks publication.

## Decisions

D1. Select zip 9.0.0, MIT, published 2026-10-09, from the existing zip-rs/zip2 project. Its declared Rust 1.88 minimum fits the pinned Rust 1.97 toolchain. The registry archive checksum was verified before source review. This is a major library update and may need source-level API adaptation.

D2. Keep default-features=false and features=[deflate]. Resolve every tracked lock, including standalone fuzz workspaces, with the targeted ZIP and approved contracts updates. Instagram CI and DEVELOPMENT must include `cargo metadata --manifest-path fuzz/Cargo.toml --locked --format-version 1` so the standalone graph cannot drift from its path dependency. Observe that command before fixing the graph; metadata does not compile a crate. Vet the published source, every new transitive name, build script and proc macro before compilation. Preserve unrelated versions and do not widen the license or source allowlist.

D3. Treat the observed policy failure as RED, then make that same gate GREEN with the fixed dependency. Manifests and locks have no separate behavioral RED. Existing archive safety tests must remain unchanged and pass. The new filename accessor returns Result<Cow<str>>, but the published source decodes invalid UTF-8 as CP437 even when the UTF-8 flag is set. A fallible accessor alone therefore does not enforce the required refusal. ChatGPT and Threads must validate raw UTF-8 bytes when flag bit 11 is set, then map the accessor error to the existing typed refusal; legacy unflagged filenames keep their previous decode behavior. Claude and Instagram already validate raw bytes. Add a fail-closed malformed-UTF8 name regression before adapting each reader; never replace its decode error with a lossy name. A characterization that is already green is recorded as such, not as an invented RED. An API compatibility refactor adds no behavior; any discovered behavior defect needs its own failing test before a fix.

D4. Publish only after the full repository gates and independent review. Wait for all four exact-commit CI results, then join the OBS-029 integration and pin promotion. Rollback must not restore the vulnerable dependency as a normal release; stop snapshot promotion if the fixed version cannot pass.

## Non-goals

No advisory suppression, new extraction helper, production deployment, credentials, product API major, database schema change or unrelated dependency upgrade.

## Approval

The owner approved zip 9.0.0 on 2026-10-17. Published-source review and candidate lock inspection passed before compilation. Implementation uses the existing four assigned worktrees.

## D5. Standalone fuzz audit decision (owner approved 2026-10-17)

Locked Instagram fuzz metadata now passes after the approved ZIP and contracts synchronization. A broader full fuzz cargo-deny audit found existing debt outside the production graph: rustls 0.23.45 resolves RUSTSEC-2026-0346 through RUSTSEC-2026-0349, while the production lock already holds fixed 0.23.46. The existing libfuzzer-sys 0.4.13 declares `(MIT OR Apache-2.0) AND NCSA`; NCSA is absent from the policy allowlist. The unpublished local fuzz package also has no license metadata, although the repository LICENSE is BSD-3-Clause. These are observed development-graph findings, not a confirmed production exploit.

The owner approved this bounded extension on 2026-10-17:

1. Align only fuzz rustls with production 0.23.46, with its existing reviewed checksum and dependency set. Production dependencies stay unchanged.
2. Declare BSD-3-Clause for the local fuzz package, matching the existing repository LICENSE. This does not change that license.
3. Add a package-specific license exception for libfuzzer-sys exactly 0.4.13 that permits MIT, Apache-2.0 and NCSA. Keep the global allowlist and every advisory gate unchanged. Re-review the exception when that package changes.
4. Add the full locked fuzz policy command to CI and DEVELOPMENT, after a child OpenSpec plan and the recorded failing audit. Validate both graphs, full local gates, source review and exact-commit CI before snapshot promotion.

Affected extra implementation files: fuzz/Cargo.lock, fuzz/Cargo.toml, deny.toml, .github/workflows/ci.yml and DEVELOPMENT.md. This is development-tool policy work beyond the owner-approved ZIP production update; the owner authorized the license-policy and TLS lock edits before implementation.

License review: the existing package manifest and README identify NCSA for bundled libfuzzer code. The canonical [SPDX NCSA text](https://spdx.org/licenses/NCSA.html) permits reuse with retained notices and disclaimers and restricts endorsement by contributor names. The proposed exception is limited to that exact tool package, rather than adding NCSA to the global allowlist.

Alternative: finish only the approved ZIP/contracts wave and locked fuzz compatibility guard. Record the failed broader fuzz audit as an explicit owner-accepted follow-up, keep the existing production gates strict, and do not call the full fuzz policy green. The current task must record that acceptance before it is closed.

## D6. Legacy filename compatibility (approved)

Published ZIP 8.6.0 decodes unflagged filename bytes as CP437. ZIP 9.0.0 instead tries UTF-8 first. Thus unflagged bytes C3 A9 name `├⌐` in the old reader and `é` in the new reader. ChatGPT and Threads use the library name decoder and inherit this difference. Claude and Instagram validate and use their own UTF-8 names, so their existing policy is separate.

The existing D3 promise to keep unflagged legacy decoding is still binding. Add public-inspector tests before a fix, keep the UTF-8-flag refusal, and honor validated Unicode Path extra fields (ZIP 9 marks those as UTF-8 after CRC validation). Do not promote workspace pins while the compatibility test is red. Read-only source inspection found no filename-encoding option in ZIP 9.0.0.

Use the owner-approved CP437 decoder only in the unflagged branch in ChatGPT and Threads. Published-source review, candidate graph inspection and owner approval preceded production edits. The existing advisory fixes stay in place; no rollback to ZIP 8.6.0 is allowed as a release. Run the same focused regressions, full local gates, source review and exact-commit CI after the fix.

### D6 approved dependency and review

The reviewed candidate is `oem_cp = { version = "2.1.2", default-features = false }` in ChatGPT and Threads only. Use the total `Cp437` byte-to-character conversion for unflagged names; retain strict UTF-8 and the existing typed errors for flagged names. Do not use replacement-character decoders. The crate is MIT, first published in 2020; this release is from 2025-12-24. Published source has no build script or procedural macro and no unexplained process, network or environment access. Disabling default features excludes its allocation/string module; its Windows unsafe calls are test-only. The decoder uses a complete fixed table and has no native platform dependency. It declares no MSRV, so Rust 1.97 host and applicable Linux/ARM64 checks remain acceptance requirements rather than an assumed result.

The inspection-only graph adds four names: oem_cp 2.1.2 (MIT), phf 0.11.3 (MIT, Rust 1.61), phf_shared 0.11.3 (MIT, Rust 1.61), and siphasher 1.0.4 (MIT OR Apache-2.0). Their registry checksums and published manifests were checked. No selected package has a build script or enabled procedural macro. Source triage found no unexplained I/O. Siphasher's unsafe blocks are bounded integer loads for its hash routines, not a new archive decoder unsafe block. Its hash APIs are not needed by the proposed byte-to-character call. The complete candidate passed cargo-deny 0.20.2 under the existing ChatGPT policy, without a license or advisory relaxation. No candidate package was compiled, and no production manifest was changed. Evidence: `/tmp/ratatoskr-sec030-cp437-review/`.

This introduces a production dependency and three transitive crates. The owner approved this exact scope before implementation. The alternative is a repository-local CP437 table and decoder, with source/license notices and exhaustive byte mapping checks; that avoids new crates but gives both repositories their own decoder maintenance. Both options must preserve the same name semantics and pass the same tests. Both public-inspector regressions ran before implementation and failed by the intended name assertion. Full acceptance remains open until the corrective tests, gates and exact-commit CI pass. Workspace pin preparation was stopped before it changed pins.

The owner approved `oem_cp` 2.1.2 with default features disabled for these two consumers. The approval includes the four reviewed packages above. Keep all other locked packages unchanged. Observe Rust 1.97, native ARM64, full policy, tests and exact-commit CI before pin promotion.
