# Ashen Hollow

Ein 2D-Soulslike in düsterer Retro-Pixelgrafik. **Engine: Godot 4.x.**

Stand: **spielbarer Kampf-Slice mit Menüs.** Titelbildschirm, Pause-Menü und ein
Knochen-HUD; dazu Laufen, springen, Angriff mit Schwert, Ausweichrolle mit
i-Frames, Ausdauer-Haushalt, ein Gegner mit telegrafiertem Angriff, Seelen als
Währung und ein „YOU DIED"-Respawn.

![Titelbildschirm](tools/shots/01_title.png)

## Öffnen & Starten

1. Godot 4.3 (oder neuer) installieren: <https://godotengine.org/download>
2. Godot öffnen → **Import** → diese `project.godot` auswählen.
3. Beim ersten Öffnen importiert Godot die PNGs automatisch. Dann **F5** (Play).

## Steuerung

| Taste | Aktion |
|---|---|
| `A` / `D` (oder ←/→) | Laufen |
| `Leertaste` / `W` | Springen |
| `J` oder linke Maustaste | Angriff |
| `K` oder `Shift` | **Ausweichrolle** |
| `Esc` | Pause-Menü |
| `↑ ↓` / `W` `S`, `Enter` | in Menüs: wählen, bestätigen |

## Menüs & HUD

Alles im Bild ist **Knochen und Eisen** — und alles ist, wie die Sprites,
code-generiert (siehe Pipeline unten):

- **Titelbildschirm**: eine Gruft mit zwei zuckenden Fackeln, aufsteigenden
  Funken und einem Schädel, der aus dem Knochenhaufen ragt. Auswahl per
  Schädel-Cursor, dessen Augenhöhlen pulsieren.
- **Pixel-Font statt Systemschrift**: eine eigene 5×7-Bitmap-Schrift
  (`assets/ui/font_5x7.png`). Godots Standardschrift ist vektorbasiert und
  kantengeglättet — neben handgesetzter Pixelart sieht das sofort falsch aus.
  Das Sheet ist rein weiß, deshalb reicht **eine** Textur für alle Farben
  (Elfenbein, Glut-Rot, Ausdauer-Grün).
- **HUD**: Lebens- und Ausdauerleiste liegen in geschnitzten Knochen-Trögen mit
  Knubbel-Enden. Darunter zählt ein Schädel die Seelen.
- **Schaden-Geist**: nach einem Treffer bleibt ein dunkelroter Streifen kurz
  stehen und läuft dann nach — man *sieht*, was der Fehler gekostet hat.
- **Pause-Menü** (`Esc`) friert den Kerker ein und blendet ihn ab; das Menü
  selbst läuft in `PROCESS_MODE_ALWAYS` weiter, sonst könnte es sich nie wieder
  schließen.

## Das Kampfsystem

Die souls-typische Logik: **jede Aktion kostet Ausdauer und ist verbindlich** —
Angriffe und Rollen lassen sich nicht abbrechen. Wer blind draufhaut, steht ohne
Ausdauer da, wenn der Hollow zuschlägt.

- **Ausdauer** (100): Angriff kostet 28, Rolle 22. Regeneration 38/s, startet
  0,45 s nach der letzten Aktion. Ohne genug Ausdauer geht die Aktion gar nicht erst los.
- **Ausweichrolle**: dauert 0,42 s; **i-Frames von 0,07 s bis 0,30 s** — also
  etwa die mittleren 55 % sind unverwundbar. Der Held färbt sich in dieser Zeit
  leicht cyan, damit das Fenster lesbar ist.
- **Angriff**: 0,36 s, der Treffer landet bei 0,15 s (dem Schlagbild), Reichweite 30 px.
- **Der Hollow** holt **0,55 s lang sichtbar aus**, bevor er zusticht — lang genug,
  um die Rolle zu timen. Danach 0,55 s Erholung: das ist dein Fenster zum Kontern.
- **Treffer** geben 0,65 s Unverwundbarkeit + Rückstoß (Blinken).
- **Seelen**: 60 pro Hollow. (Noch fallen sie beim Tod nicht — das kommt mit dem
  Lagerfeuer-Loop.)

Trefferabfragen laufen bewusst über **explizite Rechteck-Tests** im Code
(`Player._swing()`, `Hollow._strike()`) statt über Physik-Layer — deterministisch,
leicht nachvollziehbar und ohne unsichtbare Konfiguration.

## Testen (ohne Fenster)

Der Kampf-Slice lässt sich komplett **headless** durchspielen — nützlich, um nach
einer Änderung zu prüfen, ob noch alles läuft, ohne Godot zu öffnen:

```bash
tools/run_tests.sh                      # Godot aus dem PATH
GODOT=/pfad/zu/godot tools/run_tests.sh # oder explizit
```

Der Runner spielt **zwei Suiten** durch, zusammen **74 Zusicherungen**:

- `tools/smoke_test.gd` (50) startet die echte `Main.tscn` und drückt Frame für
  Frame die Tasten: Landen und Laufen, der Ausdauer-Haushalt (inklusive: ein
  Angriff ohne Ausdauer startet gar nicht), die Trefferabfrage des Schwerts, die
  i-Frames der Rolle samt verwundbarer Erholung, der komplette Telegraf-Zyklus
  des Hollows bis zum Schaden, Seelen, das HUD, Tod und Respawn.
- `tools/menu_test.gd` (24) läuft den Weg eines Spielers ab: navigieren,
  CONTROLS öffnen, Spiel starten, pausieren, zurück zum Titel.

Zwei Fallstricke, die der Runner deshalb extra abfängt:

- **Godot liefert bei einem Laufzeitfehler im Skript trotzdem Exit-Code 0.**
  Der Runner wertet daher jede `SCRIPT ERROR`-Zeile als Fehlschlag — sonst
  rutschen Parse-Fehler durch, während die Suite fröhlich „PASS" meldet.
- **Headless zeichnet nichts.** Was man nur *sehen* kann, prüft der Test über
  Invarianten: dass die Leisten-Füllung z. B. *nach* ihrem Knochenrahmen in der
  Kind-Reihenfolge steht — der Rahmen ist im Kanal deckend und übermalt sie
  sonst vollständig.

## Screenshots

Für den echten Blick aufs Bild gibt es einen Screenshot-Lauf (braucht eine
Anzeige, in CI also Xvfb):

```bash
xvfb-run -a godot --path . --script res://tools/screenshot.gd
```

Legt `tools/shots/*.png` an: Titel, Steuerung, HUD im Spiel, Pause.

## Projektstruktur

```
ashen-hollow/
├─ project.godot          Pixel-Perfect-Konfig (nearest filter, viewport 384×216)
├─ scenes/
│   ├─ MainMenu.tscn      Startszene (Titelbildschirm)
│   └─ Main.tscn          Der Kampf-Slice
├─ scripts/
│   ├─ Main.gd            Baut Level, Kollision, Licht, HUD und Akteure per Code
│   ├─ MainMenu.gd        Titelbildschirm: Fackeln, Funken, Menü, Steuerung
│   ├─ PauseMenu.gd       Esc-Menü; läuft weiter, während der Baum pausiert
│   ├─ MenuList.gd        Menü-Einträge mit Schädel-Cursor (von beiden genutzt)
│   ├─ PixelLabel.gd      Zeichnet Text mit der Bitmap-Schrift
│   ├─ UiTheme.gd         Palette, Menü-Layout und Leisten-Geometrie an einem Ort
│   ├─ Player.gd          Zustandsautomat, Ausdauer, i-Frames, Angriff
│   ├─ Hollow.gd          Gegner-KI: verfolgen → ausholen → zustechen → erholen
│   ├─ HUD.gd             Knochen-Leisten, Schaden-Geist, Seelen, „YOU DIED"
│   └─ SpriteUtil.gd      Zerschneidet die Sprite-Sheets in Animationen
├─ assets/ui/
│   ├─ font_5x7.png       Bitmap-Schrift (47 Zeichen, weiß → im Spiel getönt)
│   ├─ skull.png          Schädel-Icon, 2 Frames [dunkel, glühende Augen]
│   ├─ bar_frame_hp/sp.png  Knochen-Tröge für Leben und Ausdauer
│   └─ menu_bg.png        Gruft-Hintergrund mit Knochenhaufen (384×216)
├─ assets/sprites/
│   ├─ hero_idle.png      44×32, 4 Frames    ┐
│   ├─ hero_run.png       44×32, 6 Frames    │ alle mit gleichem Anker auf den
│   ├─ hero_attack.png    44×32, 4 Frames    │ Füßen (Frame-Pixel 22,31) →
│   ├─ hero_roll.png      44×32, 4 Frames    │ Godot-Offset (-22,-31)
│   ├─ hollow.png         44×32, 6 Frames    ┘ [idle,idle,windup,strike,hurt,dead]
│   ├─ tile_floor/wall.png, bonfire.png, torch.png, light_soft.png
└─ tools/
    ├─ gen_art.py         >>> Der Pixelart-Generator (Quelle aller Sprites) <<<
    ├─ smoke_test.gd      Headless-Durchlauf des Kampf-Slice (50 Checks)
    ├─ menu_test.gd       Headless-Durchlauf der Menüs (24 Checks)
    ├─ run_tests.sh       Startet Import + beide Suiten in einem Rutsch
    ├─ screenshot.gd      Nimmt echte Bildschirmfotos auf (braucht Anzeige)
    ├─ shots/             Ebendiese Bildschirmfotos
    ├─ ui_preview.png     Menü-/HUD-Mockup direkt aus dem Generator
    ├─ combat.gif         Animations-Vorschau aller Kampf-Animationen
    ├─ combat_contact.png Kontaktbogen (Einzelbilder) zum Prüfen
    ├─ mood.gif / preview.png   Stimmungs-Vorschau
```

Der **gemeinsame 44×32-Rahmen ist symmetrisch um den Anker** — dadurch spiegelt
`flip_h` die Figur beim Richtungswechsel an Ort und Stelle, ohne dass der Körper
verrutscht.

## Pixelart-Pipeline

Alle Sprites werden **aus Code erzeugt** (Python + Pillow), damit die Kunst
reproduzierbar und versionierbar bleibt:

```bash
python tools/gen_art.py
```

Sprites sind als Text-Raster definiert (ein Zeichen = eine Palettenfarbe), die
Palette steht oben unter `PAL`, der Held unter `PLAYER`, der Gegner unter `HOLLOW`.
Lauf-Zyklus und Schwertschwung entstehen prozedural (Sinus-Schrittzyklus bzw.
rotierende Klinge um die Hand).

Die **Oberfläche** entsteht genauso: `GLYPHS` hält die Schrift, `SKULL` und
`BONE_LONG` die Knochen-Grafiken, `big_skull()` zeichnet den großen Schädel mit
echter Geometrie (ein hochskaliertes 11-px-Icon wird nur zu Matsch), und
`menu_backdrop()` setzt Mauerwerk, Schädel, Knochenhaufen und Vignette zusammen.

Das Menü-Layout (`TITLE_Y`, `MENU_Y0`, `SKULL_TOP`) steht in `gen_art.py` **und**
in `UiTheme.gd` — der Hintergrund backt den Schädel relativ zu diesen Werten,
die Engine setzt den Text daneben. Wer eins ändert, muss das andere mitziehen.

## Nächste Schritte

1. **Lagerfeuer-Loop**: rasten = heilen + alle Gegner respawnen (der Kern der Struktur).
2. **Seelen fallen lassen**: beim Tod bleiben die Seelen liegen und lassen sich zurückholen.
3. **Mehr Gegnertypen** und ein erster Boss mit mehreren Angriffsmustern.
4. **Level-Design**: echte Tilemap mit Plattformen, Abkürzungen und Verzweigungen.
5. **Sound**: Schwerthiebe, Treffer, Feuerknistern.
6. **Optionen-Menü**: Lautstärke und Fenstergröße — die Menü-Bausteine
   (`MenuList`, `PixelLabel`) stehen dafür schon bereit.
