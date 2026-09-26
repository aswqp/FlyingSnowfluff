#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h:h}"
failures=()

for relative_path in .gitignore README.md VERSION CHANGELOG.md NOTICE.md scripts/verify_repository.sh; do
  [[ -e "$PROJECT_DIR/$relative_path" ]] || failures+=("missing $relative_path")
done

if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
  for pattern in '.build*/' 'dist/' 'work/' '.superpowers/' \
    'Resources/v3/qa/preview-frames/' 'Resources/v3/qa/runtime/'; do
    grep -Fqx "$pattern" "$PROJECT_DIR/.gitignore" || failures+=(".gitignore missing $pattern")
  done
fi

if [[ -x "$PROJECT_DIR/scripts/verify_repository.sh" ]]; then
  if ! verifier_output="$("$PROJECT_DIR/scripts/verify_repository.sh" 2>&1)"; then
    failures+=("repository verifier failed: $verifier_output")
  fi
else
  failures+=("scripts/verify_repository.sh is not executable")
fi

personal_root='/Users/'"haiyangqiu"
runtime_marker='codex-primary-'"runtime"
if personal_paths="$(rg -n -F -e "$personal_root" -e "$runtime_marker" \
  "$PROJECT_DIR/scripts" "$PROJECT_DIR/toolchain" 2>/dev/null)"; then
  failures+=("machine-specific build path: $personal_paths")
fi

grep -Fq 'OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"' "$PROJECT_DIR/scripts/build_release.sh" \
  || failures+=("build_release.sh does not default to project-local dist/")

if (( ${#failures[@]} > 0 )); then
  print -u2 -- "FAIL: repository publication contract"
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

print "PASS: repository publication contract"
