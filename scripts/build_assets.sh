#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_IMAGE="${1:-$PROJECT_DIR/Resources/v2/aemeath-pose-sheet-v2-alpha.png}"
NODE_BIN="${NODE_BIN:-${commands[node]:-}}"
NODE_MODULES="${NODE_MODULES:-$PROJECT_DIR/node_modules}"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  print -u2 "Missing pose sheet: $SOURCE_IMAGE"
  exit 1
fi
if [[ ! -x "$NODE_BIN" ]]; then
  print -u2 "Node.js 22+ not found. Install Node or set NODE_BIN."
  exit 1
fi
if [[ ! -d "$NODE_MODULES/sharp" ]]; then
  print -u2 "sharp is missing. Run npm install or set NODE_MODULES."
  exit 1
fi

mkdir -p "$PROJECT_DIR/Resources/App" "$PROJECT_DIR/Resources/CodexPet" "$PROJECT_DIR/Resources/QA"

env NODE_PATH="$NODE_MODULES" "$NODE_BIN" "$PROJECT_DIR/scripts/build_sprite_atlases.cjs" \
  "$SOURCE_IMAGE" \
  "$PROJECT_DIR/Resources/App/spritesheet@2x.png" \
  "$PROJECT_DIR/Resources/App/spritesheet.png" \
  "$PROJECT_DIR/Resources/QA/contact-sheet.png" \
  "$PROJECT_DIR/Resources/App/frames@2x" \
  "$PROJECT_DIR/Resources/App/frames@1x"

env NODE_PATH="$NODE_MODULES" "$NODE_BIN" "$PROJECT_DIR/scripts/encode_and_validate_assets.cjs" \
  "$PROJECT_DIR/Resources/App/spritesheet@2x.png" \
  "$PROJECT_DIR/Resources/App/spritesheet.png" \
  "$PROJECT_DIR/Resources/CodexPet/spritesheet.webp" \
  "$PROJECT_DIR/Resources/QA/validation.json" \
  "$SOURCE_IMAGE" \
  "$PROJECT_DIR/Resources/aemeath-pose-sheet-alpha.png"

print "Built App atlases, Codex WebP, and 72 standalone frames at both 2x and 1x."
