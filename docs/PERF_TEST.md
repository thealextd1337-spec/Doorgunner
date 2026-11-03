# Performance-Messung (PC und Handy)

Ziel: p50/p95/max der Frame-Zeit und die Chunk-/Pfad-/Spawner-Zeiten auf **deinen** Geräten, auf einer festen Route, damit PC und Handy vergleichbar sind. Die Zahlen schickst du zurück (Abschnitt 4).

## 1. Spiel mit der Anzeige öffnen

Die Adresse des Spiels (GitHub Pages) mit `?perf=1` am Ende:

```
https://thealextd1337-spec.github.io/Doorgunner/?perf=1
```

(Das Spiel dort ist erst nach dem Deploy von S4 die Version mit COPY-Knopf.)

**PC (Chrome / Edge / Firefox):** Adresse mit `?perf=1` öffnen, Spiel laden. Oben in der Mitte (rechts neben dem Statusblock) steht die Anzeige, dauerhaft, **ohne F3**. Mit F12 → Konsole siehst du dieselben Zeilen (`PERF …`, alle 10 s) und `WORLDHASH …` einmal beim Start.

**Handy (Chrome Android / Safari iOS):** dieselbe Adresse im Browser öffnen, Querformat, wenn möglich Vollbild-Knopf (oben Mitte) drücken. Die Anzeige sitzt oben in der Mitte und deckt keine Steuerung ab (Sticks und Tasten sind unten). Keine Tastatur nötig.

Optional: schnell zu einer bestimmten Lage springen, **nur** mit `perf=1`:

| Adresse | Was passiert |
|---|---|
| `…/Doorgunner/?perf=1&scenario=city` | Lauf startet ohne Titel, ca. 1500 px vor der nächsten Stadt |
| `…/Doorgunner/?perf=1&scenario=bloodmoon` | Lauf startet mit gegründeter Basis, kurz vor der Blutmond-Nacht (Angriff beginnt nach wenigen Sekunden) |

Diese Läufe sind **nie gewertet** (kein Ranking), werden **nicht gespeichert** und ändern weder gespeicherten Lauf noch Meta-Fortschritt. Im normalen Spiel gibt es den Schalter nicht.

## 2. Feste Route

Immer in dieser Reihenfolge, jeweils ein neuer Lauf (Seite neu laden). Heli nicht anhalten, außer es steht dabei.

1. **Start (30 s):** Spiel laden, Heli abheben, 30 Sekunden geradeaus fliegen. Danach steht die erste `PERF`-Zeile (alle 10 s kommt eine).
2. **Stadt:** weiter zur nächsten Stadt (große Häuserblöcke auf der Minikarte) und **einmal durch sie hindurch** fliegen (ca. 30 s). Abkürzung: `scenario=city`.
3. **Angriff / Blutmond:** in der Basis (oder mit `scenario=bloodmoon` direkt) den Angriff abwarten und **mit dem Heli über der Basis schweben**, solange die Horde kommt (ca. 60 s). Ohne Schalter: Basis gründen (B) und den ersten Angriff abwarten (Tag 3, abends). Ein Blutmond (roter Himmel) kommt erst in der 9. Nacht; deshalb ist der Schalter hier der einfache Weg.
4. **2 Minuten Neuland:** in eine Richtung, die du noch nicht kennst, **120 Sekunden lang geradeaus** fliegen (nicht an Städten hängen bleiben). Das ist der Chunk-Test.
5. Auf **COPY** tippen (Abschnitt 3).

Ein Gerät: ca. 6 Minuten. Pro Gerät eine Route reicht.

## 3. Kopieren und zurückschicken

Unter den Zahlen steht der Knopf **COPY**. Er legt in die Zwischenablage:

- Kopfzeile: Spielversion, Szenario, Browser (User-Agent), Bildschirmgröße, Fenstergröße, Pixel-Verhältnis (devicePixelRatio)
- die **letzten 20 PERF-Zeilen** (= die letzten ~200 s, also die ganze Route 4) und eine Zeile mit den Werten „jetzt“

Dann irgendwo einfügen (Notizen, Chat) und mir schicken. Wenn der Browser die Zwischenablage verweigert (z. B. Seite nicht per https), erscheint darunter ein Textfeld mit demselben Text: lang drücken bzw. markieren → Kopieren. Notfalls: ein Foto der Anzeige plus Gerätename.

Schick pro Gerät: **PC** (Browser nennen) und **Handy** (Modell nennen).

## 4. Zahlen lesen

Eine Zeile, z. B. `FPS 58  frame p50 16.7  p95 22.0  max 48.0 ms  work p50 6.1  p95 9.0`:

- **frame p50:** typische Frame-Zeit (die Hälfte der Frames ist schneller). 16.7 ms = 60 FPS, 33 ms = 30 FPS. Auf dem Handy ist das Display-Limit oft 60 oder 30 Hz.
- **frame p95:** 5 % der Frames sind langsamer als das. **Das ist die wichtigste Zahl.** Ziel: **≤ 33 ms**. Darüber schaltet das Spiel Partikel und Leichen automatisch herunter (`fx`), und ich optimiere gezielt.
- **frame max:** der schlimmste Ruckler der letzten 10 s. Einzelne Spitzen (100+ ms) beim Laden/Wechseln sind normal, wiederholte nicht.
- **work p50 / p95:** Rechenzeit pro Frame **ohne** Warten auf das Display. Liegt „work“ weit unter „frame“, begrenzt das Display (VSync), nicht das Spiel. Liegt „work“ nahe an „frame“, ist das Gerät am Limit.
- **chunk / path / spawn „avg (max)“:** ms pro Frame im Mittel und im schlimmsten Frame für Geländeerzeugung, Wegfindung und Gegner-Spawner. **Chunk max** über **50 ms** in Route 4 heißt: das Nachladen von neuem Gelände ruckelt spürbar.
- **enemies / bandits / POIs / chunks / nodes / mem:** was gerade im Spiel ist (zur Einordnung: viel Gegner = mehr Last; mem = RAM des Spiels, Handys mit < 2 GB sind knapp).

Faustregel: p95 ≤ 33 ms in allen vier Teilen der Route = in Ordnung. Auffällig ist: p95 > 33 ms, chunk max > 50 ms, oder mem stetig steigend in Route 4.
