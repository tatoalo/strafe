#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="strafe-tatoalo"
APP="build/$APP_NAME.app"
RELEASE_FLAGS=(-c release --arch arm64 -Xswiftc -Osize -Xlinker -dead_strip)
swift build "${RELEASE_FLAGS[@]}"
BIN_DIR="$(swift build "${RELEASE_FLAGS[@]}" --show-bin-path)"
FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$FRAMEWORK"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
strip -rSTx "$APP/Contents/MacOS/$APP_NAME"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
cp LICENSE "$APP/Contents/Resources/LICENSE"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}" python3 - <<'PY'
import os,pathlib,plistlib,re
version=pathlib.Path('VERSION').read_text().strip()
assert re.fullmatch(r'\d+\.\d+\.\d+',version)
build=os.environ['BUILD_NUMBER']
assert build.isdigit() and int(build)>0
info={
 'CFBundleName':'strafe-tatoalo','CFBundleDisplayName':'strafe-tatoalo',
 'CFBundleExecutable':'strafe-tatoalo','CFBundleIdentifier':'com.tatoalo.strafe',
 'CFBundlePackageType':'APPL','CFBundleShortVersionString':version,'CFBundleVersion':build,
 'LSMinimumSystemVersion':'15.0','LSUIElement':True,
 'NSHumanReadableCopyright':'Copyright © 2026 Riley Hennigh and strafe-tatoalo contributors. MIT.',
 'SUFeedURL':'https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml',
 'SUPublicEDKey':pathlib.Path('Resources/SparklePublicKey.txt').read_text().strip(),
 'SUEnableAutomaticChecks':True,'SUAutomaticallyUpdate':False,'SUEnableSystemProfiling':False,
}
pathlib.Path('build/strafe-tatoalo.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
# Sign each embedded component before its container, also for local builds.
SIGNING_IDENTITY=- Scripts/sign.sh "$APP"
echo "Built: $APP"
