#!/bin/bash

# Stop Finance Tracker Application
# Use --restart to stop, then rebuild and start again in RELEASE mode.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$LOCAL_DIR/logs/.app.pids"

RESTART=0
DEBUG=0
for arg in "$@"; do
  case "$arg" in
    --restart|-Restart) RESTART=1 ;;
    --debug|-Debug) DEBUG=1 ;;
  esac
done

echo "Stopping Finance Tracker application..."

if [[ -f "$PID_FILE" ]]; then
  while read -r pid; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "  Stopping PID $pid"
      kill "$pid" 2>/dev/null || true
    fi
  done < "$PID_FILE"
  rm -f "$PID_FILE"
fi

# Kill any running Go backend processes
echo "Stopping Go backend..."
pkill -f "financetracker" 2>/dev/null || true
pkill -f "go run main.go" 2>/dev/null || true

# Kill any process using app ports
echo "Stopping processes on ports 8080 and 3000..."
if command -v lsof >/dev/null 2>&1; then
  lsof -ti:8080 | xargs kill -9 2>/dev/null || true
  lsof -ti:3000 | xargs kill -9 2>/dev/null || true
fi

# Kill any Flutter processes for this app
echo "Stopping Flutter frontend..."
pkill -f "flutter run" 2>/dev/null || true

echo "All processes stopped."

if [[ "$RESTART" -eq 1 ]]; then
  echo ""
  if [[ "$DEBUG" -eq 1 ]]; then
    echo "Rebuilding and restarting in DEBUG mode..."
    "$SCRIPT_DIR/start.sh" --debug
  else
    echo "Rebuilding and restarting in RELEASE mode..."
    "$SCRIPT_DIR/start.sh"
  fi
fi
