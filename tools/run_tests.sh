#!/usr/bin/env bash
# Headless-Testlauf für Ashen Hollow.
#
#   tools/run_tests.sh
#   GODOT=/pfad/zu/godot tools/run_tests.sh
#
# Importiert die Assets und spielt danach den Kampf-Slice ohne Fenster durch.
# Exit-Code 0 = alle Checks bestanden, sonst 1 (damit als CI-Gate nutzbar).
set -euo pipefail

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

# Erster Lauf legt die .import-Dateien an; ohne sie findet der Test keine Texturen.
"$GODOT_BIN" --headless --import --path "$PROJECT_DIR" >/dev/null

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --script res://tools/smoke_test.gd
