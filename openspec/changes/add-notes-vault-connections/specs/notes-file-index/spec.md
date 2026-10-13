# Spec Delta

## Purpose

Defines what the index of a connected vault holds, how links resolve with Obsidian's rules, and the
read API through which clients, and later the sites, read files and their index.

## ADDED Requirements

### Requirement: The index of a Markdown file follows Obsidian's syntax

For each current Markdown file the index SHALL hold the frontmatter as JSON, the tags from the text
and from the `tags` frontmatter key, the headings with their levels, the block ids, the `aliases`
frontmatter values, and every outgoing link and embed. Links SHALL include `[[name]]`,
`[[name|alias]]`, `[[name#heading]]`, `[[name#^block]]`, `![[embed]]` and Markdown links to
relative paths. Text inside `%% comments %%`, code spans and fenced code blocks SHALL NOT produce
tags or links.

#### Scenario: A link inside a comment

- **WHEN** a file contains `%% see [[Secret]] %%` and a fenced code block with `[[Code]]`
- **THEN** the index of that file holds neither `Secret` nor `Code` as a link, verified by `crates/notes-index/tests/parse.rs::comments_and_code_produce_no_links` in `ratatoskr-notes`

### Requirement: Links resolve as Obsidian resolves them

A link target SHALL resolve to an exact vault path when one matches, otherwise to the only file with
that name, otherwise to the file with the shortest path among the files with that name. A link that
matches no file SHALL be recorded as unresolved. An alias SHALL NOT resolve a link target. For each
pinned Obsidian version, the resolved links, backlinks, tags and properties of the fixture vault
SHALL equal the golden output that the real Obsidian CLI produced for that version.

#### Scenario: The fixture vault is compared with Obsidian

- **WHEN** `crates/notes-index/tests/golden.rs::index_matches_obsidian_cli_output` runs against every directory under `crates/notes-index/tests/fixtures/obsidian-<version>/`
- **THEN** the outgoing links, backlinks, tags and properties of every fixture file equal the stored `obsidian links`, `obsidian backlinks format=json`, `obsidian tags` and `obsidian properties` output, verified by that test in `ratatoskr-notes`

#### Scenario: Two files share a name

- **WHEN** a vault holds `A/Note.md` and `B/C/Note.md` and a file links `[[Note]]`
- **THEN** the link resolves to `A/Note.md`, verified by `crates/notes-index/tests/resolve.rs::shortest_path_wins_for_equal_names` in `ratatoskr-notes`

### Requirement: Clients read files and the index only through Edge

`ratatoskr-notes` SHALL serve, behind Edge on `/v1/notes`, the list of the owner's connections with
their status, the list of current files of a connection with paths and revisions, the bytes of a file
at its current or a named revision, and the index of a file with its backlinks. Each route SHALL
return only data of the authenticated owner. The routes SHALL be read-only in this change.

#### Scenario: An owner reads another owner's file

- **WHEN** an authenticated owner requests a file of a connection that belongs to another owner
- **THEN** the response is `404`, verified by `services/notes/tests/read_api.rs::foreign_connection_is_not_found` in `ratatoskr-notes`

#### Scenario: A write is attempted

- **WHEN** a client sends `PUT` or `DELETE` to any `/v1/notes` file route
- **THEN** the response is `405`, and no revision is created, verified by `services/notes/tests/read_api.rs::file_routes_refuse_writes` in `ratatoskr-notes`
