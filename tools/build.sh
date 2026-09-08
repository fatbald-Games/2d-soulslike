#!/usr/bin/env bash
# Release build for Ashen Hollow.
#
#   tools/build.sh                       # all presets
#   tools/build.sh Linux                 # just one
#   GODOT=/path/to/godot tools/build.sh
#
# Regenerates every asset from its generator, runs the full test suite, and only
# then exports. That order is the point: the art, the audio and the level are
# outputs of scripts in this repository, so a build should never ship a PNG that
# no longer matches the code that draws it.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

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
	echo "Godot not found. Install Godot 4.3+ or set GODOT=..." >&2
	exit 127
fi

echo "=== Regenerating assets ==="
python3 tools/gen_art.py   > /dev/null || { echo "gen_art.py failed" >&2; exit 1; }
python3 tools/gen_audio.py > /dev/null || { echo "gen_audio.py failed" >&2; exit 1; }
python3 tools/gen_level.py            || { echo "gen_level.py failed" >&2; exit 1; }

echo
echo "=== Tests ==="
GODOT="$GODOT_BIN" tools/run_tests.sh || { echo "tests failed - not building" >&2; exit 1; }

echo
echo "=== Export ==="
# Godot will not create the output folder itself and fails with a bare
# "target folder does not exist" if it is missing.
mkdir -p build/windows build/linux build/macos

presets=("Windows Desktop" "Linux" "macOS")
if [[ $# -gt 0 ]]; then
	presets=("$@")
fi

status=0
for preset in "${presets[@]}"; do
	echo
	echo "--- $preset ---"
	out="$("$GODOT_BIN" --headless --path . --export-release "$preset" 2>&1)"
	rc=$?
	echo "$out" | grep -v '^Godot Engine'
	if [[ $rc -ne 0 ]] || echo "$out" | grep -qi "export template"; then
		echo "-> $preset failed. Export templates for this Godot version must be" >&2
		echo "   installed: in the editor, Editor -> Manage Export Templates," >&2
		echo "   or drop them in ~/.local/share/godot/export_templates/." >&2
		status=1
	fi
done

echo
if [[ $status -eq 0 ]]; then
	echo "Built into build/ - ready to upload."
else
	echo "BUILD FAILED" >&2
fi
exit $status
