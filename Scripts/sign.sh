#!/bin/bash
set -euo pipefail
APP="${1:?app bundle required}"
IDENTITY="${SIGNING_IDENTITY:--}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then FLAGS+=(--timestamp --options runtime); fi
for component in \
    "$FRAMEWORK/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/XPCServices/Installer.xpc" \
    "$FRAMEWORK/Autoupdate" \
    "$FRAMEWORK/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP"; do
    codesign "${FLAGS[@]}" "$component"
done
codesign --verify --deep --strict "$APP"
