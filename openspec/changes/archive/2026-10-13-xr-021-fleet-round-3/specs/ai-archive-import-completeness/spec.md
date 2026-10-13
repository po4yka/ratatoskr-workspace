## ADDED Requirements

### Requirement: A gap names something the export held and the importer could not store

An AI-archive import SHALL record a gap only for something the export contains or references that the importer could not store or model: `unrecognized_record` (a record the parser does not model) and `missing_file` (a declared file with no verified bytes). The absence of an optional section is not a gap, so ChatGPT SHALL NOT produce `projects_not_observed`, `canvas_not_observed` or `assets_not_observed`; the `AiGapKind` values stay in the contract unused. The registered ChatGPT parser path SHALL verify the declarations of `assets.json` against the extracted artifacts and the blob store: a verified asset is stored, a declared asset with no verified bytes is a `missing_file` gap, and a malformed `assets.json` is a permanent `chatgpt.archive.invalid`. An export with conversations only SHALL be `complete` and its operation `succeeded`; an export with an unrecognized record or a missing file SHALL be `partially_succeeded` with `ai_archive.import.incomplete`.

#### Scenario: A conversations-only export

- **WHEN** ChatGPT imports an export that holds conversations and nothing else
- **THEN** its completeness is `complete` and the operation is `succeeded`, verified by the import tests of `ratatoskr-chatgpt` and flow F1 of the native smoke when it is run

#### Scenario: A declared file is missing

- **WHEN** an export's `assets.json` declares a file the archive does not contain
- **THEN** the import records a `missing_file` gap and the operation is `partially_succeeded` with `ai_archive.import.incomplete`

#### Scenario: A malformed asset declaration

- **WHEN** `assets.json` cannot be parsed
- **THEN** the import fails permanently with `chatgpt.archive.invalid`

### Requirement: Deleting an export keeps the records a retained export still holds

ChatGPT exports are cumulative, and a conversation or project is announced under the first export that saw it. When a privacy deletion removes an archive, the row-removal transaction SHALL rebuild every project, conversation and artifact whose action is `retain_evidenced` and whose latest announced fact names a deleted archive, SHALL enqueue an `updated` fact whose provenance names the earliest retained observing export (by `received_at`, then export identifier), stamped a millisecond after the archive tombstone so the pump publishes it afterwards, and SHALL commit that repair together with the tombstone. A survivor whose latest fact already names a retained archive is untouched, and the deleted exports' `ai_archive.archive.imported.v1` heads leave the outbox with their rows. Claude behaves the same way, and Knowledge applies the tombstone as the whole import.

#### Scenario: The oldest of three cumulative exports is deleted

- **WHEN** the oldest export of a ChatGPT account is deleted while two later exports still hold its conversations
- **THEN** Knowledge deletes the import of that archive, then receives the re-announced facts, and a word from a conversation the retained exports hold still finds it, verified by the privacy-deletion tests of `ratatoskr-chatgpt` and flow F6 of the native smoke when it is run
