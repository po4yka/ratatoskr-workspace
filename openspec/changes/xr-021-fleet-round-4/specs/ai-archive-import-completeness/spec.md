## ADDED Requirements

### Requirement: A Claude project knowledge file is ingested, verified and counted on the production import

The Claude importer SHALL run its knowledge-file ingestor for every project knowledge file of a parsed archive, in file order, before the completeness report is built, and SHALL pass the outcomes to the report. A file whose inline bytes match the declared media type and the declared sha256 is `Verified`: its bytes are stored under `sha256/<digest>`, its `project_sources` row carries `blob_ref`, `content_hash` and `byte_size` with `locally_backed_up = true`, the blob is registered under the digest-lock protocol so that an eraser that removed it between ingest and registration causes it to be stored again, and the importing export observes the source. A file whose digest does not match is `Quarantined`: the evidence blob is referenced and `locally_backed_up` is false. A file that only references content is `ReferencedOnly`: no blob and `locally_backed_up` false, and a later export that carries the bytes upgrades the source. A storage error from the ingestor SHALL be a retryable import error, never a permanent failure and never a silently missing file. A project is `locally_backed_up` exactly when it has at least one knowledge file and every one is `Verified`. A `Verified` file contributes no gap, a `Quarantined` or missing file still produces the `ai_archive.import.incomplete` warning and a `assets_partial` report, and the operation is `succeeded` only when completeness is `complete`.

#### Scenario: A Claude archive whose knowledge file has correct bytes and digest

- **WHEN** Claude imports an archive whose single project holds one knowledge file with correct inline bytes and a matching sha256
- **THEN** the operation is `succeeded` with no `ai_archive.import.incomplete` warning, the report is `complete`, and the blob under the Claude blob root has the declared digest, verified by the import tests of `ratatoskr-claude` through the real `process_pending_once` path and flow F1 of the native smoke when it is run

#### Scenario: A knowledge file with a wrong digest

- **WHEN** the declared sha256 does not match the inline bytes
- **THEN** the operation is `partially_succeeded` with `ai_archive.import.incomplete`, the source has a `blob_ref` and `locally_backed_up` is false

#### Scenario: A referenced-only knowledge file

- **WHEN** a knowledge file carries no bytes
- **THEN** the operation is `partially_succeeded`, the source has no blob, and a later export that carries the bytes sets `blob_ref` and `locally_backed_up`

### Requirement: A privacy deletion restores survivors to a version a retained export holds

Exports are cumulative and a project, conversation, message and content part exists once per account in both archive importers. When a privacy deletion removes an export, the row-removal transaction SHALL rebuild every surviving project and conversation whose current content digest no retained export presented, from the newest retained version (a project) or from the retained versions in export order (a conversation), before the survivor fact is announced, so that the rows, the content parts, the revisions and the snapshots hold only retained content. Each export SHALL record the digest of the version of every project and conversation it presented, and one snapshot per distinct version SHALL be kept while some export names it. A source or knowledge file that no retained export observed SHALL be removed in the same transaction and its blob queued for removal through the digest-lock protocol, and a source a retained export observed stays. The survivor fact SHALL name the earliest retained export that presented the current content and carry the rebuilt content, and a tenant-scope deletion SHALL leave no snapshot. A deleted export's text SHALL NOT reach Knowledge after the tombstone.

#### Scenario: The newest of three cumulative exports is deleted

- **WHEN** three cumulative exports are imported, the newest edits a project description, a conversation title, appends a message part and adds a knowledge file, and the newest is deleted
- **THEN** the project and the conversation read the retained text, the added knowledge file's blob is gone while a retained export's file is not, and the survivor fact carries the retained text, verified for both providers by the privacy-deletion tests of `ratatoskr-claude` and `ratatoskr-chatgpt` and flow F6 of the native smoke when it is run

#### Scenario: The middle and the oldest export are deleted

- **WHEN** the middle export and then the oldest are deleted
- **THEN** each survivor holds the newest retained version and no row, part, revision, snapshot or blob holds a byte of the deleted text

### Requirement: A ChatGPT tombstone goes to the owner the archive's facts named

The owner of the tombstones of a ChatGPT privacy deletion SHALL be the owner the archive's own announced facts name, read inside the row-removal transaction before the matching outbox rows are removed: the owner of the latest `ai_archive.archive.imported.v1` envelope of the deleted archive for an archive-scope deletion, of the archive that first announced the item for a conversation-scope deletion, and of any announced fact of the account for a tenant-scope deletion. The live account mapping SHALL be consulted only when the account announced no fact. When neither source names an owner the item SHALL be marked `downstream_tombstone_unbound`, and an account that never announced a fact has nothing to tombstone and SHALL NOT be reported as a gap.

#### Scenario: The mapping changed after the facts were announced

- **WHEN** an archive is imported under a mapping, the mapping is replaced with one that no longer contains the account, and the archive is deleted
- **THEN** the tombstone is queued with the original owner and Knowledge removes the derived data, verified by the privacy-deletion tests of `ratatoskr-chatgpt` and flow F6 of the native smoke when it is run

#### Scenario: An account that never announced anything

- **WHEN** an account without a fact is deleted
- **THEN** the deletion completes with no tombstone and no `downstream_tombstone_unbound` item
