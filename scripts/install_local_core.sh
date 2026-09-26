#!/bin/zsh

if (( ! $+functions[fs_install_verify_output_app] )); then
  fs_install_verify_output_app() {
    codesign --verify --deep --strict "$1"
  }
fi

if (( ! $+functions[fs_install_verify_share_bundle] )); then
  fs_install_verify_share_bundle() {
    local output_app="$1"
    local share_zip="$2"
    local share_sum="$3"
    local share_name="$4"
    local project_dir="$5"
    local check_dir=""
    local payload=""
    local verify_status=0

    [[ "${share_zip:t}" == "$share_name" && -f "$share_zip" && -f "$share_sum" ]] || return 66
    (cd "${share_zip:h}" && shasum -a 256 -c "${share_sum:t}") || return $?
    check_dir="$(mktemp -d /private/tmp/flying-snowfluff-install-share.XXXXXX)" || return $?
    /usr/bin/ditto -x -k "$share_zip" "$check_dir" || { verify_status=$?; rm -rf "$check_dir"; return "$verify_status"; }
    payload="$check_dir/飞行雪绒·爱弥斯"
    if [[ ! -d "$payload/FlyingSnowfluff.app" || ! -f "$payload/安装与使用说明.md" || ! -f "$payload/SHA256SUMS.txt" ]]; then
      rm -rf "$check_dir"
      return 65
    fi
    (cd "$payload" && shasum -a 256 -c SHA256SUMS.txt) || { verify_status=$?; rm -rf "$check_dir"; return "$verify_status"; }
    for relative_path in Contents/Info.plist Contents/MacOS/FlyingSnowfluff Contents/MacOS/flyingsnowfluffctl Contents/MacOS/libFlyingSnowfluffCore.dylib Contents/Resources/spritesheet@2x.png Contents/Resources/spritesheet.png; do
      if ! cmp -s "$output_app/$relative_path" "$payload/FlyingSnowfluff.app/$relative_path"; then
        rm -rf "$check_dir"
        return 65
      fi
    done
    if ! cmp -s "$project_dir/Packaging/安装与使用说明.md" "$payload/安装与使用说明.md"; then
      rm -rf "$check_dir"
      return 65
    fi
    if codesign --verify --deep --strict "$payload/FlyingSnowfluff.app"; then
      verify_status=0
    else
      verify_status=$?
    fi
    rm -rf "$check_dir"
    return "$verify_status"
  }
fi

if (( ! $+functions[fs_install_verify_installed_app] )); then
  fs_install_verify_installed_app() {
    codesign --verify --deep --strict "$1"
  }
fi

if (( ! $+functions[fs_install_prime_helper] )); then
  fs_install_prime_helper() {
    "$1" --event userPromptSubmit </dev/null >/dev/null 2>&1 || true
  }
fi

if (( ! $+functions[fs_install_merge_hooks] )); then
  fs_install_merge_hooks() {
    local hooks_path="$1"
    local helper_path="$2"
    local node_bin="$3"
    local project_dir="$4"
    "$node_bin" "$project_dir/scripts/merge_hooks.cjs" "$hooks_path" "$helper_path"
  }
fi

if (( ! $+functions[fs_install_register_finder_entry] )); then
  fs_install_register_finder_entry() {
    local mode="$1"
    local target_app="$2"
    local desktop_dir="$3"
    local alias_name="$4"
    local project_dir="$5"
    /bin/zsh "$project_dir/scripts/register_finder_entry.sh" "$mode" "$target_app" "$desktop_dir" "$alias_name"
  }
fi

if (( ! $+functions[fs_install_set_permissions] )); then
  fs_install_set_permissions() {
    local target_app="$1"
    chmod 700 "$target_app/Contents/MacOS/FlyingSnowfluff" "$target_app/Contents/MacOS/flyingsnowfluffctl"
    chmod 600 "$2" "$3"
  }
fi

if (( ! $+functions[fs_install_failpoint] )); then
  fs_install_failpoint() {
    return 0
  }
fi

if (( ! $+functions[fs_install_txn_restore_move] )); then
  fs_install_txn_restore_move() {
    mv "$@"
  }
fi

typeset -g FS_INSTALL_TXN_ACTIVE=0
typeset -g FS_INSTALL_TXN_ALIAS_CREATED=0
typeset -g FS_INSTALL_TXN_ALIAS_TARGET=""
typeset -g FS_INSTALL_TXN_ALIAS_DESKTOP=""
typeset -g FS_INSTALL_TXN_ALIAS_NAME=""
typeset -g FS_INSTALL_TXN_PROJECT_DIR=""
typeset -ga FS_INSTALL_TXN_PATHS
typeset -ga FS_INSTALL_TXN_BACKUPS
typeset -ga FS_INSTALL_TXN_PRESENT
typeset -ga FS_INSTALL_TXN_CREATED_DIRS
typeset -ga FS_INSTALL_TXN_ROLLBACK_FAILURES

fs_install_txn_path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

fs_install_txn_remove_path() {
  local entry_path="$1"
  if [[ -d "$entry_path" && ! -L "$entry_path" ]]; then
    rm -rf "$entry_path"
  else
    rm -f "$entry_path"
  fi
}

fs_install_txn_ensure_dir() {
  local directory="$1"
  local parent_directory="${directory:h}"
  if [[ ! -d "$directory" ]]; then
    if [[ "$parent_directory" != "$directory" && ! -d "$parent_directory" ]]; then
      fs_install_txn_ensure_dir "$parent_directory" || return $?
    fi
    mkdir "$directory" || return $?
    FS_INSTALL_TXN_CREATED_DIRS+=("$directory")
  fi
}

fs_install_txn_snapshot() {
  local entry_path="$1"
  local backup="$2"
  local present=0
  if fs_install_txn_path_exists "$entry_path"; then
    present=1
    cp -RP "$entry_path" "$backup" || return $?
  fi
  FS_INSTALL_TXN_PATHS+=("$entry_path")
  FS_INSTALL_TXN_BACKUPS+=("$backup")
  FS_INSTALL_TXN_PRESENT+=("$present")
}

fs_install_txn_rollback() {
  local index=0
  local entry_path=""
  local backup=""
  local present=0
  local directory=""
  local rollback_status=0
  (( FS_INSTALL_TXN_ACTIVE == 1 )) || return 0
  FS_INSTALL_TXN_ACTIVE=0
  FS_INSTALL_TXN_ROLLBACK_FAILURES=()

  if (( FS_INSTALL_TXN_ALIAS_CREATED == 1 )); then
    if fs_install_register_finder_entry remove "$FS_INSTALL_TXN_ALIAS_TARGET" "$FS_INSTALL_TXN_ALIAS_DESKTOP" "$FS_INSTALL_TXN_ALIAS_NAME" "$FS_INSTALL_TXN_PROJECT_DIR" >/dev/null 2>&1; then
      :
    else
      FS_INSTALL_TXN_ROLLBACK_FAILURES+=("alias:$FS_INSTALL_TXN_ALIAS_DESKTOP/$FS_INSTALL_TXN_ALIAS_NAME")
      rollback_status=1
    fi
  fi
  for (( index = ${#FS_INSTALL_TXN_PATHS[@]}; index >= 1; index-- )); do
    entry_path="${FS_INSTALL_TXN_PATHS[$index]}"
    backup="${FS_INSTALL_TXN_BACKUPS[$index]}"
    present="${FS_INSTALL_TXN_PRESENT[$index]}"
    if fs_install_txn_path_exists "$entry_path"; then
      if fs_install_txn_remove_path "$entry_path"; then
        :
      else
        FS_INSTALL_TXN_ROLLBACK_FAILURES+=("remove:$entry_path")
        rollback_status=1
      fi
    fi
    if [[ "$present" == "1" ]] && fs_install_txn_path_exists "$backup"; then
      if fs_install_txn_restore_move "$backup" "$entry_path"; then
        :
      else
        FS_INSTALL_TXN_ROLLBACK_FAILURES+=("restore:$entry_path")
        rollback_status=1
      fi
    elif [[ "$present" == "1" ]]; then
      FS_INSTALL_TXN_ROLLBACK_FAILURES+=("missing-backup:$entry_path")
      rollback_status=1
    fi
  done
  for (( index = ${#FS_INSTALL_TXN_CREATED_DIRS[@]}; index >= 1; index-- )); do
    directory="${FS_INSTALL_TXN_CREATED_DIRS[$index]}"
    if rmdir "$directory" 2>/dev/null; then
      :
    else
      FS_INSTALL_TXN_ROLLBACK_FAILURES+=("directory:$directory")
      rollback_status=1
    fi
  done
  if (( rollback_status != 0 )); then
    print -u2 "ROLLBACK INCOMPLETE: ${FS_INSTALL_TXN_ROLLBACK_FAILURES[*]}"
    return 1
  fi
  return 0
}

fs_install_txn_fail() {
  local failure_status="$1"
  if fs_install_txn_rollback; then
    :
  else
    print -u2 "Installation failed with status $failure_status; rollback is incomplete."
  fi
  trap - ERR HUP INT TERM
  return "$failure_status"
}

fs_install_txn_signal() {
  local signal_name="$1"
  local signal_status="$2"
  if fs_install_txn_rollback; then
    print -u2 "Interrupted by $signal_name; installation transaction rolled back."
  else
    print -u2 "Interrupted by $signal_name; installation transaction rollback is incomplete."
  fi
  trap - ERR HUP INT TERM
  exit "$signal_status"
}

fs_install_txn_require_step() {
  local step="$1"
  local step_status=0
  if fs_install_failpoint "$step"; then
    return 0
  else
    step_status=$?
    return "$step_status"
  fi
}

fs_install_txn_replace() {
  local source_path="$1"
  local destination_path="$2"
  fs_install_txn_remove_path "$destination_path" || return $?
  if [[ -d "$source_path" && ! -L "$source_path" ]]; then
    cp -R "$source_path" "$destination_path"
  else
    cp "$source_path" "$destination_path"
  fi
}

install_local_transaction() {
  local project_dir="$1"
  local artifact_dir="$2"
  local user_base="$3"
  local output_app="$artifact_dir/FlyingSnowfluff.app"
  local target_applications="$user_base/Applications"
  local target_app="$target_applications/FlyingSnowfluff.app"
  local desktop_dir="$user_base/Desktop"
  local share_zip_name="飞行雪绒·爱弥斯-分享包-macOS-arm64.zip"
  local share_zip="$artifact_dir/$share_zip_name"
  local share_sum="$share_zip.sha256"
  local codex_root="$user_base/.codex"
  local pet_root="$codex_root/pets/flying-snowfluff-aemeath"
  local hooks_path="$codex_root/hooks.json"
  local backup_root="$codex_root/flying-snowfluff-backups"
  local timestamp="$(date +%Y%m%d-%H%M%S)"
  local node_bin="${NODE_BIN:-${commands[node]:-}}"
  local alias_name="飞行雪绒·爱弥斯"
  local operation_status=0
  local alias_result=""
  local alias_status=0
  local partial_status=0

  [[ -d "$output_app" ]] || return 1
  [[ -n "$node_bin" && -x "$node_bin" ]] || {
    print -u2 -- "Node.js 22+ is required for the full local hooks installation. Set NODE_BIN if it is not on PATH."
    return 69
  }
  fs_install_verify_output_app "$output_app" || return $?
  fs_install_verify_share_bundle "$output_app" "$share_zip" "$share_sum" "$share_zip_name" "$project_dir" || return $?
  fs_install_register_finder_entry check "$target_app" "$desktop_dir" "$alias_name" "$project_dir" || return $?

  FS_INSTALL_TXN_PATHS=()
  FS_INSTALL_TXN_BACKUPS=()
  FS_INSTALL_TXN_PRESENT=()
  FS_INSTALL_TXN_CREATED_DIRS=()
  FS_INSTALL_TXN_ROLLBACK_FAILURES=()
  FS_INSTALL_TXN_ALIAS_CREATED=0
  FS_INSTALL_TXN_ALIAS_TARGET="$target_app"
  FS_INSTALL_TXN_ALIAS_DESKTOP="$desktop_dir"
  FS_INSTALL_TXN_ALIAS_NAME="$alias_name"
  FS_INSTALL_TXN_PROJECT_DIR="$project_dir"
  FS_INSTALL_TXN_ACTIVE=1
  trap 'fs_install_txn_rollback' ERR
  trap 'fs_install_txn_signal HUP 129' HUP
  trap 'fs_install_txn_signal INT 130' INT
  trap 'fs_install_txn_signal TERM 143' TERM

  fs_install_txn_ensure_dir "$target_applications" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_ensure_dir "$pet_root" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_ensure_dir "$backup_root" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }

  fs_install_txn_snapshot "$target_app" "$backup_root/FlyingSnowfluff.app.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_snapshot "$pet_root/pet.json" "$backup_root/pet.json.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_snapshot "$pet_root/spritesheet.webp" "$backup_root/spritesheet.webp.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_snapshot "$hooks_path" "$backup_root/hooks.json.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_snapshot "$desktop_dir/$share_zip_name" "$backup_root/$share_zip_name.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_snapshot "$desktop_dir/$share_zip_name.sha256" "$backup_root/$share_zip_name.sha256.$timestamp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }

  fs_install_txn_require_step copy-app || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_replace "$output_app" "$target_app" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step copy-pet-json || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_replace "$project_dir/Resources/CodexPet/pet.json" "$pet_root/pet.json" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step copy-sprite || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_replace "$project_dir/Resources/CodexPet/spritesheet.webp" "$pet_root/spritesheet.webp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step set-permissions || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_set_permissions "$target_app" "$pet_root/pet.json" "$pet_root/spritesheet.webp" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step verify-installed-app || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_verify_installed_app "$target_app" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_prime_helper "$target_app/Contents/MacOS/flyingsnowfluffctl" || true
  fs_install_txn_require_step merge-hooks || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_merge_hooks "$hooks_path" "$target_app/Contents/MacOS/flyingsnowfluffctl" "$node_bin" "$project_dir" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step finder-alias || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  if alias_result="$(fs_install_register_finder_entry install "$target_app" "$desktop_dir" "$alias_name" "$project_dir")"; then
    :
  else
    alias_status=$?
    if (( alias_status >= 79 && alias_status <= 84 )); then
      partial_status=$alias_status
    else
      fs_install_txn_fail "$alias_status"
      return $?
    fi
  fi
  [[ "$alias_result" == created* ]] && FS_INSTALL_TXN_ALIAS_CREATED=1
  fs_install_txn_require_step copy-share-zip || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_replace "$share_zip" "$desktop_dir/$share_zip_name" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_require_step copy-share-sum || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }
  fs_install_txn_replace "$share_sum" "$desktop_dir/$share_zip_name.sha256" || { operation_status=$?; fs_install_txn_fail "$operation_status"; return $?; }

  FS_INSTALL_TXN_ACTIVE=0
  trap - ERR HUP INT TERM
  print "Installed app: $target_app"
  print "Installed Codex pet: $pet_root"
  print "Merged hooks: $hooks_path"
  print "Finder app: $target_app"
  print "Desktop shortcut: $desktop_dir/$alias_name"
  print "Desktop share bundle: $desktop_dir/$share_zip_name"
  print "Next: open Codex CLI, enter /hooks, and trust the /hooks page listed flyingsnowfluffctl handlers."
  print "After the current task finishes, restart Codex Desktop and create a new test task."
  if (( partial_status != 0 )); then
    print -u2 "PARTIAL: $alias_result (installer partial status $partial_status)."
    return "$partial_status"
  fi
}
