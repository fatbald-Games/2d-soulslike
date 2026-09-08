#!/usr/bin/env bash
# Tests the installer against a fake GitHub, end to end.
#
#   installer/test_install.sh
#
# Serves a mock releases API and two mock release zips over localhost, then runs
# a real install, a real update to a newer tag, a downgrade-free no-op, a
# checksum failure and an uninstall — asserting on the filesystem after each.
#
# Testing an installer any other way means publishing a release to find out it
# is broken, which is exactly the wrong order.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d)"
# A fresh port per run, so a server left behind by a killed run cannot answer
# for this one.
PORT="${AH_TEST_PORT:-$((8730 + RANDOM % 900))}"
REPO="ashen/test"
FAILS=0
CHECKS=0

# localhost must not go through an outbound proxy
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="$NO_PROXY"
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true

cleanup() {
	if [[ -n "${SERVER_PID:-}" ]]; then
		kill "$SERVER_PID" 2>/dev/null
		wait "$SERVER_PID" 2>/dev/null
	fi
	rm -rf "$ROOT"
}
trap cleanup EXIT

ok() {   # ok <label> <condition-as-exit-code>
	CHECKS=$((CHECKS + 1))
	if [[ "$2" == "0" ]]; then
		printf '  ok    %s\n' "$1"
	else
		printf '  FAIL  %s\n' "$1"
		FAILS=$((FAILS + 1))
	fi
}

eq() {   # eq <label> <got> <want>
	CHECKS=$((CHECKS + 1))
	if [[ "$2" == "$3" ]]; then
		printf '  ok    %s\n' "$1"
	else
		printf '  FAIL  %s  (got "%s", want "%s")\n' "$1" "$2" "$3"
		FAILS=$((FAILS + 1))
	fi
}

# --- build two fake releases -------------------------------------------------
mkdir -p "$ROOT/serve/dl" "$ROOT/stage"
make_release() {   # make_release <tag> <marker>
	local tag="$1" marker="$2"
	rm -rf "$ROOT/stage"; mkdir -p "$ROOT/stage"
	printf '#!/bin/sh\necho %s\n' "$marker" > "$ROOT/stage/AshenHollow.x86_64"
	chmod +x "$ROOT/stage/AshenHollow.x86_64"
	printf 'pck for %s\n' "$tag" > "$ROOT/stage/AshenHollow.pck"
	printf 'icon\n' > "$ROOT/stage/icon.png"
	( cd "$ROOT/stage" && zip -qr "$ROOT/serve/dl/AshenHollow-$tag-linux-x86_64.zip" . )
	# a Windows package too, so install.ps1 can be driven through the same mock
	rm -f "$ROOT/stage/AshenHollow.x86_64"
	printf '%s\n' "$marker" > "$ROOT/stage/AshenHollow.exe"
	( cd "$ROOT/stage" && zip -qr "$ROOT/serve/dl/AshenHollow-$tag-windows-x86_64.zip" . )
	( cd "$ROOT/serve/dl" && sha256sum \
		"AshenHollow-$tag-linux-x86_64.zip" \
		"AshenHollow-$tag-windows-x86_64.zip" > "$ROOT/serve/dl/SHA256SUMS-$tag" )
}

write_api() {      # write_api <tag> [bad-checksum]
	local tag="$1" bad="${2:-}"
	local base="http://127.0.0.1:$PORT/dl"
	local sums="$ROOT/serve/dl/SHA256SUMS-$tag"
	cp "$sums" "$ROOT/serve/dl/SHA256SUMS"
	if [[ "$bad" == "missing" ]]; then
		printf '%s  %s\n' "$(printf 'deadbeef%.0s' 1 2 3 4 5 6 7 8)" \
			"SomethingElse.zip" > "$ROOT/serve/dl/SHA256SUMS"
	elif [[ "$bad" == "bad" ]]; then
		: > "$ROOT/serve/dl/SHA256SUMS"
		for plat in linux-x86_64 windows-x86_64; do
			printf '%s  %s\n' "$(printf 'deadbeef%.0s' 1 2 3 4 5 6 7 8)" \
				"AshenHollow-$tag-$plat.zip" >> "$ROOT/serve/dl/SHA256SUMS"
		done
	fi
	mkdir -p "$ROOT/serve/repos/$REPO/releases"
	cat > "$ROOT/serve/repos/$REPO/releases/latest" <<JSON
{
  "tag_name": "$tag",
  "name": "Ashen Hollow $tag",
  "assets": [
    {"name": "AshenHollow-$tag-linux-x86_64.zip",
     "browser_download_url": "$base/AshenHollow-$tag-linux-x86_64.zip"},
    {"name": "AshenHollow-$tag-windows-x86_64.zip",
     "browser_download_url": "$base/AshenHollow-$tag-windows-x86_64.zip"},
    {"name": "AshenHollow-$tag-macos-universal.zip",
     "browser_download_url": "$base/AshenHollow-$tag-macos-universal.zip"},
    {"name": "SHA256SUMS",
     "browser_download_url": "$base/SHA256SUMS"}
  ]
}
JSON
}

make_release "v0.0.1" "ONE"
make_release "v0.0.2" "TWO"
write_api "v0.0.1"

# The mock API serves a directory tree, so /repos/<owner>/<repo>/releases/latest
# is simply a file at that path.
#
# Started WITHOUT a subshell: wrapping it in ( ... ) & makes $! the subshell's
# pid, so the cleanup trap killed the wrapper and left the server running on the
# port — which then answered the next test run from a deleted directory.
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/serve" \
	>/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 40); do
	curl -fsS "http://127.0.0.1:$PORT/repos/$REPO/releases/latest" >/dev/null 2>&1 && break
	sleep 0.2
done

export AH_REPO="$REPO"
export AH_API="http://127.0.0.1:$PORT"
export AH_PREFIX="$ROOT/home/game"
export AH_BIN_DIR="$ROOT/home/bin"
export AH_DESKTOP_DIR="$ROOT/home/applications"
export AH_DRY_RUN=1

echo "— installer test —"

# --- 1. a clean install ------------------------------------------------------
out="$("$HERE/install.sh" 2>&1)"; rc=$?
ok "a clean install succeeds" "$rc"
ok "it says what version it installed" \
	"$(printf '%s' "$out" | grep -q 'v0.0.1 installed' && echo 0 || echo 1)"
ok "it verifies the checksum" \
	"$(printf '%s' "$out" | grep -q 'Checksum verified' && echo 0 || echo 1)"
ok "the game binary is there" "$([[ -x "$AH_PREFIX/AshenHollow.x86_64" ]] && echo 0 || echo 1)"
ok "the data pack is there" "$([[ -f "$AH_PREFIX/AshenHollow.pck" ]] && echo 0 || echo 1)"
eq "the installed version is recorded" "$(cat "$AH_PREFIX/version.txt" 2>/dev/null)" "v0.0.1"
ok "a launcher was created" "$([[ -x "$AH_BIN_DIR/ashen-hollow" ]] && echo 0 || echo 1)"
ok "a menu entry was created" \
	"$([[ -f "$AH_DESKTOP_DIR/ashen-hollow.desktop" ]] && echo 0 || echo 1)"
ok "the installer copies itself in, so the launcher can update" \
	"$([[ -x "$AH_PREFIX/install.sh" ]] && echo 0 || echo 1)"
eq "the installed build is the one served" \
	"$("$AH_PREFIX/AshenHollow.x86_64")" "ONE"

# --- 2. running it again changes nothing -------------------------------------
out="$("$HERE/install.sh" 2>&1)"; rc=$?
ok "re-running on an up-to-date install succeeds" "$rc"
ok "and says so rather than downloading again" \
	"$(printf '%s' "$out" | grep -q 'already up to date' && echo 0 || echo 1)"

# --- 3. --check reports an update --------------------------------------------
write_api "v0.0.2"
out="$("$HERE/install.sh" --check 2>&1)"; rc=$?
eq "--check exits 10 when an update is waiting" "$rc" "10"
ok "--check names both versions" \
	"$(printf '%s' "$out" | grep -q 'installed: v0.0.1' \
		&& printf '%s' "$out" | grep -q 'latest:    v0.0.2' && echo 0 || echo 1)"
eq "--check installs nothing by itself" "$(cat "$AH_PREFIX/version.txt")" "v0.0.1"

# --- 4. the update ------------------------------------------------------------
out="$("$HERE/install.sh" 2>&1)"; rc=$?
ok "the update succeeds" "$rc"
eq "the version moves on" "$(cat "$AH_PREFIX/version.txt")" "v0.0.2"
eq "the new build replaced the old one" "$("$AH_PREFIX/AshenHollow.x86_64")" "TWO"
ok "no half-installed leftovers" \
	"$([[ ! -e "$AH_PREFIX.new" && ! -e "$AH_PREFIX.old" ]] && echo 0 || echo 1)"

# --- 5. --launch updates, then plays -----------------------------------------
write_api "v0.0.1"          # pretend the newest release was pulled
out="$("$HERE/install.sh" --launch 2>&1)"; rc=$?
ok "--launch runs the game" "$rc"
ok "and it is the game it launches" \
	"$(printf '%s' "$out" | grep -q 'would launch:.*AshenHollow' && echo 0 || echo 1)"

# --- 6. an unreachable GitHub must not stop the game --------------------------
out="$(AH_API=http://127.0.0.1:1 "$HERE/install.sh" --launch 2>&1)"; rc=$?
ok "--launch still plays when GitHub is unreachable" "$rc"
ok "and says why it could not check" \
	"$(printf '%s' "$out" | grep -q 'Continuing with the installed version' && echo 0 || echo 1)"

# --- 7. a bad checksum must stop the install ---------------------------------
before="$(cat "$AH_PREFIX/version.txt")"
write_api "v0.0.2" "bad"
out="$("$HERE/install.sh" 2>&1)"; rc=$?
ok "a corrupted download fails loudly" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
ok "and says it was the checksum" \
	"$(printf '%s' "$out" | grep -q 'Checksum mismatch' && echo 0 || echo 1)"
eq "and leaves the working install alone" "$(cat "$AH_PREFIX/version.txt")" "$before"

# --- 7b. a checksum file that does not mention our asset ---------------------
before="$(cat "$AH_PREFIX/version.txt")"
write_api "v0.0.2" "missing"
out="$("$HERE/install.sh" --force 2>&1)"; rc=$?
ok "an asset missing from SHA256SUMS is refused" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
ok "and says it was not listed" \
	"$(printf '%s' "$out" | grep -q 'not listed in SHA256SUMS' && echo 0 || echo 1)"
eq "and leaves the working install alone" "$(cat "$AH_PREFIX/version.txt")" "$before"

# --- 8. uninstall -------------------------------------------------------------
out="$("$HERE/install.sh" --uninstall 2>&1)"; rc=$?
ok "uninstall succeeds" "$rc"
ok "the install is gone" "$([[ ! -e "$AH_PREFIX" ]] && echo 0 || echo 1)"
ok "the launcher is gone" "$([[ ! -e "$AH_BIN_DIR/ashen-hollow" ]] && echo 0 || echo 1)"
ok "the menu entry is gone" \
	"$([[ ! -e "$AH_DESKTOP_DIR/ashen-hollow.desktop" ]] && echo 0 || echo 1)"
ok "it says where the saves were kept" \
	"$(printf '%s' "$out" | grep -q 'app_userdata' && echo 0 || echo 1)"

# --- 9. the Windows installer, driven through the same mock ------------------
# PowerShell runs on Linux, and everything install.ps1 does except making
# shortcuts is cross-platform - so the Windows path can be tested here rather
# than only on a Windows machine.
PWSH="${AH_PWSH:-$(command -v pwsh || true)}"
if [[ -n "$PWSH" ]]; then
	echo
	echo "— install.ps1 (PowerShell $("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')) —"
	export AH_PREFIX="$ROOT/win/game"
	write_api "v0.0.1"

	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" 2>&1)"; rc=$?
	ok "ps1: a clean install succeeds" "$rc"
	ok "ps1: it verifies the checksum" \
		"$(printf '%s' "$out" | grep -q 'Checksum verified' && echo 0 || echo 1)"
	ok "ps1: the game is there" "$([[ -f "$AH_PREFIX/AshenHollow.exe" ]] && echo 0 || echo 1)"
	eq "ps1: the installed version is recorded" \
		"$(cat "$AH_PREFIX/version.txt" 2>/dev/null)" "v0.0.1"
	ok "ps1: it copies itself in, so the shortcut can update" \
		"$([[ -f "$AH_PREFIX/install.ps1" ]] && echo 0 || echo 1)"
	eq "ps1: the installed build is the one served" \
		"$(cat "$AH_PREFIX/AshenHollow.exe")" "ONE"

	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" 2>&1)"; rc=$?
	ok "ps1: re-running changes nothing" \
		"$([[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q 'already up to date' && echo 0 || echo 1)"

	write_api "v0.0.2"
	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" -Check 2>&1)"; rc=$?
	eq "ps1: -Check exits 10 when an update is waiting" "$rc" "10"
	eq "ps1: -Check installs nothing" "$(cat "$AH_PREFIX/version.txt")" "v0.0.1"

	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" 2>&1)"; rc=$?
	ok "ps1: the update succeeds" "$rc"
	eq "ps1: the version moves on" "$(cat "$AH_PREFIX/version.txt")" "v0.0.2"
	eq "ps1: the new build replaced the old one" \
		"$(cat "$AH_PREFIX/AshenHollow.exe")" "TWO"
	ok "ps1: no half-installed leftovers" \
		"$([[ ! -e "$AH_PREFIX.new" && ! -e "$AH_PREFIX.old" ]] && echo 0 || echo 1)"

	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" -Launch 2>&1)"; rc=$?
	ok "ps1: -Launch runs the game" "$rc"
	ok "ps1: and it is the game it launches" \
		"$(printf '%s' "$out" | grep -q 'would launch:.*AshenHollow' && echo 0 || echo 1)"

	out="$(AH_API=http://127.0.0.1:1 "$PWSH" -NoProfile -File "$HERE/install.ps1" -Launch 2>&1)"; rc=$?
	ok "ps1: -Launch still plays when GitHub is unreachable" "$rc"

	before="$(cat "$AH_PREFIX/version.txt")"
	write_api "v0.0.2" "bad"
	# force it past the up-to-date check so the download is actually verified
	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" -Force 2>&1)"; rc=$?
	ok "ps1: a corrupted download fails loudly" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
	ok "ps1: and says it was the checksum" \
		"$(printf '%s' "$out" | grep -q 'Checksum mismatch' && echo 0 || echo 1)"
	eq "ps1: and leaves the working install alone" \
		"$(cat "$AH_PREFIX/version.txt")" "$before"

	out="$("$PWSH" -NoProfile -File "$HERE/install.ps1" -Uninstall 2>&1)"; rc=$?
	ok "ps1: uninstall succeeds" "$rc"
	ok "ps1: the install is gone" "$([[ ! -e "$AH_PREFIX" ]] && echo 0 || echo 1)"
else
	echo
	echo "  skip  install.ps1 (no pwsh on PATH; set AH_PWSH to test it)"
fi

echo
if [[ $FAILS -eq 0 ]]; then
	echo "PASS — $CHECKS checks"
	exit 0
fi
echo "FAIL — $FAILS of $CHECKS checks failed" >&2
exit 1
