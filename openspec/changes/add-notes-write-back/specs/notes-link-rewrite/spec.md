# Spec Delta

## Purpose

Defines which links in a connected Obsidian vault a rename or a move through Ratatoskr rewrites, how
the result must match what Obsidian itself does, and the golden fixtures from the real Obsidian app
that decide what "match" means.

## ADDED Requirements

### Requirement: A rename rewrites every link that resolved to the old path

When notes delivers a `rename` or a `move`, it SHALL rewrite, in the same write group, every wikilink
(`[[name]]`, `[[name|alias]]`, `[[name#heading]]`, `[[name#^block]]`), embed (`![[name]]`) and
Markdown link that resolved to the old path, so that each one resolves to the new path. Every link
whose resolution the rename changes SHALL be written again for the file it named before the rename;
this includes a link to another file whose name the rename made ambiguous. A link whose resolution
does not change SHALL NOT change. Known limit: notes does not rewrite a link in the frontmatter.

#### Scenario: A shortest-path link becomes ambiguous

- **WHEN** `Notes/Plan.md` moves to `Archive/Plan.md`, another `Drafts/Plan.md` exists, and
  `Index.md` links `[[Plan]]` to the moved file
- **THEN** `Index.md` links `[[Archive/Plan]]` after the move, as the fixture
  `shortest-path-collision` records, verified by
  `services/notes/tests/link_rewrite_golden.rs::shortest_path_collision` in `ratatoskr-notes`

#### Scenario: A link inside a code block is not a link

- **WHEN** a note contains `[[A]]` inside a fenced code block and `A.md` is renamed
- **THEN** the code block does not change, verified by the fixture `code-block-link` and
  `link_rewrite_golden.rs::code_block_link`

### Requirement: A rewrite keeps everything except the target

A rewritten link SHALL keep its alias, heading, block reference, display text and link form, in
Obsidian's default link form `shortest`; the fixtures also cover `relative` and `absolute`. No byte
outside the rewritten link targets SHALL change.

#### Scenario: An alias and a heading survive

- **WHEN** `A.md` is renamed to `B.md`, and a note links `[[A#Goals|our goals]]`
- **THEN** the note links `[[B#Goals|our goals]]` after the rename and every other byte of the note
  is unchanged, verified by the fixture `alias-and-heading` and
  `link_rewrite_golden.rs::alias_and_heading`

### Requirement: The rename and its rewrites are one write group

The rename and every rewrite SHALL form one write group. The group SHALL wait until it is at the head
of the queue of every file it changes. When the base check fails for any file, notes SHALL deliver
nothing and SHALL raise one conflict. The event `notes/conflict.v1` SHALL name the first stale file
in `path`, and `GET /v1/notes/conflicts/{id}` SHALL list every stale file in `stale_paths`. The
result SHALL list each changed path and its new revision hash.

#### Scenario: A linked file changed meanwhile

- **WHEN** a rename must rewrite `Index.md`, and `Index.md` changed in the vault before the group
  reached the head of its queue
- **THEN** neither the rename nor any rewrite is delivered, and one conflict names `Index.md`, verified
  by `services/notes/tests/link_rewrite_atomic.rs::stale_linked_file_blocks_rename`

### Requirement: Revisions of a group become current as the channel acknowledges them

Each revision of a write group SHALL become current only when the channel acknowledges it. When the
channel reports that it applied only part of the group, the applied files SHALL become current as
acknowledged, the operation SHALL fail with `notes.write.partially_applied`, and one conflict SHALL
name the files that were not applied.

#### Scenario: The device applies half a rename

- **WHEN** a device acknowledges the rename and one of two rewrites, and reports the other as
  `base_mismatch`
- **THEN** the two acknowledged files are current, the third keeps its previous revision, and one
  conflict names it, verified by `link_rewrite_atomic.rs::partial_application_fails_with_a_conflict`

### Requirement: Golden fixtures from the real Obsidian app are the oracle

`ratatoskr-notes` SHALL hold golden fixtures, each with a vault before the operation, the operation,
and the vault after it as the real Obsidian app produced it through `fileManager.renameFile` (the
call behind `obsidian move` and `obsidian rename`), plus the Obsidian version and vault settings. The notes rewrite SHALL produce the
"after" vault of every fixture byte for byte.

One case differs from Obsidian on purpose: a link nested in another link (a wikilink in the text of
a Markdown link, or a Markdown link in the alias of a wikilink). Notes SHALL rewrite the inner link
inside the new text of the outer link, where Obsidian 1.14.4 loses the inner rewrite. No fixture
records this case, because Obsidian corrupts these notes.

#### Scenario: A link nested in a Markdown link is rewritten inside it

- **WHEN** `A.md` is renamed, and a note holds a Markdown link to `A.md` whose text holds `[[A]]`
- **THEN** the note links the new name both in the outer link and in the inner wikilink, and every
  other byte is unchanged, verified by
  `crates/notes-index/tests/rewrite.rs::a_wikilink_in_the_text_of_a_markdown_link_is_rewritten_inside_it`
  in `ratatoskr-notes`

#### Scenario: The rewrite disagrees with Obsidian

- **WHEN** the notes rewrite of any fixture differs from the recorded "after" vault by one byte
- **THEN** `link_rewrite_golden.rs::every_fixture_matches` fails and names the fixture and the first
  differing file

### Requirement: The fixture corpus covers the known hard cases

The corpus SHALL cover at least: shortest-path links with and without a name collision, the
relative-path and absolute-path link settings, aliases, headings, block references, embeds of notes
and of attachments, Markdown links with encoded spaces, names that differ only in letter case, and a
name in NFD against NFC.

#### Scenario: A required case is missing

- **WHEN** the corpus has no fixture tagged with one of the required cases
- **THEN** `link_rewrite_golden.rs::corpus_covers_required_cases` fails and names the missing case

### Requirement: Fixtures are recorded, never edited by hand

A fixture SHALL be produced only by the documented recording script, which stores a checksum list of
the "after" vault. A fixture whose files do not match its checksum list SHALL fail the test suite.

#### Scenario: A fixture is edited by hand

- **WHEN** a file of a fixture's "after" vault does not match the fixture's checksum list
- **THEN** `link_rewrite_golden.rs::fixtures_match_their_recording` fails and names the fixture
