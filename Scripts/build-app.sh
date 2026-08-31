#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/划译.app"
DMG_PATH="$DIST_DIR/划译.dmg"
ZIP_PATH="$DIST_DIR/划译.zip"
CONTENTS_DIR="$APP_DIR/Contents"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/huayi-dmg.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/release/Huayi" "$CONTENTS_DIR/MacOS/Huayi"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "THIRD-PARTY-NOTICES.md" "$CONTENTS_DIR/Resources/THIRD-PARTY-NOTICES.md"
codesign \
    --force \
    --deep \
    --identifier "com.local.huayi" \
    --requirements '=designated => identifier "com.local.huayi"' \
    --sign - \
    "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

rm -f "$DMG_PATH" "$ZIP_PATH"
ditto "$APP_DIR" "$STAGING_DIR/划译.app"
ln -s /Applications "$STAGING_DIR/应用程序"
hdiutil create \
    -volname "划译" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built $APP_DIR"
echo "Built $DMG_PATH"
echo "Built $ZIP_PATH"
