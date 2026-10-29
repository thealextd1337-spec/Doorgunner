-- Migration 4: run scoring and upsert_run.
-- Errors: not_authenticated | no_player | run_invalid | not_your_run | run_ended | rate_limit | rate_limit_new_runs | implausible

-- Score of one run. P18 (balance) edits only this function; upsert_run recomputes points on every call.
create or replace function public.run_points(p_day int, p_rescued int, p_kills int, p_victory boolean, p_factor numeric default 1)
returns int language sql immutable as $$
  select floor((p_day * 100 + p_rescued * 25 + p_kills + case when p_victory then 2000 else 0 end) * p_factor)::int
$$;

-- Creates the run on the first call, then only lets values grow (lower values are ignored, not an error).
-- Returns the server-side points. The modifiers are taken from the first call and then frozen.
create or replace function public.upsert_run(
  p_run_id uuid, p_day int, p_rescued int, p_kills int, p_ended boolean, p_victory boolean,
  p_modifiers text[], p_version text) returns int
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  -- A game day lasts 900 s (DAY_SECONDS, P5); the bound uses 360 s so it still holds if P18 retunes the pace.
  c_min_day_seconds constant int := 360;
  c_max_kills_per_day constant int := 400;
  c_max_rescued_per_day constant int := 60;
  c_min_sync_seconds constant int := 30;       -- between two upserts of one run (the final ended=true call is exempt)
  c_max_new_runs_per_day constant int := 20;
  c_max_factor constant numeric := 3;          -- cap of the combined modifier factor (P15)
  uid uuid := auth.uid();
  r public.runs;
  mods text[];
  factor numeric;
  elapsed numeric;
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

  if v_day > 1 + floor(elapsed / c_min_day_seconds)
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
