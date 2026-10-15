# Spec Delta

## Purpose

Defines how a publication selects files from one vault connection, how the sites service builds an
immutable release from that selection, how a release becomes current and is announced, and what
happens to a publication when its vault connection goes away.

## ADDED Requirements

### Requirement: A publication belongs to one site and one vault connection

A publication SHALL belong to exactly one site and select files from exactly one vault connection.
Several publications, of the same site or of different sites, MAY select from the same connection.

#### Scenario: Two sites publish from one connection

- **WHEN** site `a` and site `b` each have a publication over the same connection, and a note in a
  folder that both include has `publish: [a]`
- **THEN** the release of `a` has a page for the note and the release of `b` has none, verified by
  `crates/publications/tests/selection.rs::publish_list_limits_a_file_to_named_sites` in
  `ratatoskr-sites`

### Requirement: A publication selects Markdown files by one fixed precedence

A publication SHALL decide for each Markdown file by this precedence, highest first: an excluded
folder excludes; a file outside the included folders (when any are named) is excluded;
`publish: false` excludes; a `publish` list that does not name the site excludes; `publish: true` or
a list that names the site includes; an included tag includes; then the mode `all` includes and the
mode `flagged` excludes.

#### Scenario: An excluded folder wins over the frontmatter key

- **WHEN** a publication excludes `private/` and the file `private/launch.md` has `publish: true`
- **THEN** the release contains no page for `private/launch.md`, verified by
  `selection.rs::excluded_folder_wins_over_publish_true`

#### Scenario: The frontmatter key works only inside the included folders

- **WHEN** a publication includes only `blog/` and the file `journal/today.md` has `publish: true`
- **THEN** the release contains no page for it, verified by
  `selection.rs::publish_true_outside_included_folders_is_not_selected`

#### Scenario: The frontmatter key overrides an included tag

- **WHEN** a publication includes the tag `#public` and a file has the tag `#public` and
  `publish: false`
- **THEN** the release contains no page for that file, verified by
  `selection.rs::publish_false_overrides_included_tag`

#### Scenario: A flagged publication ignores unflagged files

- **WHEN** a publication in the mode `flagged` sees a Markdown file with no `publish` key and no
  included tag
- **THEN** the release contains no page for it, verified by `selection.rs::default_is_not_selected`

### Requirement: Attachments and configuration are never selected by a folder or a tag

A file that is not Markdown SHALL be published only through the attachment rule of
`site-release-privacy`, never because it is in an included folder. A file under `.obsidian/`, and a
file that the vault connection does not index, SHALL never be selected.

#### Scenario: An image in an included folder that no page uses

- **WHEN** a publication includes `blog/` and `blog/draft-cover.png` is used by no published page
- **THEN** the release holds no asset for it, verified by
  `selection.rs::attachment_in_included_folder_needs_a_published_use`

#### Scenario: The configuration folder is ignored

- **WHEN** a publication includes the folder `.obsidian/` by mistake
- **THEN** the release holds nothing from that folder, verified by
  `selection.rs::obsidian_folder_is_never_selected`

### Requirement: A release is immutable and named by its content

The sites service SHALL name a release by the SHA-256 digest of its canonical release document
(`sites/release.v1`), and a release SHALL NOT change after it is built. A build whose digest equals
the current release SHALL NOT make a new release and SHALL NOT publish
`evt.sites.release.published.v1`.

#### Scenario: A rebuild with no content change makes no release

- **WHEN** the owner requests a build twice and no selected file changed between the two builds
- **THEN** the second build reports the existing release id, the release list holds one release,
  and the bus carries one `evt.sites.release.published.v1`, verified by
  `services/sites/tests/release_build.rs::unchanged_content_makes_no_new_release`

#### Scenario: A stored release is not modified

- **WHEN** a file of a published release changes and a new release is built
- **THEN** the earlier release's document and pages still hash to the earlier release id, verified
  by `release_build.rs::earlier_release_is_unchanged`

### Requirement: Every page has one stable slug

Each page SHALL have a slug that is unique within its release. The slug SHALL be the frontmatter
key `slug` when present; otherwise the vault path without `.md`, lower-cased, with each run of
characters other than ASCII letters, digits and `/` replaced by one `-`. When two selected files get
the same slug, the build SHALL fail with the class `sites.slug_collision` and make no release.

#### Scenario: Two files collide on one slug

- **WHEN** `Notes/A B.md` and `notes/a-b.md` are both selected and neither has a `slug` key
- **THEN** the build fails with `sites.slug_collision`, the current release stays current, and the
  owner's operation names both files, verified by
  `crates/publications/tests/slug.rs::colliding_paths_fail_the_build`

### Requirement: A release becomes current atomically

When a build makes a new release, the sites service SHALL make it the site's current release and
write the outbox row of `evt.sites.release.published.v1` in one transaction. A reader of the
Content Delivery API SHALL see either the previous release or the new one, never a mix of both.

#### Scenario: A reader never sees a mixed release

- **WHEN** a reader fetches the release document and then each page it lists while a new release
  becomes current
- **THEN** every page answer either belongs to the release id that the reader fetched or is a
  not-found answer, verified by
  `services/sites/tests/release_switch.rs::readers_see_one_release_or_the_other`

### Requirement: The release event carries no content

`evt.sites.release.published.v1` SHALL carry the site id, the release id, the publication ids, the
page count and the time of publication. It SHALL NOT carry a page title, a slug, a vault path or any
page content.

#### Scenario: The event bytes hold no page data

- **WHEN** `evt.sites.release.published.v1` is published for a release whose pages have titles
- **THEN** the envelope validates against the contract schema, and no title, slug or path of the
  release appears in its bytes, verified by
  `release_switch.rs::published_event_carries_no_content`

### Requirement: A build starts only from a request or from a selected file change

A build SHALL start when Edge publishes `cmd.sites.release.build_requested.v1`, or, for a publication
in the release mode `automatic` that already has a release, after `evt.notes.file.changed.v1` reports
a file that the publication selects now or selected in the current release. A removal build (the
next requirement) SHALL also start, in every release mode. The sites service SHALL NOT publish a
command itself.

#### Scenario: A change to a file outside the publication starts no build

- **WHEN** `evt.notes.file.changed.v1` reports a file that the automatic publication neither
  selects now nor selected in the current release
- **THEN** no build starts and no operation is reported, verified by
  `services/sites/tests/build_triggers.rs::unrelated_change_starts_no_build`

#### Scenario: A manual publication waits for a request

- **WHEN** a selected file of a publication in `manual` mode changes
- **THEN** no build starts until Edge publishes `cmd.sites.release.build_requested.v1` for that
  site, verified by `build_triggers.rs::manual_publication_ignores_file_changes`

### Requirement: A removal build releases no new content

When the effective publications of a released site shrink, or a released publication is changed or
deleted, the sites service SHALL request a build of the origin `removal`, in every release mode. A
removal build SHALL read only the files that the current release was built from, SHALL apply the
publications that stay in the effective set, and SHALL publish no note change that the owner did not
release. A build from the release SHALL only shrink a publication: a released row is eligible for
publication P only when P published it at release time and the current configuration of P still
selects it.

#### Scenario: A removed publication leaves the kept pages

- **WHEN** a publication is removed from the manifest of a released site in the release mode
  `manual`
- **THEN** a build starts, and the new release holds no slug or title of it in the kept pages,
  verified by `services/sites/tests/removal_build.rs::removed_publication_is_built_out_of_the_kept_pages`

#### Scenario: A removal build keeps the released text

- **WHEN** in the release mode `manual` the owner changes a note after the release and then removes
  another publication
- **THEN** the release of the removal build holds the released text of the changed note, verified
  by `removal_build.rs::removal_build_keeps_the_released_text`

#### Scenario: A narrowed publication drops its notes

- **WHEN** a PUT adds a folder to the excluded folders of a released manual publication
- **THEN** the removal build removes the notes of that folder, verified by
  `release_narrowing.rs::narrowed_publication_drops_its_pages_in_a_build_from_the_release`

### Requirement: The first release of a publication is explicit

The first release that contains a publication SHALL be built only from
`cmd.sites.release.build_requested.v1`, whatever the publication's release mode. The mode `automatic`
SHALL apply only after that first release. This keeps notes that already carry Obsidian Publish
flags out of a release until the owner asks for one.

#### Scenario: A new automatic publication on a flagged vault

- **WHEN** an automatic publication is created over a connection whose notes already carry
  `publish: true`, and a selected note changes
- **THEN** no build starts and no release exists until Edge publishes
  `cmd.sites.release.build_requested.v1` for the site, verified by
  `build_triggers.rs::first_release_needs_an_explicit_request`

### Requirement: Changes during a build cause at most one more build

Changes that arrive while a build of a site runs SHALL cause at most one further build of that site
after the running build ends.

#### Scenario: A burst of changes makes one follow-up build

- **WHEN** five selected files change while one build of the site runs
- **THEN** exactly one more build runs after it, verified by
  `build_triggers.rs::changes_during_a_build_coalesce_into_one`

### Requirement: A disconnected vault suspends its publications

When the sites service consumes `evt.notes.vault.disconnected.v1`, every publication over that
connection SHALL become `suspended` and SHALL NOT build. The site's current release SHALL stay
current until the site's approval is withdrawn or the vault is reconnected.

#### Scenario: A build request for a suspended publication fails

- **WHEN** the owner requests a build of a site whose only publication is suspended
- **THEN** the operation fails with the class `sites.publication_suspended` and the current release
  does not change, verified by
  `services/sites/tests/disconnect.rs::suspended_publication_does_not_build`

### Requirement: A withdrawn site serves nothing

A site whose approval Platform has withdrawn (`site-manifest`) SHALL serve no content, and its
content routes SHALL answer exactly as for a site that does not exist. Its releases SHALL stay stored
until the owner deletes the site.

#### Scenario: A withdrawn site is unknown

- **WHEN** the sites service consumes a withdrawal for a site that has a current release
- **THEN** every route under `/v1/sites/{site}/content` for that site answers exactly as for a site
  that never existed, verified by `disconnect.rs::withdrawn_site_is_indistinguishable_from_unknown`

### Requirement: A build is one operation of the sites lane

Edge SHALL mint each build request as an operation of the kind `sites.release.build` with the lane
`ratatoskr-sites`. The sites service SHALL report its progress and its result through
`evt.platform.operation.reported.v1`, and Platform SHALL apply a report for that kind only from
`ratatoskr-sites`. A build that makes no new release SHALL succeed and name the existing release id.

#### Scenario: Another identity reports for a build

- **WHEN** the NOTES identity publishes a well-formed report, with the owner's tenant, for a
  `sites.release.build` operation
- **THEN** the report is rejected and the operation is unchanged, verified by
  `crates/operations/tests/report_authority.rs::sites_build_accepts_only_the_sites_lane` in
  `ratatoskr-platform`

#### Scenario: A build reports its result

- **WHEN** a requested build makes a new release
- **THEN** the operation ends `succeeded` with the release id in its result, verified by
  `services/sites/tests/release_build.rs::build_reports_its_release_id`
