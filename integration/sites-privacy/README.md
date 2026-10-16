# Sites privacy integration

`scenario.py` is a leg of `../run-site-owner-editing.sh`. It uses the same private Compose
project and the deployed NATS ACL. The workspace `sites-integration` job runs it.

The scenario uploads every file of the pinned Sites repository's `fixtures/privacy-vault/vault`
through the real Notes device API. Notes parses the files and serves its real internal index;
the scenario does not seed that index from the fixture's `index.json`.

A primary owner approves a manifest and requests its first manual release through Edge. The
publication selects all notes except `private/` and notes with `publish: false`. Every subsequent
content request is anonymous. The scenario checks the release document, every listed page and
asset, their hashes, a positive search control, and a search for every `zq7` canary in the fixture.
No response may expose a canary or the unapproved owner-email field. Both published pages and a
published asset must exist, so an empty release cannot pass.

Use the exact inputs and command in [the integration guide](../README.md). The runner publishes
`result.json` only after the complete profile, final source checks and teardown succeed. Its
`privacy` entry records the numbers of pages, assets and negative searches. A local pass and the
published workspace job are separate evidence. This scenario does not exercise a browser,
Obsidian Sync, or a production host.
