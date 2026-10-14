# Workspace threat model

> Status: Proposed  
> Last reviewed: 2026-10-14

## Assets

Private repository access, Git history, worktrees, CI/release identities, changesets, pins, agent permissions, integration environments, and release integrity.

## Trust boundaries

Developer/agent to harness; harness to Git; harness to child commands; harness to GitHub; task environments to local services; CI to private repositories.

## Threats

- **Destructive Git mutation:** allow only scoped harness operations; block force pushes, baseline edits, and unscoped cleanup.
- **Agent path escape:** validate writable roots and launch agents inside assigned worktrees.
- **Credential leakage:** use short-lived credentials and redact prompts, commands, logs, and fixtures.
- **Command injection:** avoid shell interpolation; constrain executable, arguments, environment, timeout, and working directory.
- **Malicious child repository:** treat hooks, scripts, and build inputs as untrusted; isolate execution.
- **Cross-task contamination:** namespace databases, streams, buckets, ports, volumes, and Compose projects.
- **Inconsistent release:** require pin, lock, contract, and integration checks before advancing `main`.

Residual risk includes compromised developer machines, zero-days in Git/build tools, and administrator misuse. Re-review when adding MCP writes, cloud agents, new credential paths, or automatic merge/deploy behavior.

## Server access to the Obsidian secrets of a `sync` connection

`ratatoskr-notes` connects a vault through Obsidian Sync with the Obsidian Headless client `ob`
(openspec change `add-notes-vault-connections`). The host therefore holds secrets that open the
user's whole vault, including an end-to-end encrypted one:

- **At rest, in the database:** the Obsidian account password and the end-to-end password of each
  `sync` connection. Each is encrypted with XChaCha20-Poly1305 under the 32-byte key file
  `/etc/ratatoskr/notes-secrets.key` (owner `ratatoskr-notes`, mode 0400), with the connection id
  and the kind as associated data. `notes.connection_secrets` holds only the ciphertext. A failed
  login or a disconnect deletes it.
- **During a login only, in plain text:** the email, the two passwords, the MFA code and the vault
  id, in `/run/ratatoskr-notes/credentials/<id>/` (directory 0700, files 0600, owner
  `ratatoskr-notes`). `/run` is tmpfs, so the files never reach a disk. The login unit reads them
  with `LoadCredential=`, and `ob` reads each password on standard input, never from its command
  line. The service deletes the files when the unit stops, and removes the whole `credentials`
  directory at start.
- **After the login, in plain text:** `ob` keeps its Sync token and the derived end-to-end key in
  0600 files in the client state of the connection, `/mnt/nvme/ratatoskr/notes/clients/<id>`, a
  0700 directory under the 0700 clients root, which `ratatoskr-notes-sync` owns.

Mitigations:

- `ob` runs as `ratatoskr-notes-sync`, a user that shares its group with no other user. The
  clients root is mode 0700. The working trees are under a separate trees root, which is setgid
  with the group `ratatoskr-notes-trees`; `ratatoskr-notes` is its only member, so the notes service
  reads the trees and no other user can. The sync and login units run with `UMask=0027`, and
  `ob login` runs with the umask 0077, so the client state is 0700 and a tree is 2750 with files
  0640. The cleanup unit runs with `UMask=0077`. The units run with `ProtectSystem=strict`, and
  they write only under the trees root and the clients root.
- The sync units log to their own journal namespace, `ratatoskr-notes-sync`. An ACL gives
  `ratatoskr-notes` read access to that namespace only, so the notes service is not in the group
  `systemd-journal` and cannot read the journal of another unit. The ACL names no other group: the
  deploy role removes the group `adm`, which the default ACL of `/var/log/journal` gives on Debian,
  because a line of `ob` can name a file of the vault.
- Only `ratatoskr-notes` can open the key file. The service refuses a key file that is a symbolic
  link, that has another owner, or that other users can open.
- One polkit rule lets `ratatoskr-notes` start and stop only the three notes template units, with a
  UUID instance name. A template unit starts only `/usr/bin/ob`, `/bin/rm` and `/bin/sh -c`, and
  `release_artifact_callers.rs` checks this at each pin.
- No secret goes into a log line, an event, an error envelope or the journal of a unit. The notes
  test `secret_custody.rs` checks each of these points with marker secrets.
- A disconnect runs `ob sync-unlink` and removes the working tree and the client state of the
  connection.

Residual risk: root on the host, or code that runs as `ratatoskr-notes-sync`, can read the Sync
token and the end-to-end key of every connection, and so every connected vault. Root, or code that
runs as `ratatoskr-notes`, can read the key file and the database, and so decrypt every stored
password. A backup that holds both the database dump and the key file holds the passwords. The
server reads the whole vault by design: end-to-end encryption protects the vault from Obsidian, not
from this host. If the host is compromised, disconnect each `sync` connection and change the
Obsidian account password and the end-to-end password.
