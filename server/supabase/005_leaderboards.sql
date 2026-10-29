-- Migration 5: leaderboards. The views run with the owner's rights (no security_invoker) so they can read all runs;
-- hidden players are filtered here. Client query: GET /rest/v1/leaderboard_points?order=rank&limit=100,
-- own rank: ...?player_id=eq.<uid>. Columns: rank, player_id, name, avatar, value.

create or replace view public.leaderboard_points as
  select rank() over (order by sum(r.points) desc)::int as rank, p.id as player_id, p.name::text as name, p.avatar,
         sum(r.points)::bigint as value
  from public.runs r join public.players p on p.id = r.player_id
  where not p.hidden group by p.id;

create or replace view public.leaderboard_days as
  select rank() over (order by sum(r.day) desc)::int as rank, p.id as player_id, p.name::text as name, p.avatar,
         sum(r.day)::bigint as value
  from public.runs r join public.players p on p.id = r.player_id
  where not p.hidden group by p.id;

create or replace view public.leaderboard_rescued as
  select rank() over (order by sum(r.rescued) desc)::int as rank, p.id as player_id, p.name::text as name, p.avatar,
         sum(r.rescued)::bigint as value
  from public.runs r join public.players p on p.id = r.player_id
  where not p.hidden group by p.id;

create or replace view public.leaderboard_kills as
  select rank() over (order by sum(r.kills) desc)::int as rank, p.id as player_id, p.name::text as name, p.avatar,
         sum(r.kills)::bigint as value
  from public.runs r join public.players p on p.id = r.player_id
  where not p.hidden group by p.id;

-- Best single run per player.
create or replace view public.best_run as
  select rank() over (order by b.points desc)::int as rank, p.id as player_id, p.name::text as name, p.avatar,
         b.points::bigint as value, b.day, b.victory, b.modifiers
  from (select distinct on (player_id) player_id, points, day, victory, modifiers
          from public.runs order by player_id, points desc, started_at) b
  join public.players p on p.id = b.player_id
  where not p.hidden;

revoke all on public.leaderboard_points, public.leaderboard_days, public.leaderboard_rescued,
  public.leaderboard_kills, public.best_run from anon, authenticated;
grant select on public.leaderboard_points, public.leaderboard_days, public.leaderboard_rescued,
  public.leaderboard_kills, public.best_run to anon, authenticated;
