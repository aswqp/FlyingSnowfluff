#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
BACKUP_DIR="${BACKUP_DIR:-$OUTPUT_DIR/.backups}"
BUILD_DIR="$(mktemp -d /private/tmp/flying-snowfluff-release.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

MODULE_CACHE="/private/tmp/flying-snowfluff-release-module-cache"
APP_BUNDLE="$BUILD_DIR/FlyingSnowfluff.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
CORE_LIBRARY="$BUILD_DIR/libFlyingSnowfluffCore.dylib"

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$OUTPUT_DIR" "$BACKUP_DIR"

swiftc -O -whole-module-optimization -parse-as-library -emit-library -emit-module \
  -module-name FlyingSnowfluffCore \
  "$PROJECT_DIR"/Sources/FlyingSnowfluffCore/*.swift \
  -module-cache-path "$MODULE_CACHE" \
  -emit-module-path "$BUILD_DIR/FlyingSnowfluffCore.swiftmodule" \
  -o "$CORE_LIBRARY"

swiftc -O -whole-module-optimization -swift-version 5 \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/PetDialogue.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/PetSpeechBubble.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/LivelyMotion.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/SpriteAtlas.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/PetEventServer.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/PetApplication.swift" \
  "$PROJECT_DIR/Sources/FlyingSnowfluffApp/main.swift" \
  -I "$BUILD_DIR" -L "$BUILD_DIR" -lFlyingSnowfluffCore \
  -module-cache-path "$MODULE_CACHE" \
  -Xlinker -rpath -Xlinker @executable_path \
  -o "$APP_MACOS/FlyingSnowfluff"

swiftc -O -whole-module-optimization -swift-version 5 \
  "$PROJECT_DIR"/Sources/FlyingSnowfluffCore/*.swift \
  "$PROJECT_DIR/Sources/flyingsnowfluffctl/main.swift" \
  -module-cache-path "$MODULE_CACHE" \
  -o "$APP_MACOS/flyingsnowfluffctl"

install_name_tool -id @rpath/libFlyingSnowfluffCore.dylib "$CORE_LIBRARY"
install_name_tool -change "$CORE_LIBRARY" @rpath/libFlyingSnowfluffCore.dylib "$APP_MACOS/FlyingSnowfluff"

cp "$CORE_LIBRARY" "$APP_MACOS/libFlyingSnowfluffCore.dylib"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/App/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$PROJECT_DIR/Resources/App/spritesheet@2x.png" "$APP_RESOURCES/spritesheet@2x.png"
cp "$PROJECT_DIR/Resources/App/spritesheet.png" "$APP_RESOURCES/spritesheet.png"
cp -R "$PROJECT_DIR/Resources/App/frames@2x" "$APP_RESOURCES/frames@2x"
cp -R "$PROJECT_DIR/Resources/App/frames@1x" "$APP_RESOURCES/frames@1x"
mkdir -p "$APP_RESOURCES/Lively"
cp "$PROJECT_DIR/Resources/v3/motion.json" "$APP_RESOURCES/Lively/motion.json"
cp "$PROJECT_DIR"/Resources/v3/*.png "$APP_RESOURCES/Lively/"

chmod 755 "$APP_MACOS/FlyingSnowfluff" "$APP_MACOS/flyingsnowfluffctl" "$APP_MACOS/libFlyingSnowfluffCore.dylib"
codesign --force --sign - --timestamp=none "$APP_MACOS/libFlyingSnowfluffCore.dylib"
codesign --force --sign - --timestamp=none "$APP_MACOS/flyingsnowfluffctl"
codesign --force --sign - --timestamp=none "$APP_MACOS/FlyingSnowfluff"
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -e "$OUTPUT_DIR/FlyingSnowfluff.app" ]]; then
  mv "$OUTPUT_DIR/FlyingSnowfluff.app" "$BACKUP_DIR/FlyingSnowfluff.app.$TIMESTAMP"
fi
if [[ -e "$OUTPUT_DIR/FlyingSnowfluff-macOS-arm64.zip" ]]; then
  mv "$OUTPUT_DIR/FlyingSnowfluff-macOS-arm64.zip" "$BACKUP_DIR/FlyingSnowfluff-macOS-arm64.zip.$TIMESTAMP"
fi
if [[ -e "$OUTPUT_DIR/FlyingSnowfluff-CodexPet.zip" ]]; then
  mv "$OUTPUT_DIR/FlyingSnowfluff-CodexPet.zip" "$BACKUP_DIR/FlyingSnowfluff-CodexPet.zip.$TIMESTAMP"
fi
if [[ -e "$OUTPUT_DIR/FlyingSnowfluff-preview.png" ]]; then
  mv "$OUTPUT_DIR/FlyingSnowfluff-preview.png" "$BACKUP_DIR/FlyingSnowfluff-preview.png.$TIMESTAMP"
fi
if [[ -e "$OUTPUT_DIR/安装与使用说明.md" ]]; then
  mv "$OUTPUT_DIR/安装与使用说明.md" "$BACKUP_DIR/安装与使用说明.md.$TIMESTAMP"
fi
SHARE_ZIP_NAME="飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
for artifact in "$SHARE_ZIP_NAME" "$SHARE_ZIP_NAME.sha256"; do
  if [[ -e "$OUTPUT_DIR/$artifact" ]]; then
    mv "$OUTPUT_DIR/$artifact" "$BACKUP_DIR/$artifact.$TIMESTAMP"
  fi
done

cp -R "$APP_BUNDLE" "$OUTPUT_DIR/FlyingSnowfluff.app"
# macOS performs a one-time signature validation on a newly copied executable.
# Warm the helper without emitting an event so hook calls retain their 300 ms fail-open budget.
"$OUTPUT_DIR/FlyingSnowfluff.app/Contents/MacOS/flyingsnowfluffctl" \
  --event userPromptSubmit </dev/null >/dev/null 2>&1 || true
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/FlyingSnowfluff-macOS-arm64.zip"

PET_PACKAGE="$BUILD_DIR/flying-snowfluff-aemeath"
mkdir -p "$PET_PACKAGE"
cp "$PROJECT_DIR/Resources/CodexPet/pet.json" "$PET_PACKAGE/pet.json"
cp "$PROJECT_DIR/Resources/CodexPet/spritesheet.webp" "$PET_PACKAGE/spritesheet.webp"
/usr/bin/ditto -c -k --keepParent "$PET_PACKAGE" "$OUTPUT_DIR/FlyingSnowfluff-CodexPet.zip"
cp "$PROJECT_DIR/Resources/v3/qa/contact-sheet.png" "$OUTPUT_DIR/FlyingSnowfluff-preview.png"
cp "$PROJECT_DIR/Packaging/安装与使用说明.md" "$OUTPUT_DIR/安装与使用说明.md"
cp "$PROJECT_DIR/Packaging/经典台词与来源.md" "$OUTPUT_DIR/经典台词与来源.md"

SHARE_PAYLOAD="$BUILD_DIR/飞行雪绒·爱弥斯"
mkdir -p "$SHARE_PAYLOAD"
cp -R "$APP_BUNDLE" "$SHARE_PAYLOAD/FlyingSnowfluff.app"
cp "$PROJECT_DIR/Packaging/安装与使用说明.md" "$SHARE_PAYLOAD/安装与使用说明.md"
cp "$PROJECT_DIR/Packaging/经典台词与来源.md" "$SHARE_PAYLOAD/经典台词与来源.md"
(
  cd "$SHARE_PAYLOAD"
  shasum -a 256 \
    "FlyingSnowfluff.app/Contents/Info.plist" \
    "FlyingSnowfluff.app/Contents/MacOS/FlyingSnowfluff" \
    "FlyingSnowfluff.app/Contents/MacOS/flyingsnowfluffctl" \
    "FlyingSnowfluff.app/Contents/MacOS/libFlyingSnowfluffCore.dylib" \
    "FlyingSnowfluff.app/Contents/Resources/spritesheet@2x.png" \
    "FlyingSnowfluff.app/Contents/Resources/spritesheet.png" \
    "FlyingSnowfluff.app/Contents/Resources/AppIcon.icns" \
    "FlyingSnowfluff.app/Contents/Resources/Lively/motion.json" \
    FlyingSnowfluff.app/Contents/Resources/Lively/*.png \
    "安装与使用说明.md" "经典台词与来源.md" > SHA256SUMS.txt
)
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$SHARE_PAYLOAD" "$OUTPUT_DIR/$SHARE_ZIP_NAME"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$SHARE_ZIP_NAME" > "$SHARE_ZIP_NAME.sha256"
)

print "Built: $OUTPUT_DIR/FlyingSnowfluff.app"
print "Built: $OUTPUT_DIR/FlyingSnowfluff-macOS-arm64.zip"
print "Built: $OUTPUT_DIR/FlyingSnowfluff-CodexPet.zip"
print "Built: $OUTPUT_DIR/FlyingSnowfluff-preview.png"
print "Built: $OUTPUT_DIR/安装与使用说明.md"
print "Built: $OUTPUT_DIR/$SHARE_ZIP_NAME"
print "Built: $OUTPUT_DIR/$SHARE_ZIP_NAME.sha256"
