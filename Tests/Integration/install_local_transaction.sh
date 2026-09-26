#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d /private/tmp/flying-snowfluff-install-transaction.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
ALIAS_NAME="飞行雪绒·爱弥斯"

typeset CASE_ROOT=""
typeset CASE_PROJECT=""
typeset CASE_WORKSPACE=""
typeset CASE_HOME=""
typeset ORDER_LOG=""
typeset FAIL_AT=""
typeset REGISTER_MODE="success"
typeset MERGE_STATUS=0
typeset RESTORE_MOVE_STATUS=0
typeset PRIME_STATUS=0

setup_case() {
  local case_name="$1"
  local with_originals="$2"
  CASE_ROOT="$TEST_ROOT/$case_name"
  CASE_PROJECT="$CASE_ROOT/project"
  CASE_WORKSPACE="$CASE_ROOT/workspace"
  CASE_HOME="$CASE_ROOT/home"
  ORDER_LOG="$CASE_ROOT/order.log"
  FAIL_AT=""
  REGISTER_MODE="success"
  MERGE_STATUS=0
  RESTORE_MOVE_STATUS=0
  PRIME_STATUS=0

  mkdir -p "$CASE_PROJECT/Resources/CodexPet" "$CASE_WORKSPACE/outputs/FlyingSnowfluff.app" "$CASE_HOME/Desktop"
  print -r -- "new-app" > "$CASE_WORKSPACE/outputs/FlyingSnowfluff.app/marker"
  print -r -- "new-pet" > "$CASE_PROJECT/Resources/CodexPet/pet.json"
  print -r -- "new-sprite" > "$CASE_PROJECT/Resources/CodexPet/spritesheet.webp"
  print -r -- "new-share" > "$CASE_WORKSPACE/outputs/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
  print -r -- "new-sum" > "$CASE_WORKSPACE/outputs/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256"

  if [[ "$with_originals" == "yes" ]]; then
    mkdir -p "$CASE_HOME/Applications/FlyingSnowfluff.app" "$CASE_HOME/.codex/pets/flying-snowfluff-aemeath"
    print -r -- "old-app" > "$CASE_HOME/Applications/FlyingSnowfluff.app/marker"
    print -r -- "old-pet" > "$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/pet.json"
    print -r -- "old-sprite" > "$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/spritesheet.webp"
    print -r -- "old-hooks" > "$CASE_HOME/.codex/hooks.json"
    print -r -- "old-share" > "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
    print -r -- "old-sum" > "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256"
  fi
}

fs_install_verify_output_app() {
  print -r -- "codesign" >> "$ORDER_LOG"
  return "${VERIFY_OUTPUT_STATUS:-0}"
}

fs_install_verify_share_bundle() {
  print -r -- "share-zip" >> "$ORDER_LOG"
  return "${VERIFY_SHARE_STATUS:-0}"
}

fs_install_merge_hooks() {
  local hooks_path="$1"
  print -r -- "merge-hooks" >> "$ORDER_LOG"
  print -r -- "new-hooks" > "$hooks_path"
  return "$MERGE_STATUS"
}

fs_install_set_permissions() {
  return 0
}

fs_install_verify_installed_app() {
  print -r -- "verify-installed-app" >> "$ORDER_LOG"
  return 0
}

fs_install_prime_helper() {
  print -r -- "prime-helper:$1" >> "$ORDER_LOG"
  return "$PRIME_STATUS"
}

fs_install_register_finder_entry() {
  local mode="$1"
  local _target_app="$2"
  local desktop_dir="$3"
  local alias_name="$4"
  case "$mode" in
    check)
      print "available"
      ;;
    install)
      : > "$desktop_dir/$alias_name"
      if [[ "$REGISTER_MODE" == "partial" ]]; then
        print "created partial-launch-services"
        return 79
      fi
      if [[ "$REGISTER_MODE" == "alias-failure" ]]; then
        rm -f "$desktop_dir/$alias_name"
        return 17
      fi
      print "created"
      ;;
    remove)
      rm -f "$desktop_dir/$alias_name"
      print "removed"
      ;;
    *)
      return 64
      ;;
  esac
}

fs_install_failpoint() {
  [[ -z "$FAIL_AT" || "$FAIL_AT" != "$1" ]] || return 91
}

fs_install_txn_restore_move() {
  [[ "$RESTORE_MOVE_STATUS" == "0" ]] || return "$RESTORE_MOVE_STATUS"
  mv "$@"
}

source "$PROJECT_DIR/scripts/install_local_core.sh"

assert_originals_restored() {
  [[ "$(<"$CASE_HOME/Applications/FlyingSnowfluff.app/marker")" == "old-app" ]]
  [[ "$(<"$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/pet.json")" == "old-pet" ]]
  [[ "$(<"$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/spritesheet.webp")" == "old-sprite" ]]
  [[ "$(<"$CASE_HOME/.codex/hooks.json")" == "old-hooks" ]]
  [[ "$(<"$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip")" == "old-share" ]]
  [[ "$(<"$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256")" == "old-sum" ]]
  [[ ! -e "$CASE_HOME/Desktop/$ALIAS_NAME" ]]
}

assert_original_absence_restored() {
  [[ ! -e "$CASE_HOME/Applications" ]]
  [[ ! -e "$CASE_HOME/.codex" ]]
  [[ ! -e "$CASE_HOME/Applications/FlyingSnowfluff.app" ]]
  [[ ! -e "$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/pet.json" ]]
  [[ ! -e "$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/spritesheet.webp" ]]
  [[ ! -e "$CASE_HOME/.codex/hooks.json" ]]
  [[ ! -e "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip" ]]
  [[ ! -e "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip.sha256" ]]
  [[ ! -e "$CASE_HOME/Desktop/$ALIAS_NAME" ]]
}

run_install() {
  install_local_transaction "$CASE_PROJECT" "$CASE_WORKSPACE/outputs" "$CASE_HOME"
}

setup_case "preflight-signature" "no"
VERIFY_OUTPUT_STATUS=41
VERIFY_SHARE_STATUS=0
if run_install; then
  print -u2 "FAIL: invalid candidate signature was accepted"
  exit 1
else
  [[ "$?" -eq 41 ]]
fi
[[ "$(<"$ORDER_LOG")" == "codesign" ]]
[[ ! -e "$CASE_HOME/Applications" ]]
[[ ! -e "$CASE_HOME/.codex" ]]

setup_case "preflight-share" "no"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=42
if run_install; then
  print -u2 "FAIL: invalid share ZIP was accepted"
  exit 1
else
  [[ "$?" -eq 42 ]]
fi
[[ "$(<"$ORDER_LOG")" == $'codesign\nshare-zip' ]]
[[ ! -e "$CASE_HOME/Applications" ]]
[[ ! -e "$CASE_HOME/.codex" ]]

for failure_step in copy-app copy-pet-json copy-sprite merge-hooks copy-share-zip copy-share-sum; do
  setup_case "rollback-$failure_step" "yes"
  VERIFY_OUTPUT_STATUS=0
  VERIFY_SHARE_STATUS=0
  FAIL_AT="$failure_step"
  if [[ "$failure_step" == "merge-hooks" ]]; then
    FAIL_AT=""
    MERGE_STATUS=92
  fi
  if run_install; then
    print -u2 "FAIL: $failure_step failure was accepted"
    exit 1
  fi
  assert_originals_restored
done

setup_case "rollback-alias-failure" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
REGISTER_MODE="alias-failure"
if run_install; then
  print -u2 "FAIL: alias failure was accepted"
  exit 1
fi
assert_originals_restored

setup_case "rollback-absence" "no"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
FAIL_AT="copy-sprite"
if run_install; then
  print -u2 "FAIL: absent-state failure was accepted"
  exit 1
fi
assert_original_absence_restored

setup_case "rollback-dangling-share-link" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
rm -f "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
ln -s "$CASE_ROOT/original-share-missing.zip" "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
FAIL_AT="copy-share-sum"
if run_install; then
  print -u2 "FAIL: dangling-share rollback failure was accepted"
  exit 1
fi
[[ -L "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip" ]]
[[ "$(readlink "$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip")" == "$CASE_ROOT/original-share-missing.zip" ]]

setup_case "rollback-incomplete" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
FAIL_AT="copy-sprite"
RESTORE_MOVE_STATUS=95
ROLLBACK_OUTPUT=""
if ROLLBACK_OUTPUT="$(run_install 2>&1)"; then
  print -u2 "FAIL: incomplete rollback failure was accepted"
  exit 1
else
  [[ "$?" -eq 91 ]]
fi
[[ "$ROLLBACK_OUTPUT" == *"ROLLBACK INCOMPLETE"* ]]

SIGNAL_ROOT="$TEST_ROOT/signal"
SIGNAL_TARGET="$SIGNAL_ROOT/target"
SIGNAL_BACKUP="$SIGNAL_ROOT/backup"
mkdir -p "$SIGNAL_ROOT"
print -r -- "new-value" > "$SIGNAL_TARGET"
print -r -- "old-value" > "$SIGNAL_BACKUP"
if /bin/zsh -c '
  source "$1"
  FS_INSTALL_TXN_ACTIVE=1
  FS_INSTALL_TXN_ALIAS_CREATED=0
  FS_INSTALL_TXN_PATHS=("$2")
  FS_INSTALL_TXN_BACKUPS=("$3")
  FS_INSTALL_TXN_PRESENT=(1)
  FS_INSTALL_TXN_CREATED_DIRS=()
  trap "fs_install_txn_signal TERM 143" TERM
  kill -TERM $$
  exit 1
' signal-child "$PROJECT_DIR/scripts/install_local_core.sh" "$SIGNAL_TARGET" "$SIGNAL_BACKUP"; then
  print -u2 "FAIL: TERM handler returned instead of exiting"
  exit 1
else
  [[ "$?" -eq 143 ]]
fi
[[ "$(<"$SIGNAL_TARGET")" == "old-value" ]]

setup_case "launch-services-partial" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
REGISTER_MODE="partial"
if run_install; then
  print -u2 "FAIL: Launch Services partial completion was hidden"
  exit 1
else
  [[ "$?" -eq 79 ]]
fi
[[ "$(<"$CASE_HOME/Applications/FlyingSnowfluff.app/marker")" == "new-app" ]]
[[ "$(<"$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip")" == "new-share" ]]
[[ -e "$CASE_HOME/Desktop/$ALIAS_NAME" ]]

setup_case "success" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
REGISTER_MODE="success"
run_install
[[ "$(tail -n 3 "$ORDER_LOG")" == $'verify-installed-app\nprime-helper:'"$CASE_HOME"$'/Applications/FlyingSnowfluff.app/Contents/MacOS/flyingsnowfluffctl\nmerge-hooks' ]]
[[ "$(<"$CASE_HOME/Applications/FlyingSnowfluff.app/marker")" == "new-app" ]]
[[ "$(<"$CASE_HOME/.codex/pets/flying-snowfluff-aemeath/pet.json")" == "new-pet" ]]
[[ "$(<"$CASE_HOME/.codex/hooks.json")" == "new-hooks" ]]
[[ "$(<"$CASE_HOME/Desktop/飞行雪绒·爱弥斯-分享包-macOS-arm64.zip")" == "new-share" ]]
[[ -e "$CASE_HOME/Desktop/$ALIAS_NAME" ]]

setup_case "prime-fail-open" "yes"
VERIFY_OUTPUT_STATUS=0
VERIFY_SHARE_STATUS=0
PRIME_STATUS=77
run_install
[[ "$(tail -n 3 "$ORDER_LOG")" == $'verify-installed-app\nprime-helper:'"$CASE_HOME"$'/Applications/FlyingSnowfluff.app/Contents/MacOS/flyingsnowfluffctl\nmerge-hooks' ]]
[[ "$(<"$CASE_HOME/Applications/FlyingSnowfluff.app/marker")" == "new-app" ]]

print "PASS: install transaction preflight, rollback, Launch Services partial, and success"
