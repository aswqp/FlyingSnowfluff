#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: upgrade_app_only.sh --source NEW_APP --backup-dir DIR [options]

Safely replaces only ~/Applications/FlyingSnowfluff.app.

Options:
  --target PATH   Override the target for isolated testing.
  --app-stopped   Assert the caller already stopped the target app.
  --dry-run       Verify the candidate and print the plan without writing.
  -h, --help      Show this help.

This command does not edit Codex hooks, pets/skins, trust records, login items,
Finder aliases, Desktop files, or launchd state.
USAGE
}

SOURCE_APP=""
BACKUP_DIR=""
TARGET_APP="${HOME:?User home is required}/Applications/FlyingSnowfluff.app"
APP_STOPPED=0
DRY_RUN=0

while (( $# > 0 )); do
  case "$1" in
    --source)
      (( $# >= 2 )) || { print -u2 -- "--source requires a path"; exit 64; }
      SOURCE_APP="$2"; shift 2
      ;;
    --backup-dir)
      (( $# >= 2 )) || { print -u2 -- "--backup-dir requires a path"; exit 64; }
      BACKUP_DIR="$2"; shift 2
      ;;
    --target)
      (( $# >= 2 )) || { print -u2 -- "--target requires a path"; exit 64; }
      TARGET_APP="$2"; shift 2
      ;;
    --app-stopped) APP_STOPPED=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -- "Unknown option: $1"; usage >&2; exit 64 ;;
  esac
done

[[ -n "$SOURCE_APP" && -n "$BACKUP_DIR" ]] || { usage >&2; exit 64; }
[[ "$SOURCE_APP" == /* && "$BACKUP_DIR" == /* && "$TARGET_APP" == /* ]] || {
  print -u2 -- "Source, backup, and target paths must be absolute"
  exit 64
}
[[ "$SOURCE_APP" == *.app && -d "$SOURCE_APP" ]] || {
  print -u2 -- "Candidate app does not exist: $SOURCE_APP"
  exit 66
}
[[ "${TARGET_APP:t}" == "FlyingSnowfluff.app" ]] || {
  print -u2 -- "Target basename must be FlyingSnowfluff.app"
  exit 64
}
[[ -d "$TARGET_APP" ]] || {
  print -u2 -- "Existing target app is required for an upgrade: $TARGET_APP"
  exit 66
}
[[ "$BACKUP_DIR" != "$SOURCE_APP"/* && "$BACKUP_DIR" != "$TARGET_APP"/* ]] || {
  print -u2 -- "Backup directory cannot be inside the source or target app"
  exit 64
}

verify_signature() {
  codesign --verify --deep --strict "$1"
}

verify_signature "$SOURCE_APP"

if (( DRY_RUN )); then
  print -- "DRY RUN: would back up $TARGET_APP to $BACKUP_DIR"
  print -- "DRY RUN: would stage and activate $SOURCE_APP"
  print -- "DRY RUN: hooks, Codex skins, trust records, Desktop, and launchd remain untouched"
  exit 0
fi

TARGET_PARENT="${TARGET_APP:h}"
mkdir -p "$TARGET_PARENT" "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ZIP_BACKUP="$BACKUP_DIR/FlyingSnowfluff.app.$STAMP.zip"
PREVIOUS_APP="$BACKUP_DIR/FlyingSnowfluff.app.previous-$STAMP"
FAILED_APP="$BACKUP_DIR/FlyingSnowfluff.app.failed-$STAMP"
STAGE_APP="$TARGET_PARENT/.FlyingSnowfluff.app.stage.$STAMP"
VERIFY_DIR="$(mktemp -d /private/tmp/flying-snowfluff-upgrade-verify.XXXXXX)"
RETIRED=0
ACTIVATED=0
SUCCEEDED=0

safe_remove_stage() {
  [[ -e "$STAGE_APP" ]] || return 0
  [[ "${STAGE_APP:h}" == "$TARGET_PARENT" && "${STAGE_APP:t}" == .FlyingSnowfluff.app.stage.* ]] || {
    print -u2 -- "Refusing unsafe stage cleanup: $STAGE_APP"
    return 70
  }
  rm -rf -- "$STAGE_APP"
}

restore_previous() {
  if (( ACTIVATED )) && [[ -e "$TARGET_APP" ]]; then
    mv "$TARGET_APP" "$FAILED_APP" || {
      print -u2 -- "ROLLBACK INCOMPLETE: could not quarantine failed app"
      return 71
    }
  fi
  if (( RETIRED )) && [[ -d "$PREVIOUS_APP" ]]; then
    /usr/bin/ditto "$PREVIOUS_APP" "$TARGET_APP" || {
      print -u2 -- "ROLLBACK INCOMPLETE: restore $PREVIOUS_APP manually to $TARGET_APP"
      return 71
    }
  fi
}

fail_and_restore() {
  local failure_status="$1"
  restore_previous || failure_status="$?"
  safe_remove_stage || true
  SUCCEEDED=1
  exit "$failure_status"
}

finish() {
  local exit_status="${1:-0}"
  trap - EXIT HUP INT TERM
  rm -rf -- "$VERIFY_DIR"
  if (( ! SUCCEEDED )); then
    restore_previous || exit "$?"
  fi
  safe_remove_stage || true
  exit "$exit_status"
}
trap 'finish $?' EXIT
trap 'finish 129' HUP
trap 'finish 130' INT
trap 'finish 143' TERM

# Preserve two independently useful recovery forms, then prove the ZIP expands
# to byte-identical regular files before touching the installed app.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TARGET_APP" "$ZIP_BACKUP"
/usr/bin/ditto -x -k "$ZIP_BACKUP" "$VERIFY_DIR"
[[ -d "$VERIFY_DIR/FlyingSnowfluff.app" ]]
/usr/bin/diff -qr "$TARGET_APP" "$VERIFY_DIR/FlyingSnowfluff.app"

# Stage on the target filesystem so the final rename does not cross volumes.
/usr/bin/ditto "$SOURCE_APP" "$STAGE_APP"
verify_signature "$STAGE_APP"

if (( ! APP_STOPPED )); then
  TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/FlyingSnowfluff"
  for pid in ${(f)"$(pgrep -x FlyingSnowfluff 2>/dev/null || true)"}; do
    [[ -n "$pid" ]] || continue
    process_command="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    [[ "$process_command" == "$TARGET_EXECUTABLE" ]] || continue
    kill -TERM "$pid"
    for _ in {1..50}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      print -u2 -- "Installed app did not stop cleanly (pid $pid)"
      exit 75
    fi
  done
fi

mv "$TARGET_APP" "$PREVIOUS_APP"
RETIRED=1

# Test-only rollback injection is allowed only for an explicitly overridden
# target below /private/tmp, never for the production Applications path.
if [[ "${FS_UPGRADE_TEST_FAIL_AFTER_RETIRE:-0}" == 1 && "$TARGET_APP" == /private/tmp/* ]]; then
  print -u2 -- "Injected activation failure"
  fail_and_restore 91
fi

mv "$STAGE_APP" "$TARGET_APP"
ACTIVATED=1
if verify_signature "$TARGET_APP"; then
  :
else
  signature_status="$?"
  fail_and_restore "$signature_status"
fi

SUCCEEDED=1
print -- "Upgraded App: $TARGET_APP"
print -- "Restorable App backup: $PREVIOUS_APP"
print -- "Verified ZIP backup: $ZIP_BACKUP"
print -- "Codex hooks, skins, and trust records were not changed"
