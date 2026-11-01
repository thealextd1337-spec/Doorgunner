# Progression – Plan (Stand 2026-10-28, Entscheidungen: Slots 1/2/2 → 2/3/3, Heli-Cap 30)

Ziel: ein Vampire-Survivors-artiger Pfad für den Helikopter. Jedes Level-up bietet drei Karten,
man nimmt eine. Der Heli hat feste Slots, jedes Teil hat ein Maximallevel, Slots sind knapp,
also muss man sich für einen Build entscheiden. Dazu ein Maximallevel für den Heli selbst und
dauerhafte Freischaltungen über Runs hinweg.

## 1. Slots am Helikopter

| Slot-Typ | Anzahl (Start) | Was hinein passt | Thema |
|---|---|---|---|
| Hardpoint | 1 (max 2) | Waffen (Door MG, Minigun, Autocannon, Flak, Raketen, Railgun, Q8: Scatter Gun, Flammenwerfer, Granatwerfer, Präzisionsgewehr, Schallkanone, Netzwerfer) | Türbewaffnung links/rechts |
| System | 2 (max 3) | aktive Bordsysteme, feuern/wirken automatisch | Avionik und Crew |
| Modul | 2 (max 3) | passive Boni | Zelle, Triebwerk, Munition |

- Jeder Slot-Typ hat eine Obergrenze. Ein voller Slot-Typ bietet nur noch Level-ups für vorhandene Teile.
- Zweiter Hardpoint: Werkstatt Stufe 1 oder Meta (Tag 5 erreicht). Dritter System-Slot: Werkstatt Stufe 2 oder Meta (Tag 15). Dritter Modul-Slot: Werkstatt Stufe 3 oder Meta (300 Überlebende).
- Start mit nur einer Waffe am Hardpoint. Gefundene Waffen gehen ohne freien Hardpoint in die Bucht der Basis; mit zwei Hardpoints wechselt Q wie heute. Waffen werden künftig ebenfalls gelevelt.

## 2. Teile und Maximallevel

Alle Teile haben Level 1 bis 5. Level 5 ist das "Ausbaulevel" mit einem spürbaren Sprung, nicht nur +Prozent.

### Waffen (Hardpoint), Level 1-5
| Waffe | pro Level | Level 5 |
|---|---|---|
| Door MG | +12 % Schaden | Doppel-MG: zwei Tracer pro Schuss |

Reichweiten (umgesetzt): Door MG 42 m, Minigun 32 m, Autocannon 62 m, Flak 20 m, Raketen 52 m, Railgun 90 m. Geschosse verpuffen am Ende der Reichweite; der HUD zeigt einen Ring.
| Minigun | +10 % Feuerrate | Überhitzung weg: Dauerfeuer ohne Streuung-Anstieg |
| Autocannon | +15 % Schaden | Sprengmunition: kleiner Flächenschaden |
| Flak | +1 Projektil | Doppelter Kegel |
| Raketen | +15 % Flächenradius | Salve: 3 Raketen pro Auslösung |
| Railgun | +20 % Schaden | Kettenblitz: Treffer springt auf 2 weitere Ziele |

### Q8 Arsenal (Stand 2026-11-02)

Alle Werte stehen in `scripts/weapons.gd` (Tabelle, `level_mods`, `tune`), `scripts/progression.gd` (Items, `apply`) und als Konstanten oben in `scripts/burn.gd`, `scripts/systems/thermal.gd`, `smoke.gd`. Eigenschaften wie Brand, Betäubung, Bogenflug, Durchschlag und Schadensabfall sind Eigenschaften der Kugel (`bullet.gd`), nicht von `enemy.gd`. Sounds sind Platzhalter (vorhandene Dateien), Q16 tauscht gegen Q7.

| Waffe (Hardpoint) | Werte (Lv 1) | pro Level | Level 5 | Freischaltung |
|---|---|---|---|---|
| Scatter Gun | 10 Schrot à 6, Kegel 30°, 14 m, Schaden fällt bis auf 35 %, 3 Munition | +1 Schrot | Drachenatem: Schrot zündet | 8 Runs |
| Flammenwerfer | 4 Schaden alle 0,08 s, 11 m, durchschlägt alles, Brand 8/s für 3 s | +15 % Brandschaden | Lauffeuer: Brennende zünden Nachbarn (28 px) | 150 gerettet |
| Granatwerfer | 70 Schaden, Flächenradius 5,5 m, fliegt im Bogen zum Mauszeiger (6–42 m), trifft nur am Ziel, 4 Munition | +15 % Radius | Cluster: 3 Granaten | 15 Basis-Angriffe |
| Präzisionsgewehr | 80 Schaden, 100 m, Durchschlag 2, +20 % Kopftreffer, 2 Munition, 0,9 s | +15 % Schaden | Dead-eye: +2 Durchschlag, 50 % Kopftreffer | Tag 12 |
| Schallkanone | Welle (Radius 24 px), 4 Schaden, betäubt 0,8 s, schiebt, 16 m, 3 Munition; Banditen unbetroffen | +25 % Schaden, +0,2 s | Resonanz: Schaden ×4 | 15 Bosse |
| Netzwerfer | Granate, Radius 4,5 m, 3 Schaden, Zombies stehen 2 s (danach 4 s immun), Bosse immun | +0,5 s | Weites Netz: Radius ×2 | 12 Runs |

| Item | Slot | Wirkung | pro Level | Level 5 | Freischaltung |
|---|---|---|---|---|---|
| Thermal Sight | System | Gegner nachts als Wärmebild, 20 m | +4 m | 45 m, sieht auch Zombies im Wald | Tag 25 |
| Smoke Launcher | System | Nebelwand (r 4,8 m) bei Beschuss oder anfliegender Rakete: Raketen verlieren das Ziel, Zombies darin −50 % Tempo; 6 s, alle 24 s | länger (+1 s), schneller (−3 s) | Zombies im Nebel 2 s betäubt | 10 Basis-Angriffe |
| Extra Tank | Modul | +10 Treibstoff | +10 | +60, 10 % weniger Verbrauch | 5 Runs |
| Heavy Plates | Modul | +20 % Rüstung, −4 % Tempo (Gewicht) | +20 % / −4 % | +150 % Rüstung, −20 % Tempo | 5 Boss-Kills |

Brand wird nicht gespeichert (dauert 3 s). Neue Gegenstände sind alte Spielstände-kompatibel: `SAVE_FORMAT` bleibt, `Game.stats` bekommt `tank` und `weight` (`BASE_STATS`).

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
| Zieloptik | +10 % Reichweite | Treffer im äußeren Drittel der Reichweite machen +50 % Schaden |

## 3. Angebot beim Level-up (Vampire-Survivors-Logik)

1. Pool bilden: alle eigenen Teile unter Level 5 (als Level-up) plus neue Teile, sofern ihr Slot-Typ noch frei ist.
2. Drei verschiedene Karten ziehen, gewichtet: Level-up eigener Teile 60 %, neue Teile 40 %. Ab Heli-Level 10 sinkt das Gewicht neuer Teile, damit Builds dicht werden.
3. Jede Karte zeigt: Slot-Symbol, Name, aktuelles Level als Punkte, Beschreibung der nächsten Stufe.
4. Reroll (einmal pro Run, Meta-Unlock bis 3), Überspringen (gibt 15 Scrap), Verbannen (Karte erscheint im Run nie wieder, Meta-Unlock).
5. Hat kein Slot-Typ mehr Platz und sind alle Teile Level 5, bringt ein Level-up 40 Scrap und 10 % Reparatur.

Die heutigen Waffenkisten an POIs geben wie bisher eine neue Waffe (sie belegt einen Hardpoint oder geht in die Bucht); die heutige Upgrade-Wahl an Kisten bietet künftig eine Karte aus demselben Pool.

## 4. Maximallevel des Helikopters

- Heli-Level 1 bis 30. Die XP-Kurve ist 30 × Level^1,6 (P5; vorher 25 × Level^1,4).
- Ab Level 30 fließen XP in Scrap (10 XP = 1 Scrap). Der Build ist dann fertig, der Rest des Runs ist Basisverteidigung und Rettungsquote.
- Mit voll ausgebauten 2 + 3 + 3 Slots und Level 5 pro Teil braucht ein kompletter Build 8 Teile × 5 Level = 40 Karten; mit den Start-Slots 1 + 2 + 2 sind es 25. 29 Level-ups reichen also für einen vollen Start-Build plus ein paar Stufen in nachgekauften Slots. Slots nachzukaufen lohnt nur, wenn man früh dran ist.

## 5. Dauerhafte Freischaltungen (Meta)

Gezählt werden über alle Runs: gerettete Überlebende, Tage überlebt, Boss-Kills, Basis-Angriffe gehalten.

| Freischaltung | Bedingung |
|---|---|
| Teile im Pool: Start sind Door MG, Minigun, Suchscheinwerfer, Zweiter Schütze, Triebwerk, Panzerplatten, Magerbrand, Munitionsgurte, Kabinenausbau | immer |
| Täuschkörper, Autocannon | 50 Überlebende gerettet (P5: ×2) |
| Seilwinde, Sanitäter | 100 Überlebende |
| Lautsprecher, Flak | 6 Basis-Angriffe gehalten |
| Raketen, Abwurfkiste | 10 Boss-Kills |
| Railgun, Hartkern | Tag 20 erreicht |
| Veteran, Plünderer | 20 Runs gespielt |
| Reroll 2 und 3, Verbannen | 200 / 400 Überlebende |
| Zweiter Hardpoint ab Start | Tag 10 erreicht |
| Dritter System-Slot ab Start | Tag 30 erreicht |
| Dritter Modul-Slot ab Start | 600 Überlebende |

Die bestehenden Boni: ein Sitz pro 50 Gerettete, Tank und Munition pro 20, Hülle pro 40 (seit P5 Tempo verdoppelt).

## 6. Anzeige

- HUD: unter den Balken eine Zeile mit den Slots als kleine Kästchen (Waffe, System, Modul) mit Level-Punkten.
- Titelbildschirm: "Hangar"-Tab mit allen Teilen, gesperrte grau mit Bedingung.
- Basis-Menü HANGAR: zeigt Slots, erlaubt ein Teil zu verschrotten (Slot frei, 50 % der Karten als Scrap zurück) und kauft Slot-Erweiterungen über die Werkstatt.

## 7. Umsetzung in Schritten

1. `scripts/progression.gd`: Tabelle aller Teile (id, Slot-Typ, Maximallevel, Effekt pro Level, Level-5-Effekt, Freischaltbedingung). Ersetzt `upgrades.gd`.
2. `Game`: `heli_items: {id: level}`, Slot-Grenzen, Level-Cap 30 mit XP-zu-Scrap, Reroll-Zähler. `recompute()` leitet alle Stats aus den Teilen ab.
3. Angebotslogik und Karten-UI (Level-Punkte, Reroll, Skip, Verbannen).
4. Systeme als kleine Skripte: Suchscheinwerfer, Täuschkörper, Lautsprecher, Seilwinde, Zweiter Schütze, Sanitäter, Abwurfkiste.
5. Waffenlevel und Level-5-Ausbauten in `heli.gd`/`bullet.gd`.
6. Meta-Freischaltungen und Hangar-Tab am Titelbildschirm.
7. Balancing-Durchlauf mit Headless-Simulation: ein Bot-Run über 20 Minuten, Statistik von Level, Kills, Rettungen.

Aufwand: Schritte 1-3 ein Block, 4-5 ein Block, 6-7 ein Block. Jeder Block ist für sich spielbar.
