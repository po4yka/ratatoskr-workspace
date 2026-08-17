# Workspace interfaces

> Status: Proposed  
> Last reviewed: 2026-08-17

## Inbound

- Human and CI invocations of the `ws` CLI.
- Read-oriented MCP requests from coding agents.
- Git state, child check results, GitHub PR metadata, tasks, and changesets.

## Outbound

- Structured system Git operations.
- Repository-local bootstrap, format, lint, test, build, and integration commands.
- Task-specific Docker Compose environments.
- Approved GitHub branch, PR, pin, and release operations.

## Rules

- Commands that mutate Git or external state require a task/changeset ID.
- Executables and arguments are represented structurally; avoid shell interpolation.
- MCP is read-only by default; write tools are separately authorized and audited.
- Child commands run in the assigned worktree with bounded environment and timeout.
- Partial failures are reported per repository; pins never change silently.
- Contract impact and rollout order are derived before child PR creation.

## Failure contract

Failures identify repository, task, command, transient/permanent class, safe summary, correlation ID, and recovery action without exposing credentials or private file content.
