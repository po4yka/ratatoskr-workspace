# Spec Delta

This delta requires `add-notes-write-back` (OBS-024) to be archived first.

## MODIFIED Requirements

### Requirement: The snapshot pins every product repository

The workspace manifest SHALL declare exactly the twenty-one product repositories `browser-extension`, `channel-digests`, `chatgpt`, `claude`, `contracts`, `export-agent`, `extractor`, `github`, `instagram`, `knowledge`, `mobile`, `notes`, `obsidian-plugin`, `platform`, `site-sdk`, `sites`, `telegram`, `threads`, `vault`, `web` and `x`, and each SHALL have a `.gitmodules` entry, a gitlink and a `workspace.lock` row. `channel-digests` SHALL be pinned at `repos/integrations/channel-digests` from `https://github.com/po4yka/ratatoskr-channel-digests.git`. `notes` SHALL be pinned at `repos/notes` from `https://github.com/po4yka/ratatoskr-notes.git`, and `obsidian-plugin` at `repos/clients/obsidian-plugin` from `https://github.com/po4yka/ratatoskr-obsidian-plugin.git`. `sites` SHALL be pinned at `repos/sites` from `https://github.com/po4yka/ratatoskr-sites.git`, and `site-sdk` at `repos/clients/site-sdk` from `https://github.com/po4yka/ratatoskr-site-sdk.git`.

#### Scenario: The committed snapshot includes channel digests

- **WHEN** `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current` reads the committed workspace
- **THEN** it finds twenty-one repositories, `channel-digests` among them at `repos/integrations/channel-digests` with its audited commit, and a lock that is current

#### Scenario: A manifest without channel digests is incomplete

- **WHEN** `ws manifest check` validates a manifest that omits `channel-digests`
- **THEN** validation fails with `manifest.repository.missing` naming `channel-digests`

#### Scenario: The committed snapshot includes the notes repositories

- **WHEN** `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current` reads the committed workspace after the pins of `add-notes-vault-connections`
- **THEN** it finds `notes` at `repos/notes` and `obsidian-plugin` at `repos/clients/obsidian-plugin`, each with its audited commit

#### Scenario: The committed snapshot includes the sites repositories

- **WHEN** the same test reads the committed workspace after the pins of `add-site-publications`
- **THEN** it finds `sites` at `repos/sites` and `site-sdk` at `repos/clients/site-sdk`, each with its audited commit

#### Scenario: A manifest without the sites service is incomplete

- **WHEN** `ws manifest check` validates a manifest that omits `sites`
- **THEN** validation fails with `manifest.repository.missing` naming `sites`
