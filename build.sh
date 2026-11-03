#!/usr/bin/env bash
# Builds, signs and zips build/Wisp.app.
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
rm -rf "$APP" build/Wisp.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build "${ARGS[@]}" --show-bin-path)/Wisp" "$APP/Contents/MacOS/Wisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "${SIGN_ID:--}" "$APP"

if [ "${NOTARIZE:-0}" = "1" ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  ditto -c -k --keepParent "$APP" build/Wisp.zip
  xcrun notarytool submit build/Wisp.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm build/Wisp.zip
fi
ditto -c -k --keepParent "$APP" build/Wisp.zip
echo "built $APP and build/Wisp.zip"
