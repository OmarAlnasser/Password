-- Cross-tenant attack tests. Alice tries to read / modify Bob's data.
-- Every check prints PASS or FAIL; the runner fails on any FAIL.
\set QUIET on
\set ON_ERROR_STOP on
set client_min_messages = notice;

create table public._results (n serial, label text, ok boolean, detail text);
grant all on public._results to anon, authenticated;
grant all on sequence public._results_n_seq to anon, authenticated;

-- expect the statement to raise an error
create function public._expect_error(label text, stmt text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    insert into public._results(label, ok, detail) values (label, true, sqlerrm);
    return;
  end;
  insert into public._results(label, ok, detail) values (label, false, 'statement succeeded');
end $$;

-- expect the query to return exactly n
create function public._expect_count(label text, q text, n bigint) returns void
language plpgsql as $$
declare got bigint;
begin
  begin
    execute 'select count(*) from (' || q || ') t' into got;
  exception when others then
    insert into public._results(label, ok, detail) values (label, false, 'error: ' || sqlerrm);
    return;
  end;
  insert into public._results(label, ok, detail)
    values (label, got = n, format('expected %s, got %s', n, got));
end $$;
-- run a DML statement and expect exactly n affected rows
create function public._expect_rows(label text, stmt text, n bigint) returns void
language plpgsql as $$
declare got bigint;
begin
  begin
    execute stmt;
    get diagnostics got = row_count;
  exception when others then
    insert into public._results(label, ok, detail) values (label, false, 'error: ' || sqlerrm);
    return;
  end;
  insert into public._results(label, ok, detail)
    values (label, got = n, format('expected %s rows, got %s', n, got));
end $$;
grant execute on function public._expect_error(text, text), public._expect_count(text, text, bigint), public._expect_rows(text, text, bigint) to anon, authenticated;

\set alice '''aaaaaaaa-0000-0000-0000-000000000001'''
\set bob   '''bbbbbbbb-0000-0000-0000-000000000002'''

-- ---------------------------------------------------------------- seed Bob
set role authenticated;
select set_config('request.jwt.claim.sub', :bob, false);
insert into public.vault_headers (header, recovery_auth_hash)
  values ('{"kdf":{"v":1,"ops":3,"mem":67108864},"salt":"Qk9CU0FMVEJPQlNBTFQxMg==","vk_pw":"x","vk_rc":"y"}', repeat('b', 64));
select * from public.push_item('11111111-1111-1111-1111-111111111111', 'Ym9iLWNpcGhlcnRleHQ=', false, 0);
select * from public.push_item('22222222-2222-2222-2222-222222222222', 'Ym9iLTI=', false, 0);

-- ---------------------------------------------------------------- seed Alice
select set_config('request.jwt.claim.sub', :alice, false);
insert into public.vault_headers (header) values ('{"kdf":{"v":1,"ops":3,"mem":67108864},"salt":"QUxJQ0VTQUxUQUxJQ0VTQQ==","vk_pw":"x","vk_rc":"y"}');
select * from public.push_item('33333333-3333-3333-3333-333333333333', 'YWxpY2U=', false, 0);

-- ================================================================ READ
select public._expect_count('R1 alice sees only her items', 'select * from public.vault_items', 1);
select public._expect_count('R2 alice filtering by bob user_id sees nothing',
  'select * from public.vault_items where user_id = ''bbbbbbbb-0000-0000-0000-000000000002''', 0);
select public._expect_count('R3 alice reading bob item by id sees nothing',
  'select * from public.vault_items where id = ''11111111-1111-1111-1111-111111111111''', 0);
select public._expect_count('R4 alice sees only her header', 'select user_id, header from public.vault_headers', 1);
select public._expect_error('R5 recovery_auth_hash column not readable',
  'select recovery_auth_hash from public.vault_headers');
select public._expect_error('R6 select * on headers denied (includes hash column)',
  'select * from public.vault_headers');
select public._expect_error('R7 private.settings not readable', 'select * from private.settings');
select public._expect_error('R8 user_id_by_email not callable', 'select public.user_id_by_email(''bob@example.com'')');
select public._expect_error('R9 auth.users not readable', 'select * from auth.users');

-- ================================================================ WRITE
select public._expect_rows('W1 update bob payload affects 0 rows',
  'update public.vault_items set payload = ''cHduZWQ='' where user_id = ''bbbbbbbb-0000-0000-0000-000000000002''', 0);
select public._expect_error('W2 delete is not permitted at all',
  'delete from public.vault_items where user_id = ''bbbbbbbb-0000-0000-0000-000000000002''');
select public._expect_rows('W3 update bob header affects 0 rows',
  'update public.vault_headers set header = ''{}'' where user_id = ''bbbbbbbb-0000-0000-0000-000000000002''', 0);
select public._expect_error('W4 insert header for bob rejected',
  'insert into public.vault_headers (user_id, header) values (''bbbbbbbb-0000-0000-0000-000000000002'', ''{}'')');
-- forged user_id on insert is rewritten to the caller by the trigger
select public._expect_rows('W5a insert with forged user_id is accepted...',
  'insert into public.vault_items (user_id, id, payload) values (''bbbbbbbb-0000-0000-0000-000000000002'', ''44444444-4444-4444-4444-444444444444'', ''eA=='')', 1);
select public._expect_count('W5b ...but lands in alice''s own rows',
  'select * from public.vault_items where id = ''44444444-4444-4444-4444-444444444444''', 1);
select public._expect_rows('W6a update own row user_id to bob',
  'update public.vault_items set user_id = ''bbbbbbbb-0000-0000-0000-000000000002'' where id = ''33333333-3333-3333-3333-333333333333''', 1);
select public._expect_count('W6b row still belongs to alice',
  'select * from public.vault_items where id = ''33333333-3333-3333-3333-333333333333''', 1);
-- push_item with bob's item id only creates/updates alice's own row
select * from public.push_item('11111111-1111-1111-1111-111111111111', 'YXR0YWNr', false, 0);
select public._expect_rows('W7a update own revision to 999',
  'update public.vault_items set revision = 999 where id = ''33333333-3333-3333-3333-333333333333''', 1);
select public._expect_count('W7b revision was not forged',
  'select * from public.vault_items where id = ''33333333-3333-3333-3333-333333333333'' and revision = 999', 0);
select public._expect_error('W8 payload over 1 MiB rejected',
  'select public.push_item(''55555555-5555-5555-5555-555555555555'', repeat(''A'', 1048577), false, 0)');
select public._expect_error('W9 live row without payload rejected',
  'insert into public.vault_items (id, payload, deleted) values (''66666666-6666-6666-6666-666666666666'', null, false)');
select public._expect_error('W10 alice cannot overwrite recovery hash of bob via upsert',
  'insert into public.vault_headers (user_id, header, recovery_auth_hash) values (''bbbbbbbb-0000-0000-0000-000000000002'', ''{}'', ''x'') on conflict (user_id) do update set recovery_auth_hash = ''x''');

-- ================================================================ SEQUENCE (cross-tenant side effects)
select public._expect_error('S1 setval on the shared change sequence denied',
  'select setval(''public.vault_items_seq'', 1)');
select public._expect_error('S2 setval on the shared change sequence (large) denied',
  'select setval(''public.vault_items_seq'', 9000000000000000000)');

-- ================================================================ ANON
reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select public._expect_error('A1 anon cannot read items', 'select * from public.vault_items');
select public._expect_error('A2 anon cannot read headers', 'select user_id, header from public.vault_headers');
select public._expect_error('A3 anon cannot push', 'select public.push_item(''77777777-7777-7777-7777-777777777777'', ''eA=='', false, 0)');
select public._expect_count('A4 prelogin works for anon', 'select public.prelogin(''bob@example.com'')', 1);
select public._expect_count('A5 prelogin unknown email gives the same shape',
  'select 1 where (select jsonb_object_keys(public.prelogin(''nobody@example.com'')) limit 1) is not null', 1);
select public._expect_count('A6 prelogin fake salt is deterministic',
  'select 1 where public.prelogin(''nobody@example.com'') = public.prelogin(''nobody@example.com'')', 1);
select public._expect_count('A7 prelogin fake salt decodes to 16 bytes',
  'select 1 where length(decode(public.prelogin(''nobody@example.com'')->>''salt'', ''base64'')) = 16', 1);

-- ================================================================ Bob's data is intact
reset role;
select public._expect_count('I0 bob row 1111 still bob''s and unmodified by alice push',
  'select * from public.vault_items where user_id = ''bbbbbbbb-0000-0000-0000-000000000002'' and id = ''11111111-1111-1111-1111-111111111111'' and payload = ''Ym9iLWNpcGhlcnRleHQ='' and revision = 1', 1);
select public._expect_count('I1 bob still has exactly 2 items',
  'select * from public.vault_items where user_id = ''bbbbbbbb-0000-0000-0000-000000000002''', 2);
select public._expect_count('I2 bob payloads untouched',
  'select * from public.vault_items where user_id = ''bbbbbbbb-0000-0000-0000-000000000002'' and payload in (''Ym9iLWNpcGhlcnRleHQ='', ''Ym9iLTI='')', 2);
select public._expect_count('I3 bob header untouched',
  'select * from public.vault_headers where user_id = ''bbbbbbbb-0000-0000-0000-000000000002'' and recovery_auth_hash = repeat(''b'', 64)', 1);

\set QUIET off
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from public._results order by n;
select count(*) filter (where not ok) as failures, count(*) as total from public._results;
