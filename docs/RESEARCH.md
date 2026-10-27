# Doorgunner – Research (Stand 2026-10-27)

Quellen: WebSearch, Stand Oktober 2026. Reviews/Wikis sind Sekundärquellen; harte Zahlen (Build-Größen, Godot-Settings) vor Umsetzung gegen aktuelle Godot-Docs prüfen.

## Empfehlung: nächste 5 Features

1. **Reroll / Skip / Banish im Level-up-Menü** (S) – billigster Weg, Level-ups spannend zu halten; Meta-Unlock wie in Vampire Survivors.
2. **Passagiere mit Wert und Risiko** (M) – Survivors haben Rolle (Medic, Engineer, Gunner) und können beim harten Landen oder Treffer sterben (Choplifter HD / Death Road). Macht jeden Flug zur Entscheidung.
3. **Sichtbarer Druck-Timer im Overworld** (M) – „Hive-Front“ wandert wie die Rebel Fleet in FTL über die Chunks; alte Towns fallen, Nachzügler-Loot sinkt. Zwingt nach vorn, verhindert Farmen.
4. **Nacht als Lesbarkeits-Feature** (S/M) – CanvasModulate + PointLight2D an Heli, Base, Flares; Gegner-Augen leuchten. Nacht fühlt sich gefährlich an, ohne neue Mechanik.
5. **Blood-Moon-Variante der Base-Attacke** (S) – jede dritte Nacht ist Standard; jede neunte endet erst, wenn die Welle tot ist (Kingdom Two Crowns). Gibt dem Rhythmus einen Peak.

---

## 1. Vergleichbare Spiele und was ihren Loop trägt

### Choplifter (1982 / HD 2012)
- Kern: Landen, Geiseln einsammeln, zur Base fliegen. Der Heli fasst nur einen Bruchteil der Geiseln pro Level, daher **erzwungene Mehrfach-Trips** bei steigender Gegner-Aggression. Ausweichen und sauberes Landen zählen mehr als Schießen.
- HD-Version: Passagiere haben Timer, **harte Landung tötet Passagiere**, Fuel an Base oder Depots nachfüllen, Sterne-Progression schaltet bessere Helis frei.
- Quellen: [bitvint Choplifter](https://bitvint.com/pages/choplifter), [Filfre Choplifter](https://www.filfre.net/?p=645), [Choplifter HD Wikipedia](https://en.wikipedia.org/wiki/Choplifter_HD), [ztgd Review](https://ztgd.com/reviews/choplifter-hd/)

### Nuclear Throne / Enter the Gungeon
- NT: Rads = XP, Level-up bietet **4 zufällige Mutations**; Crowns = optionaler Risiko-Modifier mit Nachteil. Aim entkoppelt von Movement, Reticle frei auf dem Screen, Screen Shake skaliert mit Waffenstärke (Spieler drehen es bei starken Waffen runter → Option anbieten).
- Gungeon: **Dodge Roll mit i-Frames** (Startup-Delay, nicht ab Frame 1) als wiederholbares Tool, **Blanks** als limitierter Panik-Button (mind. 2 pro Floor). Gestaffelte Defensive: Skill-Tool + Konsumgut.
- Quellen: [NT Wikipedia](https://en.wikipedia.org/wiki/Nuclear_Throne), [GamingOnLinux NT](https://www.gamingonlinux.com/2015/08/gol-cast-maxing-out-the-geiger-counter-in-nuclear-throne/), [Game Wisdom Gungeon](https://game-wisdom.com/analysis/enter-the-gungeon), [Gamedeveloper Gungeon Q&A](https://www.gamedeveloper.com/design/q-a-the-guns-and-dungeons-of-i-enter-the-gungeon-i-)

### Vampire Survivors
- Level-up = 3–4 Karten; **Reroll / Skip / Banish** sind Meta-Unlocks, „Preserve“ gibt Chance, sie zu behalten. Evolution: Waffe auf Max-Level + Partner-Item + Boss-Chest.
- Lehre: Die Karten-Economy lebt von Spieler-Kontrolle über den Zufall, nicht von mehr Karten.
- Quellen: [VS Wiki Preserve](https://vampire.survivors.wiki/w/Preserve), [PCGamesN Power-ups](https://www.pcgamesn.com/vampire-survivors/power-ups-best), [Digital Trends Evolutions](https://www.digitaltrends.com/?p=3653537)

### FTL / Darkest Dungeon
- FTL: Rebel Fleet rückt **nur bei Jumps** vor und frisst Beacons; Scrap nur durch Erkunden; jedes Encounter kostet potenziell Hull/Crew. Die zentrale Spannung ist „mehr Beacons = mehr Scrap, aber Fleet im Nacken“.
- DD: Stress als Ressource, die über die Party schwappt; Hamlet als Base mit Recruit/Heal/Upgrade zwischen Expeditionen. Stories entstehen aus dem Druck, nicht aus Content.
- Quellen: [FTL Wikipedia](https://en.wikipedia.org/wiki/FTL:_Faster_Than_Light), [FTL Steam Fleet-Thread](https://steamcommunity.com/app/212680/discussions/0/828936718810691367), [DD Review GodisaGeek](https://godisageek.com/reviews/darkest-dungeon-review/), [GDC DD Postmortem](https://www.gdcvault.com/play/1023089/contactUs)

### Kingdom Two Crowns
- Tag bauen, Nacht verteidigen, Coins sind alles. Greed stehlen **Coins, dann die Krone** – Verlust ist ökonomisch, nicht nur HP. **Blood Moon endet erst, wenn die Welle tot ist.** Kritik: Late-Game-Verteidigung wird repetitiv → Wellen brauchen Varianten.
- Quellen: [Kingdom Wiki Dawn](https://kingdomthegame.fandom.com/wiki/Dawn), [gideonsgaming Review](https://gideonsgaming.com/kingdom-two-crowns-review-money/), [Steam Forum](https://steamcommunity.com/app/701160/discussions/0/4849904828217616805)

### Top-down Heli-Zombie-Spiele
- Keine kanonische Flash-Referenz gefunden. Nächste Treffer: **Z Escape** (Switch: MG vom Chopper, Zombies werden nach jedem Escape härter), **Dustoff Z** (Mobile, Rescue + Shooting), **SOS Zombie Survivors** (Distress-Signal halten, bis Heli kommt).
- Quellen: [Z Escape](https://www.timeextension.com/games/switch-eshop/z_escape_complete_edition), [Dustoff Z](https://toucharcade.com/2019/09/13/dustoff-z-open-beta), [SOS Zombie Survivors](https://store.steampowered.com/app/2689600)

### Death Road to Canada
- Survivors sind Ressource **und** Risiko: Morale pro Charakter, Traits ändern Event-Optionen, Supplies-Mangel senkt Morale, Siege kann Crew kosten. Random Text-Events werden als Schwachpunkt genannt, wenn sie beliebig wirken.
- Quellen: [DRTC Wikipedia](https://en.wikipedia.org/wiki/Death_Road_to_Canada), [COGconnected Review](https://cogconnected.com/review/death-road-to-canada-review/)

### Feature-Ideen, gerankt (Aufwand S/M/L für Solo-Dev)

| # | Feature | Warum | Aufwand |
|---|---------|-------|---------|
| 1 | Reroll/Skip/Banish als Meta-Unlock | Günstigster Spannungsgewinn im Level-up (VS) | S |
| 2 | Passagier-Rollen (Medic/Engineer/Gunner) mit Base-Effekt | Survivors werden zur Entscheidung, nicht zum Counter (DRTC) | M |
| 3 | Harte Landung / Treffer töten Passagiere | Landen bleibt Skill-Moment (Choplifter HD) | S |
| 4 | Wandernde Hive-Front über Chunks | FTL-Fleet: zwingt nach vorn, kein Farmen | M |
| 5 | Blood-Moon-Nacht (Welle muss sterben) | Rhythmus-Peak, Kingdom | S |
| 6 | Flares/Blanks: 2 pro Run, löschen Projektile im Radius | Panik-Button, Gungeon | S |
| 7 | Crowns: Run-Modifier mit Vor- und Nachteil beim Start | Replay ohne neuen Content (NT) | S |
| 8 | Scrap-Diebstahl: Gegner tragen Base-Ressourcen weg | Verlust ökonomisch statt nur HP (Kingdom) | M |
| 9 | Sichtbarer Passagier-Timer pro Town (Hive erreicht Town in X) | Entscheidung „noch eine Town?“ (Choplifter HD) | S |
| 10 | Weapon-Evolution: Max-Waffe + Workshop-Item = neue Waffe | Build-Ziel für lange Runs (VS) | M |
| 11 | Morale/Stress der Base-Crew, sinkt bei Hunger/Nachtverlust | Base-vs-Expedition-Spannung (DD) | L |
| 12 | Screen-Shake-Slider + Shake proportional zur Waffe | NT-Lehre: Feel, aber abschaltbar | S |
| 13 | Dodge/Boost mit i-Frames (Shift) für den Heli | Wiederholbares Defensiv-Tool (Gungeon) | S |
| 14 | Wellen-Varianten (Flanke, Tunnel, Boss-Nacht) | Kingdom-Kritik: Late-Game monoton | M |
| 15 | Rescue-Chain: Heli trägt nur N, Town hat 3N | Mehrfach-Trips mit steigendem Risiko (Choplifter) | S |

---

## 2. Art Style – eine Richtung

**Empfehlung: „Clean Military Pixel“ – Nuclear-Throne-Lesbarkeit mit gedeckter Brotato-Farbcodierung, kein Hotline-Miami-Neon, kein Desert-Strike-Iso.**

- **Auflösung:** 16-px-Tiles, Heli 32×32, Aliens 12–16 px, Survivors 8×12. Viewport 640×360 bei 2x auf 1280×720 (integer scaling, `canvas_items` Stretch, Texture Filter Nearest). Alles auf dem Pixelgrid snappen, Rotation nur für Heli/Rotor/Projektile.
- **Palette: Endesga 32** ([Lospec](https://lospec.com/palette-list/endesga-32)). Begründung: 32 Farben reichen für Erde/Gras/Asphalt/Militärgrün plus eine klare Alien-Rampe; warme Rost-Creme-Töne passen zu Countryside; Jam-erprobt, viele kompatible Asset-Packs auf itch. **AAP-64** ([Lospec](https://lospec.com/palette-list/aap-64)) wäre die Ausweichlösung, falls Nacht-Rampen zu wenig Stufen haben; **Resurrect 64** ([Lospec](https://lospec.com/palette-list/resurrect-64)) ist für mehrere Biome gedacht – zu viel für ein Biom + Nacht.
- **Farb-Codierung (Brotato-Regel):** Spieler/Base = Oliv + Orange-Akzent, Zivilisten = Blau/Weiß, Aliens = Violett/Magenta, **Gefahr = reines Rot** (Projektile, Nest-Aura, Warn-UI). Nie Rot für Loot verwenden.
- **Outline-Regel:** Charaktere/Vehicles/Projektile: 1 px dunkle Outline (dunkelste Palettenfarbe, nicht Schwarz, Endesga `#181425`). Terrain und Gebäude: **keine** Outline, nur Wertkontrast. Nuclear-Throne-Lehre: dicke Outline + wenig AA macht 16-px-Sprites bei Bewegung lesbar.
- **Nacht und Gefahr lesen:** CanvasModulate auf Blau-Grau (`#262b44`-nah), PointLight2D an Heli (Suchscheinwerfer, Kegel), Base-Pad, Flares, Mündungsfeuer. Aliens bekommen Emissive-Augen (Sprite-Layer ohne Modulate oder additive Light). Gefahr-Radius um Nester als pulsierendes Rot, Base-Attack-Nacht färbt den Himmel-Modulate Richtung Rot (Blood Moon).
- **VFX:** Muzzle Flash 2 Frames 8×8 additiv, Tracer = 1×4 px helle Linie mit 2-Frame-Trail, Hülsen als 1-px-Partikel, Alien-Goo in Violett (bleibt 10 s als Decal, Spritzer 3–5 Partikel), Screen Shake 2–4 px bei Treffer, 8 px bei Explosion, immer mit Slider. Hit-Flash: Sprite 2 Frames weiß. Hit-Stop 2 Frames bei Boss-Kills.
- **UI:** Field-Radio-HUD: monochrom Oliv-Phosphor, Bitmap-Font 5×7, Rahmen aus 1-px-Linien, Fuel/Ammo als Segment-Balken, Radio-Hints als Ticker unten mit Rausch-Icon. Base-Menü als Klemmbrett/Inventar-Panel. Kein Rounded-Corner, kein Gradient.
- **Gegenbeispiel Desert Strike:** Iso-Heli aus 3D-Renders braucht 8+ Richtungen und Perspektiv-Tiles – für Solo-Dev zu teuer, und Top-down mit rotierendem Sprite reicht für Twin-Stick.
- Referenzen: [NT Presskit](https://www.indiedb.com/games/nuclear-throne/presskit), [Brotato Review Farbcodierung](https://medium.com/@xtreme2g/brotato-is-almost-perfect-complete-review-0d49d27708ef), [Brotato Art Dev](https://hyper3d.ai/blog/brotatos-unique-art-style-an-inside-look-at-its-development), [Silhouette-first Guide](https://the-pixel.art/articles/pixel-art-character-design/), [Alain Pixel Art for Gamedev](https://alain.xyz/blog/pixel-art-design-for-game-dev), [Godot 2D Lights](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html), [Catlike Coding Top-down Light](https://catlikecoding.com/godot/true-top-down-2d/4-light-and-shadow/), [Desert Strike Hintergrund](https://gamicus.fandom.com/wiki/Desert_Strike:_Return_to_the_Gulf)

---

## 3. Sound-Richtung

1. **Hybrid:** SFX chiptune-ish aus jsfxr/sfxr (schnell, konsistent, winzig für Web), aber Radio-Layer sampled: Funk-Rauschen, Squelch, verzerrte Stimme als Textur über Hints.
2. Rotor als loopender Low-Noise-Layer mit Pitch an Speed; Türgeschütz = kurzer sfxr-„Shoot“ mit Random-Pitch ±5 %, Hülsen-Klick separat.
3. Aliens: Goo/Squish aus sfxr „Hit“ mit Lowpass; Nest-Pulse als Sub-Bass-Loop, hörbar vor sichtbar.
4. Musik: ein Ambient-Drone tags, Percussion-Layer nachts, zusätzlicher Layer bei Base-Attack (3 Stems, Godot AudioStreamSynchronized).
5. Lizenz: Freesound pro Sound prüfen – CC0 ohne Credit, CC-BY mit Credits-Screen, **CC-BY-NC nicht verwenden**. jsfxr-Code: Lizenz im Repo prüfen (npm zeigt „none“, Hinweise auf Unlicense); generierte WAVs gehören dir.
- Tools: [jsfxr / sfxr.me](https://github.com/chr15m/jsfxr), [Freesound Lizenz-Forum](https://freesound.org/forum/legal-help-and-attribution-questions/35069/), [Kenney CC0 Audio Guide](https://gtstu.com/free-sound-effects-indie-game/), [GodotSfxr Addon](https://godotengine.org/asset-library/asset/edit/5065)

---

## 4. Browser-Distribution (Godot 4 Web Export)

- **Threads:** Seit Godot 4.3 gibt es im Web-Preset **Thread Support** aus = Single-threaded, kein SharedArrayBuffer, keine COOP/COEP-Header nötig → läuft auf **plain GitHub Pages**. Mit Threads an braucht es `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp`; GitHub Pages kann keine Header setzen → Workaround `coi-serviceworker` (nicht jeder Browser respektiert ihn). Empfehlung: Threads aus, für ein 2D-Spiel reicht das.
- **itch.io:** Embed-Option „SharedArrayBuffer support“ anhaken, dann laufen auch Threaded-Builds. Eigener Server: Header selbst setzen.
- **Build-Größe:** Engine-wasm ~37–40 MB roh, ~10 MB gzip, ~5 MB Brotli; .pck für ein Pixel-Spiel 1–3 MB. „Export with debug“ aus halbiert fast. Custom-stripped Template kommt auf ~17 MB roh / 4 MB gzip, kostet aber eigenen Engine-Build – erst bei Bedarf.
- **Mobile/Touch:** Browser übersetzen Touch in Mouse-Events, auch wenn `emulate_mouse_from_touch` aus ist; Gesten (Pan/Pinch) werden in Mobile-Browsern nicht erkannt. Twin-Stick mit WASD+Maus funktioniert auf Touch nicht ohne eigene virtuelle Sticks (TouchScreenButton / eigener Joystick). iOS/Safari war bis 4.2 kaputt (SAB + WebGL2); mit 4.3+ single-threaded auf echtem iPhone testen, nicht annehmen. Firefox markiert itch-Downloads gelegentlich als Virus; itch-App zeigt teils leere Seite.
- Links: [Godot Docs Exporting for Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [Godot 4.3 Web Progress Report](https://godotengine.org/article/progress-report-web-export-in-4-3/), [Forum: 4.3 ohne SharedArrayBuffer](https://forum.godotengine.org/t/godot-4-3-will-finally-fix-web-builds-no-sharedarraybuffers-required/38885), [GitHub Pages Docs-Issue](https://github.com/godotengine/godot-docs/issues/7084), [OB Studio Build-Size](https://obstudio.org/blog/godot-web-export-size/), [foosel itch.io Howto](https://foosel.net/til/2023-05-14-how-to-export-a-godot-4-game-to-run-on-the-web-on-itchio/), [Forum Touch-Events Web](https://forum.godotengine.org/t/why-are-mouse-motion-events-occurring-when-i-have-emulate-mouse-from-touch-disabled/133327)
