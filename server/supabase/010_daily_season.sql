-- Migration 10 (Q14): daily seed + weekly season. Safe to re-run. Needs 001-007 and 009.
-- The daily: one row per UTC date (seed, modifiers, start heli), made on first demand by daily_for() from the date and a
-- server secret (table daily_secret, unreadable through the API), so nobody can compute a future day's world.
-- get_daily() shows today's modifiers and heli (never the seed); start_daily(run_id) reveals the seed at run start and
-- claims the player's ONE ranked attempt of the day (first start counts; later starts get the seed but ranked = false).
-- A claimed attempt must reach the runs table within an hour (upsert_run at run start), else it counts as practice: nobody
-- can take the seed, practise the world offline and hand in the best try under the ranked id later.
-- upsert_run (007) is NOT rewritten: a BEFORE INSERT trigger on runs turns the claimed run id into a daily run (mode,
-- daily_date, the daily's modifiers and the points for them). All of upsert_run's checks stay as they are.
-- Season = ISO week (UTC) of a run's start, over all runs. Views leaderboard_daily / leaderboard_season have the column
-- daily_date / season_week; the client filters with ?daily_date=eq.2026-11-02 or ?season_week=eq.2026-W45.
-- Errors (message = code): not_authenticated | no_player | run_invalid

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.daily_secret (
  id     boolean primary key default true check (id),            -- exactly one row
  secret bytea not null default extensions.gen_random_bytes(32)
);
insert into public.daily_secret default values on conflict do nothing;

create table if not exists public.daily (
  date      date primary key,
  seed      int  not null check (seed >= 0),
  modifiers text[] not null default '{}',
  heli      text not null
);

create table if not exists public.daily_attempts ( -- the ranked attempt of a player per day
  player_id  uuid not null references public.players(id) on delete cascade,
  date       date not null references public.daily(date),
  run_id     uuid not null unique,
  started_at timestamptz not null default now(),
  primary key (player_id, date)
);

alter table public.runs add column if not exists mode text not null default 'normal';
alter table public.runs add column if not exists daily_date date;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'runs_mode_check') then
    alter table public.runs add constraint runs_mode_check
      check (mode in ('normal', 'daily') and (mode = 'daily') = (daily_date is not null));
  end if;
end $$;
create index if not exists runs_daily_idx on public.runs (daily_date, points desc) where daily_date is not null;

-- RLS on, no policy, no grant: secret, seeds and attempts only through the functions below.
alter table public.daily_secret   enable row level security;
alter table public.daily          enable row level security;
alter table public.daily_attempts enable row level security;
revoke all on public.daily_secret, public.daily, public.daily_attempts from anon, authenticated;

-- The daily of p_date, made once (deterministic from date + secret; stored so later changes to modifiers keep it).
create or replace function public.daily_for(p_date date) returns public.daily
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c_helis constant text[] := array['huey', 'little_bird', 'black_hawk', 'chinook', 'hind']; -- scripts/heli_types.gd TYPES
  c_max_mods constant int := 2;
  k bytea;
  h bytea;
  mods text[];
  r public.daily;
begin
  select * into r from public.daily where date = p_date;
  if found then return r; end if;
  select secret into k from public.daily_secret;
  h := hmac(convert_to('daily:' || p_date::text, 'UTF8'), k, 'sha256');
  select coalesce(array_agg(id order by id), '{}') into mods from (
    select id from public.modifiers order by hmac(convert_to(p_date::text || ':' || id, 'UTF8'), k, 'sha256')
    limit 1 + get_byte(h, 4) % c_max_mods) s;
  insert into public.daily (date, seed, modifiers, heli)
  values (p_date, ((get_byte(h, 0) & 127) << 24) | (get_byte(h, 1) << 16) | (get_byte(h, 2) << 8) | get_byte(h, 3),
          mods, c_helis[1 + get_byte(h, 5) % array_length(c_helis, 1)])
  on conflict (date) do nothing;
  select * into r from public.daily where date = p_date;
  return r;
end $$;

-- Today's daily without the seed: {date, season_week, modifiers, heli, played, resets_in (s)}.
create or replace function public.get_daily() returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'utc')::date;
  d public.daily;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  d := public.daily_for(today);
  return jsonb_build_object('date', d.date, 'season_week', to_char(today, 'IYYY-"W"IW'), 'modifiers', to_jsonb(d.modifiers),
    'heli', d.heli, 'played', exists (select 1 from public.daily_attempts where player_id = uid and date = today),
    'resets_in', floor(extract(epoch from (today + 1)::timestamp - (now() at time zone 'utc')))::int);
end $$;

-- Run start of a daily: {date, seed, modifiers, heli, ranked}. The first call of the day binds p_run_id as the ranked
-- attempt (a retry with the same id stays ranked); every later start is practice. p_run_id must be a new run id.
create or replace function public.start_daily(p_run_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'utc')::date;
  d public.daily;
  ranked boolean;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.players where id = uid) then raise exception 'no_player'; end if;
  if p_run_id is null or exists (select 1 from public.runs where id = p_run_id) then raise exception 'run_invalid'; end if;
  d := public.daily_for(today);
  insert into public.daily_attempts (player_id, date, run_id) values (uid, today, p_run_id) on conflict do nothing;
  select coalesce(bool_or(run_id = p_run_id and started_at > now() - interval '1 hour'), false) into ranked
    from public.daily_attempts where player_id = uid and date = today;
  return jsonb_build_object('date', d.date, 'seed', d.seed, 'modifiers', to_jsonb(d.modifiers), 'heli', d.heli, 'ranked', ranked);
end $$;

-- upsert_run's insert of a claimed run id: daily mode, its date, the daily's modifiers (whatever the client sent) and
-- the points for them (same factor formula and cap 3 as upsert_run). Later updates keep the stored modifiers.
create or replace function public.runs_bind_daily() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  a public.daily_attempts;
  mods text[];
  factor numeric;
begin
  new.mode := 'normal';
  new.daily_date := null;
  select * into a from public.daily_attempts where run_id = new.id and player_id = new.player_id
    and started_at > now() - interval '1 hour'; -- an older claim without a run row: practice
  if found then
    select modifiers into mods from public.daily where date = a.date;
    select least(round(coalesce(exp(sum(ln(m.factor))), 1), 4), 3) into factor from public.modifiers m where m.id = any(mods);
    new.mode := 'daily';
    new.daily_date := a.date;
    new.modifiers := mods;
    new.points := public.run_points(new.day, new.rescued, new.kills, new.victory, factor);
  end if;
  return new;
end $$;
drop trigger if exists runs_bind_daily on public.runs;
create trigger runs_bind_daily before insert on public.runs for each row execute function public.runs_bind_daily();

-- 009's trigger: an ended daily run drops the 'daily' cloud slot, a normal one the 'run' slot.
create or replace function public.cloud_saves_drop_ended_run() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.ended and (tg_op = 'INSERT' or not old.ended) then
    delete from public.cloud_saves where player_id = new.player_id and slot = case when new.mode = 'daily' then 'daily' else 'run' end;
  end if;
  return null;
end $$;

revoke execute on function public.daily_for(date), public.get_daily(), public.start_daily(uuid), public.runs_bind_daily(),
  public.cloud_saves_drop_ended_run() from public, anon, authenticated;
grant execute on function public.get_daily(), public.start_daily(uuid) to authenticated;

-- Boards. Owner's rights like 005 (they read all runs), hidden players left out before ranking.
create or replace view public.leaderboard_daily as
  select r.daily_date, rank() over (partition by r.daily_date order by r.points desc)::int as rank, p.id as player_id,
         p.name::text as name, p.avatar, r.points::bigint as value, r.day, r.victory, r.ended
  from public.runs r join public.players p on p.id = r.player_id
  where r.mode = 'daily' and not p.hidden;

-- shortcut: season_week is computed per row (no index); add a stored week column if the runs table grows past ~1M rows.
create or replace view public.leaderboard_season as
  select to_char(r.started_at at time zone 'utc', 'IYYY-"W"IW') as season_week,
         rank() over (partition by to_char(r.started_at at time zone 'utc', 'IYYY-"W"IW') order by sum(r.points) desc)::int as rank,
         p.id as player_id, p.name::text as name, p.avatar, sum(r.points)::bigint as value
  from public.runs r join public.players p on p.id = r.player_id
  where not p.hidden
  group by 1, p.id;

revoke all on public.leaderboard_daily, public.leaderboard_season from anon, authenticated;
grant select on public.leaderboard_daily, public.leaderboard_season to anon, authenticated;
