## Purpose

Complete the deferred OBS-024 write contract rules so every producer, consumer and Obsidian adapter uses the same file names and can read a group conflict without losing its stale paths.

## ADDED Requirements

### Requirement: Write names are portable across the supported vault adapters

Every write path and target path SHALL refuse a colon and any segment that ends in a dot or an ASCII space. Existing relative-path, control-character and first-segment `.obsidian` rules SHALL remain in force. The Rust parser and the generated JSON Schema SHALL enforce these restrictions.

#### Scenario: A file name or directory has an unsafe suffix

- **WHEN** a write names `Notes./x.md`, `.obsidian./app.json`, `Notes /x.md`, or a target with the same suffix
- **THEN** both contract validators refuse it, as checked by `write_request::segment_that_ends_in_a_dot_or_a_space_is_refused`

#### Scenario: A path or rename target contains a colon

- **WHEN** a write names `A:B.md` or target `Notes/B:C.md`
- **THEN** both validators refuse it, as checked by `write_request::colon_is_refused`

#### Scenario: A normal hidden folder or internal space remains writable

- **WHEN** a write names `.obsidian-archive/Plan.md`, `Notes 2026/Plan.md`, or `Notes.v1/Plan.md`
- **THEN** both validators accept it, as checked by the path boundary tests

### Requirement: A conflict event can identify every stale file of a write group

`notes.conflict.raised.v1` SHALL accept optional `stale_paths`, a list of vault-relative paths. The field SHALL use the existing vault path vocabulary. Its authority is Notes, from the stale members of the write group. The list carries private path metadata and SHALL remain in the owner-scoped event. An absent list SHALL keep the previous event form, and serialization SHALL omit an absent list. A group producer SHALL include all stale paths and keep `path` equal to the first stale path. The conflict read API SHALL retain the same list.

#### Scenario: A group event round trips through the contract

- **WHEN** the valid `group-with-stale-paths.json` fixture names two stale files
- **THEN** serde and JSON Schema accept it and the paths survive serialization, checked by `conflict::raised_may_name_every_stale_path`

#### Scenario: An old producer omits the optional list

- **WHEN** Platform reads the existing event form without `stale_paths`
- **THEN** it applies the conflict and keeps its operation result reference, checked by the existing Platform conflict consumer tests

#### Scenario: A new producer names the group list

- **WHEN** a rename and its rewrite both report a stale base
- **THEN** Notes emits both stale paths, the read API returns the same list, and Platform applies the event, checked by Notes `link_rewrite_atomic` and Platform `notes_conflicts` tests

### Requirement: Consumers are released before group list emission

Every strict event consumer SHALL accept the optional list before Notes starts to emit it. The workspace SHALL pin one contracts revision across all Rust consumers only after their gates and CI succeed and the combined snapshot passes integration checks.

#### Scenario: The verified snapshot is reproduced

- **WHEN** workspace validation reads the committed child pointers and lock
- **THEN** the contracts pin guard, committed snapshot tests, lock check and integration profile pass for those exact commits
