## ADDED Requirements

### Requirement: A joining repository receives the shared fleet files byte for byte

`ws fleet init <target-dir>` SHALL copy, from the committed tree of the source repository, every path that `drift.yml` requires to be one blob across the fleet and that is not repository-specific: `.github/workflows/fleet.yml`, `.github/workflows/zizmor.yml`, `.github/workflows/openspec.yml`, `.github/workflows/dependabot-automerge.yml`, `.githooks/pre-commit`, `.gitattributes`, `.editorconfig`, `LICENSE`, and every path under the prefixes `openspec init` generates. Each copy SHALL have the source blob's exact bytes, a `100755` blob SHALL be written executable, and a symbolic link SHALL be written as a symbolic link with the same target. Uncommitted source content SHALL NOT be copied.

#### Scenario: Shared and generated files arrive identical

- **WHEN** `harness/crates/workspace-core/tests/fleet.rs::rust_target_receives_every_shared_generated_and_rust_file` runs the command against an empty Rust target
- **THEN** each shared and generated path in the target has the source blob's bytes, `.githooks/pre-commit` is executable, and a file outside the fleet set is not copied

#### Scenario: Only committed content is copied

- **WHEN** `fleet.rs::only_committed_content_is_copied` edits a fleet file and adds an untracked skill in the source after its commit
- **THEN** the target receives the committed bytes and not the untracked skill

#### Scenario: A file the source lacks is reported

- **WHEN** `fleet.rs::absent_source_files_are_reported` uses a source without `dependabot-automerge.yml`
- **THEN** the command succeeds and reports that path as absent from the source

### Requirement: Class-specific files follow the target's class

A target with a root `Cargo.toml` SHALL be the Rust class and SHALL additionally receive `.github/dependabot.yml`, `skills-lock.json`, `.github/workflows/advisories.yml`, and every vendored skill path under `.agents/skills/` and `.claude/skills/` other than the `openspec init` ones. Any other target SHALL be the non-Rust class and SHALL additionally receive `.github/dependabot.yml` only. A source is the Rust class when its committed tree has a `Cargo.toml` at any depth, the rule `drift.yml` applies. When the classes differ the command SHALL fail, SHALL tell the operator to pass `--from` a fleet repository of the target's class, and SHALL write nothing. `advisories.yml` SHALL be copied only from a source with a root `Cargo.toml`, because `drift.yml` requires one blob only across those; from any other Rust source it SHALL be reported as not copied.

#### Scenario: A Rust target receives the catalogue and its symlinks

- **WHEN** `fleet.rs::rust_target_receives_every_shared_generated_and_rust_file` runs against a target with a root `Cargo.toml`
- **THEN** `skills-lock.json`, `advisories.yml`, `dependabot.yml` and the vendored skills arrive, and `.claude/skills/rust-tdd` is a symbolic link to `../../.agents/skills/rust-tdd`

#### Scenario: A non-Rust target receives no Rust files

- **WHEN** `fleet.rs::non_rust_target_receives_dependabot_but_no_rust_files` runs from a non-Rust source into a target without `Cargo.toml`
- **THEN** `dependabot.yml` arrives and no Rust skill, `skills-lock.json` or `advisories.yml` does

#### Scenario: A source of the other class is refused

- **WHEN** `fleet.rs::class_mismatch_fails_and_writes_nothing` runs from a Rust source into a non-Rust target
- **THEN** the command fails with `fleet.class-mismatch`, the message names `--from`, and the target is unchanged

#### Scenario: The advisory workflow is withheld from a source whose Rust is nested

- **WHEN** `fleet.rs::advisories_are_withheld_from_a_source_with_nested_rust` runs from a source whose only `Cargo.toml` is below the root
- **THEN** every other Rust-class file arrives and `advisories.yml` is reported as not copied

### Requirement: An existing differing file is never replaced silently

Before writing, the command SHALL compare every planned path with the target. An identical file SHALL be left alone. When any path differs in bytes, executable bit or link target, the command SHALL fail with one `fleet.conflict` per path and write nothing, unless `--force` is given, in which case it SHALL replace those files. A directory where a file belongs SHALL be a conflict even with `--force`.

#### Scenario: A conflict stops the run and `--force` resolves it

- **WHEN** `fleet.rs::differing_file_is_a_conflict_unless_forced` runs against a target whose `LICENSE` differs
- **THEN** the run fails naming `LICENSE` and writes no other file, and a second run with `--force` replaces `LICENSE` with the source bytes

#### Scenario: A second run changes nothing

- **WHEN** `fleet.rs::second_run_changes_nothing` runs the command twice
- **THEN** the second run copies no file and reports every planned file unchanged

### Requirement: The operator learns which required files remain

After copying, the command SHALL list each file that `fleet.yml` requires, and a Rust repository additionally needs, that the target still lacks and that cannot be copied because its content is repository-specific: `.gitignore`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEVELOPMENT.md`, `SECURITY.md`, `openspec/config.yaml`, `docs/ARCHITECTURE.md`, `docs/REQUIREMENTS.md`, `docs/THREAT_MODEL.md`, `docs/TESTING.md`, `docs/adr/README.md`, and for the Rust class `clippy.toml` and `.github/workflows/ci.yml`.

#### Scenario: Missing hand-written files are listed

- **WHEN** `fleet.rs::hand_written_required_files_are_reported` runs against a Rust target that already has `SECURITY.md`
- **THEN** the report lists `README.md`, `clippy.toml` and `.github/workflows/ci.yml` and does not list `SECURITY.md`

#### Scenario: The command line reports the result

- **WHEN** `harness/crates/workspace-cli/tests/commands.rs::fleet_init_copies_and_reports_missing_files` runs `ws fleet init <target>` from a source workspace root
- **THEN** it exits 0 and prints the copied, absent and still-missing paths, and `fleet_init_conflict_exits_with_validation_status` exits 2 with `fleet.conflict` until `--force` is given
