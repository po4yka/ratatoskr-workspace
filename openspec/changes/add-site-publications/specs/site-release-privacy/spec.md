# Spec Delta

## Purpose

Defines what a site release must never contain from a file that its publication does not select,
and how links, embeds, comments, frontmatter and attachments are filtered before a release is
rendered. A release is public: everything in it can be read by anyone.

## ADDED Requirements

### Requirement: A release holds no data read from an unselected file

A release SHALL NOT contain any data that the release builder read from a file that the
publication does not select: not its content, its frontmatter, its headings, its block ids, its
tags, its title, its vault path, its slug, its digest or its size, and not the fact that it exists.
The only text in a release SHALL be text from selected files and text that the release builder
generates itself.

#### Scenario: Canary strings from private files do not leak

- **WHEN** a release is built from the fixture vault `fixtures/privacy-vault/`, in which every
  unselected file carries a unique canary string in its file name, frontmatter `title`, frontmatter
  fields, headings, block ids, tags and body
- **THEN** no canary string appears in any byte of the release document, its pages, its search
  index or its assets, verified by
  `crates/release/tests/privacy.rs::no_canary_from_an_unselected_file_reaches_the_release` in
  `ratatoskr-sites`

### Requirement: A link to an unselected note looks like an unresolved link

A link in a published page whose target is a note that the publication does not select, or a
heading or block of such a note, SHALL be rendered exactly like a link whose target does not exist:
plain text without a target. The text SHALL be the author's alias, or else the link text as written
in the published page without brackets. Nothing read from the target SHALL be added.

#### Scenario: A link with an alias to a private note

- **WHEN** a published page contains `[[Salary review 2026|my notes]]` and that note is not selected
- **THEN** the page body contains the plain text `my notes`, no link element, and neither the
  target's path nor its frontmatter `title`, verified by
  `privacy.rs::aliased_link_to_unselected_note_is_plain_alias`

#### Scenario: A private target and a missing target are indistinguishable

- **WHEN** one published page links to an unselected note and another identical page links to a
  name that matches no file
- **THEN** the two rendered bodies are byte-identical in both the AST and the HTML, verified by
  `privacy.rs::unselected_target_renders_like_missing_target`

### Requirement: An embed of an unselected file is removed

An embed (`![[name]]`, `![[name#heading]]`, `![[name#^block]]` or `![alt](path)`) whose target is a
note or an attachment that the release does not publish SHALL be removed from the page without a
trace: no placeholder, no alternative text taken from the target, and no empty element.

#### Scenario: An embedded private note leaves nothing behind

- **WHEN** a published page embeds `![[Diary]]` and `Diary.md` is not selected
- **THEN** the rendered page is byte-identical to the same page with the embed line removed,
  verified by `privacy.rs::embed_of_unselected_note_leaves_no_trace`

### Requirement: Comments are removed before rendering

The release builder SHALL remove every Obsidian comment (`%% … %%`, inline or over several lines)
and every HTML comment (`<!-- … -->`) from a page before it renders the page. A comment marker
inside a code span or a fenced code block SHALL be kept as code.

#### Scenario: A block comment over several lines

- **WHEN** a published page holds a `%%` comment over three lines that contains a canary string
- **THEN** neither the AST nor the HTML of the page contains the canary string, verified by
  `privacy.rs::obsidian_comment_is_removed`

#### Scenario: A comment marker in code is kept

- **WHEN** a published page holds the fenced code block `` ```text `` with the line `%% not a comment %%`
- **THEN** the page's code block contains that line unchanged, verified by
  `privacy.rs::comment_marker_in_code_is_kept`

### Requirement: Only allowlisted frontmatter fields are published

A page SHALL carry only the frontmatter fields on the publication's allowlist. The default
allowlist SHALL be `title`, `description`, `tags`, `aliases`, `date`, `updated` and `cover`. The
owner MAY add field names to the allowlist of a publication. The fields `publish` and `slug` SHALL
be used by the release builder and SHALL NOT be published as fields. The tags of a page SHALL be
published only as the page carries them; the release SHALL hold no tag list that includes tags of
unselected files.

#### Scenario: An unlisted field is dropped

- **WHEN** a published page has the frontmatter fields `title`, `owner_email` and `publish`
- **THEN** its page carries `title` only, verified by
  `privacy.rs::frontmatter_outside_allowlist_is_dropped`

### Requirement: An attachment is published only when a published page uses it

An attachment SHALL be in a release only when at least one page of that release embeds it or links
to it after the filters above have run. A page SHALL refer to an asset only by its public asset URL,
which is built from the asset's SHA-256 digest and never from its vault path. The same bytes used by
a selected and by an unselected note SHALL be published once, for the selected note only.

#### Scenario: An attachment used only by a private note

- **WHEN** `img/plan.png` is embedded only by an unselected note
- **THEN** the release has no asset with that digest, and the asset route answers not-found for
  it, verified by `privacy.rs::attachment_of_unselected_note_is_not_published`

#### Scenario: A published asset hides its vault path

- **WHEN** a published page embeds `attachments/2026/passport-scan-blurred.png`
- **THEN** the page refers to the asset as `assets/<sha256 hex>` and the string `passport-scan`
  appears nowhere in the release, verified by `privacy.rs::asset_url_carries_no_vault_path`

### Requirement: Rendered HTML is sanitised

The HTML body of a page SHALL contain only elements and attributes from a closed allowlist. It
SHALL NOT contain `script`, `style`, `iframe`, `object`, `embed` or `form` elements, any `on*`
attribute, or a URL whose scheme is not `https`, `http`, `mailto` or a relative reference. Raw HTML
in a note SHALL pass through the same allowlist. A Dataview or other plugin query block SHALL be
rendered as a code block and SHALL NOT be run.

#### Scenario: Script in a note does not reach the HTML

- **WHEN** a published note contains `<script>alert(1)</script>` and `<a href="javascript:x">`
- **THEN** the page HTML contains no `script` element and no `javascript:` URL, verified by
  `crates/release/tests/sanitise.rs::script_and_javascript_urls_are_removed`

### Requirement: Every build renders every selected page from current sources

Each build SHALL parse, filter and render every selected page from the current revisions of the
vault connection, and SHALL NOT reuse a page rendered by an earlier build. A later change that adds
page reuse SHALL keep the two scenarios below passing.

#### Scenario: A link target leaves the publication after a release

- **WHEN** page `a` links to note `b`, a release publishes both, and `b` then gets `publish: false`
  while `a` does not change
- **THEN** the next release renders the link in `a` as plain text and holds nothing from `b`,
  verified by `crates/release/tests/privacy.rs::target_unselected_after_release_rerenders_linking_page`
  in `ratatoskr-sites`

#### Scenario: A backlink from a page that leaves the publication

- **WHEN** page `c` links to page `d`, a release lists `c` as a backlink of `d`, and `c` then moves
  into an excluded folder while `d` does not change
- **THEN** the next release lists no backlink from `c` on `d` and holds nothing from `c`, verified by
  `privacy.rs::backlink_from_unselected_page_is_dropped_on_rebuild`
