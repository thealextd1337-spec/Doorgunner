# Word list attribution

`banned_words.txt` is a curated subset of the English and German lists of
**List of Dirty, Naughty, Obscene, and Otherwise Bad Words** (LDNOOBW),
© 2012–2020 Shutterstock, Inc., https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words,
licensed under **Creative Commons Attribution 4.0 International** (https://creativecommons.org/licenses/by/4.0/).
License verified on 2026-10-29 (repository LICENSE file and GitHub license metadata: CC-BY-4.0; lists fetched at commit 5faf2ba).

Changes: entries were filtered (sexual-practice phrases, multi-word phrases and short or ambiguous words such as
"ass", "anal", "sex", "butt", "tit", "mong" removed because they match harmless names as substrings) and normalized
(lowercase, unaccented, letters only). Own additions: slurs, insults, Nazi terms and names, and all of `allowed_words.txt`.

`tools/gen_wordlist_sql.py` turns both lists into SQL inserts (`server/supabase/zz_wordlists.sql`); that output is derived from the same material.
