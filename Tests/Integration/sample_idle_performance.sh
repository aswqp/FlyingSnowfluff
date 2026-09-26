#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ '^[0-9]+$' ]]; then
  print -u2 "usage: sample_idle_performance.sh PID"
  exit 2
fi

pid="$1"
sample_file="$(mktemp /private/tmp/flying-snowfluff-idle-samples.XXXXXX)"
trap 'rm -f "$sample_file"' EXIT

for index in {1..13}; do
  if ! ps -p "$pid" -o %cpu=,rss= >> "$sample_file"; then
    print -u2 "FAIL: process $pid exited during idle sampling"
    exit 1
  fi
  [[ "$index" -eq 13 ]] || sleep 10
done

awk '
  { cpu += $1; if ($2 > max_rss) max_rss = $2; count += 1 }
  END {
    average_cpu = cpu / count
    max_rss_mib = max_rss / 1024
    if (average_cpu >= 1 || max_rss_mib >= 100) {
      printf "FAIL: idle average CPU %.2f%%, max RSS %.2f MiB\n", average_cpu, max_rss_mib
      exit 1
    }
    printf "PASS: idle average CPU %.2f%%, max RSS %.2f MiB over 120 seconds\n", average_cpu, max_rss_mib
  }
' "$sample_file"
