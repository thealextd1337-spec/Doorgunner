-- Doorgunner backend tests. Run AFTER migrations 001-007 (and the generated word list, if you like), in the SQL editor
-- or with psql. Everything happens in one transaction that is rolled back at the end: no data is left behind.
-- Success = the last result shows "ALL TESTS PASSED". A failure raises "FAIL: ..." - then run `rollback;` once.
-- The seed words below are test-only; they are rolled back and do not replace the generated word list (P3).

begin;

-- helpers (session-local) ---------------------------------------------------
create function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$
begin if c is not true then raise exception 'FAIL: %', msg; end if; end $$;

-- statement must fail with a message starting with `code`
create function pg_temp.expect(code text, stmt text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlerrm like code || '%' then return; end if;
    raise exception 'FAIL: expected [%] but got [%] for: %', code, sqlerrm, stmt;
  end;
  raise exception 'FAIL: expected [%] but statement succeeded: %', code, stmt;
end $$;

-- become a signed-in (anonymous) Supabase user
create function pg_temp.act(uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

-- as postgres: make a run look older, to get past the time based limits
create function pg_temp.age_run(rid uuid, delta interval) returns void language plpgsql as $$
begin
  reset role;
  update public.runs set started_at = started_at - delta, updated_at = updated_at - delta where id = rid;
end $$;

-- seed data (rolled back) ----------------------------------------------------
-- players.id references auth.users (001), so the fake players need auth rows (rolled back with everything else)
insert into auth.users (id, aud, role)
select ('00000000-0000-0000-0000-00000000000' || n)::uuid, 'authenticated', 'authenticated' from generate_series(1, 4) n
on conflict do nothing;
insert into public.banned_words (word, lang) values ('badword', 'en'), ('nazi', 'en'), ('ass', 'en') on conflict do nothing;
insert into public.allowed_words (word) values ('classic'), ('assassin') on conflict do nothing;
insert into public.modifiers (id, factor) values ('dense', 1.3), ('warlords', 1.25), ('big', 2.5) on conflict do nothing;

-- 1. name filter (as postgres) ----------------------------------------------------
select pg_temp.ok(public.name_normalize('B@d-W0rD!') = 'badword', 'normalize leet + case + symbols');
select pg_temp.ok(public.name_normalize('Nàzí') = 'nazi', 'normalize accents');
select pg_temp.ok(public.name_ok('Alex'), 'plain name ok');
select pg_temp.ok(not public.name_ok('BadWord'), 'banned word, any case');
select pg_temp.ok(not public.name_ok('xxbadwordxx'), 'banned word as substring');
select pg_temp.ok(not public.name_ok('b4dw0rd'), 'leetspeak');
select pg_temp.ok(not public.name_ok('b_a_d-w o r d'), 'separators between letters');
select pg_temp.ok(not public.name_ok('N@zi'), 'leetspeak with @');
select pg_temp.ok(public.name_ok('Classic'), 'allowed word that contains "ass"');
select pg_temp.ok(public.name_ok('Assassin_7'), 'allowed word, double hit');
select pg_temp.ok(not public.name_ok('ClassicAss'), 'allowed word does not shield a real hit next to it');
select pg_temp.ok(not public.name_ok('Assclassic'), 'real hit before an allowed word');
select pg_temp.ok(public.name_ok('Alex88'), '88 inside a name is fine');
select pg_temp.ok(not public.name_ok('Bob 88'), '88 as a word');
select pg_temp.ok(not public.name_ok('Pilot1488'), '1488');
select pg_temp.ok(not public.name_ok('x14x88'), '1488 with separators');
select pg_temp.ok(public.name_error('Alex') = '', 'name_error ok');
select pg_temp.ok(public.name_error('ab') = 'name_invalid', 'too short');
select pg_temp.ok(public.name_error('abcdefghijklmnopq') = 'name_invalid', '17 chars');
select pg_temp.ok(public.name_error('abcdefghijklmnop') = '', '16 chars');
select pg_temp.ok(public.name_error('a  b') = 'name_invalid', 'double space');
select pg_temp.ok(public.name_error(' abc') = 'name_invalid', 'leading space');
select pg_temp.ok(public.name_error('abc ') = 'name_invalid', 'trailing space');
select pg_temp.ok(public.name_error('abc$') = 'name_invalid', 'bad character');
select pg_temp.ok(public.name_error('äbc') = 'name_invalid', 'non-ascii');
select pg_temp.ok(public.name_error('---') = 'name_invalid', 'no alphanumeric');
select pg_temp.ok(public.name_error('BadWord') = 'name_banned', 'banned via name_error');

select pg_temp.ok(public.run_points(5, 2, 30, true) = 5580, 'run_points formula (007: victory 5000)');
select pg_temp.ok(public.run_points(5, 2, 30, true, 1.5) = 8370, 'run_points with factor');

-- 2. access control ------------------------------------------------------------
set local role anon;
select pg_temp.expect('permission denied', 'select * from public.banned_words');
select pg_temp.expect('permission denied', 'select * from public.runs');
select pg_temp.expect('permission denied', 'insert into public.players (id, name, avatar) values (gen_random_uuid(), ''Hax'', 1)');
select pg_temp.expect('permission denied', 'select public.register_player(''Hax'', 1::smallint)');
select pg_temp.expect('permission denied', 'select public.name_ok(''Alex'')');
select pg_temp.ok((select count(*) from public.leaderboard_points) >= 0, 'anon reads leaderboard');
select pg_temp.ok((select count(*) from public.modifiers) = 3, 'anon reads modifiers');
reset role;

-- 3. register / rename / avatar --------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.expect('permission denied', 'select * from public.banned_words');
select pg_temp.expect('permission denied', 'insert into public.runs (id, player_id, day) values (gen_random_uuid(), ''00000000-0000-0000-0000-000000000001'', 1)');
select pg_temp.expect('permission denied', 'update public.players set hidden = true');
select pg_temp.expect('no_player', 'select public.upsert_run(gen_random_uuid(), 1, 0, 0, false, false, ''{}'', ''t'')');
select pg_temp.expect('name_banned', 'select public.register_player(''BadWord'', 1::smallint)');
select pg_temp.expect('name_invalid', 'select public.register_player(''ab'', 1::smallint)');
select pg_temp.expect('avatar_invalid', 'select public.register_player(''Alex'', 12::smallint)');
select pg_temp.ok((select name::text from public.register_player('Alex_One', 3::smallint)) = 'Alex_One', 'register ok');
select pg_temp.expect('already_registered', 'select public.register_player(''Other'', 1::smallint)');

select pg_temp.act('00000000-0000-0000-0000-000000000002');
select pg_temp.expect('name_taken', 'select public.register_player(''alex_one'', 1::smallint)');   -- case-insensitive
select pg_temp.ok((select name::text from public.register_player('Beta', 0::smallint)) = 'Beta', 'second player');
select pg_temp.expect('name_taken', 'select public.rename_player(''ALEX_ONE'')');
select pg_temp.expect('name_banned', 'select public.rename_player(''nazi'')');
select pg_temp.ok((select name::text from public.rename_player('BETA')) = 'BETA', 'rename to own name in other case');
select pg_temp.ok((select avatar from public.set_avatar(11::smallint)) = 11, 'set_avatar');
select pg_temp.expect('avatar_invalid', 'select public.set_avatar(12::smallint)');
select pg_temp.ok((select count(*) from public.players) = 2, 'players readable');

-- 4. runs ------------------------------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000001', 1, 2, 10, false, false, '{}', 'v1') = 160,
                  'points: 1*100 + 2*25 + 10');
select pg_temp.expect('rate_limit', 'select public.upsert_run(''a0000000-0000-0000-0000-000000000001'', 1, 3, 11, false, false, ''{}'', ''v1'')');
select pg_temp.expect('implausible', 'select public.upsert_run(gen_random_uuid(), 2, 0, 0, false, false, ''{}'', ''v1'')');          -- day 2 at t=0
select pg_temp.expect('implausible', 'select public.upsert_run(gen_random_uuid(), 1, 0, 301, false, false, ''{}'', ''v1'')');        -- kills > 300/day (007)
select pg_temp.expect('implausible', 'select public.upsert_run(gen_random_uuid(), 1, 61, 0, false, false, ''{}'', ''v1'')');         -- rescued > 60/day
select pg_temp.expect('run_invalid', 'select public.upsert_run(gen_random_uuid(), 0, 0, 0, false, false, ''{}'', ''v1'')');
select pg_temp.expect('run_invalid', 'select public.upsert_run(gen_random_uuid(), 1, -1, 0, false, false, ''{}'', ''v1'')');

-- time passes: 1 h => up to day 6 allowed (007: 150 s for day 1, then 810 s a day); values never decrease; modifiers stay frozen
select pg_temp.age_run('a0000000-0000-0000-0000-000000000001', interval '1 hour');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.expect('implausible', 'select public.upsert_run(''a0000000-0000-0000-0000-000000000001'', 7, 0, 0, false, false, ''{}'', ''v1'')');
select pg_temp.expect('implausible', 'select public.upsert_run(''a0000000-0000-0000-0000-000000000001'', 12, 0, 0, false, false, ''{}'', ''v1'')');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000001', 5, 1, 3, false, false, '{dense,big}', 'v2') = 5*100 + 2*25 + 10,
                  'day grows, rescued/kills never shrink, modifiers of later calls are ignored');
select pg_temp.age_run('a0000000-0000-0000-0000-000000000001', interval '1 minute');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000001', 3, 2, 10, true, true, '{}', 'v2') = 5*100 + 2*25 + 10 + 5000,
                  'final call (ended + victory), lower day ignored');
select pg_temp.expect('run_ended', 'select public.upsert_run(''a0000000-0000-0000-0000-000000000001'', 6, 2, 10, true, true, ''{}'', ''v2'')');
select pg_temp.ok((select ended and victory and day = 5 and game_version = 'v2' from public.runs where id = 'a0000000-0000-0000-0000-000000000001'),
                  'stored run');

-- modifiers; the final ended=true call is not blocked by the 30 s sync limit
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000002', 1, 0, 0, false, false, '{dense,warlords,dense}', 'v1') = 162,
                  'modifier factors multiply (1.3 * 1.25), duplicates ignored');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000002', 1, 0, 5, true, false, '{}', 'v1') = 170,
                  'death right after a sync is accepted: floor(105 * 1.625)');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000003', 1, 0, 0, false, false, '{dense,big,warlords,nope}', 'v1') = 300,
                  'combined factor capped at 3, unknown id counts 1.0');
select pg_temp.ok(public.upsert_run('a0000000-0000-0000-0000-000000000004', 1, 0, 0, false, false, '{nope}', 'v1') = 100, 'unknown modifier = 1.0');

select pg_temp.act('00000000-0000-0000-0000-000000000002');
select pg_temp.expect('not_your_run', 'select public.upsert_run(''a0000000-0000-0000-0000-000000000001'', 1, 0, 0, false, false, ''{}'', ''v1'')');

-- 20 new runs per day, the 21st is refused
select pg_temp.ok((select count(public.upsert_run(gen_random_uuid(), 1, 0, 0, false, false, '{}', 'v1')) from generate_series(1, 20)) = 20, '20 runs');
select pg_temp.expect('rate_limit_new_runs', 'select public.upsert_run(gen_random_uuid(), 1, 0, 0, false, false, ''{}'', ''v1'')');

-- 5. leaderboards ------------------------------------------------------------------
reset role;
select pg_temp.ok((select value from public.leaderboard_points where name = 'Alex_One') = 5560 + 170 + 300 + 100,
                  'points sum over runs');
select pg_temp.ok((select rank from public.leaderboard_points where name = 'Alex_One') = 1, 'rank 1');
select pg_temp.ok((select value from public.best_run where name = 'Alex_One') = 5560, 'best single run');
select pg_temp.ok((select value from public.leaderboard_days where name = 'Alex_One') = 5 + 1 + 1 + 1, 'days sum');
select pg_temp.ok((select value from public.leaderboard_rescued where name = 'Alex_One') = 2, 'rescued sum');
select pg_temp.ok((select value from public.leaderboard_kills where name = 'Alex_One') = 15, 'kills sum');
update public.players set hidden = true where name = 'Alex_One';
select pg_temp.ok(not exists (select 1 from public.leaderboard_points where name = 'Alex_One'), 'hidden player not on the board');
select pg_temp.ok(not exists (select 1 from public.best_run where name = 'Alex_One'), 'hidden player not on best_run');
set local role anon;
select pg_temp.ok(not exists (select 1 from public.players where name = 'Alex_One'), 'hidden player not readable');
reset role;

-- 6. delete_me -------------------------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(exists (select 1 from public.players where id = '00000000-0000-0000-0000-000000000001'), 'hidden player still sees themself');
select public.delete_me();
reset role;
select pg_temp.ok(not exists (select 1 from public.players where id = '00000000-0000-0000-0000-000000000001'), 'player deleted');
select pg_temp.ok(not exists (select 1 from public.runs where player_id = '00000000-0000-0000-0000-000000000001'), 'runs deleted');
select pg_temp.act('00000000-0000-0000-0000-000000000003');
select pg_temp.ok((select name::text from public.register_player('alex_one', 5::smallint)) = 'alex_one', 'name free again after delete_me');

reset role;
select 'ALL TESTS PASSED' as result;
rollback;
