#!/usr/bin/env bash
# Headless test run for Ashen Hollow.
#
#   tools/run_tests.sh
#   GODOT=/path/to/godot tools/run_tests.sh
#
# Imports the assets, then plays the combat slice and the menus through without
# a window. Exit code 0 means everything passed, anything else means it did not,
# so this works as a CI gate.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Find Godot: $GODOT, else godot / godot4 from PATH.
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

echo "Godot: $("$GODOT_BIN" --version)"

status=0

# The level first: gen_level.py proves that every enemy, every bonfire, every
# inscription and every weapon can actually be reached with the real jump
# physics. A ledge nobody can get to should fail here, not in someone's run.
if command -v python3 >/dev/null 2>&1; then
	echo
	echo "=== Level layout ==="
	if python3 "$PROJECT_DIR/tools/gen_level.py"; then
		if ! git -C "$PROJECT_DIR" diff --quiet -- scripts/LevelMap.gd 2>/dev/null; then
			echo "-> LevelMap.gd was out of date and has been regenerated" >&2
		fi
	else
		echo "-> Level layout: the reachability check failed" >&2
		status=1
	fi
else
	echo "python3 missing - level check skipped." >&2
fi

# The first pass writes the .import files; without them the tests find no
# textures.
"$GODOT_BIN" --headless --import --path "$PROJECT_DIR" >/dev/null 2>&1
# ...then one throwaway boot, whose only job is to rebuild the script class
# cache that --import invalidates. Without it the next launch reports the test
# script as "File not found", loads it on a retry, and passes anyway — leaving
# three engine errors in the log that fail the run for no reason at all.
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --quit >/dev/null 2>&1

# Run one test script. Godot still exits 0 when a script hits a runtime error,
# so any SCRIPT ERROR line counts as a failure too - that is how parse errors in
# the menus slipped through while both suites reported PASS.
run_suite() {
	local name="$1" script="$2" out
	echo
	echo "=== $name ==="
	out="$("$GODOT_BIN" --headless --path "$PROJECT_DIR" --script "$script" 2>&1)"
	local rc=$?
	echo "$out" | grep -v '^Godot Engine'
	if [[ $rc -ne 0 ]]; then
		echo "-> $name: checks failed (exit $rc)" >&2
		status=1
	fi
	# The suite has to have actually started. A script that fails to load makes
	# Godot exit 0 with no output at all, which would otherwise sail through.
	if ! echo "$out" | grep -q 'Ashen Hollow'; then
		echo "-> $name: the suite never started (no banner in the output)" >&2
		status=1
		return
	fi
	# Only errors from the suite ITSELF count. Everything before its banner is
	# engine start-up noise on a cold cache: regenerating LevelMap.gd and
	# reimporting the assets invalidates the script class cache, and the first
	# launch after that reports the test script as missing, retries, and runs
	# fine. That is the toolchain warming up, not the game being broken.
	if echo "$out" | sed -n '/Ashen Hollow/,$p' | grep -qE 'SCRIPT ERROR|^ERROR:'; then
		echo "-> $name: engine errors in the log (see SCRIPT ERROR above)" >&2
		status=1
	fi
}

run_suite "Combat slice" "res://tools/smoke_test.gd"
run_suite "Menus" "res://tools/menu_test.gd"

echo
if [[ $status -eq 0 ]]; then
	echo "ALL GREEN"
else
	echo "FAILED" >&2
fi
exit $status
