# Doorgunner – Roadmap „Tiefe“ (Stand 2026-10-28)

Plan für die parallele Umsetzung durch mehrere Agenten. Nur Plan, noch nichts gebaut.
Von Fable 5.1 gegen den Code geprüft (2026-10-28); die Befunde (Welt-Replay, Ladepunkt, Speichern im Angriff,
Tastenkonflikte, Personen-Fassade, Hotspots, Kosten des Straßen-A*, Web-Speicherung) sind eingearbeitet.
Entscheidungen des Users (2026-10-28): Speichern zuerst (Ironman-Autosave), Online-Rangliste über Supabase mit
Profil (Name + Profilbild) und Schimpfwortfilter, benannte Überlebende mit Fähigkeiten, Moral, neue Infizierte,
Angriffe mit Charakter, Funk-Aufträge, Evakuierung als optionaler Sieg (danach endlos weiter), Konvois,
Außenposten und verbündete Dörfer, feindliche Banditen-Fraktion, 3× größere Abstände zwischen Städten,
Verschleiß am Heli mit Autorotation, andere Helis als bergbare Wracks, Run-Modifier. Der Spieler bleibt der
Doorgunner (kein Zu-Fuß-Gameplay). Runs sollen viele Stunden tragen: Flug, Zombies und Fortschritt werden langsamer.

Probleme, die der Plan lösen soll (User): „Die Map fühlt sich immer gleich an, Kämpfe sind stumpf.“

---

## 0. Spielregeln für die parallele Umsetzung

### Ablauf
- Jedes Paket läuft in einem eigenen Git-Worktree auf dem Branch `t3/<paket-id>` (z. B. `t3/p1-save`).
- Merge-Reihenfolge: innerhalb einer Welle in der Reihenfolge der Tabelle, vor jedem Merge `git merge main` im
  Paket-Branch und alle Tests grün. Danach Review durch **Fable 5.1** (Code-Review des Diffs gegen dieses Dokument).
- Eine Welle startet erst, wenn alle Pakete der vorherigen Welle auf `main` sind (Ausnahme: als „früh“ markierte).
- Vor Welle 1: die aktuell offene Arbeit (Versionierung/Deploy in `game_state.gd`, `title_ui.gd`, `settings_ui.gd`,
  `tools/deploy_web.sh`) ist committet und gemergt.

### Modelle
| Modell | Wofür |
|---|---|
| **Opus 5.5** | Architektur und verzahnte Systeme: Speichern, Weltgenerator, Personen-Modell, Banditen-KI, Wracks/Helitypen, Konvois |
| **Sonnet 5.5** | Klar spezifizierte Features mit eigenen Dateien: Rangliste, UI, Infizierte, Angriffe, Aufträge, Außenposten, Evakuierung, Verschleiß |
| **Haiku 5.5** | Mechanische Arbeit: Wortlisten, Balance-Konstanten, README-Pflege |
| **Fable 5.1** | Review dieses Plans und jedes Merges (unabhängige Sicht, nicht Implementierer) |

### Konfliktregeln (Hotspots)
Gemeinsam genutzte Dateien: `game_state.gd`, `main.gd`, `chunk_manager.gd`, `spawner.gd`, `enemy.gd`, `heli.gd`,
`hud.gd`, `base.gd`, `base_ui.gd`, `poi.gd`, `title_ui.gd`, `tutorial.gd`, `progression.gd`, `tools/gen_sprites.py`
(inklusive der `TILES`-Liste, deren Index dem `enum T` entspricht), `README.md`.
- Neue Logik kommt in **neue Dateien** (`scripts/<system>.gd`). In Hotspots nur die im Paket genannten
  **Einhängepunkte** ändern (ein Aufruf, ein Signal, ein Eintrag in einer Tabelle).
- `game_state.gd`: neue Run-Variablen nicht dort, sondern im eigenen System-Node; der speichert sich selbst (siehe P1).
  Einzige Ausnahme: P7 (`Game.people`).
- **Stabile Fassade für Personen:** Alle Pakete verletzen, töten und zählen Leute nur über `Game.injure(n)`,
  `Game.lose_person(was_injured)`, `Game.passengers_injured`, `Game.rescued`, `Game.injured`. P7 baut die Personen
  dahinter, ändert diese Signaturen aber nicht. So laufen P9, P10 und P12 parallel zu P7.
- Neue Gegnertypen und Spawn-Gewichte nur über die Tabelle `scripts/spawn_table.gd` (legt P9 an), Angriffe nur über
  `scripts/assault.gd` (legt P10 an). `enemy.gd` bekommt pro Paket höchstens einen neuen Zweig in der Zustandsmaschine.
- `gen_sprites.py`: jedes Paket fügt eigene Funktionen am Ende an und trägt sie an einer Stelle in die Hauptliste ein.
  Ein neues Tile wird in `enum T` (`chunk_manager.gd`) **und** in `TILES` (`gen_sprites.py`) an derselben Position angehängt.
- `README.md`: jedes Paket ergänzt nur seine eigene Zeile bzw. seinen eigenen Absatz.
- Neue Tests: Datei `tests/<name>_test.gd` genügt, P1 stellt die Test-Auswahl in `main.gd` auf
  `SMOKE=<name>` → `tests/<name>_test.gd` um (Fallback mit `ResourceLoader.exists`), danach braucht kein Paket
  `main.gd` dafür anzufassen.
- **Tasten** (heute belegt: WASD/Pfeile, SPACE, Q, E, X, B, R, F, M, H im Titel, ESC, 1–8 im Bau-Modus):
  P13 **J** (Aufträge), P6 **L** (Rangliste, nur Titel), P14 **O** (Außenposten) und **P** (Dorf schützen),
  P15 **G** (Lasthaken). Kein Paket nimmt eine andere Taste ohne Eintrag hier.

### Pflicht pro Paket
1. Speicher-Hook (P1-Vertrag) für jeden neuen Zustand. Ein Paket ohne Speicher-Hook ist nicht fertig.
2. Ein headless Test `tests/<name>_test.gd` plus alle bestehenden Tests grün:
   `for s in 1 poi base ui prog tut nav found town <neu>; do SMOKE=$s godot --headless --path . --quit-after 30000; done`
3. README-Zeile, Texte im Spiel auf Englisch, Code auf Englisch.
4. Neue Zahlen als `const` oben in der eigenen Datei, damit P18 (Balance) sie findet.

---

## Übersicht der Pakete und Wellen

| Welle | Paket | Thema | Modell | Hängt ab von |
|---|---|---|---|---|
| 1 | **P1** | Speichern (Ironman), Profile auf der Platte | Opus | – |
| 1 | P2 | Supabase-Backend (SQL, RLS, RPCs) | Sonnet | – |
| 1 | P3 | Namensfilter (Client) + Wortlisten | Sonnet (Listen: Haiku) | – |
| 1 | P4 | Profilbilder (Porträts) in `gen_sprites.py` | Haiku | – |
| 1 | P5 | Tempo: Heli, Zombies, Tageslänge, XP langsamer | Sonnet | – |
| 2 | P6a | Online-Client (Auth, Token-Refresh, Warteschlange, RPCs) | Sonnet | P1, P2 |
| 2 | P6b | Profil-Erstellung, Profilverwaltung, Rangliste im Hauptmenü | Sonnet | P1, P3, P4, P6a-Schnittstelle |
| 2 | **P7** | Benannte Überlebende mit Fähigkeiten + Moral | Opus | P1 |
| 2 | **P8** | Weltgenerator: 3× Abstände, Makro-Raster, Landmarken, ordnungsunabhängig | Opus | P1 |
| 2 | P9 | Neue Infizierte + Trefferfeedback | Sonnet | P1, P5 |
| 3 | P10 | Angriffe mit Charakter (Richtung, Blutmond, Themenwellen) | Sonnet | P9 |
| 3 | **P11** | Banditen-Fraktion | Opus | P8, P9 |
| 3 | P12 | Verschleiß am Heli, Autorotation, Notlandung | Sonnet | P1, P5 |
| 3 | P13 | Funk-Aufträge | Sonnet | P7, P8 |
| 3 | P14 | Außenposten + verbündete Dörfer | Sonnet | P7, P8 |
| 4 | **P15** | Heli-Wracks bergen, reparieren, Helitypen, Run-Modifier | Opus | P8, P12 |
| 4 | **P16** | Konvois auf dem Straßennetz | Opus | P7, P8, P11 |
| 4 | P17 | Evakuierung (optionaler Sieg, danach endlos) | Sonnet | P7, P10, P11 |
| 5 | P18 | Integration: Balance-Pass über viele Stunden, Rangliste live, Deploy | Opus + Haiku | alle |

Fett = Pakete mit hohem Risiko, bei denen Fable zusätzlich den Ansatz vor dem Start prüft.

---

## Welle 1 – Fundament

### P1 Speichern (Ironman) und Profile auf der Platte · Opus 5.5
**Ziel:** Ein Run lässt sich beenden und später exakt fortsetzen. Ein Spielstand pro Profil, automatisch, Tod löscht ihn.

**Profile auf der Platte** (die UI dazu baut P6):
- `user://profiles/<profile_id>/meta.json` (heutiges `meta` pro Profil) und `.../run.sav` (laufender Run).
  `user://profiles.json`: Liste `[{id, name, avatar, created}]` und `last`.
- Migration: existiert `user://meta.json`, wird es zum ersten Profil „Gunner“ (Avatar 0); die Datei bleibt als Backup.
- Einstellungen (Lautstärke) bleiben global in `user://settings.json`, nicht pro Profil.
- API in `game_state.gd`: `profile_dir() -> String`, `switch_profile(id)`, `create_profile(name, avatar) -> String`.

**Speicher-Vertrag** (neues Autoload `Save`, `scripts/save.gd`):
```gdscript
Save.register(key: String, save_fn: Callable, load_fn: Callable) # save_fn() -> Variant (nur Built-in-Typen), load_fn(data)
Save.autosave()          # schreibt run.sav
Save.has_run() -> bool
Save.load_run() -> bool  # false: kein oder veralteter Stand
Save.delete_run()
```
- Format: `var_to_bytes()` eines Dictionaries `{version, saved_at, systems: {key: data}}`. Keine Objekte, keine Nodes.
  Vector2/Vector2i bleiben erhalten (deshalb nicht JSON).
- Schreiben atomar: `run.sav.tmp` schreiben, dann umbenennen; die vorherige Datei bleibt als `run.sav.bak`.
  Im Web-Build (IndexedDB) prüfen, ob `DirAccess.rename_absolute` funktioniert, sonst direkt schreiben.
- `version` = `config/version` aus `project.godot` plus eine eigene `SAVE_FORMAT`-Zahl. Bei anderem `SAVE_FORMAT`:
  Spielstand verwerfen und im Titel melden („Your saved run is from an older version and cannot be continued.“).
  In der Entwicklungsphase keine Migration.

**Was P1 selbst speichert:**
- `Game`: alle Run-Variablen (Ressourcen, Tag/Uhrzeit, Level, Items, Loadout, Basis-Bestand, Arbeiter, Gebäude,
  Sandsäcke, Verletzte, Stats nach `recompute()` neu berechnen statt speichern), `seed`.
- Heli: Position, Geschwindigkeit, Rotation, `landed`, aktuelle Waffe.
- Welt: `seed`, die Reihenfolge der geladenen Chunks (`chunks.loaded`, Dictionary-Reihenfolge) und ein
  **Änderungsprotokoll** `chunks.edits` (Zelle → Tile/Alternative/Prop entfernt). Alle Laufzeit-Änderungen gehen über
  die neue Funktion `chunks.edit(cell, tile, alt := 0)`: `base.gd:373`, `base.gd:498`, `enemy.gd:240` (`break_in`),
  `main.gd:91` (`paint_base_at`), `tutorial.gd:85`, außerdem das Entfernen von Props beim Abriss.
- **Welt-Ereignisprotokoll statt nur Chunk-Liste.** Der Generator hängt heute nicht nur von Seed und Ladereihenfolge
  ab, sondern auch von `Game.world.BASE_POS` (`chunk_manager.gd:295`, `:490`, `:1207`), das `main.found_base`
  verschiebt, und von der Gründung selbst (`paint_base_at` lädt vier Chunks und hängt an `_ports` an,
  `chunk_manager.gd:365-377`). Deshalb protokolliert P1 in Reihenfolge: `["chunk", cx, cy]` bei jedem `_ensure`,
  `["found", cell]` bei der Gründung. Beim Laden wird das Protokoll Eintrag für Eintrag abgespielt, `BASE_POS` wechselt
  genau beim `found`-Eintrag. Danach werden die `edits` angewendet. Das bleibt auch nach P8 korrekt (dann nur unnötig).
- **Ladepunkt:** Die Welt entsteht heute in `main._ready` mit `Game.new_run()` (neuer Zufalls-Seed) und lädt schon im
  ersten Frame 25 Chunks. CONTINUE setzt `Save.pending = true` und ruft `get_tree().reload_current_scene()`;
  `main._ready` prüft `Save.pending` **vor** `Game.new_run()` und dem Anlegen von `chunks`, übernimmt den Seed aus dem
  Stand und spielt das Protokoll ab, bevor `chunk_manager._process` läuft.
- **Lade-Reihenfolge der Hooks** fest: Game → Heli → Welt-Protokoll + edits → POIs → Base → Gegner → alle übrigen
  Systeme in Registrierungsreihenfolge. POIs verbinden sich in `_ready` mit `Game.heli` (`poi.gd:52`), deshalb Heli vor POIs.
- POIs: `chunk_manager` führt pro Chunk einen Zähler und übergibt `spawn_poi` eine `uid` = `"cx,cy#n"`.
  Gespeichert wird nur der veränderliche Zustand (`done`, `discovered`, verbliebene Überlebende, `hp`, `boarded` …).
  POIs außerhalb des Generators (Tutorial `tutorial.gd:86`, Supply Drop `systems/supply.gd:19`) bekommen
  `"dyn#<n>"` und werden vollständig gespeichert und neu erzeugt.
- Gegner: Art, Position, HP, `target_base`. Bei mehr als 150 nur die 150 nächsten zur Basis/zum Heli.
- Basis: zusätzlich `base.demolitions` (ohne Node-Referenz; das Prop wird über die Zelle wiedergefunden).
- Basis-Pawns werden nicht gespeichert, sondern aus dem Zustand neu aufgebaut (`base.sync_pawns`).
- Tutorial: Läuft eines, wird kein Run gespeichert. Ein abgebrochenes Tutorial startet neu.
- Typisierte Arrays (`heli_weapons: Array[String]`, `treating: Array[float]`) kommen aus `bytes_to_var` untypisiert
  zurück: mit `.assign()` laden.
- Mit jedem Autosave auch `_save_meta()`, denn `meta["assaults_held"]` u. a. ändern sich mitten im Run
  (`spawner.gd:32`). Der Kopf des Spielstands enthält `{day, rescued, kills}`, damit NEW RUN den alten Run werten kann.

**Wann gespeichert wird:** Landung auf dem Basis-Pad, Tageswechsel, alle 120 s im Flug, beim Schließen
(`NOTIFICATION_WM_CLOSE_REQUEST`). **Nicht** während `Game.attack_active` oder `attack_pending` (der Angriff beginnt bei
`time >= 0.8`, also vor dem Tageswechsel; die Wellen-Zähler in `spawner.gd:7-8` werden nicht gespeichert), dann wird
das Speichern bis zum Ende des Angriffs aufgeschoben. Web: Godot schreibt `user://` asynchron nach IndexedDB, ein
Speichern beim Tab-Schließen kann verloren gehen. Die echte Garantie sind die Speicherungen bei Landung und alle 120 s;
zusätzlich `visibilitychange` und `pagehide` über `JavaScriptBridge` (das Callback-Objekt in einer Member-Variable
halten, sonst wird es freigegeben). Tod: `Save.delete_run()` **bevor** der Game-Over-Screen erscheint.

**Titel:** Gibt es einen Stand: Knopf **CONTINUE** (Tag, Uhrzeit, Gerettete) über **NEW RUN**. NEW RUN mit
vorhandenem Stand fragt nach („Abandon the current run? It counts as lost.“) und wertet den alten Run als beendet
(Meta-Fortschritt wie bei Tod, Rangliste bekommt das Ergebnis).

**Nebenbei:** Test-Auswahl in `main.gd:56` auf Fallback umstellen (siehe Konfliktregeln).

**Tests (`SMOKE=save`):** Run starten, 10 Chunks laden, **dann** die Basis abseits des Startplatzes gründen, weitere
Chunks laden, Sandsack bauen, POI erledigen, Haus einreißen lassen, speichern, Szene neu laden, laden: gleiche
Ressourcen, gleiche Tiles an 500 Stichproben-Zellen (auch nahe der Basis und an Straßen), POI bleibt erledigt,
Sandsack steht. Zweiter Test: Tod löscht `run.sav`. Dritter: `SAVE_FORMAT` erhöht → Stand wird verworfen.
Vierter: Autosave während eines Angriffs wird aufgeschoben.

**Akzeptanz:** Laden nach Speichern ist für den Spieler nicht vom Weiterspielen zu unterscheiden (Ausnahme: Gegner
bekommen neue Pfade, Partikel fehlen).

### P2 Supabase-Backend · Sonnet 5.5 (früh, keine Spieldateien)
Alles in `server/supabase/` als SQL-Migrationen plus `server/README.md` mit der Einrichtung.
- **Manueller Schritt für den User:** Supabase-Projekt anlegen, Anonymous Sign-ins aktivieren, die Migrationen im
  SQL-Editor ausführen, Projekt-URL und **anon key** in `scripts/online_config.gd` eintragen (beide sind öffentlich,
  Schutz kommt aus RLS). Der `service_role` key kommt nie ins Repo.
  Vor der Umsetzung prüfen, ob Anonymous Sign-ins und die Free-Tier-Grenzen noch so bestehen.
- Tabellen:
  - `players(id uuid pk = auth.uid(), name citext unique, avatar smallint, created_at, hidden bool default false)`
  - `runs(id uuid pk, player_id, started_at, updated_at, ended bool, victory bool, day int, rescued int, kills int,
    modifiers text[], points int, game_version text)`
  - `banned_words(word text pk, lang text)`, `allowed_words(word text pk)` gegen Fehlalarme (Scunthorpe-Problem).
  - `modifiers(id text pk, factor numeric)`: Punkte-Faktoren der Run-Modifier. P2 legt die Tabelle an, P15 trägt nur
    Zeilen ein. `upsert_run` multipliziert die Faktoren der übergebenen ids, unbekannte ids zählen 1.0.
- Hinweis für die Spieler-Doku: Die anonyme Identität liegt nur auf dem Gerät (`auth.json`, im Browser IndexedDB).
  Wer Browserdaten löscht, verliert die Verbindung zu seinem Ranglisten-Eintrag; der Name bleibt dann belegt.
- RLS: Lesen von `players` (ohne `hidden`) und der Ranglisten-Views für alle; Schreiben nur über RPCs.
- RPCs (`security definer`):
  - `register_player(name, avatar)`: Namensregeln (3–16 Zeichen, `[A-Za-z0-9 _-]`, keine doppelten Leerzeichen),
    Filter (Funktion `name_ok(text)`: Kleinbuchstaben, `unaccent`, Leetspeak-Map `0→o 1→i 3→e 4→a 5→s 7→t @→a $→s`,
    Nicht-Buchstaben raus, Treffer als Teilwort gegen `banned_words`, Ausnahmen aus `allowed_words`), eindeutig.
  - `rename_player(name)`, `delete_me()` (löscht Spieler und Runs: Datenschutz).
  - `upsert_run(run_id, day, rescued, kills, ended, victory, modifiers, version)`: Werte dürfen nur steigen;
    Plausibilität: `day <= 1 + (now() - started_at) / interval '6 min'` (ein Spieltag dauert mindestens so lange,
    an P5 anpassen), `kills <= 400 * day`, `rescued <= 60 * day`. Punkte berechnet der Server, nicht der Client.
- Punkte pro Run: `day * 100 + rescued * 25 + kills * 1 + (victory ? 2000 : 0)`, multipliziert mit dem Faktor der
  Run-Modifier (P15). Formel als SQL-Funktion `run_points(...)`, damit P18 sie ändern kann.
- Views: `leaderboard_points` (Summe aller Runs pro Spieler), `leaderboard_days` (Summe Tage), `leaderboard_rescued`,
  `leaderboard_kills`, plus `best_run` (höchste Punkte eines einzelnen Runs). Jeweils Rang, Name, Avatar, Wert.
- Rate-Limit: höchstens 1 `upsert_run` pro Run alle 30 s, höchstens 20 neue Runs pro Spieler und Tag.
- Ehrlich: Ein Client-Spiel lässt sich nicht fälschungssicher machen. Plausibilität und Rate-Limit halten nur
  gelegentliche Manipulation auf. Moderation: `hidden = true` im Supabase-Dashboard.
- Test: `server/test.sql` mit Fällen (gültiger Name, Schimpfwort, Leetspeak, erlaubtes Wort mit Teilstring,
  Doppelname, unplausibler Run).

### P3 Namensfilter im Client · Sonnet 5.5 (Wortlisten: Haiku 5.5)
- `scripts/name_filter.gd` mit `static func check(name: String) -> String` (leer = ok, sonst Grund auf Englisch).
  Dieselbe Normalisierung wie `name_ok` in P2, damit der Spieler sofort Rückmeldung bekommt. Der Server bleibt maßgeblich.
- Wortlisten `data/banned_words.txt` (Deutsch + Englisch, Beleidigungen, Slurs, Nazi-Begriffe und Codes wie 88/1488
  als eigene Regel), `data/allowed_words.txt`. Herkunft: eine frei lizenzierte Liste (z. B. LDNOOBW, CC-BY-4.0:
  Namensnennung in `data/ATTRIBUTION.md` nötig, Lizenz vor der Übernahme erneut prüfen) plus eigene Ergänzungen. Dieselben Listen erzeugen die SQL-Inserts für P2 (`tools/gen_wordlist_sql.py`).
- Test `SMOKE=filter`: 30 Fälle, inklusive Fehlalarm-Fälle (Wörter, die ein verbotenes Wort enthalten, aber harmlos sind).

### P4 Profilbilder · Haiku 5.5 (früh, nur `gen_sprites.py` und `assets/`)
- 12 Porträts 48×48 (bei 4× erzeugt, wie die übrige Art) im Field-Map-/RimWorld-Stil: Doorgunner mit Helm/Headset,
  Mütze, Bart, kurze/lange Haare, verschiedene Hauttöne, Gesichtstarnung, Gasmaske, Sonnenbrille. Gemischte Geschlechter.
- Ausgabe `assets/sprites/b/avatar_00.png` … `avatar_11.png`, Vorschau `docs/avatars.png`.
- Kein Hochladen eigener Bilder (keine Moderation nötig).

### P5 Tempo · Sonnet 5.5
Ziel: Ein Run trägt viele Stunden, alles wirkt schwerer. Startwerte, die P18 nachjustiert:
| Wert | Heute | Neu |
|---|---|---|
| `heli.gd` `MAX_SPEED` / `ACCEL` | 160 / 220 | 115 / 150 |
| Zombies `speed` (shambler / runner / brute / boss) | 16 / 58 / 13 / 12 | 12 / 42 / 10 / 9 |
| `DAY_SECONDS` | 600 | 900 |
| `xp_needed()` | `25 * L^1.4` | `30 * L^1.6` |
| Kraftstoffverbrauch (`heli.gd:108-114`, `burn = 0.35 + vel/MAX_SPEED * 0.9` pro s) | Starttank ≈ 80–120 s bei Vollgas | Faktoren so senken, dass ein voller Starttank ~5 min Flug bei Vollgas trägt |
| Meta-Freischaltungen (`progression.gd` `unlock`) | 25 / 50 Gerettete … | ×2 |
| `danger_at()` Anstieg pro Tag | 0.15 | 0.08 |

Überlebende (`survivor.gd`) und Basis-Pawns behalten ihr Tempo, sonst dauert das Einsteigen zu lange.
Test: bestehende Tests anpassen, wo sie Flugzeiten oder Distanzen annehmen (`smoke.gd` fliegt 600 px nach Osten).

---

## Welle 2 – Kernsysteme

### P6a Online-Client · Sonnet 5.5
- `scripts/online.gd` (Autoload `Online`): `HTTPRequest` gegen die Supabase-REST-API und Auth-API.
- Anonyme Anmeldung, Access-Token läuft nach ca. 1 h ab: Refresh-Token nutzen, bei 401 einmal erneuern und wiederholen.
  Tokens in `user://profiles/<id>/auth.json`.
- Schnittstelle für P6b (zuerst festlegen und als Stub committen, damit P6b parallel arbeiten kann):
  `register(name, avatar) -> signal done(ok, error)`, `rename(name)`, `delete_me()`,
  `submit_run(run_id, stats: Dictionary)`, `fetch_board(kind, limit) -> signal board(rows, own_row)`,
  `fetch_player(id) -> signal player(stats)`, `is_online() -> bool`.
- Warteschlange für `submit_run` in `user://profiles/<id>/outbox.json`, wird bei Fehlern später gesendet.
  Run-Ergebnis bei jedem Tageswechsel und beim Run-Ende (auch endlose Runs erscheinen live).
- **Keine Offline-Runs in der Rangliste** (User, 2026-10-29): Der erste `upsert_run` geht beim Run-Start (Tag 1) raus.
  Klappt er nicht, ist der Run lokal markiert (`ranked = false`, im Spielstand), läuft normal weiter und wird nie
  gesendet; der Titel zeigt „Offline – this run is not ranked“. Ein gewerteter Run, der unterwegs die Verbindung
  verliert, sammelt Updates in der Outbox und reicht sie nach (P2 lehnt sonst zu viele Tage auf einmal als
  `implausible` ab). P2 hat dafür `set_avatar` zusätzlich, Fehlercodes stehen in `server/README.md`.
- Desktop- und Web-Build (CORS bei Supabase prüfen). Test `SMOKE=online` gegen einen lokalen Stub
  (`ONLINE_URL` zeigt auf einen kleinen Python-Server in `tools/fake_supabase.py`).

### P6b Profil und Rangliste im Hauptmenü · Sonnet 5.5
- **Erster Start / neues Profil:** Bildschirm „ENLIST“: Name eingeben (Live-Prüfung mit `NameFilter.check`), Porträt aus
  dem 4×3-Raster wählen, Hinweis „Your name and portrait are shown on the public leaderboard.“
  Online: `register_player`; Name vergeben → Meldung, anderer Name. Offline: Profil wird lokal angelegt und beim
  nächsten Online-Kontakt registriert.
- **Titel:** Porträt + Name oben links, Knopf **PROFILES** (wechseln, neu, umbenennen, löschen mit Rückfrage;
  Löschen ruft `delete_me`). Meta-Fortschritt und Spielstand gehören zum Profil (P1).
- **Rangliste** (Knopf **LEADERBOARD**, Taste L): Reiter **POINTS / DAYS / RESCUED / KILLS / BEST RUN**, Top 50 mit
  Rang, Porträt, Name, Wert; die eigene Zeile immer sichtbar (auch außerhalb der Top 50). Klick auf einen Spieler zeigt
  seine Aufschlüsselung (Punkte gesamt, Tage, Gerettete, Kills, Runs, Siege, bester Run).
  Offline: „Leaderboard offline“ plus die eigenen lokalen Werte.
- Test `SMOKE=profile`: Profil anlegen, wechseln, Meta getrennt, Namensprüfung, Rangliste rendert Stub-Daten.

### P7 Benannte Überlebende mit Fähigkeiten + Moral · Opus 5.5
**Personen-Modell** (größter Umbau in Welle 2):
- `Game.people: Array[Dictionary]`: `{id, name, skill, skill_lv 1-3, trait, injured, job, mood, origin_day}`.
  `rescued`, `injured` und die Arbeiterzahlen werden daraus **abgeleitet** (Getter), damit bestehender Code und Tests
  weiterlaufen. `workers` bleibt als Soll-Zahl pro Job, die Zuteilung wählt automatisch die Passendsten
  (Fähigkeit vor Zufall).
- Passagiere sind Personen: Siedlungen erzeugen Personen beim Einsteigen, `poi.gd` gibt sie an den Heli, die Basis
  übernimmt sie bei der Lieferung. Bei vollen Sitzen zeigt der HUD, wer an Bord ist (Name + Fähigkeit-Icon).
- Fähigkeiten: **Mechanic** (repair, workshop, später Heli-Reparatur P15), **Farmer** (farm, water), **Medic**,
  **Soldier** (militia, trifft besser), **Builder** (build, demolish), **Driver** (Konvois P16), **Engineer** (selten:
  Generator, Funkstation P17, Heli-Reparatur ×2). Passender Job: Rate ×1.5 (Stufe 2: ×1.75, Stufe 3: ×2).
  Stufe steigt nach 5/15 Tagen im passenden Job.
- Ein Trait pro Person (optional, 50 %): Tough (seltener verletzt), Glutton (isst 1.5×), Lazy (×0.8), Brave
  (Moral-Verlust bei Angriffen halbiert), Insomniac (arbeitet nachts mit 50 %).
- Namen: `data/names.txt` (international gemischt, ~300 Vor- und ~300 Nachnamen), deterministisch aus Run-Seed.
- WORKERS-Tab: pro Job die Personen mit Fähigkeit; Klick auf eine Person zeigt Name, Fähigkeit, Trait, Stimmung,
  Tage in der Basis. Tod einer Person meldet der Funk mit Namen („Base: Marta Kowalski didn't make it.“).

**Moral** (`scripts/morale.gd`):
- Basiswert 0–100, startet bei 60. Täglich: −10 Hunger, −10 Durst, −5 pro Camper-Anteil 25 %, −8 pro Toter (an dem
  Tag), −5 wenn Angriff mit Verlusten; +5 Strom, +5 genug Betten, +3 pro gehaltenem Angriff, +8 Sieg über
  Banditenlager (P11), +4 pro geretteter Gruppe ≥ 4.
- Wirkung: < 40 Arbeitsrate ×0.85, < 25 jede Nacht 10 % Chance, dass jemand geht (mit Name im Funk), > 75 Rate ×1.1.
- Status-Spalte im Basis-Menü zeigt Moral mit den drei stärksten Gründen.
- Test `SMOKE=people`: Lieferung erzeugt Personen mit Namen, Zuteilung bevorzugt Fähigkeit, Tod entfernt die
  richtige Person, Getter `rescued` stimmt, Moral fällt bei Hunger. Speicher-Hook für `people` und Moral.

### P8 Weltgenerator: größer, abwechslungsreicher, ordnungsunabhängig · Opus 5.5
**Ziel:** Städte ~3× weiter auseinander, dazwischen große, unterschiedliche Landschaften mit Landmarken. Jeder Chunk
ergibt sich nur aus Seed und Koordinate, egal in welcher Reihenfolge geladen wird.
- **Makro-Raster:** Zellen von 5×5 Chunks (2560 px). Jede Makrozelle hat genau einen deterministisch gejitterten
  Standort (Hash aus Seed + Makrozelle): Stadt, Dorf-Typ (die sieben Vorlagen), City (selten), Landmarke oder leer.
  Ersetzt `TOWN_CHANCE` pro Chunk. Mittlerer Abstand zwischen Orten ~2600 px statt ~870 px.
- **Straßennetz deterministisch:** Jeder Standort verbindet sich mit seinen 2 nächsten Nachbarn im Makro-Graph
  (aus den 3×3 umgebenden Makrozellen berechnet). Der Weg kommt aus A* über die **reine** Terrainfunktion `_terrain()`
  (nicht über geladene Tiles), daher in jedem Chunk gleich. Ein Chunk malt beim Laden nur die Wegstücke, die durch ihn
  laufen. `_ports`, `_net`, `_pending` und `ROAD_REACH` fallen weg oder werden zum Cache. Asphaltstraße zwischen
  Cities, Feldwege sonst. Brücken über Flüsse (neues Tile `BRIDGE`, in `enum T` und `TILES` anhängen) statt Furten > 2 Zellen.
- **Kosten:** A* über ~160×160 Zellen mit `_terrain()`-Aufrufen kostet ~50–100 ms pro Straße; beim Betreten einer
  Makrozelle können bis zu ~18 Straßen nötig werden. Deshalb: grobes A* auf 4×4-Zellen-Knoten, danach nur die Feinlage
  im Korridor; Ergebnis pro Standort-Paar cachen; Berechnung vorausschauend für Makrozellen in Flugrichtung, verteilt
  über mehrere Frames (Budget ~4 ms pro Frame). Abnahme: kein Frame über 50 ms beim Flug über Makrogrenzen.
- **Straßenanschlüsse ohne Malen:** Die Ortsvorlagen (`_village`, `_hamlet`, `_city` …) werden in einen reinen
  Layout-Schritt (liefert Zellen und Straßenenden) und einen Mal-Schritt geteilt, damit Straßenenden eines Nachbarorts
  bekannt sind, ohne dessen Chunk zu laden.
- **Abhängigkeit von `BASE_POS` entfernen:** Generator-Entscheidungen nahe der Basis (`chunk_manager.gd:490`, `:1207`)
  beziehen sich auf den Startplatz (fest), nicht auf die gegründete Basis. Die Gründung selbst ist nur noch ein Edit.
- **Größere Regionen:** Biom-Rauschen mit 1/3 der Frequenz. Neue Regionen: **Highland** (Fels, Nadelwald, Steinbrüche,
  enge Täler) und **River valley** (breiter Fluss mit Auen, Brücken als Engstellen). Bestehende Regionen bekommen
  innere Abwechslung: Lichtungen, Waldseen, Windschutzhecken, Obstplantagen, abgebrannte Flächen.
- **Landmarken** (Stempel-Vorlagen, je Region gewichtet): Tankstelle, Militär-Checkpoint, Campingplatz, Steinbruch,
  kleiner Flugplatz (Heli-Wrack-Standort für P15), Funkmast (heutiger relay tower), Staudamm, abgestürztes
  Verkehrsflugzeug (viel Bergegut), Gefängnis (Banditen-Festung für P11), Motel, Holzfällerlager, Kirchenruine,
  Autobahnabschnitt mit Autowracks. Jede Landmarke meldet sich als Standort mit Typ, damit P11/P14/P15 sie finden:
  `chunks.sites_near(pos, radius, kind := "") -> Array[Dictionary]` (`{kind, pos, uid}`).
- Wilde POIs zwischen den Orten seltener und an Landmarken gebunden; in der Wildnis überwiegend Natur.
- Kraftstoff: Tankstellen und Checkpoints geben Treibstoff (neue POI-Art `fuel_station`), damit die größeren Wege fliegbar sind.
- Der Startplatz bleibt in Chunk (0,0), die nächste Siedlung liegt höchstens ~1200 px entfernt (Tutorial und
  `found_test`/`tutorial_test` brauchen das). Dafür in der Start-Makrozelle einen Ort erzwingen (heute schließt
  `_has_town` Chunk (0,0) aus, Cities erst ab 3 Chunks Abstand).
- Speicher: Mit P1-Protokoll kompatibel. Ist der Generator ordnungsunabhängig, lädt P1 nur noch die Chunks um den Heli.
- Tests: `town_test` anpassen; neuer `SMOKE=world`: dieselben 30 Chunks in zwei Reihenfolgen erzeugen → identische
  Tiles; jede Stadt hat eine Straße zu einem Nachbarn; Abstand zwischen benachbarten Orten im Mittel 2200–3000 px;
  Screenshots aller Regionen und Landmarken nach `docs/region_*.png` (`SMOKE=shot`, `SHOT_AT`).

### P9 Neue Infizierte + Trefferfeedback · Sonnet 5.5
Kämpfe sind „stumpf“: Jeder neue Typ kontert eine bestimmte Verteidigung oder zwingt zu einer anderen Taktik.
| Typ | Verhalten | Kontert | Konter |
|---|---|---|---|
| **Screamer** | bleibt stehen und schreit (3 s Anlauf, sichtbar): großer Lärm, zieht Zombies im Umkreis 600 px an | Leise Landungen | Zuerst erschießen, Anlauf ist lesbar |
| **Spitter** | hält Abstand 80–120 px, spuckt Säure: Schaden an Sandsäcken/Draht, Pfütze 4 s | Sandsack-Linien | Lange Reichweite, Railgun |
| **Crawler** | flach, kriecht unter Draht ohne Verlangsamung, schwer zu treffen (−40 % Trefferfläche) | Stacheldraht | Flak, Splash |
| **Bloater** | langsam, viel HP, platzt beim Tod: Giftwolke 3 s, verletzt Personen in der Basis | Nahe Verteidigung | Auf Distanz töten |
| **Elite-Varianten** | ab Tag 10: gepanzerte Brute (Front −70 % Schaden), Runner-Rudel | Frontales Feuer | Flanke über Q/E |

- Neue Datei `scripts/spawn_table.gd`: Gegnertypen und Spawn-Gewichte nach Gefahr und Region (Bloater eher Stadt,
  Crawler eher Wald/Sumpf). `spawner._pick` liest nur noch daraus; spätere Pakete ergänzen dort Zeilen.
- Bloater-Gift in der Basis und Treffer auf Personen nur über `Game.injure(n)` (Fassade, siehe Konfliktregeln).
- **Trefferfeedback:** kurzer Rückstoß, weißes Aufblitzen beim Treffer, Blut-/Splitter-Partikel, Leichen bleiben 60 s
  liegen (max. 120, älteste zuerst weg), Kopfschuss-Chance mit Extra-Schaden bei Optics, leichter Screenshake bei
  schweren Waffen (Option im ESC-Menü), Treffer-Sound abhängig vom Ziel.
- Sprites der neuen Typen in `gen_sprites.py`. Test `SMOKE=infected`: jeder Typ zeigt sein Verhalten (Screamer
  erzeugt Lärm, Spitter beschädigt Sandsack, Crawler verliert im Draht kein Tempo, Bloater verletzt bei Tod).

---

## Welle 3 – Gegner, Aufträge, Logistik

### P10 Angriffe mit Charakter · Sonnet 5.5
- Neue Datei `scripts/assault.gd` übernimmt `spawner._on_attack` und die Wellensteuerung; `spawner.gd` delegiert nur.
  Wellen-Zustand registriert einen Speicher-Hook (dann darf P1 auch während eines Angriffs speichern; bis dahin bleibt
  das Aufschieben aus P1).
- **Richtung angesagt:** Mit Watchtower meldet der Funk am Vorabend die Hauptrichtung („Watchtower: movement north-east.“),
  der HUD zeigt einen Pfeil am Basisrand. Ohne Watchtower: keine Richtung. Wellen kommen zu 70 % aus dieser Richtung.
- **Themenwellen** (zufällig, ab dem 2. Angriff): Runner-Sturm, Brute-Rammbock (zielt auf Tor/Sandsack-Lücken),
  Spitter-Belagerung (bleibt auf Abstand), Screamer-Kette (Wellen werden größer, bis die Screamer tot sind),
  Mischwelle. Name im Funk und im HUD.
- **Blutmond** jede 9. Nacht ab der ersten Basis-Gründung: roter Himmel, Welle endet erst, wenn alle Angreifer tot sind
  (die Nacht wird bis dahin verlängert), Boss garantiert, Belohnung ×2 XP, Moral +10 nach dem Halten.
- **Belagerungsphasen:** Welle in 2–3 Schüben mit Pausen (Zeit zum Nachladen und Reparieren) statt Dauerstrom.
- Test `SMOKE=assault`: Themenwelle spawnt passende Typen, Blutmond endet nicht vor dem letzten Angreifer.

### P11 Banditen-Fraktion · Opus 5.5
- **Lager:** an Landmarken (Gefängnis, Checkpoint, Motel, Steinbruch) über `chunks.sites_near`. Ab Tag 4 erste Lager,
  dichter mit der Entfernung. Lager haben Wachen, ein MG-Nest, später einen RPG-Schützen, und Beute: Gewehre,
  Treibstoff, Munition, Gefangene (= Personen mit Fähigkeiten, P7).
- **Einheiten:** `bandit.gd` (Infanterie mit Gewehr, sucht Deckung hinter Häusern/Hecken/Wald, schießt auf Heli in
  Reichweite, kämpft auch gegen Zombies und macht dabei Lärm), `technical.gd` (Pickup mit MG, fährt auf dem
  Straßennetz von P8, Flugabwehr). Der RPG-Schütze zielt 1.5 s sichtbar (rote Linie und Funk-Warnung), danach Rakete:
  Ausweichen oder **Flares** (vorhandenes System) lenken sie ab. Heute kommen Flares erst auf Stufe 5 in die Gruppe
  `decoys` (`systems/flares.gd:28`); für Raketen zählt jede Flare ab Stufe 1 (eigene Gruppe `rocket_decoys`).
- **Verhalten:** Patrouillen zwischen Lager und Nachbarorten, überfallen Siedlungen (nehmen Leute mit), Außenposten
  (P14), Konvois (P16) und später die Basis (Überfall-Event, ab Tag 12, getrennt von den Zombie-Angriffen und nie in
  derselben Nacht). Ein ausgehobenes Lager bleibt leer.
- **Ziel des Heli:** Banditen schießen auf den Heli (anders als Zombies). Damit wird Flughöhe/Abstand wichtig.
- Funk: Abgefangener Banditenfunk kündigt Überfälle an (Hinweis für Aufträge P13).
- Test `SMOKE=bandits`: Lager spawnt Wachen, Technical folgt der Straße, Bandit trifft Heli, Flare lenkt Rakete ab,
  Banditen und Zombies bekämpfen sich.

### P12 Verschleiß am Heli, Autorotation, Notlandung · Sonnet 5.5
- Komponenten mit Zustand 0–100 %: **Rotor, Engine, Gearbox, Door gun**. Verschleiß pro Flugminute (klein) und durch
  Treffer (Banditen-Treffer zählen mehr). Reparatur in der Basis: Repair-Arbeiter + Teile (`salvage.parts`), Mechanic-
  Fähigkeit beschleunigt. HANGAR-Tab zeigt die vier Balken und Kosten.
- Wirkung unter 50 %: Engine → weniger Höchstgeschwindigkeit, Rotor → Vibration (Zielen streut), Gearbox → mehr
  Treibstoff, Door gun → Ladehemmung (kurze Pausen beim Dauerfeuer).
- **Triebwerksausfall:** Chance steigt unter 25 % Engine stark; Warnton und Funk 3 s vorher. Dann **Autorotation**:
  kein Schub, der Heli gleitet mit abnehmendem Tempo 8–12 s, der Spieler lenkt und drückt SPACE für die Landung.
  Landung auf freiem Boden: Hüllenschaden, Passagiere können verletzt werden (Choplifter-Idee). Landung auf
  Wald/Wasser/Haus: schwerer Schaden.
- **Notgelandet:** Der Heli steht, die Crew repariert vor Ort (Balken 45 s, schneller mit Mechanic an Bord), der Spieler
  verteidigt mit der Door gun (bleibt Doorgunner). Danach Start mit Engine 30 %. Kein Zu-Fuß-Gameplay.
- Test `SMOKE=wear`: Verschleiß sinkt im Flug, Ausfall startet Autorotation, Landung → Reparatur → Start möglich.

### P13 Funk-Aufträge · Sonnet 5.5
- `scripts/missions.gd`: höchstens 3 offene Aufträge, neue kommen per Funk (Ton + Zeile), Liste im HUD (Taste J) mit
  Ziel, Richtung/Entfernung, Restzeit und Belohnung. Annehmen ist implizit (hinfliegen), Ablauf = verfallen.
- Auftragstypen:
  - **Rooftop rescue:** Familie auf einem Dach in einer City, 4–6 min, Landung auf dem Dach nicht möglich →
    Winch oder Landung im Hof daneben unter Beschuss.
  - **Medicine run:** Medizin aus der Basis zu einem verbündeten Dorf (P14) bringen.
  - **Black box / parts:** Teil aus einer Absturzstelle bergen (liefert Schlüsselteile für Heli-Reparatur P15).
  - **Clear the camp:** Banditenlager ausheben (P11).
  - **Silence the screamer:** Screamer-Nest, das jede Nacht Horden Richtung Siedlung zieht.
  - **Escort:** Flüchtlingsgruppe zu Fuß auf der Straße zur Basis begleiten (läuft auf dem Straßennetz).
- Belohnung: Schrott, XP, Moral, oft eine **Person mit seltener Fähigkeit** (Engineer, Driver) oder ein Schlüsselteil.
- Test `SMOKE=missions`: Auftrag entsteht, Ziel ist gültig, Erfüllung gibt Belohnung, Ablauf entfernt ihn.

### P14 Außenposten und verbündete Dörfer · Sonnet 5.5
- **Außenposten:** An Tankstellen, Checkpoints, Funkmasten. Landen und **O** drücken: kostet 40 Schrott und 2 Militia
  aus der Basis (werden per Heli hingeflogen, zählen als Passagiere). Ein Außenposten ist ein kleines Pad mit Tank:
  auftanken (Treibstoff, den die Tankstelle langsam liefert oder den man hinbringt), Munition aus einer Kiste,
  Speicherpunkt (P1 speichert bei Landung). Er kann überfallen werden (Zombies nachts, Banditen), Garnison verteidigt.
  Maximal 1 + Watchtower-Stufen Außenposten.
- **Verbündete Dörfer:** Eine Siedlung, deren Leute man nicht alle mitnimmt, kann man nach dem Freikämpfen „schützen“
  (**P** bei Landung): Sie bleibt bestehen, wird Verbündeter, liefert alle 2 Tage Nahrung/Wasser per Abholung,
  stellt Aufträge (P13) und kann fallen, wenn man sie lange nicht besucht oder Banditen sie überfallen.
- Karte/Minimap zeigt Außenposten und Verbündete mit Zustand.
- Test `SMOKE=outpost`: Gründen, auftanken, Garnison hält einen kleinen Angriff, Dorf liefert Nahrung.

---

## Welle 4 – Große Systeme

### P15 Heli-Wracks, Helitypen, Run-Modifier · Opus 5.5
- **Helitypen** (`scripts/heli_types.gd`, eine Tabelle): Grundwerte pro Typ, auf die Items und Loadout aufsetzen.
  | Typ | Rolle | Sitze | Hardpoints | Tempo | Panzerung | Besonderes |
  |---|---|---|---|---|---|---|
  | **Huey** | Start, Allrounder | 4 | 1 | 100 % | 100 % | – |
  | **Little Bird** | Späher | 2 | 1 | 135 % | 60 % | schnellster Spool, leise (halber Lärm) |
  | **Black Hawk** | Kampf/Transport | 8 | 2 | 95 % | 140 % | zwei Door guns gleichzeitig |
  | **Chinook** | Schwerlast | 14 | 1 | 75 % | 120 % | Lasthaken stark (Wracks ohne Tempoverlust), Evakuierung schneller |
  | **Hind** | Kanonenboot | 4 | 3 | 90 % | 170 % | selten, nur an Militär-Landmarken |
- **Wracks finden:** an Flugplätzen, Checkpoints, Absturzstellen (P8-Standorte). Zustand und Typ zufällig.
- **Bergen:** über dem Wrack hovern (langsam, < 20 % Tempo) und **G** drücken: Haken wird abgelassen, nach 4 s
  ruhigem Hovern ist das Seil eingehakt (SPACE bleibt Landen). Mit Last: Tempo −50 % (Chinook −15 %), Treibstoff ×2,
  Pendeln der Last (träge Physik, Kollision mit Bäumen ruckt), keine Landung möglich, Zombies und Banditen greifen an.
  **G** erneut klinkt aus: innerhalb des Basiszauns wird das Wrack abgesetzt, sonst bleibt es dort liegen und kann
  später wieder geholt werden.
- **Reparatur:** großes Bauprojekt im HANGAR-Tab: viel Metall/Teile/Elektronik (z. B. 200/120/60), 1–3
  **Schlüsselteile** (Rotorkopf, Turbine, Avionik: aus Aufträgen P13 und Militär-Landmarken), und 10–20 Arbeitstage
  von Mechanics (Engineer ×2). Fortschrittsbalken, dauert bewusst mehrere Spieltage.
- **Wechseln:** Repariert steht der Heli in der Basis. Am Pad im HANGAR-Tab den aktiven Heli wählen. Items und
  Waffen bleiben am jeweiligen Heli, Verschleiß (P12) pro Heli. Der zweite Heli kann einen notgelandeten (P12) nicht
  automatisch retten – optionaler Ausbau für später.
- **Meta:** Der erste reparierte Typ eines Profils wird dauerhaft als Start-Heli wählbar (Titel → NEW RUN).
- **Run-Modifier** (Titel → NEW RUN, freiwillig, Punkte-Faktor für die Rangliste, je eigener Meta-Unlock):
  Dense Horde (+50 % Zombies, ×1.3), Warlords (Banditen ab Tag 1, ×1.25), Scarcity (−30 % Beute, ×1.25),
  Dry Season (Brunnen −50 %, ×1.15), Glass Cockpit (−40 % Hülle, ×1.3), Blackout (Karte deckt nichts auf, ×1.2).
  Faktoren multiplizieren sich, Obergrenze ×3. Werden mit dem Run gespeichert und an `upsert_run` gesendet.
- Test `SMOKE=wreck`: Wrack einhaken, mit Last fliegen (Tempo/Verbrauch), absetzen in der Basis, Reparatur mit
  Teilen abschließen, Heli wechseln, Werte stimmen.

### P16 Konvois · Opus 5.5
- Neues Gebäude **Motor Pool** (Build-Tab, 80 Schrott). Fahrzeuge: **Truck** (Bergegut, 4 Personen) aus Bergegut
  baubar, Wracks von Autos an Autobahn-Landmarken liefern Teile.
- Im Basis-Menü (Reiter CONVOY): Ziel wählen (bekannter Ort, Landmarke, verbündetes Dorf, Außenposten), Fahrer
  (Driver-Fähigkeit nötig) und bis zu 3 Begleiter (Militia mit Gewehren). Der Konvoi fährt über das Straßennetz
  (A* nur auf Straßen-Tiles, eigener Cache), plündert am Ziel (Zeit), fährt zurück.
- Gefahren: Zombies auf der Straße (Fahrzeug wird langsamer, nimmt Schaden), Banditen-Hinterhalte (P11) an Brücken
  und Engstellen. Funk meldet „Convoy under attack“ mit Richtung → Heli eskortiert. Ein zerstörter Truck verliert
  Ladung, Personen können verletzt werden oder sterben.
- Liefert Bergegut, Nahrung und Treibstoff in großen Mengen: Ersatz für viele Einzelflüge in den späteren Tagen.
- Test `SMOKE=convoy`: Konvoi fährt nur auf Straßen, kommt an, plündert, kehrt zurück; Hinterhalt stoppt ihn.

### P17 Evakuierung (optionaler Sieg) · Sonnet 5.5
- Ab Tag 15 meldet der Funk eine Militärfrequenz. Bauprojekt **Radio Station** (Engineer nötig, Elektronik) stellt
  Kontakt her. Danach: **Airstrip** bauen (gerade, freie Fläche 4×24 Zellen in der Basis oder an einem Außenposten,
  Felder und Straßen erlaubt, Bäume müssen weg). In der Basis braucht das mindestens Perimeter-Stufe 1
  (Radius ≥ 220 px), sonst passt die Bahn nicht hinein.
- Countdown 3 Tage, dann **letzte Belagerung**: größter Angriff des Runs plus Banditen-Überfall, die Transportmaschine
  landet in der zweiten Hälfte der Nacht und braucht 60 s zum Einsteigen; der Spieler hält die Landebahn.
- Sieg-Bildschirm: Gerettete, Tage, Kills, Personen mit Namen, die mitflogen; Ergebnis mit `victory = true` an die
  Rangliste. Wahl: **END RUN** (Run endet mit Sieg) oder **STAY BEHIND** (Run geht endlos weiter, Sieg bleibt
  gezählt, Gefahr steigt weiter, ein zweiter Sieg ist nicht möglich).
- Wer die Evakuierung nie anstößt, spielt einfach endlos.
- Test `SMOKE=evac`: Kontakt, Airstrip-Prüfung, Countdown, Belagerung, Sieg wird gezählt, STAY BEHIND läuft weiter.

---

## Welle 5 – Integration

### P18 Balance, Rangliste live, Deploy · Opus 5.5 (Zahlenpflege: Haiku 5.5)
- Headless-Langzeitsimulation `SMOKE=longrun`: Bot fliegt Routen, liefert, baut, hält Angriffe über 40 Spieltage
  (beschleunigt mit `Engine.time_scale`; `--quit-after` zählt Frames, der Test beendet sich selbst nach Tag 40),
  protokolliert Ressourcen, Moral, Tote, Punkte pro Tag nach
  `build/longrun.csv`. Ziel: Tag 1–10 eng, Tag 10–30 stabil mit Rückschlägen, danach steigender Druck ohne Zusammenbruch.
- Alle `const` aus den Paketen abgleichen (Haiku sammelt, Opus entscheidet). Punkteformel und Plausibilitätsgrenzen
  in P2 an das echte Tempo anpassen.
- Rangliste live schalten: Supabase-URL/Key eintragen, Web-Build über `tools/deploy_web.sh`, Test mit zwei Profilen
  in Desktop- und Web-Build.
- README, CHANGELOG, Version auf 1.0.0-beta.

---

## Offene Punkte für spätere Entscheidungen
- Rettet ein zweiter Heli den notgelandeten automatisch (KI-Pilot)? Erst nach P15 entscheiden.
- Moderations-Werkzeug über das Supabase-Dashboard hinaus (z. B. Melde-Knopf) – erst bei echten Spielern.
- Gemeinsame Bestenliste pro Woche („Season“) – nach dem Start der Rangliste.
