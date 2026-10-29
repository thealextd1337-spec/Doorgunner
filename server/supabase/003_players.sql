-- Migration 3: profile RPCs. Errors are raised as plain codes in the message (PostgREST: {"code":"P0001","message":"name_taken"}):
-- not_authenticated | no_player | already_registered | name_invalid | name_banned | name_taken | avatar_invalid

create or replace function public.register_player(p_name text, p_avatar smallint) returns public.players
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  err text;
  r public.players;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.players where id = uid) then raise exception 'already_registered'; end if;
  if p_avatar is null or p_avatar not between 0 and 11 then raise exception 'avatar_invalid'; end if;
  err := public.name_error(p_name);
  if err <> '' then raise exception '%', err; end if;
  begin
    insert into public.players (id, name, avatar) values (uid, p_name, p_avatar) returning * into r;
  exception when unique_violation then
    raise exception 'name_taken';
  end;
  return r;
end $$;

create or replace function public.rename_player(p_name text) returns public.players
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  err text;
  r public.players;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  err := public.name_error(p_name);
  if err <> '' then raise exception '%', err; end if;
  begin
    update public.players set name = p_name where id = uid returning * into r;
  exception when unique_violation then
    raise exception 'name_taken';
  end;
  if not found then raise exception 'no_player'; end if;
  return r;
end $$;

-- Extra (not in the roadmap list): the profile screen needs to change the portrait too.
create or replace function public.set_avatar(p_avatar smallint) returns public.players
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  uid uuid := auth.uid();
  r public.players;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_avatar is null or p_avatar not between 0 and 11 then raise exception 'avatar_invalid'; end if;
  update public.players set avatar = p_avatar where id = uid returning * into r;
  if not found then raise exception 'no_player'; end if;
  return r;
end $$;

-- Privacy: removes the player, their runs (cascade) and the anonymous auth user.
-- The client must drop its tokens afterwards (they stop working).
create or replace function public.delete_me() returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  delete from public.players where id = uid;
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.register_player(text, smallint), public.rename_player(text),
  public.set_avatar(smallint), public.delete_me() from public, anon, authenticated;
grant execute on function public.register_player(text, smallint), public.rename_player(text),
  public.set_avatar(smallint), public.delete_me() to authenticated;
