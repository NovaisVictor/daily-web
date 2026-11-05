#!/usr/bin/env bash
# Runs a build/test command while watching the Swift compiler's memory, and
# stops it before the machine runs out. Two unbounded parallel Swift builds
# reached ~150 GB of compiler memory on a 26 GB Mac and froze it (2026-11-05).
#
# Usage: Scripts/guarded.sh <command...>
# Limits (KB of resident memory): one compiler process, and all of them together.
set -uo pipefail

LIMIT_ONE_KB="${GUARD_LIMIT_ONE_KB:-6000000}"
LIMIT_ALL_KB="${GUARD_LIMIT_ALL_KB:-14000000}"

"$@" &
child=$!
peak_one=0
peak_all=0
while kill -0 "$child" 2>/dev/null; do
  read -r one all < <(ps -axo rss=,comm= | awk '/swift-frontend/ {s+=$1; if ($1>m) m=$1} END {print m+0, s+0}')
  (( one > peak_one )) && peak_one=$one
  (( all > peak_all )) && peak_all=$all
  if (( one > LIMIT_ONE_KB || all > LIMIT_ALL_KB )); then
    echo "guarded: stopping — one compiler at $((one / 1024)) MB, all at $((all / 1024)) MB" >&2
    pkill -f swift-frontend
    kill "$child"
    wait "$child" 2>/dev/null
    exit 99
  fi
  sleep 2
done
wait "$child"
status=$?
echo "guarded: peak compiler memory $((peak_one / 1024)) MB (one), $((peak_all / 1024)) MB (all)" >&2
exit $status
