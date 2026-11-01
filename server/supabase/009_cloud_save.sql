-- Migration 9 (Q3): cloud backup of the saved run. Safe to re-run. Needs 001-004.
-- One row per (player, slot): slot is 'run' (and 'daily' for Q14). data is the client's compressed save, base64 over the
-- API (PostgREST has no bytea in JSON), stored as bytea, at most 2 MB. Only the RPCs touch data; nobody reads others' rows.
-- delete_me is NOT rewritten (Q2 edits it in parallel): the FK to players below cascades when delete_me removes the player.
-- Errors (message = code): not_authenticated | no_player | slot_invalid | save_invalid | save_too_large | rate_limit

create table if not exists public.cloud_saves (
  player_id  uuid not null references public.players(id) on delete cascade,
  slot       text not null check (slot in ('run', 'daily')),
  updated_at timestamptz not null default now(),
  version    text not null default '',
  format     int  not null default 0,
  data       bytea not null check (octet_length(data) <= 2097152),
  primary key (player_id, slot)
);

alter table public.cloud_saves enable row level security;
revoke all on public.cloud_saves from anon, authenticated;
-- A player may list their own slots (not the data column); everything else goes through the RPCs.
grant select (player_id, slot, updated_at, version, format) on public.cloud_saves to authenticated;
drop policy if exists cloud_saves_read_own on public.cloud_saves;
create policy cloud_saves_read_own on public.cloud_saves for select to authenticated using (player_id = auth.uid());

create or replace function public.put_save(p_slot text, p_data text, p_version text, p_format int) returns timestamptz
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c_max_bytes constant int := 2097152;
  c_min_seconds constant int := 30;   -- between two puts of one slot (the client sends every 5 min)
  uid uuid := auth.uid();
  bytes bytea;
  prev timestamptz;
  t timestamptz;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.players where id = uid) then raise exception 'no_player'; end if;
  if p_slot is null or p_slot not in ('run', 'daily') then raise exception 'slot_invalid'; end if;
  if p_data is null or p_data = '' or p_format is null or p_format < 0 or p_format > 1000000 then raise exception 'save_invalid'; end if;
  if length(p_data) > c_max_bytes * 4 / 3 + 16 then raise exception 'save_too_large'; end if; -- before decoding
  begin
    bytes := decode(p_data, 'base64');
  exception when others then
    raise exception 'save_invalid';
  end;
  if octet_length(bytes) > c_max_bytes then raise exception 'save_too_large'; end if;
  select updated_at into prev from public.cloud_saves where player_id = uid and slot = p_slot for update;
  if found and now() - prev < make_interval(secs => c_min_seconds) then raise exception 'rate_limit'; end if;
  insert into public.cloud_saves (player_id, slot, updated_at, version, format, data)
  values (uid, p_slot, now(), left(coalesce(p_version, ''), 32), p_format, bytes)
  on conflict (player_id, slot) do update
    set updated_at = excluded.updated_at, version = excluded.version, format = excluded.format, data = excluded.data
  returning updated_at into t;
  return t;
end $$;

-- {updated_at, version, format, data (base64)} or null when the slot is empty. p_meta_only leaves data out (the title
-- asks first, the download happens only on RESTORE).
create or replace function public.get_save(p_slot text, p_meta_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  r public.cloud_saves;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into r from public.cloud_saves where player_id = uid and slot = p_slot;
  if not found then return null; end if;
  return jsonb_build_object('updated_at', r.updated_at, 'version', r.version, 'format', r.format)
    || case when p_meta_only then '{}'::jsonb else jsonb_build_object('data', encode(r.data, 'base64')) end;
end $$;

create or replace function public.delete_save(p_slot text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  delete from public.cloud_saves where player_id = uid and slot = p_slot;
end $$;

revoke execute on function public.put_save(text, text, text, int), public.get_save(text, boolean), public.delete_save(text)
  from public, anon, authenticated;
grant execute on function public.put_save(text, text, text, int), public.get_save(text, boolean), public.delete_save(text)
  to authenticated;
