#!/bin/sh
set -eu
task_legacy_only=false
case "${1:-}" in
  --legacy-only) task_legacy_only=true ;;
  '') ;;
  *) echo 'Usage: tools/test.sh [--legacy-only]' >&2; exit 2 ;;
esac
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_log=$(mktemp /tmp/ye-ci-tests.XXXXXX)
trap 'rm -f "$task_log"' EXIT
for task_phase in P0 P1 P2 P3 P4 P5Domain P5 P6 P7 P7Night P8; do
  if [ "$task_legacy_only" = true ] && [ "$task_phase" = P8 ]; then continue; fi
  case "$task_phase" in
    P0) task_prefix=p8-p0-regression ;;
    P1) task_prefix=p8-p1-regression ;;
    P2) task_prefix=p8-p2-regression ;;
    P3) task_prefix=p8-p3-regression ;;
    P4) task_prefix=p8-p4-regression ;;
    P5Domain) task_prefix=p8-p5-domain-regression ;;
    P5) task_prefix=p8-p5-regression ;;
    P6) task_prefix=p8-p6-regression ;;
    P7) task_prefix=p8-p7-regression ;;
    P7Night) task_prefix=p8-p7-night-regression ;;
    P8) task_prefix=p8 ;;
  esac
  if ! "$task_root/tools/godot.sh" --headless "tests/${task_phase}Suite.tscn" --log-file "$task_log" -- --report-prefix="$task_prefix"; then
    exit 1
  fi
  # Godot may exit zero after a script error; require a clean log and result marker.
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL[: ]' "$task_log"; then
    exit 1
  fi
  grep -Eq "$task_phase RESULT: [0-9]+ checks, 0 failures" "$task_log"
done

# P8 isolated ghost behavior and active-roster disk/replay boundaries.
for task_suite in P8Ghost P8Persistence P8Observer; do
  if [ "$task_legacy_only" = true ]; then break; fi
  case "$task_suite" in
    P8Ghost) task_prefix=p8-ghost; task_marker=P8Ghost ;;
    P8Persistence) task_prefix=p8-persistence; task_marker='P8 PERSISTENCE' ;;
    P8Observer) task_prefix=p8-observer; task_marker=P8Observer ;;
  esac
  if ! "$task_root/tools/godot.sh" --headless --script "$task_root/tests/${task_suite}Suite.gd" --log-file "$task_log" -- --report-prefix="$task_prefix"; then
    exit 1
  fi
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL[: ]' "$task_log"; then
    exit 1
  fi
  grep -Eq "$task_marker RESULT: [0-9]+ checks, 0 failures" "$task_log"
done
# P6 bridge exercises resumed paid inputs and queued carried actors from disk archives.
if ! "$task_root/tools/godot.sh" --headless --script "$task_root/tests/P6BridgeSuite.gd" --log-file "$task_log" -- --report-prefix=p8-p6-bridge-regression; then
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL[: ]' "$task_log"; then
  exit 1
fi
grep -Eq 'P6Bridge RESULT: [0-9]+ checks, 0 failures' "$task_log"

# Growth persistence and roster identity exercise real event/save/replay boundaries.
for task_suite in P7Persistence P7Carry; do
  case "$task_suite" in
    P7Persistence) task_prefix=p8-p7-persistence-regression ;;
    P7Carry) task_prefix=p8-p7-carry-regression ;;
  esac
  if ! "$task_root/tools/godot.sh" --headless --script "$task_root/tests/${task_suite}Suite.gd" --log-file "$task_log" -- --report-prefix="$task_prefix"; then
    exit 1
  fi
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL[: ]' "$task_log"; then
    exit 1
  fi
  grep -Eq "$task_suite RESULT: [0-9]+ checks, 0 failures" "$task_log"
done
