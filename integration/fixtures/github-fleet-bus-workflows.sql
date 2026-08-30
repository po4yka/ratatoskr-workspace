insert into github_catalog.repositories (repository_id, provider_repository_id, mode)
values
  ('018f0000-0000-7000-8000-000000000902', 99002, 'tracked'),
  ('018f0000-0000-7000-8000-000000000903', 99003, 'tracked'),
  ('018f0000-0000-7000-8000-000000000906', 99006, 'tracked');

insert into github_catalog.repository_watches
  (watch_id, owner_ref, repository_id, trigger_type, downstream_action,
   last_evaluated_content_hash)
values
  ('018f0000-0000-7000-8000-000000000904',
   'user:018f0000-0000-7000-8000-000000000901',
   '018f0000-0000-7000-8000-000000000902',
   'metadata_changed', 'repository_analysis', 'fixture-completed'),
  ('018f0000-0000-7000-8000-000000000905',
   'user:018f0000-0000-7000-8000-000000000901',
   '018f0000-0000-7000-8000-000000000903',
   'metadata_changed', 'repository_analysis', 'fixture-failed');

insert into github_catalog.repository_analysis_requests
  (request_id, watch_id, owner_ref, repository_id, github_repository_numeric_id,
   source_revision, repository_attributes, request_payload, attributes_digest_hex,
   idempotency_digest_hex, requested_contract, status, not_before)
values
  (
    '018f0000-0000-7000-8000-000000000911',
    '018f0000-0000-7000-8000-000000000904',
    'user:018f0000-0000-7000-8000-000000000901',
    '018f0000-0000-7000-8000-000000000902',
    99002,
    '{"attributes_digest":{"algorithm":"sha256","hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"readme":{"state":"absent","reason":"not_found"}}',
    '{"repository_full_name":"fixture/completed","description":"synthetic completion","primary_language":"Rust"}',
    '{"owner":"user:018f0000-0000-7000-8000-000000000901","repository_id":"018f0000-0000-7000-8000-000000000902","github_repository_numeric_id":99002,"request_id":"018f0000-0000-7000-8000-000000000911","source_revision":{"attributes_digest":{"algorithm":"sha256","hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"readme":{"state":"absent","reason":"not_found"}},"repository_attributes":{"repository_full_name":"fixture/completed","description":"synthetic completion","primary_language":"Rust"},"requested_contract":"repository_analysis","idempotency_key":{"algorithm":"sha256","hex":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}}',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'repository_analysis', 'queued', now()
  ),
  (
    '018f0000-0000-7000-8000-000000000912',
    '018f0000-0000-7000-8000-000000000905',
    'user:018f0000-0000-7000-8000-000000000901',
    '018f0000-0000-7000-8000-000000000903',
    99003,
    '{"attributes_digest":{"algorithm":"sha256","hex":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"readme":{"state":"absent","reason":"not_found"}}',
    '{"repository_full_name":"fixture/failed","description":"synthetic failure","primary_language":"Rust"}',
    '{"owner":"user:018f0000-0000-7000-8000-000000000901","repository_id":"018f0000-0000-7000-8000-000000000903","github_repository_numeric_id":99003,"request_id":"018f0000-0000-7000-8000-000000000912","source_revision":{"attributes_digest":{"algorithm":"sha256","hex":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"readme":{"state":"absent","reason":"not_found"}},"repository_attributes":{"repository_full_name":"fixture/failed","description":"synthetic failure","primary_language":"Rust"},"requested_contract":"repository_analysis","idempotency_key":{"algorithm":"sha256","hex":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    'repository_analysis', 'queued', now()
  );

insert into github_catalog.backup_policies
  (backup_policy_id, repository_id, policy_level, mirror_cadence, priority_hint,
   size_hint_bytes, exclusions)
values
  ('018f0000-0000-7000-8000-000000000907',
   '018f0000-0000-7000-8000-000000000906',
   'git_mirror', 'daily', 'standard', 1024,
   '[{"scope":"refs_matching","expression":"refs/heads/scratch/*"}]');

insert into github_catalog.backup_policy_publication_cursor
  (scope, dirty_generation, published_generation, not_before)
values ('catalog', 1, 0, now() - interval '1 second')
on conflict (scope) do update
set dirty_generation = greatest(
      github_catalog.backup_policy_publication_cursor.dirty_generation,
      github_catalog.backup_policy_publication_cursor.published_generation
    ) + 1,
    not_before = now() - interval '1 second';
