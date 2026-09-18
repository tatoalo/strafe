#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Developer ID Application identity required}"
: "${NOTARY_PROFILE:?notarytool keychain profile required}"
: "${BUILD_NUMBER:?release build number required}"
: "${RELEASE_TAG:?release tag required}"
: "${SPARKLE_KEY_FILE:?Sparkle private key file required}"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/strafe-tatoalo.app"
DIST="build/dist"
./Scripts/bundle.sh
./Scripts/sign.sh "$APP"
ditto -c -k --keepParent "$APP" build/notarize.zip
xcrun notarytool submit build/notarize.zip "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm -f build/notarize.zip
rm -rf "$DIST" build/dmg-root
mkdir -p "$DIST" build/dmg-root
NAME="strafe-tatoalo-${VERSION}-${BUILD_NUMBER}-arm64"
ditto "$APP" "build/dmg-root/strafe-tatoalo.app"
ln -s /Applications build/dmg-root/Applications
hdiutil create -quiet -volname "strafe-tatoalo $VERSION" -srcfolder build/dmg-root -ov -format UDZO "$DIST/$NAME.dmg"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DIST/$NAME.dmg"
xcrun notarytool submit "$DIST/$NAME.dmg" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$DIST/$NAME.dmg"
xcrun stapler validate "$DIST/$NAME.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DIST/$NAME.dmg"
test -f "release-notes/$VERSION.md"
cp "release-notes/$VERSION.md" "$DIST/$NAME.md"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "https://github.com/tatoalo/strafe/releases/download/$RELEASE_TAG/" \
    --link https://github.com/tatoalo/strafe \
    --embed-release-notes "$DIST"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" > SHA256SUMS)
python3 Scripts/verify-release.py "$APP" "$DIST/appcast.xml" "$DIST/$NAME.dmg"
