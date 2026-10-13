# Spec Delta

## Purpose

Adds the two repositories of the notes read path, `ratatoskr-notes` and
`ratatoskr-obsidian-plugin`, to the pinned fleet.

## MODIFIED Requirements

### Requirement: The snapshot pins every product repository

The workspace manifest SHALL declare exactly the nineteen product repositories `browser-extension`, `channel-digests`, `chatgpt`, `claude`, `contracts`, `export-agent`, `extractor`, `github`, `instagram`, `knowledge`, `mobile`, `notes`, `obsidian-plugin`, `platform`, `telegram`, `threads`, `vault`, `web` and `x`, and each SHALL have a `.gitmodules` entry, a gitlink and a `workspace.lock` row. `channel-digests` SHALL be pinned at `repos/integrations/channel-digests` from `https://github.com/po4yka/ratatoskr-channel-digests.git`. `notes` SHALL be pinned at `repos/notes` from `https://github.com/po4yka/ratatoskr-notes.git`, and `obsidian-plugin` at `repos/clients/obsidian-plugin` from `https://github.com/po4yka/ratatoskr-obsidian-plugin.git`.

#### Scenario: The committed snapshot includes channel digests

- **WHEN** `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current` reads the committed workspace
- **THEN** it finds nineteen repositories, `channel-digests` among them at `repos/integrations/channel-digests` with its audited commit, and a lock that is current

#### Scenario: A manifest without channel digests is incomplete

- **WHEN** `ws manifest check` validates a manifest that omits `channel-digests`
- **THEN** validation fails with `manifest.repository.missing` naming `channel-digests`

#### Scenario: The committed snapshot includes the notes repositories

- **WHEN** `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current` reads the committed workspace after the pins of `add-notes-vault-connections`
- **THEN** it finds `notes` at `repos/notes` and `obsidian-plugin` at `repos/clients/obsidian-plugin`, each with its audited commit
