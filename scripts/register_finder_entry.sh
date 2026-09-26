#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
MODE="${1:?mode check or install is required}"
TARGET_APP="${2:?target app is required}"
DESKTOP_DIR="${3:?desktop directory is required}"
ALIAS_NAME="${4:-飞行雪绒·爱弥斯}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

source "$PROJECT_DIR/scripts/register_finder_entry_core.sh"
register_finder_entry "$PROJECT_DIR" "$MODE" "$TARGET_APP" "$DESKTOP_DIR" "$ALIAS_NAME" "$LSREGISTER"
