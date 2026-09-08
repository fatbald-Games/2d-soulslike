#!/usr/bin/env bash
# Ashen Hollow installer and updater for Linux and macOS.
#
#   install.sh                install, or update an existing install
#   install.sh --launch       update if possible, then start the game
#   install.sh --check        say whether an update is available, change nothing
#   install.sh --uninstall    remove the game (save files are kept)
#   install.sh --force        reinstall even if already up to date
#
# It fetches the latest GitHub Release of the game, verifies the download
# against the release's checksum file, and swaps it into place atomically. No
# admin rights, no package manager, nothing outside your home directory.
#
# A copy of this script is installed alongside the game, and the launcher it
# creates runs it with --launch — which is what makes the game self-updating:
# every start checks for a new release, and a failed check never stops you
# playing the version you already have.
set -uo pipefail

REPO="${AH_REPO:-fettglatze/2d-soulslike}"
API="${AH_API:-https://api.github.com}"
RAW="${AH_RAW:-https://raw.githubusercontent.com/$REPO/main/installer}"
NAME="Ashen Hollow"
SLUG="ashen-hollow"

case "$(uname -s)" in
	Darwin) PLATFORM="macos";  ASSET_MATCH="macos" ;;
	Linux)  PLATFORM="linux";  ASSET_MATCH="linux" ;;
	*) echo "Unsupported system: $(uname -s). Windows users want install.ps1." >&2
	   exit 1 ;;
esac

if [[ "$PLATFORM" == "macos" ]]; then
	PREFIX="${AH_PREFIX:-$HOME/Applications/AshenHollow}"
else
	PREFIX="${AH_PREFIX:-$HOME/.local/share/$SLUG}"
fi
BIN_DIR="${AH_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${AH_DESKTOP_DIR:-$HOME/.local/share/applications}"
VERSION_FILE="$PREFIX/version.txt"

WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

installed_version() {
	[[ -f "$VERSION_FILE" ]] && cat "$VERSION_FILE" || echo ""
}

# --- talking to GitHub -------------------------------------------------------
# Parsed with grep and sed rather than jq: an installer that needs a JSON
# parser installed first is not an installer.
fetch_release() {
	local url="$API/repos/$REPO/releases/latest"
	curl -fsSL --retry 3 --retry-delay 2 -H "Accept: application/vnd.github+json" \
		${AH_TOKEN:+-H "Authorization: Bearer $AH_TOKEN"} "$url" 2>/dev/null
}

json_field() {   # json_field <body> <key>  -> first string value for that key
	printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
		| head -n 1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

asset_url() {    # asset_url <body> <substring>  -> browser_download_url
	printf '%s' "$1" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
		| sed 's/.*:[[:space:]]*"//; s/"$//' | grep -- "$2" | head -n 1
}

download() {     # download <url> <dest>
	curl -fL --retry 3 --retry-delay 2 --progress-bar \
		${AH_TOKEN:+-H "Authorization: Bearer $AH_TOKEN"} -o "$2" "$1"
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'   # macOS
	fi
}

# --- install -----------------------------------------------------------------
do_install() {
	local force="$1" quiet="$2"
	need curl
	need unzip

	local body
	body="$(fetch_release)" || body=""
	if [[ -z "$body" ]]; then
		warn "Could not reach GitHub ($API/repos/$REPO)."
		warn "If this repository is private, set AH_TOKEN to a personal access token."
		return 2
	fi
	if printf '%s' "$body" | grep -q '"status"[[:space:]]*:[[:space:]]*"404"'; then
		warn "No published release found for $REPO."
		warn "A release is created by pushing a version tag; see .github/workflows/release.yml."
		return 2
	fi

	local tag current
	tag="$(json_field "$body" "tag_name")"
	[[ -n "$tag" ]] || { warn "The release has no tag_name; nothing to install."; return 2; }
	current="$(installed_version)"

	if [[ "$tag" == "$current" && "$force" != "yes" ]]; then
		[[ "$quiet" == "yes" ]] || say "$NAME $tag is already up to date."
		return 0
	fi

	local url
	url="$(asset_url "$body" "$ASSET_MATCH")"
	[[ -n "$url" ]] || { warn "Release $tag has no $ASSET_MATCH build attached."; return 2; }

	local tmp
	tmp="$(mktemp -d)" || die "Could not create a temporary directory."
	WORK="$tmp"          # cleaned up by the EXIT trap, wherever we return from

	say "Downloading $NAME $tag..."
	download "$url" "$tmp/package.zip" || { warn "Download failed."; return 2; }

	# Checksums are optional so an older release without them still installs,
	# but when they are published a mismatch stops the install dead.
	local sums_url
	sums_url="$(asset_url "$body" "SHA256SUMS")"
	if [[ -n "$sums_url" ]]; then
		if download "$sums_url" "$tmp/SHA256SUMS" 2>/dev/null; then
			local want got file
			file="$(basename "$url")"
			want="$(grep -F " $file" "$tmp/SHA256SUMS" | awk '{print $1}' | head -n 1)"
			got="$(sha256_of "$tmp/package.zip")"
			if [[ -z "$want" ]]; then
				# The release publishes checksums but not for this file. That
				# is not "unverified", it is wrong — refuse rather than shrug.
				warn "Checksum mismatch: $file is not listed in SHA256SUMS."
				return 2
			fi
			if [[ "$want" != "$got" ]]; then
				warn "Checksum mismatch for $file."
				warn "  expected $want"
				warn "  got      $got"
				return 2
			fi
			say "Checksum verified."
		fi
	fi

	say "Installing to $PREFIX"
	mkdir -p "$tmp/unpacked"
	unzip -q "$tmp/package.zip" -d "$tmp/unpacked" || { warn "The archive is corrupt."; return 2; }

	# Swap atomically: the old install is only removed once the new one is in
	# place, so a failure here never leaves a half-installed game behind.
	mkdir -p "$(dirname "$PREFIX")"
	rm -rf "$PREFIX.new" "$PREFIX.old"
	mv "$tmp/unpacked" "$PREFIX.new"
	printf '%s\n' "$tag" > "$PREFIX.new/version.txt"
	ensure_updater "$PREFIX.new"
	[[ -d "$PREFIX" ]] && mv "$PREFIX" "$PREFIX.old"
	mv "$PREFIX.new" "$PREFIX"
	rm -rf "$PREFIX.old"

	chmod +x "$PREFIX"/AshenHollow* 2>/dev/null || true
	install_launcher
	say "$NAME $tag installed."
	[[ "$PLATFORM" == "linux" ]] && say "Run it with: $BIN_DIR/$SLUG"
	return 0
}

## A copy of this script has to end up next to the game, because that copy is
## what the launcher runs to self-update. Three ways it can get there, in order:
##
##   1. the release package ships it (the release workflow puts it in the zip)
##   2. we were run from a file and can simply copy ourselves
##   3. neither, so fetch it from the repository
##
## Step 3 is not hypothetical: `curl ... | bash` makes $0 the string "bash", and
## the copy that used to be attempted here failed silently — leaving a desktop
## shortcut pointing at a script that was never installed.
ensure_updater() {
	local dest="$1/install.sh"
	if [[ -f "$dest" ]]; then
		chmod +x "$dest" 2>/dev/null
		return 0
	fi
	if [[ -f "$0" ]] && cp "$0" "$dest" 2>/dev/null; then
		chmod +x "$dest" 2>/dev/null
		return 0
	fi
	if curl -fsSL --retry 2 -o "$dest" "$RAW/install.sh" 2>/dev/null \
			&& [[ -s "$dest" ]]; then
		chmod +x "$dest" 2>/dev/null
		return 0
	fi
	rm -f "$dest"
	warn "Could not install the updater alongside the game."
	warn "The game will play, but you will have to re-run this script to update."
	return 1
}


# --- launcher and menu entry -------------------------------------------------
game_binary() {
	if [[ "$PLATFORM" == "macos" ]]; then
		local app
		app="$(find "$PREFIX" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
		[[ -n "$app" ]] && printf '%s' "$app" && return 0
	fi
	find "$PREFIX" -maxdepth 1 -type f -name 'AshenHollow*' ! -name '*.pck' \
		! -name '*.txt' ! -name '*.sh' -print -quit 2>/dev/null
}

install_launcher() {
	mkdir -p "$BIN_DIR"
	# Falls back to playing directly when no updater is installed, so a failed
	# self-update install can never turn into a shortcut that does nothing.
	cat > "$BIN_DIR/$SLUG" <<LAUNCHER
#!/usr/bin/env sh
# Generated by the $NAME installer. Checks for a new release, then plays.
if [ -x "$PREFIX/install.sh" ]; then
	exec "$PREFIX/install.sh" --launch "\$@"
fi
exe=\$(find "$PREFIX" -maxdepth 1 -type f -name 'AshenHollow*' ! -name '*.pck' \\
	! -name '*.txt' ! -name '*.sh' -print -quit 2>/dev/null)
if [ -n "\$exe" ]; then
	exec "\$exe" "\$@"
fi
echo "$NAME is not installed in $PREFIX" >&2
exit 1
LAUNCHER
	chmod +x "$BIN_DIR/$SLUG"

	[[ "$PLATFORM" == "linux" ]] || return 0
	mkdir -p "$DESKTOP_DIR"
	cat > "$DESKTOP_DIR/$SLUG.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$NAME
Comment=A 2D souls-like in dark retro pixel art
Exec=$BIN_DIR/$SLUG
Icon=$PREFIX/icon.png
Categories=Game;ActionGame;
Terminal=false
DESKTOP
	command -v update-desktop-database >/dev/null 2>&1 \
		&& update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1
	return 0
}

do_launch() {
	# The update is best-effort on purpose: GitHub being unreachable, or a
	# release being broken, must never stand between a player and the copy of
	# the game they already have.
	do_install "no" "yes" || warn "Continuing with the installed version."
	local exe
	exe="$(game_binary)"
	[[ -n "$exe" ]] || die "No game found in $PREFIX. Run install.sh first."
	if [[ "${AH_DRY_RUN:-}" == "1" ]]; then
		say "would launch: $exe"
		return 0
	fi
	if [[ "$PLATFORM" == "macos" && "$exe" == *.app ]]; then
		exec open "$exe"
	fi
	exec "$exe"
}

do_check() {
	local body tag current
	body="$(fetch_release)" || body=""
	current="$(installed_version)"
	[[ -n "$current" ]] && say "installed: $current" || say "installed: (nothing)"
	if [[ -z "$body" ]]; then
		say "latest:    (could not reach $API)"
		return 1
	fi
	tag="$(json_field "$body" "tag_name")"
	say "latest:    ${tag:-(none published)}"
	if [[ -n "$tag" && "$tag" != "$current" ]]; then
		say "An update is available. Run this script with no arguments to install it."
		return 10
	fi
	say "Up to date."
	return 0
}

do_uninstall() {
	rm -rf "$PREFIX" "$PREFIX.new" "$PREFIX.old"
	rm -f "$BIN_DIR/$SLUG" "$DESKTOP_DIR/$SLUG.desktop"
	say "$NAME removed. Save files and settings were left alone."
	if [[ "$PLATFORM" == "linux" ]]; then
		say "They live in ~/.local/share/godot/app_userdata/$NAME"
	else
		say "They live in ~/Library/Application Support/Godot/app_userdata/$NAME"
	fi
}

usage() {
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
	case "${1:-}" in
		--launch)    do_launch ;;
		--check)     do_check ;;
		--uninstall) do_uninstall ;;
		--force)     do_install "yes" "no" ;;
		-h|--help)   usage ;;
		"")          do_install "no" "no" ;;
		*)           die "Unknown option: $1  (try --help)" ;;
	esac
}

main "$@"
