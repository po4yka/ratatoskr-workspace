# Security Policy for Ratatoskr Workspace

> Status: Proposed  
> Last reviewed: 2026-08-17

## Supported versions

There is no supported production release yet. This section must be updated when tagged releases begin.

## Reporting

Do not publish exploit details, credentials, private repository data, agent prompts containing secrets, or production logs in a public issue. Use GitHub private vulnerability reporting when enabled; otherwise contact the repository owner through an established private channel.

Include the affected repository/commit, impact, attack preconditions, minimal reproduction, possible data exposure, and known mitigation. Use synthetic evidence only.

## Sensitive changes

Security review is required for agent permissions, Git mutation, worktree isolation, command execution, credentials, private submodules, CI identities, MCP write tools, integration environment isolation, release pins, and cleanup behavior.

## Baseline

- Use short-lived least-privilege credentials.
- Treat child repositories and their scripts as untrusted.
- Avoid shell interpolation for structured commands.
- Never place secrets in manifests, lockfiles, changesets, prompts, logs, fixtures, or Compose overrides.
- Preserve evidence and coordinate fixes across affected repositories before disclosure.
