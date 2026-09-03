#!/usr/bin/env bash
# Headless-Testlauf für Ashen Hollow.
#
#   tools/run_tests.sh
#   GODOT=/pfad/zu/godot tools/run_tests.sh
#
# Importiert die Assets und spielt danach Kampf-Slice und Menüs ohne Fenster
# durch. Exit-Code 0 = alles bestanden, sonst 1 (damit als CI-Gate nutzbar).
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Godot finden: $GODOT, sonst godot / godot4 aus dem PATH.
GODOT_BIN="${GODOT:-}"
if [[ -z "$GODOT_BIN" ]]; then
	for candidate in godot godot4 Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			GODOT_BIN="$candidate"
			break
		fi
	done
fi

if [[ -z "$GODOT_BIN" ]] || ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "Godot nicht gefunden. Godot 4.3+ installieren oder GODOT=... setzen." >&2
	exit 127
fi

echo "Godot: $("$GODOT_BIN" --version)"

status=0

# Das Level zuerst: gen_level.py beweist, dass jeder Gegner, jedes Lagerfeuer
# und jede Inschrift mit der echten Sprungphysik erreichbar ist. Ein Vorsprung,
# auf den niemand kommt, soll hier auffallen und nicht erst im Spiel.
if command -v python3 >/dev/null 2>&1; then
	echo
	echo "=== Level-Layout ==="
	if python3 "$PROJECT_DIR/tools/gen_level.py"; then
		if ! git -C "$PROJECT_DIR" diff --quiet -- scripts/LevelMap.gd 2>/dev/null; then
			echo "-> LevelMap.gd war nicht aktuell und wurde neu erzeugt" >&2
		fi
	else
		echo "-> Level-Layout: Erreichbarkeitsprüfung fehlgeschlagen" >&2
		status=1
	fi
else
	echo "python3 fehlt - Level-Prüfung übersprungen." >&2
fi

# Erster Lauf legt die .import-Dateien an; ohne sie findet der Test keine Texturen.
"$GODOT_BIN" --headless --import --path "$PROJECT_DIR" >/dev/null 2>&1

# Ein Testskript laufen lassen. Godot liefert bei einem Laufzeitfehler im Skript
# trotzdem Exit-Code 0, deshalb gilt jede SCRIPT-ERROR-Zeile ebenfalls als
# Fehlschlag — genau so sind sonst Parse-Fehler in den Menüs durchgerutscht.
run_suite() {
	local name="$1" script="$2" out
	echo
	echo "=== $name ==="
	out="$("$GODOT_BIN" --headless --path "$PROJECT_DIR" --script "$script" 2>&1)"
	local rc=$?
	echo "$out" | grep -v '^Godot Engine'
	if [[ $rc -ne 0 ]]; then
		echo "-> $name: Checks fehlgeschlagen (Exit $rc)" >&2
		status=1
	fi
	if echo "$out" | grep -qE 'SCRIPT ERROR|^ERROR:'; then
		echo "-> $name: Engine-Fehler im Log (siehe SCRIPT ERROR oben)" >&2
		status=1
	fi
}

run_suite "Kampf-Slice" "res://tools/smoke_test.gd"
run_suite "Menüs" "res://tools/menu_test.gd"

echo
if [[ $status -eq 0 ]]; then
	echo "ALLES GRÜN"
else
	echo "FEHLGESCHLAGEN" >&2
fi
exit $status
