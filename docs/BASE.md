# Basis-Simulation – Spezifikation Block 2 (Stand 2026-10-28)

Baut auf Block 1 auf (manuelle Sandsäcke, Bauarbeiter, Miliz-Besetzung, Jobs fuel/ammo/repair/militia/farm/build/medic).
Alles in English im Code, Texte im Spiel English. Zahlen sind Startwerte für das Balancing.

## 1. Bevölkerung und Unterkünfte
- `Game.rescued` bleibt die Gesamtzahl. Neu: `housing` = 4 × Barracken-Stufe + 2 (Hangar-Notlager).
- Überzählige Leute (rescued > housing) campen draußen: sie essen doppelt, arbeiten nicht (zählen nicht als idle)
  und bei jedem Basisangriff wird je Welle einer von ihnen verletzt. Radio warnt beim Abliefern: "no beds left".
- Barracke wird nicht mehr gekauft, sondern GEBAUT: im BUILD-Tab "Barracks (40 scrap)" setzt einen 2×2-Bauplatz
  (wie Sandsäcke per Klick im Perimeter), Bauarbeiter brauchen 90 s pro Barracke. Sprite: hangar.png getönt.
- Dasselbe Bau-Schema für: Field Clinic (2×2, 50 scrap, 90 s), Generator (1×1, 60 scrap, 60 s), Well (1×1, 30 scrap, 60 s),
  Watchtower (1×1, 35 scrap, 45 s: ein Milizposten mit +50 % Reichweite). Fuel Depot und Armory bleiben Kauf-Upgrades.

## 2. Perimeter
- `Game.base_radius` startet bei 160 px. "Expand perimeter" im BUILD-Tab kostet 60 scrap × Stufe und braucht
  60 s Bauzeit durch Bauarbeiter; +60 px pro Stufe, max 5 Stufen (460 px).
- Bauplätze (Sandsäcke, Gebäude) nur innerhalb des Perimeters. Am Rand stehen alle 32 px Zaunpfosten (fence.png),
  die Perimeterfläche bekommt Basisboden-Kacheln nur um die Gebäude, sonst bleibt das Gelände.
- Horden spawnen nie innerhalb Perimeter + 300 px.

## 3. Bedürfnisse: Nahrung, Wasser, Medizin
- Vorräte: `base_food` (gibt es), neu `base_water`, `base_medicine`, `base_rifles`.
- Verbrauch pro Person und Tag: 1 Nahrung, 1 Wasser; Camper doppelt.
- Wasser-Quellen: Well-Gebäude +8/Tag pro Brunnen; Job "water" holt +15/Tag pro Arbeiter, nur wenn Wasser
  (Fluss/See) innerhalb 400 px der Basis liegt; POI "water_tower" in Orten (+40 Wasser beim Landen, Prop water_tower.png,
  2 pro Ort maximal); Versorgungskisten +10 Wasser; Seehütten +20.
- Medizin-Quellen: POI "pharmacy" in Orten (Gebäude mit grünem Kreuz-Prop, +4 Medizin), Kisten +1, Absturzstellen +2.
- Nahrungs-Quellen bleiben (Farm-Job, Kisten +15), neu: Felder im Perimeter: jedes FIELD-Tile im Perimeter +0,5 Nahrung/Tag.
- Bei 0 Nahrung oder 0 Wasser: pro Tag wird eine Person verletzt (nicht mehr: geht weg). Bei 3 Tagen ohne beides geht eine.

## 4. Verletzungen und Lazarett
- `Game.injured` zählt Verletzte. Verletzte arbeiten nicht und zählen nicht als idle.
- Wer verletzt wird: Camper bei Angriffswellen; bei Siedlungsüberfällen wird ein Überlebender zu 50 % verletzt statt getötet
  (verletzte Überlebende in Siedlungen gehen langsam, 25 px/s, und brauchen beim Einsteigen doppelt so lang);
  Passagiere beim Treffer des Helis (10 % pro Treffer, verhindert durch das Sanitäter-System des Helis).
- Heilung: Field Clinic hat 2 Betten pro Stufe. Je Bett: 1 Medizin verbrauchen, dann 1,5 Tage Heilzeit; Medic-Job halbiert
  die Zeit (ein Medic pro 2 Betten), Strom halbiert nochmal. Ohne Bett oder ohne Medizin: 15 % Sterbechance pro Tag.
- Radio-Zeilen: "2 injured, 1 medicine left", "Clinic: patient recovered".

## 5. Elektrizität
- Generator-Gebäude: verbraucht 10 Treibstoff/Tag aus `base_fuel` pro Stufe, liefert `power` = true, solange Treibstoff da ist.
- Wirkung mit Strom: Licht in der Nacht (PointLight2D mit radialer GradientTexture2D über dem Perimeter, warm, Radius = Perimeter + 80),
  Türme und Wachtürme feuern mit voller Rate (ohne Strom halbe Rate), Lazarett heilt doppelt so schnell, Horden-Spawn
  um die Basis nachts 30 % seltener (Licht hält sie fern), Funkhinweise alle 30 statt 45 s.
- HUD-Zeile: "POWER on/off (gen fuel 10/day)".

## 6. Waffen für Überlebende
- `base_rifles`: Miliz schießt nur mit Gewehr. Ohne Gewehr steht ein Milizposten nur da (blockiert nichts, trifft nichts).
- Quellen: Waffenkisten-POI +2 Gewehre zusätzlich zur Karte, Absturzstellen +1, Armory-Upgrade produziert +1 Gewehr/Tag pro Stufe,
  Zombie-Drops 2 % Chance.
- WORKERS-Tab zeigt "Militia 3 (rifles 2)" und warnt rot bei Mangel.

## 7. Tutorial
- Erster Run (meta runs == 0) oder Button "Tutorial" am Titelbildschirm. Ein kleiner Skript-Knoten `tutorial.gd` steuert
  Schritte mit Funk-Zeilen und einem gelben Zielmarker (HUD-Pfeil wie Funkziel), jeder Schritt wartet auf eine Bedingung:
  1. "Take off (SPACE)" → nicht mehr gelandet.
  2. "Fly to the marked settlement" (nächste Siedlung, garantiert innerhalb 900 px: beim Tutorial-Start wird eine Siedlung
     mit 3 Leuten 700 px östlich der Basis erzeugt) → innerhalb 160 px.
  3. "Land next to it (SPACE), hold the LZ, people board one by one" → passengers ≥ 1; Hinweis auf Lärm und Zombies.
  4. "Return to base and land on the pad" → rescued ≥ 3.
  5. "Open BUILD, place a Barracks blueprint, assign 1 Build worker in WORKERS" → Barracke-Bauplatz vorhanden und build ≥ 1.
  6. "Place 6 sandbags on the east side" → 6 Blueprints.
  7. "Assign 1 Militia. Tonight's assault will test your line." → militia ≥ 1; dann Tutorial-Ende, Angriff in dieser Nacht wird erzwungen (klein: 8 Zombies).
- Kann jederzeit mit ESC-Menü-Button "Skip tutorial" beendet werden. Tutorial-Status in `Game.meta["tutorial_done"]`.

## 8. Tests
- base_test: Wasser sinkt pro Tag, Brunnen produziert, Verletzung bei 0 Wasser, Lazarett heilt mit Medizin, Camper ohne Betten
  werden bei Welle verletzt, Generator zieht Treibstoff, Miliz ohne Gewehre feuert nicht, Perimeter-Stufe erhöht Radius.
- tutorial_test (SMOKE=tut): Schritte 1-4 per Simulation durchlaufen, Schritt 5-7 per direkten Aufrufen, `tutorial_done` gesetzt.
