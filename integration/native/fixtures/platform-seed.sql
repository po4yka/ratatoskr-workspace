-- SEEDED principals of the native smoke, labelled as seeded in every result.txt. Modelled on integration/fixtures/export-agent-product-runtime.sql, with the columns read from platform/schema.sql. Token hashes are the sha256 of per-run random credentials (psql variables h1, h2, hm, hd); the device secret hash is ds. Run as the PostgreSQL administrator after Edge has applied schema.sql.
insert into identity.users (user_id, status, created_at, updated_at) values
 ('01980000-0000-7000-8000-000000000001', 'active', now(), now()),
 ('01980000-0000-7000-8000-000000000002', 'active', now(), now())
on conflict (user_id) do nothing;

insert into identity.registered_devices (device_id, user_id, kind, display_name, secret_hash, created_at) values
 ('01980000-0000-7000-8000-0000000000d1', '01980000-0000-7000-8000-000000000001', 'browser_extension', 'seeded extension', decode(:'ds', 'hex'), now())
on conflict (device_id) do nothing;

insert into identity.sessions (session_id, user_id, kind, device_id, audience, issued_at, expires_at, token_hash) values
 ('01980000-0000-7000-8000-0000000000a1', '01980000-0000-7000-8000-000000000001', 'browser', null, 'edge', now(), now() + interval '6 hours', decode(:'h1', 'hex')),
 ('01980000-0000-7000-8000-0000000000a2', '01980000-0000-7000-8000-000000000002', 'browser', null, 'edge', now(), now() + interval '6 hours', decode(:'h2', 'hex')),
 ('01980000-0000-7000-8000-0000000000a3', '01980000-0000-7000-8000-000000000001', 'telegram_mini_app', null, 'edge', now(), now() + interval '6 hours', decode(:'hm', 'hex')),
 ('01980000-0000-7000-8000-0000000000a4', '01980000-0000-7000-8000-000000000001', 'device', '01980000-0000-7000-8000-0000000000d1', 'edge', now(), now() + interval '6 hours', decode(:'hd', 'hex'))
on conflict (session_id) do nothing;
