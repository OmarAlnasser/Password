-- VaultSnap schema. Supabase is used only for auth and encrypted blobs.
-- Every table has Row Level Security; users can only touch rows whose
-- user_id equals auth.uid().

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Key header: salt, KDF params and wrapped vault keys (no secrets).
-- ---------------------------------------------------------------------------
create table if not exists public.vault_headers (
  user_id uuid primary key default auth.uid()
    references auth.users (id) on delete cascade,
  header jsonb not null,
  -- sha256(recovery auth secret); used by the `recover` edge function.
  recovery_auth_hash text,
  updated_at timestamptz not null default now(),
  constraint header_size check (pg_column_size(header) < 8192)
);

alter table public.vault_headers enable row level security;
alter table public.vault_headers force row level security;

create policy "headers: owner can read"
  on public.vault_headers for select to authenticated
  using (user_id = (select auth.uid()));
create policy "headers: owner can insert"
  on public.vault_headers for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "headers: owner can update"
  on public.vault_headers for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- No delete policy: headers go away only with the auth user (cascade).

-- Clients must never be able to read the recovery hash back. A column-level
-- REVOKE is ineffective while a table-level SELECT grant exists (Supabase
-- grants ALL by default), so revoke the table grant and re-grant columns.
revoke all on public.vault_headers from anon, authenticated;
grant select (user_id, header, updated_at) on public.vault_headers to authenticated;
grant insert (user_id, header, recovery_auth_hash) on public.vault_headers to authenticated;
grant update (header, recovery_auth_hash, updated_at) on public.vault_headers to authenticated;

-- ---------------------------------------------------------------------------
-- Encrypted items.
-- ---------------------------------------------------------------------------
create sequence if not exists public.vault_items_seq;

create table if not exists public.vault_items (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  id uuid not null,
  payload text,                     -- base64 XChaCha20-Poly1305 envelope
  deleted boolean not null default false,
  revision bigint not null default 1,
  seq bigint not null default nextval('public.vault_items_seq'),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint payload_size check (payload is null or length(payload) <= 1048576),
  constraint tombstone_shape check (
    (deleted and payload is null) or (not deleted and payload is not null)
  )
);

create index if not exists vault_items_user_seq on public.vault_items (user_id, seq);

alter table public.vault_items enable row level security;
alter table public.vault_items force row level security;

create policy "items: owner can read"
  on public.vault_items for select to authenticated
  using (user_id = (select auth.uid()));
-- Writes go through push_item(); direct insert/update are still restricted
-- to the owner as defence in depth.
create policy "items: owner can insert"
  on public.vault_items for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "items: owner can update"
  on public.vault_items for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- No delete policy: deletion is a tombstone (deleted = true).

revoke all on public.vault_items from anon;
revoke delete on public.vault_items from authenticated;

-- Server-assigned bookkeeping: clients cannot choose revision / seq /
-- updated_at / user_id.
create or replace function public.vault_items_bookkeeping()
returns trigger language plpgsql as $$
begin
  new.user_id := auth.uid();
  new.seq := nextval('public.vault_items_seq');
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.revision := 1;
  else
    if new.id <> old.id then
      raise exception 'id is immutable';
    end if;
    new.revision := old.revision + 1;
  end if;
  return new;
end $$;

drop trigger if exists vault_items_bookkeeping on public.vault_items;
create trigger vault_items_bookkeeping
  before insert or update on public.vault_items
  for each row execute function public.vault_items_bookkeeping();

-- Optimistic-concurrency write. SECURITY INVOKER: runs with the caller's
-- rights, so RLS applies to everything it touches.
create or replace function public.push_item(
  p_id uuid,
  p_payload text,
  p_deleted boolean,
  p_base_revision bigint
)
returns table (
  id uuid, payload text, deleted boolean, revision bigint, seq bigint,
  updated_at timestamptz, conflict boolean
)
language plpgsql security invoker set search_path = '' as $$
declare
  cur public.vault_items%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into cur from public.vault_items v
    where v.user_id = auth.uid() and v.id = p_id
    for update;

  if not found then
    if p_base_revision <> 0 then
      -- Client thinks the row exists but it does not: treat as conflict
      -- with an empty tombstone so the client re-creates it.
      return query select p_id, null::text, true, 0::bigint, 0::bigint,
        now(), true;
      return;
    end if;
    insert into public.vault_items as v (id, payload, deleted)
      values (p_id, case when p_deleted then null else p_payload end, p_deleted)
      returning v.* into cur;
    return query select cur.id, cur.payload, cur.deleted, cur.revision,
      cur.seq, cur.updated_at, false;
    return;
  end if;

  if cur.revision <> p_base_revision then
    return query select cur.id, cur.payload, cur.deleted, cur.revision,
      cur.seq, cur.updated_at, true;
    return;
  end if;

  update public.vault_items as v
    set payload = case when p_deleted then null else p_payload end,
        deleted = p_deleted
    where v.user_id = auth.uid() and v.id = p_id
    returning v.* into cur;
  return query select cur.id, cur.payload, cur.deleted, cur.revision,
    cur.seq, cur.updated_at, false;
end $$;

revoke all on function public.push_item(uuid, text, boolean, bigint) from public, anon;
grant execute on function public.push_item(uuid, text, boolean, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Pre-login: salt + KDF params for an email, before authentication.
-- Unknown emails get a deterministic fake salt (HMAC of the email with a
-- server secret) so the response does not reveal whether an account exists.
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.settings (
  name text primary key,
  value text not null
);
insert into private.settings (name, value)
  values ('prelogin_secret', encode(extensions.gen_random_bytes(32), 'hex'))
  on conflict (name) do nothing;

create or replace function public.prelogin(p_email text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  h jsonb;
  secret text;
begin
  select vh.header into h
    from public.vault_headers vh
    join auth.users u on u.id = vh.user_id
    where lower(u.email) = lower(trim(p_email));
  if h is not null then
    return jsonb_build_object('salt', h->'salt', 'kdf', h->'kdf');
  end if;
  select value into secret from private.settings where name = 'prelogin_secret';
  return jsonb_build_object(
    'salt', encode(substring(extensions.hmac(lower(trim(p_email)), secret, 'sha256') from 1 for 16), 'base64'),
    'kdf', jsonb_build_object('v', 1, 'ops', 3, 'mem', 67108864)
  );
end $$;

revoke all on function public.prelogin(text) from public;
grant execute on function public.prelogin(text) to anon, authenticated;

-- Used only by the `recover` edge function (service role).
create or replace function public.user_id_by_email(p_email text)
returns uuid
language sql security definer set search_path = '' as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1
$$;
revoke all on function public.user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.user_id_by_email(text) to service_role;
