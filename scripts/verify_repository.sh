#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
MAX_BYTES=$((100 * 1024 * 1024))
failures=()
candidate_count=0

required=(
  README.md VERSION CHANGELOG.md NOTICE.md Package.swift
  Packaging/Info.plist Sources Tests Resources scripts
)
for relative_path in "${required[@]}"; do
  [[ -e "$PROJECT_DIR/$relative_path" ]] || failures+=("missing required path: $relative_path")
done

candidate_file="$(mktemp /private/tmp/flying-snowfluff-repository-files.XXXXXX)"
trap 'rm -f "$candidate_file"' EXIT
git -C "$PROJECT_DIR" ls-files --cached --others --exclude-standard -z > "$candidate_file"

while IFS= read -r -d '' relative_path; do
  absolute_path="$PROJECT_DIR/$relative_path"
  [[ -f "$absolute_path" && ! -L "$absolute_path" ]] || continue
  (( candidate_count += 1 ))
  file_size="$(stat -f %z "$absolute_path")"
  (( file_size <= MAX_BYTES )) || failures+=("file exceeds 100 MiB: $relative_path ($file_size bytes)")

  case "$relative_path" in
    *.swift|*.sh|*.cjs|*.js|*.json|*.md|*.plist|*.yml|*.yaml|*.txt|Package.swift|VERSION)
      token_prefix='gh''p_'
      fine_token_prefix='github_pat_'
      private_key_marker='BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
      secret_pattern="${token_prefix}[A-Za-z0-9]{20,}|${fine_token_prefix}[A-Za-z0-9_]{20,}|${private_key_marker}"
      if LC_ALL=C rg -n -i -e "$secret_pattern" "$absolute_path" >/dev/null 2>&1; then
        failures+=("credential-like content: $relative_path")
      fi
      personal_home='/Users/'"haiyangqiu"
      temporary_marker='Temporary''Items/'
      socket_marker='flying-snowfluff-''501.sock'
      if LC_ALL=C rg -n -F -e "$personal_home" -e "$temporary_marker" -e "$socket_marker" \
        "$absolute_path" >/dev/null 2>&1; then
        failures+=("machine-specific personal path: $relative_path")
      fi
      ;;
  esac
done < "$candidate_file"

(( candidate_count > 0 )) || failures+=("no publication candidates found")

for ignored_probe in \
  .build/example \
  dist/example \
  work/example \
  .superpowers/example \
  Resources/v3/qa/preview-frames/example.png \
  Resources/v3/qa/runtime/example.png; do
  git -C "$PROJECT_DIR" check-ignore -q "$ignored_probe" || failures+=("ignore rule not effective: $ignored_probe")
done

if (( ${#failures[@]} > 0 )); then
  print -u2 -- "FAIL: repository verification"
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

print "PASS: repository verification ($candidate_count candidate files, max file <= 100 MiB, no credential pattern matches)"
