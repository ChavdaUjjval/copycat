#!/bin/bash
# Points the Homebrew cask in ChavdaUjjval/homebrew-tap at a published release.
# Run it after the release for a tag has finished building:
#
#   scripts/update-homebrew-tap.sh 1.0.2
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/update-homebrew-tap.sh VERSION}
version=${version#v}
sha=$(curl -fsSL "https://github.com/ChavdaUjjval/copycat/releases/download/v${version}/Copycat.dmg.sha256" | awk '{print $1}')
[[ ${#sha} == 64 ]] || { echo "No checksum found for v${version}" >&2; exit 1; }

tap=$(mktemp -d)
trap 'rm -rf "${tap}"' EXIT
gh repo clone ChavdaUjjval/homebrew-tap "${tap}" -- --quiet
sed -i '' -e "s/^  version \".*\"/  version \"${version}\"/" -e "s/^  sha256 \".*\"/  sha256 \"${sha}\"/" \
  "${tap}/Casks/copycat.rb"
git -C "${tap}" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
  commit --quiet -am "copycat ${version}"
git -C "${tap}" push --quiet
echo "homebrew-tap now installs Copycat ${version} (sha256 ${sha})"
