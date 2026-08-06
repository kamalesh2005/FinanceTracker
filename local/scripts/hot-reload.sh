#!/bin/bash
# Hot-reload the running Flutter frontend
# Usage: ./local/scripts/hot-reload.sh
#        ./local/scripts/hot-reload.sh --restart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_PID_FILE="$LOCAL_DIR/logs/flutter.pid"

RESTART=0
if [[ "${1:-}" == "--restart" || "${1:-}" == "-Restart" ]]; then
  RESTART=1
fi

if [[ ! -f "$FLUTTER_PID_FILE" ]]; then
  echo "Flutter pid file not found: $FLUTTER_PID_FILE"
  echo "Start the app with ./local/scripts/start.sh first."
  exit 1
fi

PID="$(tr -d '[:space:]' < "$FLUTTER_PID_FILE")"
if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
  echo "Flutter process (pid=$PID) is not running."
  exit 1
fi

if [[ "$RESTART" -eq 1 ]]; then
  echo "Hot restarting Flutter (SIGUSR2) pid=$PID..."
  kill -USR2 "$PID"
  echo "Hot restart signal sent."
else
  echo "Hot reloading Flutter (SIGUSR1) pid=$PID..."
  kill -USR1 "$PID"
  echo "Hot reload signal sent."
fi
