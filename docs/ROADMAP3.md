# Doorgunner – offene Punkte nach 1.1.0 (Stand 2026-11-03)

Kleiner Block nach `docs/ROADMAP2.md`. Es gelten die Regeln aus `docs/ROADMAP.md` und `docs/ROADMAP2.md` Abschnitt 0
(Worktree pro Paket, Einhängepunkte, Speicher-Vertrag, Tests einzeln und auf `SCRIPT ERROR` prüfen, Commit vor Turn-Ende,
Fable-Review pro Welle, ein Opus-Integrationsbranch).

Entscheidungen des Users (2026-11-03): Schrott-Senke über **teure Spät-Gebäude** und **Handel mit Dörfern**;
Performance misst der User im Browser und auf dem Handy, der Parent wertet aus; wackelige Tests werden
**deterministisch** gemacht (ohne Prüfungen abzuschwächen).

| Welle | Paket | Thema | Modell | Hängt ab von |
|---|---|---|---|---|
| 1 | S1 | Spät-Gebäude (300–800 Schrott) | Sonnet | – |
| 1 | S2 | Handel mit verbündeten Dörfern | Sonnet | – |
| 1 | S3 | Wackelige Tests deterministisch | Sonnet | – |
| 1 | S4 | Perf-Anzeige auch auf dem Handy | Sonnet | – |
| 2 | **S5** | Integration, Bot nutzt S1/S2, Schrott-Kurve prüfen, Release 1.2.0 | Opus | S1–S4 |

Welle 1 läuft komplett parallel; S1 und S2 berühren beide `base_ui.gd`/`tooltips.gd` nur an Einhängepunkten.

### S1 Spät-Gebäude · Sonnet 5.5
- Vier Gebäude im Muster von `scripts/buildings2.gd`, freigeschaltet ab Tag 20 oder mit Perimeter-Stufe ≥ 2:
  **Fortress Wall** (Ring-Ausbau: Sandsäcke werden zu Mauern mit doppelten HP, 400), **Flak Emplacement** (schwere
  Abwehr gegen Gunship/RPG-Raketen und große Wellen, 500), **Command Post** (Aufträge zeigen Belohnung +25 %, ein
  Auftrag mehr gleichzeitig, Funk-Vorwarnung für Rivalen-Angriffe, 600), **Supply Vault** (Lagerobergrenzen +50 %,
  Plünderung bei Durchbruch halbiert, 300). Mindestens eins mit Unterhalt in Schrott pro Tag, damit die Senke anhält.
- Nur Maus/Touch in der Bau-Leiste, Tooltips in `tooltips.gd`, Codex-Zeilen in `codex_content.gd`, Sprites angehängt.
- Test `SMOKE=late`: Bau, Wirkung, Unterhalt, Speichern/Laden.

### S2 Handel mit Dörfern · Sonnet 5.5
- Gelandet neben einem verbündeten Dorf (P14) öffnet ein **TRADE**-Knopf (bzw. Taste/Touch-Kontextknopf) ein Fenster:
  Schrott gegen **Leute mit Fähigkeit** (über die Personen-Fassade / `Game.join`), **Elektronik**, **Medizin**,
  **Gewehre**, Nahrung. Jedes Dorf hat ein kleines Angebot pro Tag; Preise steigen mit jedem Kauf (Nachfrage) und
  sinken über die Tage zurück. Verkauf von Überschuss (z. B. Nahrung gegen Schrott) nur zu schlechten Kursen.
- Angebot und Preise pro Dorf im eigenen Speicher-Hook; UI über `UiTheme` und `overlay.gd`-Muster.
- Test `SMOKE=trade`: Angebot, Kauf, Preisanstieg und -erholung, Person tritt bei, Speichern/Laden.

### S3 Wackelige Tests deterministisch · Sonnet 5.5
- Betroffen: `bandits` (camp landmarks, open spot), `arsenal` (wide cone, flame), `assault` (ram around rock),
  `cloudsave` (restore while delete pending), `infected` (zombies come to the scream, knockback). Ursache je Test finden
  (zufälliger Seed, Gelände, Zeit, geteiltes Profil) und mit festem Seed (`Game.new_run(seed)`), gebautem Testgelände
  oder robustem Aufbau beheben. Keine Prüfung abschwächen; jede Datei 20× hintereinander grün als Nachweis.

### S4 Perf-Anzeige auf dem Handy · Sonnet 5.5
- `?perf=1` zeigt im Web zusätzlich das F3-Overlay dauerhaft an (ohne Tastatur), mit einem Knopf „Copy“, der die
  letzten PERF-Zeilen in die Zwischenablage legt (`JavaScriptBridge`), damit der User sie einfügen kann.
- Feste Messroute als Anleitung in `docs/PERF_TEST.md` (Start → Stadt → Blutmond-Nacht per Debug-Schalter
  `?perf=1&scenario=bloodmoon` falls einfach machbar, sonst normale Route), Werte, die zurückgemeldet werden sollen.

### S5 Integration und 1.2.0 · Opus 5.5
- Merge S1–S4 nach Fable-Review, Bot (`tests/longrun_test.gd`) baut die Spät-Gebäude und handelt; 3 Seeds normal
  + 3 evac: Ziel spätes Schrott-Polster < 1500 statt 4400–5200, ohne die Kurve zu brechen.
- Auswertung der vom User gemeldeten PERF-Werte (Handy/PC) und gezielte Optimierung, falls p95 > 33 ms.
- CHANGELOG 1.2.0, Version, Deploy.

### Für den User
- SQL `006`–`010` im Supabase-SQL-Editor ausführen (siehe `server/README.md`).
- Nach S4: Messroute aus `docs/PERF_TEST.md` auf PC und Handy fliegen, PERF-Zeilen schicken.
