-- Migration 7: balance pass of 1.0.0-beta (docs/ROADMAP.md P18). Idempotent (create or replace): run after 001-006.
-- Numbers come from the 40-day bot runs of tests/longrun_test.gd (build/longrun.csv, seeds 1-4):
--   kills per day of the run (cumulative / day): at most ~90, the best single day ~330 (a blood moon)
--   rescued per day (cumulative / day): at most ~19 (day 1, a settlement next to the base walks in)
--   points at day 40: ~9 000-11 500, about a third each from days, rescued and kills.
-- Changes against 004:
--   run_points: a victory (evacuation, reachable from ~day 18) is worth 5000 instead of 2000, half a long run.
--   upsert_run: the day bound follows the real 900 s day: the first day may be cut short (the tutorial jumps to the
--   evening, ~180 s), every later day needs at least 810 s (90 %); kills are capped at 300 per day (was 400).
--   Rescued stays at 60 per day (founding next to a city brings three settlements in at once).

create or replace function public.run_points(p_day int, p_rescued int, p_kills int, p_victory boolean, p_factor numeric default 1)
returns int language sql immutable as $$
  select floor((p_day * 100 + p_rescued * 25 + p_kills + case when p_victory then 5000 else 0 end) * p_factor)::int
$$;

create or replace function public.upsert_run(
  p_run_id uuid, p_day int, p_rescued int, p_kills int, p_ended boolean, p_victory boolean,
  p_modifiers text[], p_version text) returns int
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  -- A game day lasts 900 s (DAY_SECONDS). Day 2 may come after c_first_day_seconds (tutorial), each later day
  -- after another c_min_day_seconds.
  c_first_day_seconds constant int := 180;
  c_min_day_seconds constant int := 810;
  c_max_kills_per_day constant int := 300;
  c_max_rescued_per_day constant int := 60;
  c_min_sync_seconds constant int := 30;       -- between two upserts of one run (the final ended=true call is exempt)
  c_max_new_runs_per_day constant int := 20;
  c_max_factor constant numeric := 3;          -- cap of the combined modifier factor (P15)
  uid uuid := auth.uid();
  r public.runs;
  mods text[];
  factor numeric;
  elapsed numeric;
  max_day bigint;
  v_day int; v_rescued int; v_kills int; v_victory boolean;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.players where id = uid) then raise exception 'no_player'; end if;
  if p_run_id is null or p_day is null or p_rescued is null or p_kills is null
     or p_ended is null or p_victory is null
     or p_day < 1 or p_rescued < 0 or p_kills < 0 or p_day > 100000 or p_rescued > 100000000 or p_kills > 100000000 then
    raise exception 'run_invalid';
  end if;

  select * into r from public.runs where id = p_run_id for update;
  if found then
    if r.player_id <> uid then raise exception 'not_your_run'; end if;
    if r.ended then raise exception 'run_ended'; end if;
    if not p_ended and now() - r.updated_at < make_interval(secs => c_min_sync_seconds) then
      raise exception 'rate_limit';
    end if;
    mods := r.modifiers;
    v_day := greatest(p_day, r.day); v_rescued := greatest(p_rescued, r.rescued);
    v_kills := greatest(p_kills, r.kills); v_victory := p_victory or r.victory;
    elapsed := extract(epoch from now() - r.started_at);
  else
    if (select count(*) from public.runs where player_id = uid and started_at > now() - interval '1 day')
         >= c_max_new_runs_per_day then
      raise exception 'rate_limit_new_runs';
    end if;
    -- distinct, sorted, bounded: no way to pad the array with junk
    select coalesce(array_agg(m order by m), '{}') into mods
      from (select distinct left(x, 32) m from unnest(coalesce(p_modifiers, '{}')) x limit 12) s;
    v_day := p_day; v_rescued := p_rescued; v_kills := p_kills; v_victory := p_victory;
    elapsed := 0;
  end if;

  max_day := case when elapsed < c_first_day_seconds then 1
                  else 2 + floor((elapsed - c_first_day_seconds) / c_min_day_seconds) end;
  if v_day > max_day
     or v_kills > c_max_kills_per_day::bigint * v_day
     or v_rescued > c_max_rescued_per_day::bigint * v_day then
    raise exception 'implausible';
  end if;

  select least(round(coalesce(exp(sum(ln(m.factor))), 1), 4), c_max_factor) into factor
    from public.modifiers m where m.id = any(mods);

  if r.id is null then
    insert into public.runs (id, player_id, day, rescued, kills, ended, victory, modifiers, points, game_version)
    values (p_run_id, uid, v_day, v_rescued, v_kills, p_ended, v_victory, mods,
            public.run_points(v_day, v_rescued, v_kills, v_victory, factor), left(p_version, 32))
    returning * into r;
  else
    update public.runs set day = v_day, rescued = v_rescued, kills = v_kills, ended = p_ended,
           victory = v_victory, points = public.run_points(v_day, v_rescued, v_kills, v_victory, factor),
           game_version = left(p_version, 32), updated_at = now()
     where id = p_run_id returning * into r;
  end if;
  return r.points;
end $$;

revoke execute on function public.run_points(int, int, int, boolean, numeric),
  public.upsert_run(uuid, int, int, int, boolean, boolean, text[], text) from public, anon, authenticated;
grant execute on function public.upsert_run(uuid, int, int, int, boolean, boolean, text[], text) to authenticated;

-- Points already stored were computed with the old formula: recompute them (victories gain 3000).
update public.runs r set points = public.run_points(r.day, r.rescued, r.kills, r.victory,
  (select least(round(coalesce(exp(sum(ln(m.factor))), 1), 4), 3) from public.modifiers m where m.id = any(r.modifiers)))
 where r.victory;
