# Spikes 3.5 (desktop) and 3.6: Obsidian 1.14.4 engine capture

Date: 2026-10-13. Obsidian app 1.14.4 (API `apiVersion` 1.14.4), installer 1.8.10, Electron
34.2.0, macOS arm64.

## Method

The official Obsidian CLI needs installer 1.12.7 or later, and the machine had installer 1.8.10.
So the data comes from the engine itself, through a throwaway plugin (`recorder/main.js`), in an
isolated profile:

1. `recorder/gen_vault.py` builds the fixture vault of design D8 (`vault/`, 48 files and 18
   folders).
2. Obsidian starts with `--user-data-dir=<spike>/profile`. That profile lists only the fixture
   vault and holds a copy of the app's `obsidian-1.14.4.asar`. The owner's own vaults and profile
   are never opened.
3. On layout ready, the plugin dumps the metadata cache, performs the event scenario, records the
   rename goldens, and probes credential storage. It never stores a real secret.

Vault settings: `alwaysUpdateLinks: true`, `newLinkFormat: shortest`, `useMarkdownLinks: false`.
Absolute paths in the outputs are replaced with `<spike>`.

## Files

| File | Content | Used by |
|---|---|---|
| `vault/` | The fixture vault before any run | OBS-023 task 7.1 |
| `metadata.json` | Per file: the metadata cache, `resolvedLinks`, `unresolvedLinks`, backlinks and tags | OBS-023 task 7.1 (`index_matches_obsidian_engine_output`) |
| `events.jsonl` | Vault events for each action, with timestamps | OBS-023 design D5, task 11.4 |
| `metadata-after-events.json` | The cache after the event scenario | reference |
| `rename-goldens/<case>/` | `before/` and `after/` text of every changed file, and `case.json` | OBS-024 link-rewrite corpus |
| `credentials.json` | Which credential stores a plugin can reach on desktop | OBS-023 design D5 |
| `env.json` | App, Electron and Node versions and the vault settings | reference |
| `recorder/` | The vault generator and the recording plugin | re-recording for a new version |

## Findings

- **Resolution:** an exact path wins, then a file of that name in the linking file's own folder,
  then a unique name, then the shortest path. Matching ignores case. Aliases never resolve a
  target.
- **Comments and code:** links and tags inside `%% comments %%` are indexed. Code, HTML comments and
  `$$` math are not.
- **Normalisation:** paths and link text are NFC. Tags are not normalised.
- **Folder rename:** one `rename` for the folder, then one `rename` per file.
- **Rename outside Obsidian:** `create`, then `delete` about one second later.
- **Credentials:** `app.secretStorage` encrypts with `safeStorage` outside the vault, scoped to the
  vault id. `saveData` writes `data.json` inside the vault.
- **Rename goldens:** a relative Markdown link becomes a bare name, a path wikilink is shortened
  when the new name is unique, and a move into a name collision writes the full path.

## Not covered

- Physical iOS was not covered. The owner removed it from acceptance on 2026-10-21;
  the absence of device evidence is retained and no longer leaves task 3.5 open.
- Output of the Obsidian CLI: not available with installer 1.8.10. The engine JSON carries the same
  data.
