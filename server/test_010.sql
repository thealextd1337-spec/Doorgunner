-- Tests for 010_daily_season.sql (Q14). Run AFTER migrations 001-007, 009 and 010, same style as test.sql: one transaction,
-- rolled back at the end. Success = the last result shows "ALL TESTS PASSED"; on "FAIL: ..." run `rollback;` once.
begin;

create function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$
begin if c is not true then raise exception 'FAIL: %', msg; end if; end $$;
create function pg_temp.expect(code text, stmt text) returns void language plpgsql as $$
begin
  begin execute stmt;
  exception when others then
    if sqlerrm like code || '%' then return; end if;
    raise exception 'FAIL: expected [%] but got [%] for: %', code, sqlerrm, stmt;
  end;
  raise exception 'FAIL: expected [%] but statement succeeded: %', code, stmt;
end $$;
create function pg_temp.act(uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

insert into public.modifiers (id, factor) values ('dense_horde', 1.30), ('warlords', 1.25), ('scarcity', 1.25)
on conflict (id) do nothing;
insert into auth.users (id, aud, role)
select ('00000000-0000-0000-0000-00000000000' || n)::uuid, 'authenticated', 'authenticated' from generate_series(1, 3) n
on conflict do nothing;
insert into public.players (id, name, avatar) values
  ('00000000-0000-0000-0000-000000000001', 'Daily_One', 1), ('00000000-0000-0000-0000-000000000002', 'Daily_Two', 2);

-- 1. the daily is deterministic, stored once, and private --------------------------------
select pg_temp.ok((public.daily_for('2026-11-02')).seed = (public.daily_for('2026-11-02')).seed, 'same date, same seed');
select pg_temp.ok((select count(*) from public.daily where date = '2026-11-02') = 1, 'stored once');
select pg_temp.ok((select count(distinct (public.daily_for(d::date)).seed) from generate_series('2026-01-01'::date, '2026-01-10', '1 day') d) >= 9, 'seeds differ by date');
select pg_temp.ok((select bool_and(array_length(modifiers, 1) between 1 and 2 and heli in ('huey', 'little_bird', 'black_hawk', 'chinook', 'hind'))
  from public.daily), '1-2 modifiers and a known heli');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.expect('permission denied', $q$select secret from public.daily_secret$q$);
select pg_temp.expect('permission denied', $q$select seed from public.daily$q$);
select pg_temp.expect('permission denied', $q$select * from public.daily_attempts$q$);
select pg_temp.expect('permission denied', $q$select public.daily_for('2030-01-01')$q$);

-- 2. get_daily: no seed, played flag -----------------------------------------------------
select pg_temp.ok(not (public.get_daily() ? 'seed'), 'get_daily hides the seed');
select pg_temp.ok((public.get_daily()->>'played')::boolean = false, 'not played yet');
select pg_temp.ok(public.get_daily()->>'season_week' = to_char(now() at time zone 'utc', 'IYYY-"W"IW'), 'season week');
select pg_temp.ok((public.get_daily()->>'resets_in')::int between 0 and 86400, 'resets_in');

-- 3. one ranked attempt per player and day -----------------------------------------------
select pg_temp.ok((public.start_daily('aaaaaaaa-0000-0000-0000-000000000001')->>'ranked')::boolean, 'first start is ranked');
select pg_temp.ok((public.start_daily('aaaaaaaa-0000-0000-0000-000000000001')->>'ranked')::boolean, 'retry with the same id stays ranked');
select pg_temp.ok(not (public.start_daily('aaaaaaaa-0000-0000-0000-000000000002')->>'ranked')::boolean, 'second attempt is practice');
select pg_temp.ok(public.start_daily('aaaaaaaa-0000-0000-0000-000000000002')->>'seed' = public.start_daily('aaaaaaaa-0000-0000-0000-000000000001')->>'seed', 'practice gets the same seed');
select pg_temp.ok((public.get_daily()->>'played')::boolean, 'played after the start');
select pg_temp.expect('run_invalid', $q$select public.start_daily(null)$q$);
select pg_temp.act('00000000-0000-0000-0000-000000000003'); -- no player row
select pg_temp.expect('no_player', $q$select public.start_daily('aaaaaaaa-0000-0000-0000-000000000003')$q$);
set local role anon;
select pg_temp.expect('permission denied', $q$select public.get_daily()$q$);
reset role;

-- 4. upsert_run binds the claimed id: daily mode, date, the daily's modifiers and points ----
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select public.upsert_run('aaaaaaaa-0000-0000-0000-000000000001', 1, 0, 0, false, false, '{"blackout"}', 't'); -- client lies about mods
select public.upsert_run('aaaaaaaa-0000-0000-0000-000000000002', 1, 0, 0, false, false, '{}', 't'); -- the practice id
select pg_temp.expect('run_invalid', $q$select public.start_daily('aaaaaaaa-0000-0000-0000-000000000002')$q$); -- an existing run id
reset role;
select pg_temp.ok((select mode = 'daily' and daily_date = (now() at time zone 'utc')::date and modifiers = (select modifiers from public.daily d where d.date = daily_date)
  from public.runs where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'ranked attempt is a daily run with the daily modifiers');
select pg_temp.ok((select points = public.run_points(1, 0, 0, false, (select least(round(coalesce(exp(sum(ln(m.factor))), 1), 4), 3)
  from public.modifiers m where m.id = any(r.modifiers))) from public.runs r where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'points use the daily factor');
select pg_temp.ok((select mode = 'normal' and daily_date is null from public.runs where id = 'aaaaaaaa-0000-0000-0000-000000000002'), 'practice id is a normal run');
select pg_temp.expect('new row for relation "runs" violates check constraint', $q$update public.runs set mode = 'daily' where id = 'aaaaaaaa-0000-0000-0000-000000000002'$q$);

-- player 2 plays the daily too, with more points
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.start_daily('bbbbbbbb-0000-0000-0000-000000000001');
select public.upsert_run('bbbbbbbb-0000-0000-0000-000000000001', 1, 3, 40, false, false, '{}', 't');

-- 5. boards ------------------------------------------------------------------------------
set local role anon;
select pg_temp.ok((select count(*) from public.leaderboard_daily where daily_date = (now() at time zone 'utc')::date) = 2, 'daily board: the two ranked attempts');
select pg_temp.ok((select rank from public.leaderboard_daily where player_id = '00000000-0000-0000-0000-000000000002'
  and daily_date = (now() at time zone 'utc')::date) = 1, 'daily board ranks by points');
select pg_temp.ok((select count(*) from public.leaderboard_season where season_week = to_char(now() at time zone 'utc', 'IYYY-"W"IW')) = 2, 'season board: both players');
select pg_temp.ok((select value from public.leaderboard_season where player_id = '00000000-0000-0000-0000-000000000001'
  and season_week = to_char(now() at time zone 'utc', 'IYYY-"W"IW')) = (select sum(points) from public.runs where player_id = '00000000-0000-0000-0000-000000000001'),
  'season sums all runs of the week');
reset role;
update public.players set hidden = true where id = '00000000-0000-0000-0000-000000000002';
select pg_temp.ok((select rank from public.leaderboard_daily where player_id = '00000000-0000-0000-0000-000000000001'
  and daily_date = (now() at time zone 'utc')::date) = 1, 'hidden players are left out before ranking');
update public.players set hidden = false where id = '00000000-0000-0000-0000-000000000002';

-- 6. an ended daily run drops the daily cloud slot, not the run slot ----------------------
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.put_save('run', 'aGk=', 'x', 3);
select public.put_save('daily', 'aGk=', 'x', 3);
select public.upsert_run('bbbbbbbb-0000-0000-0000-000000000001', 1, 3, 40, true, false, '{}', 't');
select pg_temp.ok(public.get_save('daily') is null and public.get_save('run') is not null, 'ended daily: daily slot gone, run slot kept');

reset role;
select 'ALL TESTS PASSED' as result;
rollback;
