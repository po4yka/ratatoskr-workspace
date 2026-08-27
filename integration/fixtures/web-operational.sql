begin;

-- Fixed, non-secret browser fixtures. The runner never prints them.
-- Owner credential: web012-owner-credential
-- Member credential: web012-member-credential

insert into identity.users (user_id, status, created_at, updated_at) values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc01', 'active', '2026-08-27T08:00:00Z', '2026-08-27T08:00:00Z'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc02', 'active', '2026-08-27T08:00:00Z', '2026-08-27T08:00:00Z');

insert into identity.sessions
  (session_id, user_id, kind, audience, issued_at, expires_at, token_hash)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc11', '01a0153f-63e5-7010-a4c9-1fe6c43bcc01',
   'browser', 'edge', '2026-08-27T08:00:00Z', '2099-01-01T00:00:00Z',
   decode('cc4d9257b92340b47a8cd50816bcddffc7166c06d77df3f7822df13f005c6fca', 'hex')),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc12', '01a0153f-63e5-7010-a4c9-1fe6c43bcc02',
   'browser', 'edge', '2026-08-27T08:00:00Z', '2099-01-01T00:00:00Z',
   decode('4dc7af34e10c51b072cb2946a59499e1fa68afa9dd903dc7608f73a3f3dd8bd3', 'hex'));

insert into identity.grants (grant_id, user_id, capability, granted_at) values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc21', '01a0153f-63e5-7010-a4c9-1fe6c43bcc01',
   'platform.owner', '2026-08-27T08:00:00Z');

insert into operations.operations
  (operation_id, owner_user_id, kind, status, stage, progress_percent, correlation_id,
   retryable, accepted_at, status_changed_at, terminated_at)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc31', '01a0153f-63e5-7010-a4c9-1fe6c43bcc02',
   'content.capture.submit', 'succeeded', 'stored', 100, 'correlation:web012-success', false,
   '2026-08-27T08:01:00Z', '2026-08-27T08:02:00Z', '2026-08-27T08:02:00Z'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc32', '01a0153f-63e5-7010-a4c9-1fe6c43bcc02',
   'content.extraction.run', 'partially_succeeded', 'complete', 100,
   'correlation:web012-partial', false, '2026-08-27T08:03:00Z',
   '2026-08-27T08:04:00Z', '2026-08-27T08:04:00Z'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc33', '01a0153f-63e5-7010-a4c9-1fe6c43bcc02',
   'github.sync.requested', 'failed', 'provider', null, 'correlation:web012-failed', true,
   '2026-08-27T08:05:00Z', '2026-08-27T08:06:00Z', '2026-08-27T08:06:00Z');

insert into operations.operation_errors
  (error_id, operation_id, severity, code, message, retryable, payload, recorded_at)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc41', '01a0153f-63e5-7010-a4c9-1fe6c43bcc32',
   'warning', 'content.extraction.partial', 'One item could not be extracted.', false, '{}',
   '2026-08-27T08:04:00Z'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc42', '01a0153f-63e5-7010-a4c9-1fe6c43bcc33',
   'error', 'provider.connection.unavailable', 'The provider could not be reached.', true, '{}',
   '2026-08-27T08:06:00Z');

insert into operations.schedules
  (schedule_id, service_name, name, owner_user_id, command_type, operation_kind, payload,
   cron_expression, next_due_at, enabled, created_at, updated_at)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc51', 'github', 'nightly-sync',
   '01a0153f-63e5-7010-a4c9-1fe6c43bcc02', 'github.sync.requested.v1',
   'github.sync.requested', '{}', '0 3 * * *', '2026-08-28T03:00:00Z', true,
   '2026-08-27T08:00:00Z', '2026-08-27T08:00:00Z'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc52', 'archive', 'weekly-snapshot',
   '01a0153f-63e5-7010-a4c9-1fe6c43bcc02', 'vault.snapshot.requested.v1',
   'vault.snapshot.requested', '{}', '0 4 * * 0', '2026-08-30T04:00:00Z', false,
   '2026-08-27T08:00:00Z', '2026-08-27T08:00:00Z');

insert into operations.schedule_occurrences
  (occurrence_id, schedule_id, due_at, published_at, drift_seconds, operation_id)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc61', '01a0153f-63e5-7010-a4c9-1fe6c43bcc52',
   '2026-08-24T04:00:00Z', '2026-08-24T04:00:01Z', 1,
   '01a0153f-63e5-7010-a4c9-1fe6c43bcc33');

insert into identity.audit_events
  (audit_event_id, occurred_at, actor_user_id, actor_session_id, action, target_kind,
   target_id, outcome, correlation_id)
values
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc71', '2026-08-27T08:07:00Z',
   '01a0153f-63e5-7010-a4c9-1fe6c43bcc01', '01a0153f-63e5-7010-a4c9-1fe6c43bcc11',
   'operation.read', 'operation', '01a0153f-63e5-7010-a4c9-1fe6c43bcc33',
   'allowed', 'correlation:web012-audit'),
  ('01a0153f-63e5-7010-a4c9-1fe6c43bcc72', '2026-08-27T08:08:00Z',
   null, null, 'system.health_observed', 'system', null, 'failed',
   'correlation:web012-system');

commit;
