# Doorgunner online backend (Supabase)

Anonymous sign-in, a player profile (name + portrait), server-scored runs and leaderboards.
The game client only needs the project URL and the **anon key** (`scripts/online_config.gd`); both are public.
All writes go through `security definer` RPCs, all tables have RLS on.

| File | Content |
|---|---|
| `supabase/001_schema.sql` | extensions, tables (`players`, `runs`, `banned_words`, `allowed_words`, `modifiers`), RLS, grants |
| `supabase/002_names.sql` | `name_normalize`, `name_ok`, `name_error` (name filter) |
| `supabase/003_players.sql` | RPCs `register_player`, `rename_player`, `set_avatar`, `delete_me` |
| `supabase/004_runs.sql` | `run_points` (score formula), RPC `upsert_run` (plausibility + rate limits) |
| `supabase/005_leaderboards.sql` | views `leaderboard_points/_days/_rescued/_kills`, `best_run` |
| `supabase/006_modifiers.sql` | the six run-modifier score factors (P15), idempotent upsert into `modifiers` |
| `test.sql` | test cases, runs in one transaction that is rolled back |

## Setup (once)

The project `yucfmsvivvoufvodeyvc` (eu-central-1) already exists, has migrations 001-005 applied (006 still to run) and anonymous sign-ins on.
To set up a new project (or a second one for testing):

1. https://supabase.com -> **New project** (free plan is enough). Pick the region closest to the players, set a database password and keep it in a password manager (the game never needs it).
2. **Authentication -> Sign In / Providers -> Allow anonymous sign-ins: on.**
   Optionally enable CAPTCHA/Turnstile later (see the findings below).
3. **SQL Editor**: run `001_schema.sql`, `002_names.sql`, `003_players.sql`, `004_runs.sql`, `005_leaderboards.sql`, `006_modifiers.sql` in that order (paste, Run). They can be re-run safely.
4. **Word list:** the name filter is empty until the list is loaded. Generate the INSERTs from `data/banned_words.txt` / `data/allowed_words.txt` with `tools/gen_wordlist_sql.py` (P3) and run the output in the SQL editor. Contract: words are lowercase `a-z` only, at least 3 letters (the tables have a check constraint, a wrong row fails loudly); use `insert ... on conflict do nothing`.
5. **Test:** paste `test.sql` into the SQL editor and run. The last result must read `ALL TESTS PASSED`. If a test fails the message starts with `FAIL:`; then run `rollback;` once. The test seeds its own words/modifiers and rolls everything back, nothing stays in the database.
6. **Project Settings -> API** (or the "Connect" dialog): copy the **Project URL** and the **anon / public key** into `scripts/online_config.gd` (`URL`, `ANON_KEY`).
7. **Never commit the `service_role` key** (or the database password / a personal access token). It bypasses RLS. Nothing in the game needs it.

Moderation: Table editor -> `players` -> set `hidden = true`. The player disappears from all boards, their name stays reserved.

## API for the client (P6a)

Base: `<URL>/rest/v1`, headers `apikey: <anon key>`, `Authorization: Bearer <access token>` (the anon key itself before login).
Auth: `POST <URL>/auth/v1/signup` with body `{}` creates an anonymous user (returns `access_token`, `refresh_token`, user id); refresh with `POST /auth/v1/token?grant_type=refresh_token`.

| Call | Notes |
|---|---|
| `POST /rpc/register_player {p_name, p_avatar}` | returns the player row |
| `POST /rpc/rename_player {p_name}`, `/rpc/set_avatar {p_avatar}` | return the player row |
| `POST /rpc/delete_me {}` | deletes player, runs and the auth user; the client must drop its tokens |
| `POST /rpc/upsert_run {p_run_id, p_day, p_rescued, p_kills, p_ended, p_victory, p_modifiers, p_version}` | returns the server-side points. `p_run_id` is a client generated uuid |
| `GET /leaderboard_points?order=rank&limit=100` | also `leaderboard_days`, `_rescued`, `_kills`, `best_run`; columns `rank, player_id, name, avatar, value` (`best_run`: + `day, victory, modifiers`). Own rank: `&player_id=eq.<uid>`. Readable without login. |
| `GET /modifiers` | `id, factor` |

RPC errors are HTTP 400 with `message` = code: `not_authenticated`, `no_player`, `already_registered`, `name_invalid`, `name_banned`, `name_taken`, `avatar_invalid`, `run_invalid`, `not_your_run`, `run_ended`, `rate_limit`, `rate_limit_new_runs`, `implausible`. Calling an RPC without being signed in gives HTTP 401 (`permission denied`).

Rules the client must respect:
- Names: 3-16 chars `[A-Za-z0-9 _-]`, no double/leading/trailing spaces, case-insensitive unique, filtered. `name_filter.gd` (P3) must use the same normalization as `name_normalize`: lowercase, strip accents, `0->o 1->i 3->e 4->a 5->s 7->t @->a $->s`, drop everything but `a-z`; match as substring against the banned list after blanking out allowed words (longest first). Extra number rules in `name_ok`: `1488` anywhere (digits of the whole name), `88` as a whole word.
- `upsert_run`: call it once at run start (day 1) and then every minute or so. Values only grow (lower values are ignored), modifiers are taken from the first call and then frozen, `ended = true` is final (later calls fail with `run_ended`). The `ended = true` call is exempt from the 30 s limit so a death right after a sync is not lost. A run that is played offline for many days and synced late fails with `implausible` until enough real time has passed.
- Plausibility (constants at the top of `upsert_run`): `day <= 1 + elapsed / 360 s` (a game day is 900 s after P5; 360 s keeps a wide margin), `kills <= 400 * day`, `rescued <= 60 * day`. Rate limits: 1 call per run per 30 s, 20 new runs per player per 24 h.
- Points: `run_points(day, rescued, kills, victory, factor)` = `floor((day*100 + rescued*25 + kills + victory*2000) * factor)`; factor = product of the `modifiers.factor` of the run's ids (unknown id = 1.0), capped at 3. P15 only inserts rows into `modifiers`; P18 edits `run_points`.

## What the player must know

The anonymous identity lives only on the device (`auth.json`; in the browser build in IndexedDB). Clearing browser data loses the link to the leaderboard entry; the name stays taken. There is no recovery. `delete_me` is the privacy option (deletes everything stored about the player).

## Findings of the doc check (2026-10-29)

- Anonymous sign-ins still exist (`signInAnonymously` / `POST /auth/v1/signup {}`), off by default, enabled per project. Anonymous users have the Postgres role `authenticated` (JWT claim `is_anonymous: true`), so RLS/grants must not assume "authenticated = real account"; here only RPCs that need a registered player are exposed.
- Supabase documents abuse of anonymous sign-ins as a risk (they are stored in `auth.users`) and recommends invisible CAPTCHA/Turnstile. Not enabled: the Godot client would need to solve it. Revisit if junk accounts appear.
- Sign-up / anonymous sign-in is rate limited per IP (docs: 30 per hour per IP; the dashboard may allow changing it). Players behind one NAT (school, LAN party) share it; the client signs in once and keeps the refresh token, so this should be rare.
- Free plan (third-party summaries only, supabase.com/pricing did not show the numbers in the search; recheck there): 500 MB database, 50k monthly active users (one older source says 10k), two free projects, **a free project pauses after about one week without activity** (resume with one click in the dashboard; data is kept). A leaderboard that is idle for a week is offline until resumed - upgrade or ping it (e.g. a scheduled GET) if that matters.
- A run row is ~150 bytes; 500 MB is far beyond this game.
- The views run as owner (no `security_invoker`) on purpose so they can aggregate all runs; the Supabase linter may warn about "security definer view", expected.
- Not done: renaming is not rate limited; name uniqueness is case-insensitive only (look-alikes such as `Bob`/`B0b` are different names).

## How it was tested

`test.sql` passes (`ALL TESTS PASSED`) on a local PostgreSQL 18 with a stub of the `auth` schema and roles, and on the real project (Postgres 17, via the Management API, rolled back, tables empty afterwards). An end-to-end check over the REST API with a real anonymous user covered: RPC without login denied, direct INSERT/SELECT on tables denied, register, `upsert_run`, rate limit, leaderboard read with the anon key, `delete_me` (player, runs and auth user gone); the project was empty afterwards.
