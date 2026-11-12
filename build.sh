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

swift build "${ARGS[@]}"
APP=build/Wisp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build "${ARGS[@]}" --show-bin-path)/Wisp" "$APP/Contents/MacOS/Wisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "${SIGN_ID:--}" "$APP"

# DMG: the app plus an Applications link for drag-to-install.
STAGE=build/dmg
rm -rf "$STAGE" build/Wisp.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Wisp -srcfolder "$STAGE" -format UDZO build/Wisp.dmg
rm -rf "$STAGE"

if [ "${NOTARIZE:-0}" = "1" ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  xcrun notarytool submit build/Wisp.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/Wisp.dmg
fi
echo "built $APP and build/Wisp.dmg"
