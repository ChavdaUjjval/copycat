#!/bin/zsh
# Builds Copycat.app as a universal app (Apple Silicon and Intel) for macOS 14 Sonoma or later.
#
#   ./build.sh             build into build/Copycat.app
#   ./build.sh --install   also install it to /Applications
#   ./build.sh --package   also make build/Copycat.dmg to share
set -euo pipefail
cd "${0:A:h}"

install=0 package=0
for arg in "$@"; do
  case $arg in
    --install) install=1 ;;
    --package) package=1 ;;
    *) echo "usage: ./build.sh [--install] [--package]" >&2; exit 64 ;;
  esac
done

APP=build/Copycat.app
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -wmo -swift-version 6 -target $arch-apple-macos14 Sources/Copycat/*.swift -o "$TMP/Copycat-$arch"
done
lipo -create "$TMP/Copycat-arm64" "$TMP/Copycat-x86_64" -output "$APP/Contents/MacOS/Copycat"
cp Support/Info.plist "$APP/Contents/Info.plist"

# App icon, rendered by the app itself.
"$APP/Contents/MacOS/Copycat" --icon "$TMP/icon.png"
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if (( install )); then
  rm -rf /Applications/Copycat.app
  ditto "$APP" /Applications/Copycat.app
  touch /Applications/Copycat.app
  echo "Installed /Applications/Copycat.app"
fi

# A disk image that opens to a window with the app, an arrow and an Applications shortcut,
# so installing is a single drag. The window layout needs Finder; without it (for example when
# macOS hasn't allowed controlling Finder yet) the image still works, just without the artwork.
if (( package )); then
  DMG=build/Copycat.dmg
  STAGE="$TMP/dmg"
  mkdir -p "$STAGE/.background"
  ditto "$APP" "$STAGE/Copycat.app"
  ln -s /Applications "$STAGE/Applications"
  "$APP/Contents/MacOS/Copycat" --dmg-background "$TMP/bg.png" --scale 1
  "$APP/Contents/MacOS/Copycat" --dmg-background "$TMP/bg@2x.png" --scale 2
  tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

  hdiutil create -quiet -volname Copycat -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP/rw.dmg" 2>/dev/null
  MOUNT=$(hdiutil attach "$TMP/rw.dmg" -readwrite -noverify -noautoopen 2>/dev/null | awk -F'\t' '/Apple_HFS/ {print $NF}')
  # Icon positions match InstallerArt.swift.
  osascript - "$(basename "$MOUNT")" <<'EOF' || echo "warning: couldn't lay out the disk image window (Finder automation not allowed?)" >&2
on run {volumeName}
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {200, 120, 840, 568}
      set opts to icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to 112
      set text size of opts to 13
      set background picture of opts to file ".background:background.tiff"
      set position of item "Copycat.app" of container window to {170, 200}
      set position of item "Applications" of container window to {470, 200}
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
EOF
  # The volume icon goes in after Finder is done, since laying out the window removes it.
  cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT" 2>/dev/null || true
  rm -rf "$MOUNT/.fseventsd"
  sync
  hdiutil detach -quiet "$MOUNT"
  rm -f "$DMG"
  hdiutil convert -quiet "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
  echo "Packaged $DMG"
fi
