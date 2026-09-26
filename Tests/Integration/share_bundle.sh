#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
WORKSPACE_DIR="${PROJECT_DIR:h:h}"
OUTPUT_DIR="$WORKSPACE_DIR/outputs"
ZIP_NAME="飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
ZIP_SUM="$ZIP_PATH.sha256"
CHECK_DIR="$(mktemp -d /private/tmp/flying-snowfluff-share-check.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT

[[ -f "$ZIP_PATH" ]]
[[ -f "$ZIP_SUM" ]]
(cd "$OUTPUT_DIR" && shasum -a 256 -c "$ZIP_NAME.sha256")
/usr/bin/ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
PAYLOAD="$CHECK_DIR/飞行雪绒·爱弥斯"
[[ -d "$PAYLOAD/FlyingSnowfluff.app" ]]
[[ -f "$PAYLOAD/安装与使用说明.md" ]]
[[ -f "$PAYLOAD/SHA256SUMS.txt" ]]
(cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS.txt)
codesign --verify --deep --strict "$PAYLOAD/FlyingSnowfluff.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PAYLOAD/FlyingSnowfluff.app/Contents/Info.plist")" == "1.4.1" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PAYLOAD/FlyingSnowfluff.app/Contents/Info.plist")" == "6" ]]
[[ -f "$PAYLOAD/FlyingSnowfluff.app/Contents/Resources/AppIcon.icns" ]]
[[ -f "$PAYLOAD/FlyingSnowfluff.app/Contents/Resources/Lively/motion.json" ]]
print "PASS: Finder share bundle"
