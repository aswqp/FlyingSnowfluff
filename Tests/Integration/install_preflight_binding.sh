#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
WORKSPACE_DIR="${PROJECT_DIR:h:h}"
OUTPUT_APP="$WORKSPACE_DIR/outputs/FlyingSnowfluff.app"
ZIP_NAME="飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
SOURCE_ZIP="$WORKSPACE_DIR/outputs/$ZIP_NAME"
TEST_ROOT="$(mktemp -d /private/tmp/flying-snowfluff-preflight-binding.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
EXTRACT_ROOT="$TEST_ROOT/extracted"
STALE_ZIP="$TEST_ROOT/$ZIP_NAME"
STALE_SUM="$STALE_ZIP.sha256"

[[ -d "$OUTPUT_APP" && -f "$SOURCE_ZIP" ]]
/usr/bin/ditto -x -k "$SOURCE_ZIP" "$EXTRACT_ROOT"
print -r -- "stale package documentation" > "$EXTRACT_ROOT/飞行雪绒·爱弥斯/安装与使用说明.md"
(
  cd "$EXTRACT_ROOT/飞行雪绒·爱弥斯"
  {
    rg -v '  安装与使用说明.md$' SHA256SUMS.txt
    shasum -a 256 "安装与使用说明.md"
  } > "$TEST_ROOT/SHA256SUMS.txt"
  mv "$TEST_ROOT/SHA256SUMS.txt" SHA256SUMS.txt
)
(cd "$EXTRACT_ROOT" && /usr/bin/zip -qry "$STALE_ZIP" "飞行雪绒·爱弥斯")
(cd "$TEST_ROOT" && shasum -a 256 "$ZIP_NAME" > "$STALE_SUM:t")

source "$PROJECT_DIR/scripts/install_local_core.sh"
if fs_install_verify_share_bundle "$OUTPUT_APP" "$STALE_ZIP" "$STALE_SUM" "$ZIP_NAME" "$PROJECT_DIR"; then
  print -u2 "FAIL: stale package documentation was accepted"
  exit 1
fi
print "PASS: install preflight binds share bundle to current packaging"
