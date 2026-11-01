-- Tests for 009_cloud_save.sql (Q3). Run AFTER migrations 001-007 and 009, same style as test.sql: one transaction, rolled
-- back at the end. Success = the last result shows "ALL TESTS PASSED"; on "FAIL: ..." run `rollback;` once.
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
create function pg_temp.age_save(pid uuid, delta interval) returns void language plpgsql as $$
begin reset role; update public.cloud_saves set updated_at = updated_at - delta where player_id = pid; end $$;

insert into auth.users (id, aud, role)
select ('00000000-0000-0000-0000-00000000000' || n)::uuid, 'authenticated', 'authenticated' from generate_series(1, 3) n
on conflict do nothing;
insert into public.players (id, name, avatar) values
  ('00000000-0000-0000-0000-000000000001', 'Saver_One', 1), ('00000000-0000-0000-0000-000000000002', 'Saver_Two', 2);

-- 1. put / get / overwrite ----------------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(public.get_save('run') is null, 'empty slot -> null');
select public.put_save('run', encode('hello save'::bytea, 'base64'), '1.0.0-beta', 2);
select pg_temp.ok(convert_from(decode(public.get_save('run')->>'data', 'base64'), 'UTF8') = 'hello save', 'get returns what was put');
select pg_temp.ok((public.get_save('run')->>'format')::int = 2 and public.get_save('run')->>'version' = '1.0.0-beta', 'format and version kept');
select pg_temp.ok(not (public.get_save('run', true) ? 'data') and (public.get_save('run', true)->>'format')::int = 2, 'meta only leaves data out');
select pg_temp.expect('rate_limit', $q$select public.put_save('run', 'aGk=', 'x', 2)$q$);
select pg_temp.age_save('00000000-0000-0000-0000-000000000001', interval '1 minute');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select public.put_save('run', encode('second'::bytea, 'base64'), '1.0.1', 3);
select pg_temp.ok(convert_from(decode(public.get_save('run')->>'data', 'base64'), 'UTF8') = 'second', 'overwrite');
select public.put_save('daily', 'aGk=', 'x', 3); -- slots are independent
select pg_temp.ok((select count(*) from public.cloud_saves) = 2, 'one row per (player, slot)');

-- 2. validation ---------------------------------------------------------------------
select pg_temp.expect('slot_invalid', $q$select public.put_save('other', 'aGk=', 'x', 2)$q$);
select pg_temp.expect('save_invalid', $q$select public.put_save('run', '', 'x', 2)$q$);
select pg_temp.expect('save_invalid', $q$select public.put_save('run', '!!notbase64!!', 'x', 2)$q$);
select pg_temp.expect('save_invalid', $q$select public.put_save('run', 'aGk=', 'x', -1)$q$);
select pg_temp.age_save('00000000-0000-0000-0000-000000000001', interval '1 minute');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.expect('save_too_large', format($q$select public.put_save('run', %L, 'x', 2)$q$, repeat('QUJD', 800000))); -- 2.4 MB decoded
select pg_temp.ok(convert_from(decode(public.get_save('run')->>'data', 'base64'), 'UTF8') = 'second', 'failed put leaves the old save');

-- 3. own rows only ------------------------------------------------------------------
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select pg_temp.ok(public.get_save('run') is null, 'other player sees no save');
select pg_temp.ok((select count(*) from public.cloud_saves) = 0, 'RLS hides the other rows on direct select');
select pg_temp.expect('permission denied', $q$select data from public.cloud_saves$q$);
select pg_temp.expect('permission denied', $q$insert into public.cloud_saves (player_id, slot, data) values ('00000000-0000-0000-0000-000000000002', 'run', 'x')$q$);
select public.put_save('run', 'aGk=', 'x', 2);
select public.delete_save('run');
select pg_temp.ok(public.get_save('run') is null, 'delete_save removes the own save');
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(public.get_save('run') is not null, 'player 1 save untouched by player 2 delete');
select pg_temp.act('00000000-0000-0000-0000-000000000003'); -- no player row
select pg_temp.expect('no_player', $q$select public.put_save('run', 'aGk=', 'x', 2)$q$);
set local role anon;
select pg_temp.expect('permission denied', $q$select public.get_save('run')$q$);
reset role;

-- 4. delete_me removes the cloud saves (FK cascade, delete_me itself is not touched) -----
select pg_temp.act('00000000-0000-0000-0000-000000000001');
select public.delete_me();
reset role;
select pg_temp.ok(not exists (select 1 from public.cloud_saves where player_id = '00000000-0000-0000-0000-000000000001'), 'delete_me removed the cloud saves');

-- 5. a restored (older) run cannot lower its server values: upsert_run keeps the maximum (004/007) --------------
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.upsert_run('11111111-1111-1111-1111-111111111111', 1, 0, 0, false, false, '{}', 't');
reset role;
update public.runs set updated_at = updated_at - interval '1 minute', started_at = started_at - interval '2 hours' where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.upsert_run('11111111-1111-1111-1111-111111111111', 3, 5, 80, false, false, '{}', 't');
reset role;
update public.runs set updated_at = updated_at - interval '1 minute' where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.upsert_run('11111111-1111-1111-1111-111111111111', 2, 1, 10, false, false, '{}', 't'); -- rewound copy
reset role;
select pg_temp.ok((select day = 3 and rescued = 5 and kills = 80 from public.runs where id = '11111111-1111-1111-1111-111111111111'), 'lower values are ignored');
select pg_temp.act('00000000-0000-0000-0000-000000000002');
select public.upsert_run('11111111-1111-1111-1111-111111111111', 3, 5, 80, true, false, '{}', 't'); -- ended = final
select pg_temp.expect('run_ended', $q$select public.upsert_run('11111111-1111-1111-1111-111111111111', 1, 0, 0, false, false, '{}', 't')$q$);

reset role;
select 'ALL TESTS PASSED' as result;
rollback;
