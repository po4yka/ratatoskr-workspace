\set ON_ERROR_STOP on

\connect platform
INSERT INTO identity.users (user_id, status, created_at, updated_at)
VALUES ('01980000-0000-7000-8000-000000000001', 'active', now(), now())
ON CONFLICT (user_id) DO NOTHING;

-- SHA-256 of the synthetic owner credential passed only to the task-local pairing request.
INSERT INTO identity.sessions (
  session_id, user_id, kind, device_id, audience, issued_at, expires_at, token_hash
)
VALUES (
  '01980000-0000-7000-8000-000000000002',
  '01980000-0000-7000-8000-000000000001',
  'browser', NULL, 'edge', now(), now() + interval '6 hours',
  decode('7ee73ce90efa151c9118eb3671ab0f1d9e623cb0cbbdfddeee2669b50a525e08', 'hex')
)
ON CONFLICT (session_id) DO NOTHING;

\connect chatgpt
INSERT INTO chatgpt_archive.accounts (id, external_kind, external_ref, display_label)
VALUES (
  '01980000-0000-7000-8000-000000000003',
  'personal', 'xpa020-chatgpt', 'XPA-020 synthetic account'
)
ON CONFLICT (id) DO NOTHING;

\connect claude
INSERT INTO claude_archive.accounts (account_id, external_account_id, display_name)
VALUES (
  '01980000-0000-7000-8000-000000000003',
  'xpa020-claude', 'XPA-020 synthetic account'
)
ON CONFLICT (account_id) DO NOTHING;
