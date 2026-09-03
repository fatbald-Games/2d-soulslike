# Ashen Hollow

Ein 2D-Soulslike in düsterer Retro-Pixelgrafik. **Engine: Godot 4.x.**

Stand: **spielbarer Kampf-Slice.** Laufen, springen, Angriff mit Schwert,
Ausweichrolle mit i-Frames, Ausdauer-Haushalt, ein Gegner mit telegrafiertem
Angriff, Seelen als Währung und ein „YOU DIED"-Respawn.

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

`tools/smoke_test.gd` startet dabei die echte `Main.tscn`, drückt Frame für Frame
die Tasten und prüft **40 Zusicherungen**: Landen und Laufen, der Ausdauer-Haushalt
(inklusive: ein Angriff ohne Ausdauer startet gar nicht), die Trefferabfrage des
Schwerts, die i-Frames der Rolle samt verwundbarer Erholung, der komplette
Telegraf-Zyklus des Hollows bis zum Schaden, Seelen-Belohnung, Tod — und der
Respawn nach dem Szenen-Reload. Exit-Code 0 heißt: alles grün.

## Projektstruktur

```
ashen-hollow/
├─ project.godot          Pixel-Perfect-Konfig (nearest filter, viewport 384×216)
├─ scenes/Main.tscn       Startszene (ein Node2D mit Main.gd)
├─ scripts/
│   ├─ Main.gd            Baut Level, Kollision, Licht, HUD und Akteure per Code
│   ├─ Player.gd          Zustandsautomat, Ausdauer, i-Frames, Angriff
│   ├─ Hollow.gd          Gegner-KI: verfolgen → ausholen → zustechen → erholen
│   ├─ HUD.gd             Lebens-/Ausdauerleiste, Seelen, „YOU DIED"
│   └─ SpriteUtil.gd      Zerschneidet die Sprite-Sheets in Animationen
├─ assets/sprites/
│   ├─ hero_idle.png      44×32, 4 Frames    ┐
│   ├─ hero_run.png       44×32, 6 Frames    │ alle mit gleichem Anker auf den
│   ├─ hero_attack.png    44×32, 4 Frames    │ Füßen (Frame-Pixel 22,31) →
│   ├─ hero_roll.png      44×32, 4 Frames    │ Godot-Offset (-22,-31)
│   ├─ hollow.png         44×32, 6 Frames    ┘ [idle,idle,windup,strike,hurt,dead]
│   ├─ tile_floor/wall.png, bonfire.png, torch.png, light_soft.png
└─ tools/
    ├─ gen_art.py         >>> Der Pixelart-Generator (Quelle aller Sprites) <<<
    ├─ smoke_test.gd      Headless-Durchlauf des Kampf-Slice (40 Checks)
    ├─ run_tests.sh       Startet Import + Test in einem Rutsch
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

## Nächste Schritte

1. **Lagerfeuer-Loop**: rasten = heilen + alle Gegner respawnen (der Kern der Struktur).
2. **Seelen fallen lassen**: beim Tod bleiben die Seelen liegen und lassen sich zurückholen.
3. **Mehr Gegnertypen** und ein erster Boss mit mehreren Angriffsmustern.
4. **Level-Design**: echte Tilemap mit Plattformen, Abkürzungen und Verzweigungen.
5. **Sound**: Schwerthiebe, Treffer, Feuerknistern.
