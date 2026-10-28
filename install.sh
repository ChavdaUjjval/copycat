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
# right after $VAR as part of the name in UTF-8 locales. Symbols are written as byte escapes.
set -euo pipefail

REPO="ChavdaUjjval/copycat"
BUNDLE_ID="com.ujjvalchavda.copycat"
TMP=""
MOUNT=""
DOWNLOAD_PID=""

# Colours, symbols and the logo only when writing to a terminal that wants them.
setup_style() {
  ESC=$'\033'
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    FANCY=1
    BOLD="${ESC}[1m" DIM="${ESC}[2m" RESET="${ESC}[0m"
    GREEN="${ESC}[38;5;42m" RED="${ESC}[38;5;203m" ACCENT="${ESC}[38;5;209m" GREY="${ESC}[38;5;240m"
    CHECK=$'\xe2\x9c\x94' CROSS=$'\xe2\x9c\x98' BAR=$'\xe2\x94\x81'
    UPPER=$'\xe2\x96\x80' LOWER=$'\xe2\x96\x84'
    KEYS=$'\xe2\x8c\x83\xe2\x8c\x98V'
    SPINNER=($'\xe2\xa0\x8b' $'\xe2\xa0\x99' $'\xe2\xa0\xb9' $'\xe2\xa0\xb8' $'\xe2\xa0\xbc'
             $'\xe2\xa0\xb4' $'\xe2\xa0\xa6' $'\xe2\xa0\xa7' $'\xe2\xa0\x87' $'\xe2\xa0\x8f')
  else
    FANCY=0
    BOLD="" DIM="" RESET="" GREEN="" RED="" ACCENT="" GREY=""
    CHECK="ok" CROSS="error:" KEYS="Control-Command-V"
  fi
}

ok() { printf '  %s%s%s %s\n' "${GREEN}" "${CHECK}" "${RESET}" "$*"; }

fail() {
  if (( FANCY )); then printf '\r%s[K' "${ESC}"; fi
  printf '\n  %s%s %s%s\n\n' "${RED}" "${CROSS}" "$*" "${RESET}" >&2
  exit 1
}

cleanup() {
  if [[ -n "${DOWNLOAD_PID}" ]]; then kill "${DOWNLOAD_PID}" 2>/dev/null || true; fi
  if [[ -n "${MOUNT}" ]]; then hdiutil detach -quiet "${MOUNT}" 2>/dev/null || true; fi
  if [[ -n "${TMP}" ]]; then rm -rf "${TMP}"; fi
  if (( ${FANCY:-0} )); then printf '%s[?25h' "${ESC}"; fi
}

# The app icon in 16 x 16 pixels, two pixel rows per line of text.
# o background, k fur, p pink, w white, e eyes, l card lines, . transparent.
LOGO_ROWS=(
  "..oooooooooooo.."
  ".ookooooooookoo."
  "ookkkooooookkkoo"
  "ookpkkkkkkkkpkoo"
  "okkkkkkkkkkkkkko"
  "okkwwwkkkkwwwkko"
  "okkwewkkkkwewkko"
  "okkwwwkkkkwwwkko"
  "okkkkkkppkkkkkko"
  "ookkkkkkkkkkkkoo"
  "oowkkwwwwwwkkwoo"
  "oowwwwwwwwwwwwoo"
  "oowllllllllwwwoo"
  "oowwwwwwwwwwwwoo"
  ".owlllllwwwwwwo."
  "..oooooooooooo.."
)

# Sets COLOR to the 256-colour index of a logo pixel, or to nothing if it's transparent.
pixel() {
  case "$1" in
    o) if (( $2 < 5 )); then COLOR=215; elif (( $2 < 10 )); then COLOR=209; else COLOR=204; fi ;;
    k) COLOR=237 ;;
    p) COLOR=211 ;;
    w) COLOR=231 ;;
    e) COLOR=16 ;;
    l) COLOR=216 ;;
    *) COLOR="" ;;
  esac
}

banner() {
  if (( ! FANCY )); then
    echo "Copycat installer - github.com/${REPO}"
    return
  fi
  local text=("" "" "${BOLD}Copycat${RESET}" "${DIM}Clipboard history for your Mac${RESET}" ""
              "${GREY}github.com/${REPO}${RESET}" "" "")
  local y x top bottom line
  echo
  for (( y = 0; y < 16; y += 2 )); do
    line=""
    for (( x = 0; x < 16; x++ )); do
      pixel "${LOGO_ROWS[y]:x:1}" "${y}"; top="${COLOR}"
      pixel "${LOGO_ROWS[y + 1]:x:1}" "$(( y + 1 ))"; bottom="${COLOR}"
      if [[ -z "${top}" && -z "${bottom}" ]]; then line+=" "
      elif [[ -z "${bottom}" ]]; then line+="${ESC}[38;5;${top}m${UPPER}${RESET}"
      elif [[ -z "${top}" ]]; then line+="${ESC}[38;5;${bottom}m${LOWER}${RESET}"
      else line+="${ESC}[38;5;${top};48;5;${bottom}m${UPPER}${RESET}"
      fi
    done
    printf '  %s   %s\n' "${line}" "${text[y / 2]}"
  done
  echo
}

# Downloads $1 to $2, with a progress bar in a terminal.
download() {
  local url="$1" dest="$2" label="$3"
  if (( ! FANCY )); then
    echo "  ${label}..."
    curl -fsSL "${url}" -o "${dest}"
    return
  fi
  local total size frame=0
  total=$(curl -fsIL "${url}" | awk 'tolower($1) == "content-length:" {n = $2} END {print n + 0}')
  printf '%s[?25l' "${ESC}"
  curl -fsSL "${url}" -o "${dest}" &
  DOWNLOAD_PID=$!
  while kill -0 "${DOWNLOAD_PID}" 2>/dev/null; do
    size=$(stat -f %z "${dest}" 2>/dev/null || echo 0)
    progress "${SPINNER[frame % 10]}" "${label}" "${size}" "${total}"
    frame=$(( frame + 1 ))
    sleep 0.08
  done
  wait "${DOWNLOAD_PID}" || { DOWNLOAD_PID=""; return 1; }
  DOWNLOAD_PID=""
  printf '\r%s[K%s[?25h' "${ESC}" "${ESC}"
}

progress() {
  local spin="$1" label="$2" size="$3" total="$4" width=20 filled=0 i bar=""
  if (( total > 0 )); then filled=$(( size * width / total )); fi
  for (( i = 0; i < width; i++ )); do
    if (( i == 0 )); then bar+="${ACCENT}"; fi
    if (( i == filled )); then bar+="${GREY}"; fi
    bar+="${BAR}"
  done
  local amount
  amount=$(awk -v s="${size}" -v t="${total}" 'BEGIN {
    if (t > 0) printf "%3d%% of %.1f MB", s * 100 / t, t / 1048576
    else printf "%.1f MB", s / 1048576 }')
  printf '\r%s[K  %s%s%s %s  %s%s  %s%s%s' "${ESC}" "${ACCENT}" "${spin}" "${RESET}" "${label}" \
    "${bar}" "${RESET}" "${DIM}" "${amount}" "${RESET}"
}

# Everything runs from main, called on the last line, so a partly downloaded script does nothing.
main() {
  setup_style
  banner

  [[ "$(uname -s)" == "Darwin" ]] || fail "Copycat is a Mac app."
  local version major chip
  version=$(sw_vers -productVersion)
  major=${version%%.*}
  (( major >= 14 )) || fail "Copycat needs macOS 14 Sonoma or later. This Mac has ${version}."
  chip="Intel"
  if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then chip="Apple silicon"; fi

  local apps="/Applications"
  if [[ ! -w "${apps}" ]]; then apps="${HOME}/Applications"; mkdir -p "${apps}"; fi
  local app="${apps}/Copycat.app"
  if [[ -e "${app}" && ! -O "${app}" ]]; then
    fail "${app} belongs to another user on this Mac. Ask them to remove it, or delete it as an administrator."
  fi
  ok "macOS ${version} on ${chip}"

  TMP=$(mktemp -d)
  trap cleanup EXIT

  # Find the latest release once, so the disk image and its checksum come from the same one.
  local tag
  tag=$(curl -fsSI "https://github.com/${REPO}/releases/latest" | awk -F/ 'tolower($0) ~ /^location:/ {print $NF}' | tr -d '\r')
  [[ "${tag}" =~ ^v[0-9]+(\.[0-9]+)*$ ]] || fail "Couldn't find the latest Copycat release. Check your internet connection."
  local url="https://github.com/${REPO}/releases/download/${tag}"

  download "${url}/Copycat.dmg" "${TMP}/Copycat.dmg" "Downloading Copycat ${tag#v}" \
    || fail "Couldn't download ${url}/Copycat.dmg"
  curl -fsSL "${url}/Copycat.dmg.sha256" -o "${TMP}/Copycat.dmg.sha256" || fail "Couldn't download the checksum."
  local size
  size=$(stat -f %z "${TMP}/Copycat.dmg")
  ok "Downloaded Copycat ${tag#v} ${DIM}($(awk -v s="${size}" 'BEGIN {printf "%.1f MB", s / 1048576}'))${RESET}"

  local expected actual
  expected=$(awk '{print $1; exit}' "${TMP}/Copycat.dmg.sha256")
  actual=$(shasum -a 256 "${TMP}/Copycat.dmg" | awk '{print $1}')
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] \
    || fail "The download doesn't match its published checksum, so it wasn't installed."
  ok "Checksum matches the release"

  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh attestation verify "${TMP}/Copycat.dmg" --repo "${REPO}" --source-ref "refs/tags/${tag}" >/dev/null 2>&1 \
      || fail "The download's build attestation didn't verify, so it wasn't installed."
    ok "Built by GitHub Actions from ${tag} ${DIM}(attestation verified)${RESET}"
  fi

  MOUNT=$(hdiutil attach -nobrowse -readonly -noverify -mountrandom "${TMP}" "${TMP}/Copycat.dmg" 2>/dev/null \
    | awk -F'\t' '/Apple_HFS/ {print $NF}')
  [[ -d "${MOUNT}/Copycat.app" ]] || fail "The download doesn't contain Copycat.app."

  # Quit a running copy so it can be replaced. History and settings are kept.
  if pgrep -x Copycat >/dev/null; then
    osascript -e "quit app id \"${BUNDLE_ID}\"" 2>/dev/null || true
    local i
    for i in {1..50}; do pgrep -x Copycat >/dev/null || break; sleep 0.1; done
  fi

  rm -rf "${app}"
  ditto "${MOUNT}/Copycat.app" "${app}"
  # Downloaded with curl, the app isn't quarantined, so macOS doesn't block it. Make sure.
  xattr -dr com.apple.quarantine "${app}" 2>/dev/null || true
  ok "Installed in ${apps}"

  open "${app}"
  echo
  printf '  %sCopycat is ready.%s Press %s%s%s in any app to open your clipboard history.\n\n' \
    "${BOLD}" "${RESET}" "${ACCENT}" "${KEYS}" "${RESET}"
}

main "$@"
