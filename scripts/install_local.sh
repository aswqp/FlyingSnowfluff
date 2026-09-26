#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
USER_BASE="${HOME:?User home is required}"

source "$PROJECT_DIR/scripts/install_local_core.sh"
if install_local_transaction "$PROJECT_DIR" "$ARTIFACT_DIR" "$USER_BASE"; then
  exit 0
else
  exit "$?"
fi
