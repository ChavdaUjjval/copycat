#!/bin/bash
# Installs or updates Copycat from the latest GitHub release. No developer tools needed.
#
#   curl -fsSL https://chavdaujjval.github.io/copycat/install | bash
#
# What it does:
#   1. downloads Copycat.dmg and Copycat.dmg.sha256 from the latest release of
#      github.com/ChavdaUjjval/copycat, and stops unless the checksum matches;
#   2. if the GitHub CLI (gh) is installed and signed in, also checks the build attestation,
#      which proves the disk image was built by this repository's release workflow;
#   3. copies Copycat.app into /Applications (or ~/Applications) and opens it.
# It never asks for your password, never uses sudo, and changes nothing else.
#
# Plain ASCII and ${VAR} throughout: macOS's bash 3.2 can read a non-ASCII character
# right after $VAR as part of the name in UTF-8 locales.
set -euo pipefail

REPO="ChavdaUjjval/copycat"
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
  if [[ -e "${app}" && ! -O "${app}" ]]; then
    fail "${app} belongs to another user on this Mac. Ask them to remove it, or delete it as an administrator."
  fi

  TMP=$(mktemp -d)
  trap cleanup EXIT

  # Find the latest release once, so the disk image and its checksum come from the same one.
  local tag
  tag=$(curl -fsSI "https://github.com/${REPO}/releases/latest" | awk -F/ 'tolower($0) ~ /^location:/ {print $NF}' | tr -d '\r')
  [[ "${tag}" =~ ^v[0-9]+(\.[0-9]+)*$ ]] || fail "Couldn't find the latest Copycat release."
  local url="https://github.com/${REPO}/releases/download/${tag}"

  echo "Downloading Copycat ${tag#v}..."
  curl -fL --progress-bar "${url}/Copycat.dmg" -o "${TMP}/Copycat.dmg" || fail "Couldn't download ${url}/Copycat.dmg"
  curl -fsSL "${url}/Copycat.dmg.sha256" -o "${TMP}/Copycat.dmg.sha256" || fail "Couldn't download the checksum"

  local expected actual
  expected=$(awk '{print $1; exit}' "${TMP}/Copycat.dmg.sha256")
  actual=$(shasum -a 256 "${TMP}/Copycat.dmg" | awk '{print $1}')
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] \
    || fail "The download doesn't match its published checksum, so it wasn't installed."
  echo "Checksum verified."

  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh attestation verify "${TMP}/Copycat.dmg" --repo "${REPO}" --source-ref "refs/tags/${tag}" >/dev/null 2>&1 \
      || fail "The download's build attestation didn't verify, so it wasn't installed."
    echo "Build attestation verified."
  fi

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
