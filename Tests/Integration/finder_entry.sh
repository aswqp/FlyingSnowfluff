#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
APP_PATH="${APP_PATH:-$PROJECT_DIR/dist/FlyingSnowfluff.app}"
TEST_ROOT="$(mktemp -d /private/tmp/flying-snowfluff-finder-entry.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
GOOD_DESKTOP="$TEST_ROOT/good"
BAD_DESKTOP="$TEST_ROOT/conflict"
WRONG_TARGET_DESKTOP="$TEST_ROOT/wrong-target"
FOLDER_DESKTOP="$TEST_ROOT/folder-conflict"
BROKEN_ALIAS_DESKTOP="$TEST_ROOT/broken-alias"
LS_FAILURE_DESKTOP="$TEST_ROOT/ls-failure"
BROKEN_TARGET="$TEST_ROOT/vanished-target.app"
SYMLINK_APP="$TEST_ROOT/FlyingSnowfluff-link.app"
DOTDOT_APP="$PROJECT_DIR/dist/../dist/FlyingSnowfluff.app"
LSREGISTER_LOG="$TEST_ROOT/lsregister.log"
LSREGISTER_EXIT=0
SYSTEM_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
mkdir -p "$GOOD_DESKTOP" "$BAD_DESKTOP" "$WRONG_TARGET_DESKTOP" \
  "$FOLDER_DESKTOP" "$BROKEN_ALIAS_DESKTOP" "$LS_FAILURE_DESKTOP" "$BROKEN_TARGET"
ln -s "$APP_PATH" "$SYMLINK_APP"

recording_lsregister() {
  print -r -- "$@" >> "$LSREGISTER_LOG"
  return "$LSREGISTER_EXIT"
}

source "$PROJECT_DIR/scripts/register_finder_entry_core.sh"

[[ -d "$APP_PATH" ]]
[[ "$(<"$PROJECT_DIR/scripts/register_finder_entry.sh")" == *"LSREGISTER=\"$SYSTEM_LSREGISTER\""* ]]
[[ "$(<"$PROJECT_DIR/scripts/register_finder_entry.sh")" != *'${LSREGISTER'* ]]
/bin/zsh "$PROJECT_DIR/scripts/register_finder_entry.sh" check "$APP_PATH" "$GOOD_DESKTOP"
[[ "$(register_finder_entry "$PROJECT_DIR" install "$APP_PATH" "$GOOD_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)" == *"created"* ]]
[[ "$(tail -n 1 "$LSREGISTER_LOG")" == "-f $APP_PATH" ]]
[[ -e "$GOOD_DESKTOP/飞行雪绒·爱弥斯" ]]
[[ "$(register_finder_entry "$PROJECT_DIR" install "$SYMLINK_APP" "$GOOD_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)" == *"reused"* ]]
[[ "$(tail -n 1 "$LSREGISTER_LOG")" == "-f $SYMLINK_APP" ]]
[[ "$(register_finder_entry "$PROJECT_DIR" install "$DOTDOT_APP" "$GOOD_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)" == *"reused"* ]]
[[ "$(tail -n 1 "$LSREGISTER_LOG")" == "-f $DOTDOT_APP" ]]

touch "$BAD_DESKTOP/飞行雪绒·爱弥斯"
if register_finder_entry "$PROJECT_DIR" check "$APP_PATH" "$BAD_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister; then
  print -u2 "FAIL: ordinary-file conflict was accepted"
  exit 1
fi
[[ -f "$BAD_DESKTOP/飞行雪绒·爱弥斯" ]]

mkdir "$FOLDER_DESKTOP/飞行雪绒·爱弥斯"
if register_finder_entry "$PROJECT_DIR" check "$APP_PATH" "$FOLDER_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister; then
  print -u2 "FAIL: folder conflict was accepted"
  exit 1
fi
[[ -d "$FOLDER_DESKTOP/飞行雪绒·爱弥斯" ]]

[[ "$(register_finder_entry "$PROJECT_DIR" install "$APP_PATH/Contents" "$WRONG_TARGET_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)" == *"created"* ]]
if register_finder_entry "$PROJECT_DIR" check "$APP_PATH" "$WRONG_TARGET_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister; then
  print -u2 "FAIL: wrong-target alias was accepted"
  exit 1
fi
[[ -e "$WRONG_TARGET_DESKTOP/飞行雪绒·爱弥斯" ]]

[[ "$(register_finder_entry "$PROJECT_DIR" install "$BROKEN_TARGET" "$BROKEN_ALIAS_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)" == *"created"* ]]
rmdir "$BROKEN_TARGET"
if register_finder_entry "$PROJECT_DIR" check "$APP_PATH" "$BROKEN_ALIAS_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister; then
  print -u2 "FAIL: broken Finder alias conflict was accepted"
  exit 1
fi

LSREGISTER_EXIT=23
PARTIAL_RESULT=""
if PARTIAL_RESULT="$(register_finder_entry "$PROJECT_DIR" install "$APP_PATH" "$LS_FAILURE_DESKTOP" "飞行雪绒·爱弥斯" recording_lsregister)"; then
  print -u2 "FAIL: Launch Services partial completion was hidden"
  exit 1
else
  [[ "$?" -eq 79 ]]
fi
[[ "$PARTIAL_RESULT" == *"created partial-launch-services"* ]]
[[ "$(tail -n 1 "$LSREGISTER_LOG")" == "-f $APP_PATH" ]]
[[ -e "$LS_FAILURE_DESKTOP/飞行雪绒·爱弥斯" ]]
print "PASS: Finder entry create, reuse, and conflict protection"
