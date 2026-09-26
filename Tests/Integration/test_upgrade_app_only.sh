#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d /private/tmp/flying-snowfluff-app-upgrade.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
MOCK_BIN="$TEST_ROOT/bin"
TARGET="$TEST_ROOT/home/Applications/FlyingSnowfluff.app"
SOURCE="$TEST_ROOT/build/FlyingSnowfluff.app"
BACKUPS="$TEST_ROOT/backups"
HOOKS="$TEST_ROOT/home/.codex/hooks.json"
SKIN="$TEST_ROOT/home/.codex/pets/flying-snowfluff-aemeath/pet.json"
mkdir -p "$MOCK_BIN" "$TARGET/Contents/MacOS" "$SOURCE/Contents/MacOS" "${HOOKS:h}" "${SKIN:h}"
print -r -- old-app > "$TARGET/version"
print -r -- new-app > "$SOURCE/version"
print -r -- old-hooks > "$HOOKS"
print -r -- old-skin > "$SKIN"

cat > "$MOCK_BIN/codesign" <<'MOCK'
#!/bin/zsh
set -eu
print -r -- "$*" >> "${CODESIGN_LOG:?}"
if [[ "${FAIL_SOURCE_SIGNATURE:-0}" == 1 && "$*" == *"/build/FlyingSnowfluff.app" ]]; then
  exit 41
fi
if [[ "${FAIL_ACTIVATED_SIGNATURE:-0}" == 1 && "$*" == *"/home/Applications/FlyingSnowfluff.app" ]]; then
  exit 42
fi
exit 0
MOCK
chmod +x "$MOCK_BIN/codesign"
export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export CODESIGN_LOG="$TEST_ROOT/codesign.log"

UPGRADER="$PROJECT_DIR/scripts/upgrade_app_only.sh"

# Invalid candidates fail closed before target or backups are touched.
export FAIL_SOURCE_SIGNATURE=1
if "$UPGRADER" --source "$SOURCE" --backup-dir "$BACKUPS" --target "$TARGET" --app-stopped; then
  print -u2 -- "FAIL: invalid source signature accepted"
  exit 1
fi
[[ "$(<"$TARGET/version")" == old-app ]]
[[ ! -e "$BACKUPS" ]]
unset FAIL_SOURCE_SIGNATURE

# Dry-run preflights but performs no writes.
"$UPGRADER" --source "$SOURCE" --backup-dir "$BACKUPS" --target "$TARGET" --app-stopped --dry-run
[[ "$(<"$TARGET/version")" == old-app ]]
[[ ! -e "$BACKUPS" ]]

# A failure after retiring the old app restores it and preserves its backup.
export FS_UPGRADE_TEST_FAIL_AFTER_RETIRE=1
if "$UPGRADER" --source "$SOURCE" --backup-dir "$BACKUPS" --target "$TARGET" --app-stopped; then
  print -u2 -- "FAIL: injected activation failure accepted"
  exit 1
fi
unset FS_UPGRADE_TEST_FAIL_AFTER_RETIRE
[[ "$(<"$TARGET/version")" == old-app ]]
[[ "$(<"$HOOKS")" == old-hooks ]]
[[ "$(<"$SKIN")" == old-skin ]]
find "$BACKUPS" -name '*.zip' -type f | grep -q .
find "$BACKUPS" -name 'FlyingSnowfluff.app.previous-*' -type d | grep -q .

# A failed signature check after activation also restores the installed app.
export FAIL_ACTIVATED_SIGNATURE=1
if "$UPGRADER" --source "$SOURCE" --backup-dir "$BACKUPS" --target "$TARGET" --app-stopped; then
  print -u2 -- "FAIL: invalid activated copy accepted"
  exit 1
fi
unset FAIL_ACTIVATED_SIGNATURE
[[ "$(<"$TARGET/version")" == old-app ]]
[[ "$(<"$HOOKS")" == old-hooks ]]
[[ "$(<"$SKIN")" == old-skin ]]

# Success atomically replaces only the target app and retains both backup forms.
"$UPGRADER" --source "$SOURCE" --backup-dir "$BACKUPS" --target "$TARGET" --app-stopped
[[ "$(<"$TARGET/version")" == new-app ]]
[[ "$(<"$HOOKS")" == old-hooks ]]
[[ "$(<"$SKIN")" == old-skin ]]
find "$BACKUPS" -name '*.zip' -type f | grep -q .
find "$BACKUPS" -name 'FlyingSnowfluff.app.previous-*' -type d | grep -q .
[[ ! -e "${TARGET:h}/.FlyingSnowfluff.app.stage."* ]]

# Every signature check is deep and strict, including staged copies.
[[ "$(wc -l < "$CODESIGN_LOG" | tr -d ' ')" -ge 5 ]]
while IFS= read -r invocation; do
  [[ "$invocation" == *"--verify --deep --strict"* ]]
done < "$CODESIGN_LOG"

print -- "PASS: app-only preflight, dry-run, rollback, backup retention, and success"
