# Doorgunner – Roadmap „Feinschliff, Inhalt, Story“ (Stand 2026-11-01)

Nachfolger von `docs/ROADMAP.md` (Wellen P1–P18, abgeschlossen mit 1.0.0-beta). Nur Plan, noch nichts gebaut. Von Fable 5.1 gegen den Code geprüft (2026-11-01), Befunde eingearbeitet
(Q0-Vorbereitung, Q6 geteilt, Gunship zu Q15, Import ungewertet, Daily-Slot/Seed-Hooks, Onboarding ohne Tutorial-Slot).
Entscheidungen des Users (2026-11-01): Feinschliff (Tutorial & Onboarding, Lesbarkeit & UI, Musik & Sound), mehr
Inhalt (Waffen & Items, Bosse, Gebäude, Orte & Biome), Technik (Web-Performance, Bot testet alles, Fehler-Reporting,
Speicher-Robustheit), Story als **Zufalls-Ereignisse mit Entscheidungen** und **Anführer & Rivalen**, **Daily Seed +
Weekly Season**, **nur Touch** (kein Gamepad). Großer Block, auf maximale Parallelität geschnitten.
Nicht gewählt: Story-Kapitel, Gamepad, Melde-Knopf, Freunde-Ranglisten, Wetter, Seuchen-Ausbreitung.

---

## 0. Spielregeln

Es gelten alle Regeln aus `docs/ROADMAP.md` Abschnitt 0 (Worktree pro Paket auf `t3/<id>`, Hotspots nur über
Einhängepunkte, Personen-Fassade inkl. `Game.saved_count()`, Speicher-Vertrag `Save.register`, Gegner nur über
`spawn_table.gd`, Angriffe nur über `assault.gd`, ein neuer `enemy.gd`-Zweig pro Paket, `gen_sprites.py` nur anhängen
und bestehende Sprites byte-gleich, Zahlen als `const` oben in der eigenen Datei, Texte im Spiel Englisch). Zusätzlich:

### Ablauf (aus den bisherigen Wellen gelernt)
- **Tests strikt nacheinander**, nie parallele Schleifen: alle Tests teilen das Profil `user://profiles/_smoke/`.
  Jede Ausgabe auf `SCRIPT ERROR` greppen (ein fehlgeschlagenes `assert` loggt nur, die OK-Zeile kann trotzdem kommen).
- **Commit vor Turn-Ende.** Kein Test läuft beim Beenden im Hintergrund.
- **Keine fremden Godot-Prozesse beenden.**
- Nach einer Welle: **Fable 5.1** reviewt alle Branches der Welle zusammen (inkl. Merge-Konflikte per
  `git merge-tree`), dann baut **ein Opus-Integrationsagent** einen Branch `t3/<welle>-integrate` (Merges, Verdrahtung,
  Review-Fixes, Version, CHANGELOG). Danach Merge auf `main`, alle Tests einzeln, Deploy.
- Volle Test-Schleife (Stand 1.0.0-beta, `longrun` ausgenommen, der läuft 15–40 min):
  `for s in 1 poi base ui prog tut nav found town save filter online people world infected profiles assault bandits wear missions outposts wreck convoy evac <neu>; do SMOKE=$s godot --headless --path . --quit-after 30000; done`

### Modelle
| Modell | Wofür in diesem Block |
|---|---|
| **Opus 5.5** | Verzahnte Systeme und Architektur: Eingabe-Schicht/Touch, Web-Performance, Langzeit-Bot, neue Biome im Weltgenerator, Rivalen-System, Daily/Season (Client + Server), alle Integrationen |
| **Sonnet 5.5** | Klar umrissene Features mit eigenen Dateien: Fehler-Reporting, Cloud-Save, UI/Lesbarkeit, Tutorial, Musik/Sound, Waffen, Gebäude, Bosse, Zufalls-Ereignisse |
| **Haiku 5.5** | Mechanische Arbeit: Ereignis-Texte nach Vorlage, Waffen-/Item-Tabellenwerte, Tooltip-Texte, README/CHANGELOG-Pflege, Wortlisten |
| **Fable 5.1** | Review dieses Plans und jeder Welle (unabhängige Sicht, nie Implementierer) |

### Q0 Vorbereitung (vor Welle 1, Parent/Opus, ein Commit auf `main`)
Fable hat versteckte Überschneidungen in Welle 1 gefunden. Damit die Pakete wirklich parallel laufen, legt Q0 die
gemeinsamen Einhängepunkte vorher an (nur Gerüst, kein Feature):
- `scripts/settings_registry.gd`: `Settings.register_toggle(key, label, default)` / `register_slider(...)`;
  `settings_ui.gd` baut seine Zeilen in einer Schleife daraus, `settings.json` speichert alle registrierten Schlüssel
  (ersetzt die feste Liste `SETTINGS_KEYS` in `game_state.gd:19`; die bestehenden Schlüssel registriert Q0 selbst).
- `tools/fake_supabase.py`: Dispatch-Tabelle `RPCS = {name: funktion}`; jedes Paket hängt eine eigene Funktion und
  **eine** Tabellenzeile an. SQL-Tests pro Paket in `server/test_0NN.sql` statt in der gemeinsamen `server/test.sql`.
- `main.gd`: Funktion `_add_ui_layers()`, in die Pakete je **eine** Zeile für ihren CanvasLayer anhängen
  (Q1 Overlay, Q5 Touch, Q6a HUD-Zonen, Q11 Onboarding).
- `scripts/ui_theme.gd` (minimal): Farben aus `base_ui.gd`, `TOUCH_MIN := 44`, `ui_scale()` (vorerst 1.0). Q5 nutzt
  es, Q6a baut es aus.
- `server/README.md`: Tabelle der Migrationen mit Status (006–007 vom User einzuspielen, 008+ folgen).

### Neue Hotspot-Regeln
- **Eingabe:** Ab Q5 liest kein Code mehr Tasten oder Maus direkt für Spielaktionen, sondern nur Input-Actions bzw.
  `Controls.aim()` / `Controls.fire()` / `Controls.move()` (Q5 legt `scripts/controls.gd` an). Bis Q5 gemergt ist,
  nutzen Pakete weiter `Input.is_action_*`, nie `Input.is_key_pressed` oder rohe `InputEventKey`.
- **UI-Skalierung:** Neue UI-Elemente nutzen die Theme-Konstanten aus `scripts/ui_theme.gd` (Q0 legt es minimal an,
  Q6a baut es aus) und keine festen Pixelpositionen, die bei UI-Skalierung kollidieren.
- **Ereignisse:** Funk-Entscheidungen nur über `Events.offer(id, ...)` (Q13 legt `scripts/events.gd` an); andere
  Pakete registrieren Ereignis-Karten dort, statt eigene Dialoge zu bauen. Ereignis- und Level-up-Karten teilen sich
  die Warteschlange von `choice_ui.gd` (nie zwei Karten gleichzeitig, Tasten 1–4 eindeutig).
- **Server:** Jede SQL-Änderung als neue Datei `server/supabase/0NN_<name>.sql` (idempotent), `server/test.sql`
  ergänzt. Der User spielt sie ein (kein Token im Repo). Der Client toleriert eine noch nicht eingespielte Migration.
- **Einstellungen** nur über `Settings.register_*` (Q0), nie `settings_ui.gd` oder `SETTINGS_KEYS` direkt.
- **Server-Stub/Tests:** eigene Funktion + eine Zeile in `RPCS` (Q0), eigene `server/test_0NN.sql`.
- **Migrationsnummern fest vergeben:** Q2 `008_errors.sql`, Q3 `009_cloud_save.sql`, Q14 `010_daily_season.sql`.
- **Tasten** (belegt: WASD/Pfeile, SPACE, Q, E, X, B, R, F, M, G, J, O, P, TAB, ESC, H und L im Titel, 1–9 im
  Bau-Modus): Q6b **F1** (Hilfe/Codex), Q1 **F3** (Performance-Anzeige), Q13 **1–3** nur solange ein
  Entscheidungs-Dialog offen ist. Alle Tasten werden ab Q6b frei belegbar; die Defaults bleiben wie hier.

---

## Übersicht der Pakete und Wellen

| Welle | Paket | Thema | Modell | Hängt ab von |
|---|---|---|---|---|
| 0 | Q0 | Gemeinsame Einhängepunkte (Settings, Stub, UI-Layer, Theme) | Opus (Parent) | – |
| 1 | **Q1** | Web-Performance: messen, Overlay, optimieren | Opus | Q0 |
| 1 | Q2 | Fehler-Reporting (Web + Desktop → Supabase) | Sonnet | Q0 |
| 1 | Q3 | Speicher-Robustheit: Cloud-Backup (mit Slots), Export/Import | Sonnet | Q0 |
| 1 | **Q4** | Langzeit-Bot nutzt alle Systeme | Opus | – |
| 1 | **Q5** | Eingabe-Schicht (alle Tasten als Actions) + Touch | Opus | Q0 |
| 2 | **Q6a** | UI-Theme, UI-Skalierung, HUD-Zonen mit Ankern | Opus | Q5 |
| 2 | Q6b | Tastenbelegung, F1-Hilfe (`codex_ui.gd`), Tooltips | Sonnet (Texte: Haiku) | Q5 |
| 2 | Q7 | Musik & Sound: dynamische Musik, mehr Effekte | Sonnet | Q0 (früh möglich) |
| 2 | Q8 | Neue Waffen & Heli-Items | Sonnet (Werte: Haiku) | – (früh möglich) |
| 2 | Q9 | Neue Gebäude | Sonnet | – (früh möglich) |
| 2 | **Q10** | Neue Orte & Biome (Küste, Winter, 4 Landmarken) | Opus | Q1 (Perf-Budget) |
| 3 | Q11 | Tutorial & Onboarding: Kapitel, Kontext-Hinweise, Codex füllen | Sonnet | Q5, Q6b |
| 3 | Q12 | Neue Bosse: 3 Infizierte + Banditen-Warlord | Sonnet | Q10 (Orte) |
| 3 | Q13 | Zufalls-Ereignisse mit Entscheidungen | Sonnet (Texte: Haiku) | Q6a |
| 3 | **Q14** | Daily Seed + Weekly Season (Client + Server) | Opus | Q2, Q3 (Slot-Spalte) |
| 4 | **Q15** | Anführer & Rivalen (Nemesis) + Gunship | Opus | Q12, Q13 |
| 4 | Q16 | Integration: Bot-Balance über alles, Touch-Feinschliff, Release 1.1.0 | Opus (Zahlen: Haiku) | alle |

**Parallelität:** Nach Q0 hat Welle 1 fünf unabhängige Pakete; sie treffen sich nur an den Q0-Einhängepunkten
(je eine Zeile). Merge-Reihenfolge in Welle 1: Q1 vor Q5 (beide in `_add_ui_layers`). Q7, Q8, Q9 dürfen schon während
Welle 1 starten („früh“): sie fassen weder Eingabe noch Welt an; Q8 fasst `gen_sfx.py` nicht an, solange Q7 läuft.
Welle 2 läuft dann mit Q6a, Q6b und Q10, Welle 3 mit 4 Paketen, Welle 4 mit Q15 und der Integration.
Höchstens 6 Agenten gleichzeitig.

---

## Welle 1 – Technik & Fundament

### Q1 Web-Performance · Opus 5.5
- **Messen:** Overlay auf **F3** (FPS, Frame-Zeit p50/p95/max der letzten 10 s, Anzahl Gegner/Banditen/POIs/Chunks,
  Zeit in Chunk-Generierung, Pfadsuche, Spawner pro Frame). Im Web zusätzlich `?perf=1` in der URL: schreibt jede 10 s
  eine Zeile per `print()` (landet im Browser-Konsolenlog), damit der Parent per Browser-Vorschau messen kann.
- **Szenarien** als `SMOKE=perf` (headless, Desktop-Zahlen als Basis) und gleich im Web-Build: Stadt-Anflug,
  Blutmond mit 250 Angreifern, Banditen-Lager + Horde, Konvoi-SEND auf weite Strecke, 60 min Spielzeit (Speicher).
- **Optimieren** in dieser Reihenfolge, jeweils mit Vorher/Nachher: Chunk-Generierung über mehrere Frames strecken
  (Budget pro Frame, auch für den 3×3-Ring), Gegner-KI gestaffelt (nicht jeder Gegner jeden Frame), Pfad-Cache,
  `queue_redraw` nur bei Änderung, Partikel-/Leichen-Obergrenzen an FPS koppeln. Ziel: p95 < 33 ms im Web auf einem
  Mittelklasse-Laptop, Ruckler beim Chunk-Laden < 50 ms.
- Einhängepunkte: `main._add_ui_layers()` (eine Zeile), `chunk_manager.gd` (Budget), `enemy.gd` (Takt-Staffelung,
  kein neuer Zweig). Misst auch die Kosten von `always_track_call_stacks` (für Q2).
- Test `SMOKE=perf`: Szenarien laufen, Grenzwerte (Desktop) eingehalten, Overlay-Werte plausibel.

### Q2 Fehler-Reporting · Sonnet 5.5
- Server `server/supabase/008_errors.sql`: Tabelle `errors(id, created_at, player_id null, version, platform,
  message, stack, count)`, RPC `report_error(...)` für anon + authenticated, gleiche Meldung pro Version zusammengefasst
  (`count += 1`), Rate-Limit pro Spieler (20/h) plus globale Obergrenze pro Stunde für `anon` (IP-Header in
  PostgREST sind unsicher), Länge begrenzt, kein Lesen für Clients. `delete_me` setzt `errors.player_id` dieses
  Spielers auf `null`.
- Client `scripts/error_report.gd` (Autoload): Godot `Logger` (`OS.add_logger`, in 4.7.2 geprüft) fängt Script-Fehler
  und `push_error`; Backtraces im Export brauchen `debug/settings/gdscript/always_track_call_stacks` (Kosten misst Q1); im Web zusätzlich `window.onerror` über `JavaScriptBridge`. Gleiche Meldung nur einmal pro Sitzung,
  Warteschlange offline. **Opt-out** im ESC-Menü („Send crash reports“ über `Settings.register_toggle`), Standard an, Hinweis beim ersten Start.
  Keine personenbezogenen Daten außer der anonymen Spieler-ID.
- `server/README.md`: wie man Fehler im Dashboard ansieht (gespeicherte Abfrage).
- Test `SMOKE=errors` gegen `tools/fake_supabase.py` (erweitert): Fehler wird gemeldet, dedupliziert, Opt-out wirkt.

### Q3 Speicher-Robustheit · Sonnet 5.5
- **Cloud-Backup** für registrierte Profile: `server/supabase/009_cloud_save.sql`, Tabelle `cloud_saves(player_id,
  slot text, updated_at, version, format, data bytea ≤ 2 MB, primary key (player_id, slot))` — `slot` ist `run` oder
  `daily` (Q14 braucht den zweiten), RPCs `put_save` / `get_save` nur für den eigenen Spieler.
  Client lädt den Stand (komprimiert, `var_to_bytes` + `compress`) bei Landung auf der Basis höchstens alle 5 min hoch.
- **Wiederherstellen:** Titel zeigt „Restore from cloud“, wenn lokal kein Stand ist (z. B. Browserdaten gelöscht),
  der Cloud-Stand aber existiert. Ironman bleibt: Tod löscht **zuerst** den Cloud-Stand, dann den lokalen.
- **Export/Import:** Profil (meta + Spielstand) als Datei; im Web Download/Upload über `JavaScriptBridge`.
  Import prüft `SAVE_FORMAT` und Version. **Ein importierter Run ist immer ungewertet** (`Online.ranked = false`,
  der gespeicherte Online-Zustand wird verworfen, Titel zeigt „Imported – not ranked“), sonst ließe sich ein Tod in
  einem gewerteten Run durch eine alte Kopie zurückspulen. Dass der Server sinkende Werte ablehnt, im Test belegen.
- **Ranglisten-Identität:** Der Export enthält `auth.json` nur, wenn der Spieler es ausdrücklich ankreuzt (mit Warnung,
  dass die Datei dann wie ein Passwort zu behandeln ist). Ohne das hängt die Identität weiter an den Browserdaten;
  der Cloud-Stand ist dann nach einem Löschen der Browserdaten nicht mehr erreichbar (im Titel erklärt).
- Einhängepunkte: `save.gd` (ein Aufruf nach erfolgreichem Schreiben), `title_ui.gd` (Knopf), `online.gd` (RPC-Helfer).
  `Save` bekommt hier schon eine Variable `slot` (Standard `"run"`, Pfad `profile_dir() + slot + ".sav"`), damit Q14
  den zweiten Slot nur noch einschaltet.
- Test `SMOKE=cloudsave` gegen den Stub: Hochladen, lokal löschen, wiederherstellen, Tod löscht beides, Export/Import.

### Q4 Langzeit-Bot nutzt alles · Opus 5.5
- `tests/longrun_test.gd` erweitern: Außenposten gründen und versorgen, Dörfer schützen und abholen, Konvois schicken,
  Wracks bergen und reparieren, Aufträge annehmen, Evakuierung ab Tag 15 durchziehen (in einem zweiten Lauf-Modus,
  `LONGRUN_EVAC=1`), Modifier-Läufe (`LONGRUN_MODS=dense,warlords`).
- CSV um Spalten für diese Systeme und die **Größe von `run.sav` pro Tag** ergänzen (Datenbasis für die 2-MB-Grenze in Q3); ein Auswerte-Skript `tools/longrun_report.py` (Kurven je Phase, Ausreißer).
- Liefert die Datenbasis für Q16; ändert selbst **keine** Balance-Werte, nur Bugs, die der Bot findet (je mit Test).
- Läuft nicht in der schnellen Schleife. Bericht mit 5 Seeds je Modus.

### Q5 Eingabe-Schicht + Touch · Opus 5.5
- `scripts/controls.gd` (Autoload `Controls`): `move() -> Vector2`, `aim() -> Vector2` (Weltposition), `fire() -> bool`,
  `yaw() -> float`, plus Actions für alle Tasten. Maus/Tastatur bleibt Standard; heute direkte Maus-/Tastenzugriffe
  (Heli-Zielen, Bau-Platzieren, Overlays) werden auf `Controls` umgestellt.
- **Alle rohen Tastenabfragen werden Input-Actions** in `_setup_input()` (`game_state.gd:765`), sonst kann Q6b sie
  nicht umbelegen: `base.gd:207` (1–9), `base_ui.gd:549` (TAB), `choice_ui.gd:149` (1–4), `leaderboard_ui.gd:66`,
  `overlay.gd:97`, `sfx.gd:62` (M), `systems/loudspeaker.gd:14` (F), `title_ui.gd:372-376` (L, H, Enter). Ein Test
  sucht nach verbliebenen `KEY_`-Vergleichen außerhalb von `_setup_input`.
- **Touch** (automatisch bei Touchscreen, im ESC-Menü umschaltbar): linker virtueller Stick = Fliegen, rechter Stick =
  Zielen + Feuern (Door gun feuert, solange der Stick ausgelenkt ist), Knopfleiste rechts: Land/Take off, Waffe,
  Yaw ±, Flares/System, Haken, Kontext-Knopf (Basis bauen/Außenposten/Dorf schützen je nach Lage). Basis-Menü und
  Bau-Modus per Tippen; Platzieren mit Vorschau und Bestätigen-Knopf statt Mausklick. Querformat erzwingen (Hinweis
  bei Hochformat), Mehrfinger-Gesten (Pinch-Zoom der Minimap optional).
- UI-Mindestgrößen für Finger über `UiTheme.TOUCH_MIN` (Q0). Die Touch-Steuerung ist ein eigener CanvasLayer in
  `main._add_ui_layers()`; den HUD-Umbau macht Q6a.
- Web: `index.html`-Template mit `touch-action: none`, kein Browser-Zoom/Scroll, Vollbild-Knopf.
- Einhängepunkte: `heli.gd` (Zielen/Feuern über Controls), `base.gd`/`base_ui.gd` (Platzieren),
  `main._add_ui_layers()` (eine Zeile), `export_presets.cfg` (eigenes HTML-Template), Touch-Schalter über
  `Settings.register_toggle`.
- Test `SMOKE=controls`: simulierte Touch-Events bewegen den Heli, zielen und feuern; Bau-Platzierung per Touch;
  Maus/Tastatur unverändert (bestehende Tests bleiben grün).

---

## Welle 2 – Gefühl & Inhalt

### Q6a UI-Theme, Skalierung, HUD-Zonen · Opus 5.5
- `scripts/ui_theme.gd` (aus Q0) ausbauen: Farben, Schriftgrößen, Abstände, **UI-Skalierung** 90–150 % (Einstellung
  über `Settings.register_slider`), Mindestgrößen für Touch. Alle UIs (`base_ui`, `hud`, `title_ui`, `settings_ui`,
  `missions_ui`, `fleet_ui`, `victory_ui`, `profile_ui`, `leaderboard_ui`, `choice_ui`, Touch-Layer aus Q5) lesen daraus.
- **HUD mit Ankern statt fester 1280×720-Positionen** (`hud.gd:63, 74, 95` u. a.): feste Zonen (oben links Status,
  oben rechts Minimap + Kompass, unten Funk, unten Mitte Tasten-/Kontext-Hinweise, Alarmzeile oben Mitte) mit
  Prioritäten statt übereinanderliegender Zeilen; Blöcke ein-/ausklappbar. Eigener CanvasLayer in `_add_ui_layers()`.
- Test `SMOKE=uitheme`: Skalierung 90/100/150 % ohne Überlappungen in Basis-Menü, HUD und Touch-Layer (Rechtecke prüfen).

### Q6b Tastenbelegung, F1-Hilfe, Tooltips · Sonnet 5.5 (Tooltip-Texte: Haiku 5.5)
- **Tastenbelegung** frei wählbar im ESC-Menü (alle Input-Actions aus Q5 umbelegen, in `settings.json` gespeichert,
  Konflikte anzeigen, „Reset to defaults“).
- **F1** öffnet `scripts/codex_ui.gd`: Seite „Controls“ mit allen aktuellen Belegungen, dazu leere Kategorien, die
  Q11 füllt (Gegner, Gebäude, Items, Systeme). Datenquelle `scripts/codex.gd` (Einträge registrieren, pro Profil
  freigeschaltet in `meta.json`).
- **Tooltips** für alle Basis-Knöpfe, Jobs, Items, Gebäude, Modifier (Texte von Haiku nach Vorlage).
- Läuft parallel zu Q6a: fasst Layout und Theme nicht an, nur Inhalte.
- Test `SMOKE=keys`: Umbelegen wirkt und wird gespeichert, Konflikt wird gemeldet, F1 zeigt die neue Belegung,
  Tooltips vorhanden.

### Q7 Musik & Sound · Sonnet 5.5 (früh möglich)
- `tools/gen_music.py` (wie `gen_sfx.py`, prozedural, keine fremden Lizenzen): Stems in Ebenen pro Stimmung —
  ruhig (Erkundung), Spannung (Gegner nah/Nacht), Kampf, Angriff, Blutmond, Sieg, Titel. Gleiches Tempo/Tonart, damit
  Ebenen nahtlos überblendet werden.
- Die bestehende Überblendung in `sfx.gd` (`music_calm`/`music_tense`, `tense`-Flag, `sfx.gd:9, 137`) zu einer
  Zustandsmaschine erweitern, nicht ersetzen: Musik-Zustand aus Spiellage (Gegner in Reichweite, `Game.attack_active`, Blutmond, Evakuierung,
  Titel), Übergänge an Taktgrenzen; Ducking bei Funk-Meldungen.
- **Neue Effekte:** Funk-Piepser vor Meldungen (je Absender anders: Base, Pilot, Watchtower, Banditenfunk), RPG-Warnton,
  Autorotations-Alarm, Konvoi-Funk, Baufortschritt, UI-Klicks, Ereignis-Gong (Q13 nutzt ihn).
- Einstellungen: Musik-Lautstärke gibt es schon; zusätzlich „Radio beeps“ an/aus über `Settings.register_toggle`.
- Test `SMOKE=music`: Zustandswechsel wählt die richtige Ebene, Übergang ohne Lücke, alle Dateien vorhanden.

### Q8 Neue Waffen & Heli-Items · Sonnet 5.5 (Werte: Haiku 5.5, früh möglich)
- 4 Door-Gun-Waffen (z. B. Schrotflinte mit Streuung, Flammenwerfer kurz mit Brand, Granatwerfer mit Bogen, Präzisions-
  gewehr mit Durchschlag) in `weapons.gd`; 6 Items in `progression.gd` (2 System, 2 Modul, 2 Hardpoint), z. B. Wärmebild
  (Gegner nachts sichtbar), Panzerplatten (Gewicht), Zusatztank, Rauchwerfer, Schallkanone, Rettungskorb.
- Jede Waffe/Item mit Meta-Freischaltung (Regel wie bestehende `unlock`), Sprite in `gen_sprites.py`, Sound: bestehende Dateien
  als Platzhalter, `gen_sfx.py` nicht anfassen (gehört Q7); Q16 tauscht gegen Q7-Sounds.
- Einhängepunkte: Tabellen in `weapons.gd`/`progression.gd`, `bullet.gd` (Brand/Durchschlag als Eigenschaft),
  `systems/` neue Dateien.
- Test `SMOKE=arsenal`: jede Waffe trifft wie spezifiziert, Items wirken und lassen sich speichern/laden.

### Q9 Neue Gebäude · Sonnet 5.5 (früh möglich)
- 5 Gebäude über `Game.BUILDINGS`: **Field Hospital** (Ausbau der Klinik, mehr Betten, heilt schneller),
  **Greenhouse** (Nahrung ohne Bauernhof-Gelände, braucht Wasser), **Forge** (Metall aus Schrott, Teile aus Metall),
  **Bunker** (Leute überleben Basis-Durchbruch, Moral bei Angriffen), **Radio Relay** (größerer Aufdeck- und
  Auftragsradius, Banditen-Funk früher abgefangen).
- Je Gebäude: Kosten, Bauzeit, Arbeiter-Job falls nötig (Personen-Modell P7), Wirkung, Sprite, Tooltip.
- Bau-Leiste: Tasten 1–9 bleiben, neue Gebäude nur per Maus/Touch (wie Radio Station/Airstrip); die Leiste bricht
  schon heute in eine zweite Reihe um (1.0.0-beta) — prüfen, dass 16 Werkzeuge noch neben die Minimap passen.
- Test `SMOKE=buildings2`: Bau, Wirkung, Arbeiter, Speichern/Laden.

### Q10 Neue Orte & Biome · Opus 5.5
- **Zwei Regionen** im Weltgenerator (`chunk_manager.gd`, Makro-Raster aus P8): **Küste** (Strand, Dünen, Steilküste,
  Meer als unpassierbare Fläche, Fischerdorf-Vorlage) und **Winter/Bergland** (Schnee, gefrorene Seen begehbar,
  Hütten, Skilift-Ruine). Neue Tiles am Ende von `enum T` und `TILES`.
- **Vier Landmarken:** Krankenhaus (Medizin, Medic-Leute, viele Infizierte), Hafen (Treibstoff, Boote, Banditen-Lager
  möglich), Stadion (Massen-Horde, großes Lager an Vorräten), Kraftwerk (Strom-Bauteil für die Basis; Boss-Ort für Q12).
- Ordnungsunabhängigkeit und Performance-Budget aus Q1 einhalten; `sites_near` kennt die neuen Arten.
- `SAVE_FORMAT` erhöhen (neue Welt bei gleichem Seed) — einzige erlaubte Erhöhung in diesem Block; Hinweis im CHANGELOG.
- Test `SMOKE=world2`: Regionen erscheinen, Landmarken erreichbar und mit Straße verbunden, Ordnungsunabhängigkeit.

---

## Welle 3 – Story, Bosse, Online

### Q11 Tutorial & Onboarding · Sonnet 5.5
- Heutiges Tutorial (`tutorial.gd`) bleibt Kapitel 1. Neue **Kapitel** leben in einem eigenen Node `onboarding.gd`
  (über `_add_ui_layers()`), **nie** in `Game.world.tutorial`: `save.gd:77` speichert nicht, solange ein Tutorial
  läuft, das darf für Kapitel nicht gelten. Kapitel werden beim ersten Kontakt freigeschaltet und
  per Funk geführt (kurz, überspringbar): Basis & Arbeiter, erster Angriff, Aufträge, Außenposten & Dörfer, Banditen,
  Konvois, Wracks, Evakuierung. Jedes Kapitel 3–6 Schritte mit Bedingung wie heute.
- **Kontext-Hinweise** (einmal pro Profil): beim ersten verletzten Passagier, ersten Ladehemmung, ersten RPG usw.
- **Codex** füllen (`codex.gd`/`codex_ui.gd` aus Q6b): Gegner, Gebäude, Items, Systeme mit kurzen Texten; Einträge
  erscheinen, wenn man ihnen begegnet.
- Touch-Varianten der Hinweise (Q5).
- Test `SMOKE=onboarding`: Kapitel triggert, Schritte schließen ab, Hinweis kommt nur einmal, Codex füllt sich,
  `Save.autosave()` schreibt während eines Kapitels.

### Q12 Neue Bosse · Sonnet 5.5 (Gunship wandert zu Q15/Opus)
- **Infizierte (3):** *The Matriarch* (spawnt Brut, flieht verletzt, kommt zurück), *Juggernaut* (gepanzert bis auf
  Schwachstelle hinten, rammt Gebäude), *Hive* (stationär im Kraftwerk/Stadion, ruft Wellen bis zerstört).
- **Banditen (1):** *Warlord* im großen Lager (Leibwache, Mörser auf gelandeten Heli). Das *Gunship* (Luftkampf) ist
  neue Flug-KI und gehört zu Q15 (Opus).
- Neue Bosse erweitern `enemy.gd` `KINDS` neben dem bestehenden `"boss"` (Blutmond), ersetzen ihn nicht; die drei
  Infizierten folgen dem Fähigkeits-Muster aus `infected.gd`.
- Je Boss: Phasen (z. B. ab 50 % HP neues Muster), Telegraphing (sichtbar/hörbar vor gefährlichen Angriffen),
  Belohnung (Item-Freischaltung, Schlüsselteil, Moral). Spawns über `spawn_table.gd` / Banditen-API, Orte aus Q10.
- Q15 baut auf diesen Bossen die Rivalen auf: Bosse bekommen eine `nemesis_id` (optional, leer heute).
- Test `SMOKE=bosses`: jeder Boss erscheint, wechselt Phase, telegraphiert, stirbt, belohnt, Speichern/Laden mitten
  im Kampf.

### Q13 Zufalls-Ereignisse mit Entscheidungen · Sonnet 5.5 (Ereignistexte: Haiku 5.5)
- `scripts/events.gd`: **Ereignis-Karten** (Tabelle) mit Bedingungen (Tag, Moral, Ressourcen, Gebäude, Fraktionen,
  Ort), 2–3 Optionen mit Folgen (Ressourcen, Leute über die Fassade, Moral, Banditen-Beziehung, neue Aufträge über
  `missions.offer`, Gegner-Spawns), Abklingzeiten, Ketten (Folge-Ereignis Tage später).
- Dialog baut auf `choice_ui.gd` auf (Karten, Knöpfe, Tasten 1–4, Warteschlange) statt einen zweiten Dialog zu
  schreiben; Ereignis- und Level-up-Karten stehen in derselben Warteschlange. Funk-Stil, Optionen per Klick/Tippen;
  im Flug pausiert das Spiel nicht, der Funk wartet (max. 60 s, dann Standard-Option).
- **30 Karten** zum Start (Haiku schreibt Texte nach Vorlage, Sonnet prüft Balance), z. B. Fremde am Tor (aufnehmen /
  Quarantäne / abweisen), Krankheit in der Basis, Banditen bieten Handel, Deserteure, Funkspruch eines Kindes,
  Vorratsdiebstahl, Streit zwischen Arbeitern, abgestürzter Versorgungsabwurf.
- API für Q15: `Events.offer(id, ctx)` und Signal `chosen(id, option)`.
- Test `SMOKE=events`: Bedingung wählt passende Karte, Option wirkt, Kette folgt, Timeout wählt Standard, Speichern.

### Q14 Daily Seed + Weekly Season · Opus 5.5
- Server `server/supabase/010_daily_season.sql`: `daily(date pk, seed, modifiers, heli)` (von einer Funktion erzeugt,
  deterministisch aus dem Datum + Server-Geheimnis), Runs bekommen `mode` (`normal`/`daily`) und `daily_date`;
  **ein gewerteter Versuch pro Spieler und Tag** (erster Start zählt). `season` = ISO-Woche; Views
  `leaderboard_daily(date)`, `leaderboard_season(week)` neben den ewigen.
- Client: Titel **DAILY** (zeigt Modifier und Heli des Tages, Countdown bis Reset, ob schon gespielt), Rangliste mit
  Reitern Daily / Season / All-time. Daily-Runs nutzen Seed/Modifier vom Server (offline nicht startbar, entsprechend
  der Regel „keine Offline-Runs“), eigener Speicherstand-Slot, damit der normale Run nicht verloren geht.
- Anti-Cheat wie bisher (Plausibilität, Rate-Limit); Seed wird erst beim Start ausgeliefert.
- **Einhängepunkte (Hotspots):** `Game.new_run(seed := -1, modifiers := [], mode := "normal")` (heute nimmt
  `game_state.gd:224` den Seed nur in Debug-Builds aus `RUN_SEED`), `Save.slot = "daily"` (aus Q3),
  `Online.begin_run(modifiers, mode)`, Titel-CONTINUE zeigt beide Slots, Cloud-Backup nutzt Slot `daily`.
- **Ranglisten-Views** mit Spalte `daily_date` bzw. `season_week`; der Client filtert per `?daily_date=eq.<datum>`
  (parametrisierte Views gibt es nicht).
- **Gleiche Welt, nicht gleicher Run:** Die Weltgenerierung ist Seed-deterministisch (FastNoiseLite + Integer-Hash),
  Spawns und Beute sind es nicht. Der DAILY-Bildschirm verspricht „same world, same modifiers“. Test: Hash der Tiles
  um den Start für einen festen Seed; einmal im Web-Build per Konsole vergleichen.
- Test `SMOKE=daily` gegen den Stub: Seed holen, Run gewertet, zweiter Versuch ungewertet, Season-View.

---

## Welle 4 – Rivalen & Integration

### Q15 Anführer & Rivalen + Gunship · Opus 5.5
- `scripts/nemesis.gd`: pro Run bis zu **2 Rivalen** — ein benannter **Banditen-Warlord** und ein **Infizierten-Alpha**
  (aus den Bossen von Q12, mit Namen, Porträt im Funk-Stil, Eigenschaften).
- **Gedächtnis:** Rivalen merken sich, was der Spieler tut (welches Lager zerstört, ob er flieht, welche Waffen er
  nutzt) und passen sich an (z. B. mehr RPGs, wenn der Spieler hoch und schnell fliegt; meidet Draht, wenn Spitter
  oft im Draht sterben). Sie entkommen verletzt, kommen stärker zurück, sprechen per Funk (Drohungen, Hohn).
- **Eskalation über Tage:** Erstkontakt → Überfälle auf Außenposten/Konvois → Großangriff; Ereignisse aus Q13 als
  Bausteine (z. B. Lösegeld-Angebot).
- **Gunship** (aus Q12 hierher verschoben): gekaperter Heli des Warlords, Luftkampf mit Heli-Physik, hält Abstand,
  reagiert auf Flares; erscheint ab der Eskalationsstufe „Großangriff“.
- **Abschluss:** Rivale endgültig getötet → große Belohnung, Moral, Codex-Eintrag; neue Rivalen erst später im Run.
- Speichern/Laden des Gedächtnisses; Rangliste unverändert.
- Test `SMOKE=nemesis`: Rivale entsteht, merkt sich Verhalten, flieht und kehrt zurück, Eskalation, Tod beendet ihn.

### Q16 Integration, Balance, Release 1.1.0 · Opus 5.5 (Zahlen: Haiku 5.5)
- Bot aus Q4 über 40 Tage mit allen neuen Inhalten (Waffen, Gebäude, Biome, Bosse, Ereignisse, Rivalen) auf 5 Seeds
  je Modus; Kurve wie in P18 (Tag 1–10 eng, 10–30 stabil mit Rückschlägen, danach steigender Druck ohne Zusammenbruch).
- Touch-Feinschliff auf einem echten Gerät (User testet, Parent misst im Web mit `?perf=1`).
- Web-Performance-Nachmessung nach allen Inhalten (Q1-Ziele).
- README, CHANGELOG, Version **1.1.0**; alle noch nicht eingespielten SQL-Migrationen (006–010) für den User
  zusammengefasst, `server/README.md` aktualisiert. Platzhalter-Sounds aus Q8 durch Q7-Sounds ersetzen.

---

## Risiken und offene Punkte
- **Touch + Performance:** Handys sind langsamer als der Desktop; Q1 misst zuerst, Q10/Q12 halten sich an das Budget.
- **Cloud-Save-Größe:** Lange Runs (Welt-Protokoll, Gegner) können groß werden; Q3 misst und kappt, sonst nur lokal.
- **Daily-Fairness:** Gleiche Welt auf allen Geräten ist wahrscheinlich (kein `sin`/`cos` im Generator), aber
  zwischen Web und Desktop nicht belegt; Q14 prüft es per Tile-Hash.
- **Export/Import vs. Ironman:** Importierte Runs sind immer ungewertet (Q3), sonst ist die Rangliste angreifbar.
- **Rivalen-KI-Kosten:** Gedächtnis nur als Zähler/Flags, keine teure Simulation.
- Später entscheiden: Gamepad (abgelehnt, kann zurückkommen), Melde-Knopf für Namen, KI-Pilot für den zweiten Heli.
