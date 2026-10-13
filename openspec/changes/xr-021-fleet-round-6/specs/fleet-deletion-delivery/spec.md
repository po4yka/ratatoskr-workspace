## ADDED Requirements

### Requirement: Every published copy of a fact row is recorded

ChatGPT and Claude SHALL record in `outbox_events.published_stream_seqs` the stream sequence of every broker acknowledgement they received for a row, ascending and without duplicates; a duplicate acknowledgement SHALL add nothing. A privacy deletion SHALL read the sequences of the rows it removes in the statement that removes them and SHALL enqueue, in the same transaction, one erasure command per distinct owner with at most 500 ascending sequences each. A mark of a published row that affects other than exactly one row SHALL be a counted error (`chatgpt_outbox_mark_lost_total`, `claude_outbox_mark_lost_total`), never ignored.

#### Scenario: A row is republished after the duplicate window

- **WHEN** a commit fails after the broker acknowledged a row and the row is republished after the stream's duplicate window
- **THEN** `published_stream_seqs` holds both sequences and a deletion of the subject enqueues one command naming both, verified by the outbox tests of `ratatoskr-chatgpt` and `ratatoskr-claude` with PostgreSQL and a real JetStream

### Requirement: A fact row in flight is serialized with its deletion

The first publication of an outbox row SHALL be one short transaction per row that locks the row with `for update skip locked` while it is unpublished and deliverable, publishes it, awaits the acknowledgement, records the sequences and commits. A row that is deleted or held by a deletion SHALL be skipped and nothing SHALL be published for it. The lock SHALL be held for at most the JetStream request timeout, which the pump sets to 5 seconds, the pump SHALL never wait on a lock, and a deletion that meets the lock SHALL wait for the pump and then see its committed sequences. The resend path of an already published tombstone SHALL be unchanged and take no lock.

#### Scenario: A deletion commits after the candidates were selected

- **WHEN** the pump has selected a fact row and a deletion of its conversation commits before the pump locks it
- **THEN** nothing is published and the stream holds no message of the deleted fact

#### Scenario: A deletion starts between the acknowledgement and the commit

- **WHEN** a deletion starts while the pump holds the acknowledged row
- **THEN** the deletion waits for the pump, enqueues an erasure command naming the sequence, and the stream message is gone once Edge processes the command, verified by the in-flight tests of `ratatoskr-chatgpt` and `ratatoskr-claude` with a seam that pauses the pump and by flow F6 of the native smoke, which does not force the race and asserts the end state only

### Requirement: An acknowledgement whose commit failed is carried

The pump SHALL keep, in memory, the owner and sequences of every acknowledgement whose transaction did not commit, and SHALL merge them into the row's `published_stream_seqs` at the next first publication of that row. At the start of each pass it SHALL check every carried entry against the table; an entry whose row no longer exists names a copy no deletion knew about, so the pump SHALL enqueue the erasure command for those sequences in the owner's name and drop the entry. One residual SHALL remain and SHALL be documented: a process crash between the broker's acknowledgement and the commit, followed by a republish after the stream's 120 second duplicate window, leaves one stream copy that no record names, and it ages out at the stream's 7 days or 1 GiB.

#### Scenario: A row is deleted before its retry

- **WHEN** a carried entry's row was deleted before the pump retried it
- **THEN** the pump enqueues the erasure command itself, verified by the outbox tests of the two importers
