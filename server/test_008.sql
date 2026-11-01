-- Tests for 008_errors.sql (Q2). Run AFTER migrations 001-008, same style as test.sql: one transaction, rolled back,
-- success = the last result reads "ALL TESTS PASSED"; a failure raises "FAIL: ..." (then run `rollback;` once).

begin;

create function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$
begin if c is not true then raise exception 'FAIL: %', msg; end if; end $$;

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

create function pg_temp.act(uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

create function pg_temp.act_anon() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $$;

insert into auth.users (id, aud, role)
select ('00000000-0000-0000-0000-00000000010' || n)::uuid, 'authenticated', 'authenticated' from generate_series(1, 2) n
on conflict do nothing;
delete from public.errors; -- a real table may hold rows; this transaction is rolled back
delete from public.error_rate;

-- 1. anonymous report, dedupe per (version, message) --------------------------------------
select pg_temp.act_anon();
select public.report_error('1.0.0', 'Web', 'boom', 'at a.gd:1');
select public.report_error('1.0.0', 'Web', 'boom', 'at a.gd:1');
select public.report_error('1.0.0', 'Windows', 'boom', 'other stack, same message');
reset role;
select pg_temp.ok((select count(*) from public.errors) = 1, 'same version+message = one row');
select pg_temp.ok((select count from public.errors) = 3, 'count incremented');
select pg_temp.ok((select player_id from public.errors) is null, 'anonymous: player_id null');
select pg_temp.ok((select platform from public.errors) = 'Web', 'first report keeps its platform');
select pg_temp.act_anon();
select public.report_error('1.0.1', 'Web', 'boom', '');
reset role;
select pg_temp.ok((select count(*) from public.errors) = 2, 'another version = another row');

-- 2. signed-in player: id recorded, input validation, truncation ----------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000101');
select public.report_error('1.0.0', 'Windows', 'player error', 'x');
select pg_temp.expect('error_invalid', $$select public.report_error('1.0.0', 'Web', '', 'x')$$);
select pg_temp.expect('error_invalid', $$select public.report_error('1.0.0', 'Web', '   ', 'x')$$);
select pg_temp.expect('error_invalid', $$select public.report_error('1.0.0', 'Web', null, 'x')$$);
select public.report_error(null, null, 'nulls ok', null);
select public.report_error(repeat('v', 100), repeat('p', 100), repeat('m', 10000), repeat('s', 20000));
reset role;
select pg_temp.ok((select player_id from public.errors where message = 'player error') = '00000000-0000-0000-0000-000000000101', 'player id stored');
select pg_temp.ok((select version = '' and platform = '' and stack = '' from public.errors where message = 'nulls ok'), 'nulls become empty strings');
select pg_temp.ok((select length(message) = 500 and length(stack) = 4000 and length(version) = 32 and length(platform) = 32
                     from public.errors where message like 'mmm%'), 'length limits');

-- 3. no client access ------------------------------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000101');
select pg_temp.expect('permission denied', $$select * from public.errors$$);
select pg_temp.expect('permission denied', $$insert into public.errors (message) values ('x')$$);
select pg_temp.expect('permission denied', $$update public.errors set count = 0$$);
select pg_temp.expect('permission denied', $$select * from public.error_rate$$);
select pg_temp.act_anon();
select pg_temp.expect('permission denied', $$select * from public.errors$$);
select pg_temp.expect('permission denied', $$delete from public.errors$$);
reset role;

-- 4. rate limits: 20 per player and hour, 200 for all anonymous callers --------------------
select pg_temp.act('00000000-0000-0000-0000-000000000102');
select public.report_error('1.0.0', 'Web', 'flood', 'x') from generate_series(1, 20);
select pg_temp.expect('rate_limit', $$select public.report_error('1.0.0', 'Web', 'flood', 'x')$$);
select pg_temp.act('00000000-0000-0000-0000-000000000101'); -- another player is not affected
select public.report_error('1.0.0', 'Web', 'flood', 'x');
reset role;
select pg_temp.ok((select count from public.errors where message = 'flood') = 21, 'refused call was not counted');
update public.error_rate set hr = hr - interval '1 hour' where bucket = '00000000-0000-0000-0000-000000000102';
select pg_temp.act('00000000-0000-0000-0000-000000000102'); -- next hour: allowed again
select public.report_error('1.0.0', 'Web', 'flood', 'x');
reset role;
delete from public.error_rate where bucket = 'anon'; -- the anonymous calls of sections 1-2
select pg_temp.act_anon();
select public.report_error('1.0.0', 'Web', 'anon flood', 'x') from generate_series(1, 200);
select pg_temp.expect('rate_limit', $$select public.report_error('1.0.0', 'Web', 'anon flood', 'x')$$);
select pg_temp.act('00000000-0000-0000-0000-000000000101'); -- signed-in players have their own budget
select public.report_error('1.0.0', 'Web', 'anon flood', 'x');
reset role;
select pg_temp.ok((select count from public.errors where message = 'anon flood') = 201, 'anon cap counts all anonymous callers');

-- 5. delete_me keeps working and anonymises the error rows ---------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000101');
select public.register_player('Zed_Reporter', 0::smallint);
select public.delete_me();
reset role;
select pg_temp.ok(not exists (select 1 from public.players where id = '00000000-0000-0000-0000-000000000101'), 'player deleted');
select pg_temp.ok(not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-000000000101'), 'auth user deleted');
select pg_temp.ok(not exists (select 1 from public.errors where player_id = '00000000-0000-0000-0000-000000000101'), 'errors.player_id nulled');
select pg_temp.ok(exists (select 1 from public.errors where message = 'player error'), 'the error row itself stays');
select pg_temp.ok(not exists (select 1 from public.error_rate where bucket = '00000000-0000-0000-0000-000000000101'), 'rate counter removed');
select pg_temp.act_anon();
select pg_temp.expect('permission denied', $$select public.delete_me()$$);
reset role;

select 'ALL TESTS PASSED' as result;
rollback;
