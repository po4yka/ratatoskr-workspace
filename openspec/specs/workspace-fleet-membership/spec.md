# Workspace Fleet Membership Specification

## Purpose
Defines which product repositories the workspace snapshot pins, so that a repository joining the fleet has one checkable place to join the snapshot.

## Requirements

### Requirement: The snapshot pins every product repository

The workspace manifest SHALL declare exactly the seventeen product repositories `browser-extension`, `channel-digests`, `chatgpt`, `claude`, `contracts`, `export-agent`, `extractor`, `github`, `instagram`, `knowledge`, `mobile`, `platform`, `telegram`, `threads`, `vault`, `web` and `x`, and each SHALL have a `.gitmodules` entry, a gitlink and a `workspace.lock` row. `channel-digests` SHALL be pinned at `repos/integrations/channel-digests` from `https://github.com/po4yka/ratatoskr-channel-digests.git`.

#### Scenario: The committed snapshot includes channel digests

- **WHEN** `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current` reads the committed workspace
- **THEN** it finds seventeen repositories, `channel-digests` among them at `repos/integrations/channel-digests` with its audited commit, and a lock that is current

#### Scenario: A manifest without channel digests is incomplete

- **WHEN** `ws manifest check` validates a manifest that omits `channel-digests`
- **THEN** validation fails with `manifest.repository.missing` naming `channel-digests`
