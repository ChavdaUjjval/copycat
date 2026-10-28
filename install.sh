#!/bin/bash
# Installs or updates Copycat from the latest GitHub release. No developer tools needed.
#
#   curl -fsSL https://chavdaujjval.github.io/copycat/install | bash
#
# What it does:
#   1. downloads Copycat.dmg and Copycat.dmg.sha256 from the latest release of
#      github.com/ChavdaUjjval/copycat, and stops unless the checksum matches;
#   2. copies Copycat.app into /Applications (or ~/Applications) and opens it.
# It never asks for your password, never uses sudo, and changes nothing else.
#
# Plain ASCII and ${VAR} throughout: macOS's bash 3.2 can read a non-ASCII character
# right after $VAR as part of the name in UTF-8 locales.
set -euo pipefail

RELEASE_URL="https://github.com/ChavdaUjjval/copycat/releases/latest/download"
BUNDLE_ID="com.ujjvalchavda.copycat"
TMP=""
MOUNT=""

fail() { echo "Error: $*" >&2; exit 1; }

cleanup() {
  if [[ -n "${MOUNT}" ]]; then hdiutil detach -quiet "${MOUNT}" 2>/dev/null || true; fi
  if [[ -n "${TMP}" ]]; then rm -rf "${TMP}"; fi
}

# Everything runs from main, called on the last line, so a partly downloaded script does nothing.
main() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "Copycat is a Mac app."
  local major
  major=$(sw_vers -productVersion | cut -d. -f1)
  (( major >= 14 )) || fail "Copycat needs macOS 14 Sonoma or later."

  local apps="/Applications"
  if [[ ! -w "${apps}" ]]; then apps="${HOME}/Applications"; mkdir -p "${apps}"; fi
  local app="${apps}/Copycat.app"

  TMP=$(mktemp -d)
  trap cleanup EXIT

  echo "Downloading Copycat..."
  curl -fL --progress-bar "${RELEASE_URL}/Copycat.dmg" -o "${TMP}/Copycat.dmg" \
    || fail "Couldn't download ${RELEASE_URL}/Copycat.dmg"
  curl -fsSL "${RELEASE_URL}/Copycat.dmg.sha256" -o "${TMP}/Copycat.dmg.sha256" \
    || fail "Couldn't download the checksum for Copycat.dmg"

  local expected actual
  expected=$(awk '{print $1; exit}' "${TMP}/Copycat.dmg.sha256")
  actual=$(shasum -a 256 "${TMP}/Copycat.dmg" | awk '{print $1}')
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] \
    || fail "The download doesn't match its published checksum, so it wasn't installed."
  echo "Checksum verified."

  MOUNT=$(hdiutil attach -nobrowse -readonly -noverify -mountrandom "${TMP}" "${TMP}/Copycat.dmg" 2>/dev/null \
    | awk -F'\t' '/Apple_HFS/ {print $NF}')
  [[ -d "${MOUNT}/Copycat.app" ]] || fail "The download doesn't contain Copycat.app."

  # Quit a running copy so it can be replaced. History and settings are kept.
  if pgrep -x Copycat >/dev/null; then
    echo "Quitting the running copy..."
    osascript -e "quit app id \"${BUNDLE_ID}\"" 2>/dev/null || true
    local i
    for i in {1..50}; do pgrep -x Copycat >/dev/null || break; sleep 0.1; done
  fi

  echo "Installing to ${apps}..."
  rm -rf "${app}"
  ditto "${MOUNT}/Copycat.app" "${app}"
  # Downloaded with curl, the app isn't quarantined, so macOS doesn't block it. Make sure.
  xattr -dr com.apple.quarantine "${app}" 2>/dev/null || true

  open "${app}"
  echo "Copycat is installed and running. Open the shelf any time with Control-Command-V."
}

main "$@"
