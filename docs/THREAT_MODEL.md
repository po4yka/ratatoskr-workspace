# Workspace threat model

> Status: Proposed  
> Last reviewed: 2026-10-15

## Assets

Private repository access, Git history, worktrees, CI/release identities, changesets, pins, agent permissions, integration environments, and release integrity.

## Trust boundaries

Developer/agent to harness; harness to Git; harness to child commands; harness to GitHub; task environments to local services; CI to private repositories. For the product: the site origin (the code of a site that the owner deploys, served under its own hostname) to Edge, and the `site_owner` session of that origin to the owner's data (SITE-027, section below).

## Threats

- **Destructive Git mutation:** allow only scoped harness operations; block force pushes, baseline edits, and unscoped cleanup.
- **Agent path escape:** validate writable roots and launch agents inside assigned worktrees.
- **Credential leakage:** use short-lived credentials and redact prompts, commands, logs, and fixtures.
- **Command injection:** avoid shell interpolation; constrain executable, arguments, environment, timeout, and working directory.
- **Malicious child repository:** treat hooks, scripts, and build inputs as untrusted; isolate execution.
- **Cross-task contamination:** namespace databases, streams, buckets, ports, volumes, and Compose projects.
- **Inconsistent release:** require pin, lock, contract, and integration checks before advancing `main`.

- **Malicious site code:** a site runs code that its repository ships. A `site_owner` session reaches only the site-origin routes of its own site, each bound to one capability of the approved manifest, never a management route; see the section below.
- **Leaked sign-in code:** a code is single-use, expires after 60 seconds, needs the PKCE verifier that only the site page holds, and is bound to one site and its approved hostname.
- **Cross-site request:** the site cookie is host-only and `SameSite=Strict`, a state change needs the header `X-Ratatoskr-Site-Request` and an `Origin` equal to the approved hostname, Edge answers no CORS preflight on the site routes, and no page of the web client may be framed.

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
- One polkit rule lets `ratatoskr-notes` start and stop only the four notes template units, with a
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

## The site origin and the `site_owner` session

SITE-027 (openspec change `add-site-owner-editing-and-live`) lets the owner edit notes and read
the library from a site that runs under its own hostname. The site page is code that the owner
deploys, and it can be wrong or hostile, so it is a separate trust boundary.

- **Sign-in.** The owner approves a sign-in on the consent page of the web client, in a live
  browser session that no paired device opened and that holds `platform.owner`. Platform issues a
  code bound to the site, the owner, a PKCE challenge, the return path and the approved hostname,
  stores only its digest, and checks the approver again at the redeem. The web client and the site
  SDK follow only the callback page `/.ratatoskr/sign-in/` of the approved hostname.
- **Session.** A `site_owner` session has the audience `site:<site id>`, an idle limit of 1 hour and
  an absolute limit of 12 hours, and its cookie is `__Host-ratatoskr-site` (`HttpOnly`, `Secure`,
  `SameSite=Strict`). It is refused on every general and management route. Withdrawing the approval
  of the site revokes every session of that site, and the owner can end the sessions of one site.
- **Reach.** Each site-origin route needs a capability of the effective set of the site. An edit
  goes to the notes write path with the origin `site:<site id>`, only for a note that a publication
  of the site selects; notes serves the claim only on its upload routes and the conflict read.
- **Live events.** An anonymous client sees only `release.published`, with no page list. An owner
  stream ends with its session, and both kinds of stream have bounds per client and per site.

Known limits are recorded in the design of SITE-027: the 16 MiB read of an edit upload in memory,
the public rate bucket that the owner shares with the site, no check that `content_blob` is the
blob of the same upload, no manifest cache, no live delivery of an event older than 24 hours, and
an open stream that is not session activity. The web client host must send the frame headers that
`DEPLOYMENT_TARGET.md` names.
