#!/usr/bin/env bash
# Builds and signs build/Wisp.app and packs it into build/Wisp.dmg.
#   CONFIG=debug|release   (default release; release is universal arm64 + x86_64)
#   SIGN_ID=<identity>     Signing identity. Default: "Wisp Local Signing", a self-signed certificate that this
#                          script creates once in your login keychain and reuses for every later build. Because the
#                          certificate stays the same, macOS keeps Accessibility and Screen Recording permission
#                          when you replace the app with a new build. Use SIGN_ID=- for ad-hoc signing (macOS then
#                          asks for the permissions again after every build).
#   NOTARIZE=1 NOTARY_PROFILE=<keychain profile>   (needs a Developer ID identity in SIGN_ID)
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
BUNDLE_ID="io.github.emresarikaya35.wisp"
LOCAL_IDENTITY="Wisp Local Signing"
SIGN_ID="${SIGN_ID:-$LOCAL_IDENTITY}"
ARGS=(-c "$CONFIG")
[ "$CONFIG" = release ] && ARGS+=(--arch arm64 --arch x86_64)
if [ "${NOTARIZE:-0}" = "1" ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
fi

# Creates the self-signed code signing certificate on first use. It is never recreated while it exists:
# a new certificate is a new identity to macOS, and the permissions would have to be granted once more.
ensure_local_identity() {
  if security find-identity -p codesigning | grep -Fq "\"$LOCAL_IDENTITY\""; then return; fi
  echo "Creating the \"$LOCAL_IDENTITY\" certificate in your login keychain (one time only)…"
  local dir keychain
  dir=$(mktemp -d)
  keychain="$HOME/Library/Keychains/login.keychain-db"
  cat > "$dir/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  # /usr/bin/openssl (LibreSSL) writes a PKCS#12 file that `security import` can read.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$dir/cert.cnf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$LOCAL_IDENTITY" \
    -out "$dir/identity.p12" -passout pass:wisp
  security import "$dir/identity.p12" -k "$keychain" -P wisp -T /usr/bin/codesign
  rm -rf "$dir"
  if ! security find-identity -p codesigning | grep -Fq "\"$LOCAL_IDENTITY\""; then
    echo "error: could not create the signing certificate. See README, \"Keeping permissions across updates\"." >&2
    exit 1
  fi
}
[ "$SIGN_ID" = "$LOCAL_IDENTITY" ] && ensure_local_identity

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
# A fixed identifier plus a fixed certificate gives every build the same designated requirement, which is
# what macOS stores with a privacy permission.
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$SIGN_ID" "$APP"
if [ "$SIGN_ID" = "-" ]; then
  echo "warning: ad-hoc signed. macOS will ask for Accessibility again when this build replaces an older one." >&2
else
  echo "signed as: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
fi

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
