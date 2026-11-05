#!/usr/bin/env bash
# Runs a build/test command while watching the memory of the Swift compilers it
# starts, and stops it before the machine runs out. Two unbounded parallel Swift
# builds reached ~150 GB of compiler memory on a 26 GB Mac and froze it (2026-11-05).
#
# Only the command's own process tree is measured and stopped, so another
# project compiling at the same time (Xcode, another worktree) is left alone.
#
# Usage: Scripts/guarded.sh <command...>
# Limits (KB of resident memory): one compiler process, and all of ours together.
set -uo pipefail

LIMIT_ONE_KB="${GUARD_LIMIT_ONE_KB:-6000000}"
LIMIT_ALL_KB="${GUARD_LIMIT_ALL_KB:-14000000}"

# Every process below $1, depth first.
descendants() {
  local child
  for child in $(pgrep -P "$1"); do
    echo "$child"
    descendants "$child"
  done
}

"$@" &
root=$!
peak_one=0
peak_all=0
while kill -0 "$root" 2>/dev/null; do
  pids=$(descendants "$root" | paste -sd, -)
  one=0
  all=0
  compilers=""
  if [[ -n "$pids" ]]; then
    while read -r pid rss comm; do
      [[ "$comm" == *swift-frontend* ]] || continue
      compilers+="$pid "
      all=$((all + rss))
      ((rss > one)) && one=$rss
    done < <(ps -o pid=,rss=,comm= -p "$pids" 2>/dev/null)
  fi
  ((one > peak_one)) && peak_one=$one
  ((all > peak_all)) && peak_all=$all
  if ((one > LIMIT_ONE_KB || all > LIMIT_ALL_KB)); then
    echo "guarded: stopping — one compiler at $((one / 1024)) MB, ours at $((all / 1024)) MB" >&2
    # shellcheck disable=SC2086 # word splitting is the point: one pid per word.
    kill $compilers 2>/dev/null
    kill "$root"
    wait "$root" 2>/dev/null
    exit 99
  fi
  sleep 2
done
wait "$root"
status=$?
echo "guarded: peak compiler memory $((peak_one / 1024)) MB (one), $((peak_all / 1024)) MB (all)" >&2
exit $status
