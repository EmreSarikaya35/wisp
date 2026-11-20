#!/usr/bin/env bash
# Builds and signs build/Wisp.app and packs it into build/Wisp.dmg.
#   CONFIG=debug|release   (default release; release is universal arm64 + x86_64)
#   SIGN_ID=<identity>     (default "-" = ad-hoc; use a stable identity so macOS keeps permissions across builds)
#   NOTARIZE=1 NOTARY_PROFILE=<keychain profile>   (needs a Developer ID identity in SIGN_ID)
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
ARGS=(-c "$CONFIG")
[ "$CONFIG" = release ] && ARGS+=(--arch arm64 --arch x86_64)
if [ "${NOTARIZE:-0}" = "1" ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
fi

swift build "${ARGS[@]}"
mkdir -p build
WORK=$(mktemp -d build/.wisp-build.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/dmg"
APP="$STAGE/Wisp.app"
DMG="$WORK/Wisp.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build "${ARGS[@]}" --show-bin-path)/Wisp" "$APP/Contents/MacOS/Wisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "${SIGN_ID:--}" "$APP"

# DMG: the app plus an Applications link for drag-to-install.
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Wisp -srcfolder "$STAGE" -format UDZO "$DMG"

if [ "${NOTARIZE:-0}" = "1" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

rm -rf build/Wisp.app
mv "$APP" build/Wisp.app
mv -f "$DMG" build/Wisp.dmg
echo "built build/Wisp.app and build/Wisp.dmg"
