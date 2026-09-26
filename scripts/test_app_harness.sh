#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
HARNESS="${1:-AppBehaviorHarness}"
BUILD_DIR="/private/tmp/snowfluff-app-tests"
mkdir -p "$BUILD_DIR"
export CLANG_MODULE_CACHE_PATH=/private/tmp/snowfluff-app-cache
export SWIFT_MODULECACHE_PATH=/private/tmp/snowfluff-app-cache
swiftc -O -parse-as-library -emit-library -emit-module -module-name FlyingSnowfluffCore \
  "$PROJECT_DIR"/Sources/FlyingSnowfluffCore/*.swift \
  -emit-module-path "$BUILD_DIR/FlyingSnowfluffCore.swiftmodule" -o "$BUILD_DIR/libFlyingSnowfluffCore.dylib"
APP_SOURCES=()
for source in "$PROJECT_DIR"/Sources/FlyingSnowfluffApp/*.swift; do
  [[ "${source:t}" == main.swift ]] || APP_SOURCES+=("$source")
done
swiftc -O -swift-version 5 -D FLYING_SNOWFLUFF_QA "${APP_SOURCES[@]}" \
  "$PROJECT_DIR/Tests/$HARNESS/main.swift" -I "$BUILD_DIR" -L "$BUILD_DIR" -lFlyingSnowfluffCore \
  -Xlinker -rpath -Xlinker "$BUILD_DIR" -o "$BUILD_DIR/${HARNESS:t}"
export SNOWFLUFF_MOTION_DIR="$PROJECT_DIR/Resources/v3"
if [[ "$HARNESS" == IdlePerformanceHarness || -n "${2:-}" ]]; then
  "$BUILD_DIR/${HARNESS:t}" "$PROJECT_DIR/Resources/App/spritesheet@2x.png" "$PROJECT_DIR/Resources/App/spritesheet.png"
else
  "$BUILD_DIR/${HARNESS:t}" "$PROJECT_DIR/Resources/App/spritesheet@2x.png"
fi
