#!/bin/bash

# Stop Finance Tracker Application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.app.pids"

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
