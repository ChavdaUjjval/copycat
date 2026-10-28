#!/bin/bash
# Installs (or updates) Copycat from the latest GitHub release. No developer tools needed.
#
#   curl -fsSL https://raw.githubusercontent.com/ChavdaUjjval/copycat/main/install.sh | bash
set -euo pipefail

DMG_URL="https://github.com/ChavdaUjjval/copycat/releases/latest/download/Copycat.dmg"
BUNDLE_ID="com.ujjvalchavda.copycat"

fail() { echo "Error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Copycat is a Mac app."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "Copycat needs macOS 14 Sonoma or later."

if [[ -w /Applications ]]; then APPS=/Applications; else APPS="$HOME/Applications"; mkdir -p "$APPS"; fi
APP="$APPS/Copycat.app"

TMP=$(mktemp -d)
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "Downloading Copycat…"
curl -fL --progress-bar "$DMG_URL" -o "$TMP/Copycat.dmg" || fail "Couldn't download $DMG_URL"

MOUNT=$(hdiutil attach -nobrowse -readonly -noverify -mountrandom "$TMP" "$TMP/Copycat.dmg" 2>/dev/null \
  | awk -F'\t' '/Apple_HFS/ {print $NF}')
[[ -d "$MOUNT/Copycat.app" ]] || fail "The download doesn't contain Copycat.app."

# Quit a running copy so it can be replaced. History and settings are kept.
if pgrep -x Copycat >/dev/null; then
  echo "Quitting the running copy…"
  osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
  for _ in {1..50}; do pgrep -x Copycat >/dev/null || break; sleep 0.1; done
fi

echo "Installing to $APPS…"
rm -rf "$APP"
ditto "$MOUNT/Copycat.app" "$APP"
# Downloaded with curl, the app isn't quarantined, so macOS doesn't ask to approve it. Make sure.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "Copycat is installed and running. Open the shelf any time with Control-Command-V."
