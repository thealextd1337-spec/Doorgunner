-- Migration 8: error reporting (docs/ROADMAP2.md Q2). Idempotent: run after 001-007.
-- The client (scripts/error_report.gd) sends script errors / browser errors through report_error. Same (version, message)
-- is one row with count += 1. Clients never read or write the table; look at it in the dashboard (server/README.md).
-- Errors: error_invalid (empty message) | rate_limit. No IP headers are trusted, so anonymous callers share one hourly budget.

create table if not exists public.errors (
  id        bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  player_id uuid,                                    -- reporter of the FIRST occurrence, null if anonymous; no FK: delete_me nulls it
  version   text not null default '',
  platform  text not null default '',
  message   text not null,
  stack     text not null default '',
  count     int  not null default 1
);
create unique index if not exists errors_version_message_idx on public.errors (version, message);
create index if not exists errors_player_idx on public.errors (player_id) where player_id is not null;

-- Calls per bucket (a player id, or 'anon') and hour. Old hours are swept by report_error.
create table if not exists public.error_rate (
  bucket text not null,
  hr     timestamptz not null,
  n      int not null default 0,
  primary key (bucket, hr)
);

alter table public.errors     enable row level security;
alter table public.error_rate enable row level security;
revoke all on public.errors, public.error_rate from anon, authenticated; -- no policies either: dashboard / owner only

create or replace function public.report_error(p_version text, p_platform text, p_message text, p_stack text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c_player_per_hour constant int := 20;
  c_anon_per_hour constant int := 200;     -- all callers without a sign-in together
  c_max_rows constant int := 20000;        -- distinct errors kept; beyond that only known ones are counted
  c_max_message constant int := 500;
  c_max_stack constant int := 4000;
  uid uuid := auth.uid();
  v_bucket text := coalesce(uid::text, 'anon');
  v_hr timestamptz := date_trunc('hour', now());
  v_n int;
  v_version text := left(coalesce(p_version, ''), 32);
  v_message text := left(coalesce(p_message, ''), c_max_message);
begin
  if btrim(v_message) = '' then raise exception 'error_invalid'; end if;

  insert into public.error_rate as r (bucket, hr, n) values (v_bucket, v_hr, 1)
    on conflict (bucket, hr) do update set n = r.n + 1
    returning r.n into v_n;
  if v_n > case when uid is null then c_anon_per_hour else c_player_per_hour end then
    raise exception 'rate_limit'; -- also rolls the increment back
  end if;
  if random() < 0.05 then
    delete from public.error_rate where hr < v_hr - interval '2 hours';
  end if;

  update public.errors set count = count + 1, last_seen = now()
   where version = v_version and message = v_message;
  if found then return; end if;
  if (select count(*) from public.errors) >= c_max_rows then return; end if;
  insert into public.errors (player_id, version, platform, message, stack)
  values (uid, v_version, left(coalesce(p_platform, ''), 32), v_message, left(coalesce(p_stack, ''), c_max_stack))
  on conflict (version, message) do update set count = public.errors.count + 1, last_seen = now();
end $$;

revoke execute on function public.report_error(text, text, text, text) from public, anon, authenticated;
grant execute on function public.report_error(text, text, text, text) to anon, authenticated;

-- delete_me as in 003, plus: the player's error rows lose the id and their rate counter goes.
create or replace function public.delete_me() returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  update public.errors set player_id = null where player_id = uid;
  delete from public.error_rate where bucket = uid::text;
  delete from public.players where id = uid;
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.delete_me() from public, anon, authenticated;
grant execute on function public.delete_me() to authenticated;
