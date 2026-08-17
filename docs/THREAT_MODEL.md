# Workspace threat model

> Status: Proposed  
> Last reviewed: 2026-08-17

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
