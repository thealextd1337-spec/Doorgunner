-- Migration 6: score factors of the run modifiers (P15, scripts/modifiers.gd TABLE). Idempotent: run again after a change.
-- upsert_run multiplies the factors of a run's modifiers (unknown ids count 1.0) and caps the product at 3.
insert into public.modifiers (id, factor) values
  ('dense_horde',   1.30),
  ('warlords',      1.25),
  ('scarcity',      1.25),
  ('dry_season',    1.15),
  ('glass_cockpit', 1.30),
  ('blackout',      1.20)
on conflict (id) do update set factor = excluded.factor;
