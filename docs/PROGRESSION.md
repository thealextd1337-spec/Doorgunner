# Progression – Plan (Stand 2026-10-28)

Ziel: ein Vampire-Survivors-artiger Pfad für den Helikopter. Jedes Level-up bietet drei Karten,
man nimmt eine. Der Heli hat feste Slots, jedes Teil hat ein Maximallevel, Slots sind knapp,
also muss man sich für einen Build entscheiden. Dazu ein Maximallevel für den Heli selbst und
dauerhafte Freischaltungen über Runs hinweg.

## 1. Slots am Helikopter

| Slot-Typ | Anzahl (Start) | Was hinein passt | Thema |
|---|---|---|---|
| Hardpoint | 2 | Waffen (Door MG, Minigun, Autocannon, Flak, Raketen, Railgun) | Türbewaffnung links/rechts |
| System | 2 (max 3) | aktive Bordsysteme, feuern/wirken automatisch | Avionik und Crew |
| Modul | 3 (max 4) | passive Boni | Zelle, Triebwerk, Munition |

- Jeder Slot-Typ hat eine Obergrenze. Ein voller Slot-Typ bietet nur noch Level-ups für vorhandene Teile.
- Dritter System-Slot und vierter Modul-Slot kommen aus der Basis (Werkstatt Stufe 2 und 3) oder aus der Meta-Progression.
- Hardpoints bleiben die heutigen zwei Waffenplätze (Q wechselt). Waffen werden künftig ebenfalls gelevelt.

## 2. Teile und Maximallevel

Alle Teile haben Level 1 bis 5. Level 5 ist das "Ausbaulevel" mit einem spürbaren Sprung, nicht nur +Prozent.

### Waffen (Hardpoint), Level 1-5
| Waffe | pro Level | Level 5 |
|---|---|---|
| Door MG | +12 % Schaden | Doppel-MG: zwei Tracer pro Schuss |
| Minigun | +10 % Feuerrate | Überhitzung weg: Dauerfeuer ohne Streuung-Anstieg |
| Autocannon | +15 % Schaden | Sprengmunition: kleiner Flächenschaden |
| Flak | +1 Projektil | Doppelter Kegel |
| Raketen | +15 % Flächenradius | Salve: 3 Raketen pro Auslösung |
| Railgun | +20 % Schaden | Kettenblitz: Treffer springt auf 2 weitere Ziele |

### Systeme (System-Slot), Level 1-5
| System | Wirkung | pro Level | Level 5 |
|---|---|---|---|
| Suchscheinwerfer | Kegel vor dem Heli; Zombies darin werden nachts 30 % langsamer, POIs werden sichtbar | +Reichweite, +Verlangsamung | Blendung: Zombies im Kegel stehen 2 s still |
| Täuschkörper | alle 20 s ein Leuchtkörper, der 8 s lang Lärm an seiner Position macht, zieht Zombies weg | kürzeres Intervall, längere Dauer | zwei Körper, Zombies greifen den Köder an |
| Lautsprecher | auf Knopfdruck Lärm im Umkreis, holt Zombies gezielt aus einer Siedlung | größerer Radius | Panik: Zombies laufen 5 s weg statt hin |
| Seilwinde | nimmt im Schwebeflug (unter 40 px/s) alle 6 s einen Überlebenden auf, ohne zu landen | schneller | zwei gleichzeitig |
| Zweiter Schütze | Automatik-MG, das das nächste Ziel beschießt (40 % Schaden) | +Schaden, +Reichweite | übernimmt die Hauptwaffe mit 80 % |
| Sanitäter | Hülle regeneriert 1 HP/s im Flug; Überlebende sterben nicht bei Treffern an Bord | +Regeneration | Hülle regeneriert auch gelandet |
| Abwurfkiste | alle 90 s fällt eine Versorgungskiste am Heli-Standort (Munition oder Treibstoff) | kürzer, mehr Inhalt | Kiste enthält auch Scrap |

### Module (Modul-Slot), Level 1-5
| Modul | pro Level | Level 5 |
|---|---|---|
| Triebwerk-Tuning | +6 % Höchstgeschwindigkeit | Spool-Zeit halbiert |
| Panzerplatten | +8 % Rüstung | Rammschäden durch Zombies halbiert |
| Magerbrand | +8 % Treibstoffeffizienz | Leerlauf gelandet kostet nichts, Tank füllt 10 % bei jeder Lieferung |
| Munitionsgurte | +40 Max-Munition | Jede Lieferung bringt 20 % Munition zurück |
| Schützentraining | +8 % Feuerrate | Erster Schuss nach Pause kritisch |
| Hartkern | +1 Durchschlag alle 2 Level | Treffer prallen einmal ab |
| Kabinenausbau | +1 Sitz alle 2 Level | Zivilisten steigen doppelt so schnell ein |
| Veteran | +10 % XP | Level-ups bieten 4 statt 3 Karten |
| Plünderer | +15 % Scrap | Zombie-Drops geben Munition |

## 3. Angebot beim Level-up (Vampire-Survivors-Logik)

1. Pool bilden: alle eigenen Teile unter Level 5 (als Level-up) plus neue Teile, sofern ihr Slot-Typ noch frei ist.
2. Drei verschiedene Karten ziehen, gewichtet: Level-up eigener Teile 60 %, neue Teile 40 %. Ab Heli-Level 10 sinkt das Gewicht neuer Teile, damit Builds dicht werden.
3. Jede Karte zeigt: Slot-Symbol, Name, aktuelles Level als Punkte, Beschreibung der nächsten Stufe.
4. Reroll (einmal pro Run, Meta-Unlock bis 3), Überspringen (gibt 15 Scrap), Verbannen (Karte erscheint im Run nie wieder, Meta-Unlock).
5. Hat kein Slot-Typ mehr Platz und sind alle Teile Level 5, bringt ein Level-up 40 Scrap und 10 % Reparatur.

Die heutigen Waffenkisten an POIs geben wie bisher eine neue Waffe (sie belegt einen Hardpoint oder geht in die Bucht); die heutige Upgrade-Wahl an Kisten bietet künftig eine Karte aus demselben Pool.

## 4. Maximallevel des Helikopters

- Heli-Level 1 bis 30. Die XP-Kurve bleibt 25 × Level^1,4 (Level 30 kumuliert ca. 37.000 XP).
- Ab Level 30 fließen XP in Scrap (10 XP = 1 Scrap). Der Build ist dann fertig, der Rest des Runs ist Basisverteidigung und Rettungsquote.
- Mit 2 + 3 + 4 Slots und Level 5 pro Teil braucht ein kompletter Build 9 Teile × 5 Level = 45 Karten, also sind 29 Level-ups bewusst knapp: man schafft etwa zwei Drittel eines perfekten Builds.

## 5. Dauerhafte Freischaltungen (Meta)

Gezählt werden über alle Runs: gerettete Überlebende, Tage überlebt, Boss-Kills, Basis-Angriffe gehalten.

| Freischaltung | Bedingung |
|---|---|
| Teile im Pool: Start sind Door MG, Minigun, Suchscheinwerfer, Zweiter Schütze, Triebwerk, Panzerplatten, Magerbrand, Munitionsgurte, Kabinenausbau | immer |
| Täuschkörper, Autocannon | 25 Überlebende gerettet |
| Seilwinde, Sanitäter | 50 Überlebende |
| Lautsprecher, Flak | 3 Basis-Angriffe gehalten |
| Raketen, Abwurfkiste | 5 Boss-Kills |
| Railgun, Hartkern | Tag 10 erreicht |
| Veteran, Plünderer | 10 Runs gespielt |
| Reroll 2 und 3, Verbannen | 100 / 200 Überlebende |
| Dritter System-Slot ab Start | Tag 15 erreicht |
| Vierter Modul-Slot ab Start | 300 Überlebende |

Die bestehenden Boni (Sitz pro 25 Gerettete, Tank und Munition pro 10) bleiben.

## 6. Anzeige

- HUD: unter den Balken eine Zeile mit den Slots als kleine Kästchen (Waffe, System, Modul) mit Level-Punkten.
- Titelbildschirm: "Hangar"-Tab mit allen Teilen, gesperrte grau mit Bedingung.
- Basis-Menü HANGAR: zeigt Slots und erlaubt, ein Teil zu verschrotten (Slot frei, 50 % der Karten als Scrap zurück).

## 7. Umsetzung in Schritten

1. `scripts/progression.gd`: Tabelle aller Teile (id, Slot-Typ, Maximallevel, Effekt pro Level, Level-5-Effekt, Freischaltbedingung). Ersetzt `upgrades.gd`.
2. `Game`: `heli_items: {id: level}`, Slot-Grenzen, Level-Cap 30 mit XP-zu-Scrap, Reroll-Zähler. `recompute()` leitet alle Stats aus den Teilen ab.
3. Angebotslogik und Karten-UI (Level-Punkte, Reroll, Skip, Verbannen).
4. Systeme als kleine Skripte: Suchscheinwerfer, Täuschkörper, Lautsprecher, Seilwinde, Zweiter Schütze, Sanitäter, Abwurfkiste.
5. Waffenlevel und Level-5-Ausbauten in `heli.gd`/`bullet.gd`.
6. Meta-Freischaltungen und Hangar-Tab am Titelbildschirm.
7. Balancing-Durchlauf mit Headless-Simulation: ein Bot-Run über 20 Minuten, Statistik von Level, Kills, Rettungen.

Aufwand: Schritte 1-3 ein Block, 4-5 ein Block, 6-7 ein Block. Jeder Block ist für sich spielbar.
