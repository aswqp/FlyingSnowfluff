#!/bin/zsh
set -euo pipefail

HELPER="${1:?usage: helper_fail_open.sh /path/to/flyingsnowfluffctl}"
python3 "${0:A:h}/helper_fail_open.py" "$HELPER"
