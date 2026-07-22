#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---hidden}"
EXECUTABLE_NAME="PulseBar"
APP_NAME="庄Sir的状态栏"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${PULSEBAR_APP_BUNDLE:-$ROOT_DIR/dist/$APP_NAME.app}"
SAMPLES="${PULSEBAR_ENERGY_SAMPLES:-24}"
INTERVAL="${PULSEBAR_ENERGY_INTERVAL:-0.25}"

if [ "$MODE" = "--exercise-disk-close" ]; then
  pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n \
    --env PULSEBAR_SHOW_PANEL_ON_LAUNCH=1 \
    --env PULSEBAR_SHOW_DETAIL_ON_LAUNCH=disk \
    --env PULSEBAR_CLOSE_PANEL_AFTER_SECONDS=1.5 \
    "$APP_BUNDLE"
  sleep 3
elif [ "$MODE" != "--hidden" ]; then
  echo "usage: $0 [--hidden|--exercise-disk-close]" >&2
  exit 2
fi

PID="$(pgrep -x "$EXECUTABLE_NAME" | head -1)"
if [ -z "$PID" ]; then
  echo "FAIL: $EXECUTABLE_NAME is not running" >&2
  exit 1
fi

CPU_TOTAL="0"
TRACKED_CHILD_SAMPLES=0
for _ in $(seq 1 "$SAMPLES"); do
  CPU="$(ps -p "$PID" -o %cpu= | xargs)"
  CPU_TOTAL="$(awk -v total="$CPU_TOTAL" -v cpu="${CPU:-0}" 'BEGIN { printf "%.4f", total + cpu }')"

  while read -r CHILD_PID; do
    [ -n "$CHILD_PID" ] || continue
    COMMAND="$(ps -p "$CHILD_PID" -o comm= | xargs)"
    case "$COMMAND" in
      */du|*/nettop|*/ps)
        TRACKED_CHILD_SAMPLES=$((TRACKED_CHILD_SAMPLES + 1))
        ;;
    esac
  done < <(pgrep -P "$PID" 2>/dev/null || true)

  sleep "$INTERVAL"
done

AVERAGE_CPU="$(awk -v total="$CPU_TOTAL" -v count="$SAMPLES" 'BEGIN { printf "%.2f", total / count }')"
echo "mode=$MODE pid=$PID samples=$SAMPLES average_cpu=${AVERAGE_CPU}% tracked_child_samples=$TRACKED_CHILD_SAMPLES"

if [ "$TRACKED_CHILD_SAMPLES" -ne 0 ]; then
  echo "FAIL: hidden app still owns du, nettop, or ps processes" >&2
  exit 1
fi

echo "PASS: hidden app has no tracked detail-process activity"
