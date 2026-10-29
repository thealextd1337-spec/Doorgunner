-- Migration 2: name filter. scripts/name_filter.gd (P3) must use the same normalization.

-- lowercase, strip accents, leetspeak map (0->o 1->i 3->e 4->a 5->s 7->t @->a $->s), drop everything but a-z.
create or replace function public.name_normalize(n text) returns text
language sql stable set search_path = public, extensions, pg_temp as $$
  select regexp_replace(
           translate(lower(extensions.unaccent(coalesce(n, ''))), '013457@$', 'oieastas'),
           '[^a-z]', '', 'g')
$$;

-- true = name passes the filter. Format rules are checked by name_error, not here.
create or replace function public.name_ok(n text) returns boolean
language plpgsql stable set search_path = public, extensions, pg_temp as $$
declare
  s text := public.name_normalize(n);
  w text;
begin
  -- Number codes that normalization would drop: 1488 anywhere (separators ignored), 88 as a whole word.
  -- "Alex88" stays legal, "Bob 88" does not.
  if regexp_replace(coalesce(n, ''), '[^0-9]', '', 'g') like '%1488%'
     or exists (select 1 from regexp_split_to_table(coalesce(n, ''), '[ _-]+') t where t = '88') then
    return false;
  end if;
  -- Blank out harmless words that contain a banned substring (Scunthorpe problem), longest first.
  -- The '|' keeps the neighbours from fusing into a new banned word.
  for w in select word from public.allowed_words order by length(word) desc loop
    s := replace(s, w, '|');
  end loop;
  -- shortcut: linear scan over banned_words, fine for a few thousand words and rare calls.
  return not exists (select 1 from public.banned_words b where position(b.word in s) > 0);
end $$;

-- '' = ok, otherwise an error code that the RPCs raise: name_invalid | name_banned.
create or replace function public.name_error(n text) returns text
language sql stable set search_path = public, extensions, pg_temp as $$
  select case
    when n is null or n !~ '^[A-Za-z0-9 _-]{3,16}$' then 'name_invalid'
    when n ~ '  ' or n ~ '^ ' or n ~ ' $' then 'name_invalid'
    when n !~ '[A-Za-z0-9]' then 'name_invalid'
    when not public.name_ok(n) then 'name_banned'
    else ''
  end
$$;

revoke execute on function public.name_normalize(text), public.name_ok(text), public.name_error(text)
  from public, anon, authenticated;
