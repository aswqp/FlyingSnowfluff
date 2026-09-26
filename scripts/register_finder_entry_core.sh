#!/bin/zsh

register_finder_entry() {
  local project_dir="${1:?project directory is required}"
  local mode="${2:?mode check or install is required}"
  local target_app="${3:?target app is required}"
  local desktop_dir="${4:?desktop directory is required}"
  local alias_name="${5:-飞行雪绒·爱弥斯}"
  local lsregister="${6:?lsregister command is required}"
  local lsregister_status=0
  local alias_status=0
  local alias_result=""

  [[ "$mode" == "check" || "$mode" == "install" || "$mode" == "remove" ]] || return 64
  [[ -d "$desktop_dir" ]] || return 66
  if [[ "$mode" == "install" ]]; then
    [[ -d "$target_app" ]] || return 66
    if "$lsregister" -f "$target_app"; then
      :
    else
      lsregister_status=$?
    fi
  fi
  if alias_result=$(/usr/bin/osascript "$project_dir/scripts/create_finder_alias.applescript" \
    "$mode" "$target_app" "$desktop_dir" "$alias_name"); then
    :
  else
    alias_status=$?
    return "$alias_status"
  fi
  if (( lsregister_status != 0 )); then
    print -r -- "$alias_result partial-launch-services=$lsregister_status"
    return 79
  fi
  print -r -- "$alias_result"
}
