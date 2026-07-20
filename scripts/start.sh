#!/bin/bash

# Start Finance Tracker Application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$SCRIPT_DIR/.app.pids"
LOGS_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOGS_DIR"

echo "Stopping any existing instance..."
"$SCRIPT_DIR/stop.sh"

echo "Building Go backend..."
cd "$PROJECT_DIR/backend"
go build -o financetracker .
if [[ $? -ne 0 ]]; then
  echo "Backend build failed"
  exit 1
fi

echo "Starting Go backend on port 8080..."
cd "$PROJECT_DIR/backend"
./financetracker > "$LOGS_DIR/backend.log" 2>&1 &
BACKEND_PID=$!

echo "Waiting for backend to start..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:8080/api/v1/portfolio/summary" >/dev/null 2>&1 || \
     (command -v lsof >/dev/null 2>&1 && lsof -ti:8080 >/dev/null 2>&1); then
    break
  fi
  sleep 0.5
done

echo "Starting Flutter frontend on web (port 3000)..."
cd "$PROJECT_DIR/frontend"
FLUTTER_PID_FILE="$LOGS_DIR/flutter.pid"
rm -f "$FLUTTER_PID_FILE"
flutter run -d chrome --web-port=3000 --pid-file "$FLUTTER_PID_FILE" > "$LOGS_DIR/frontend.log" 2>&1 &
FRONTEND_PID=$!

printf "%s\n%s\n" "$BACKEND_PID" "$FRONTEND_PID" > "$PID_FILE"

echo ""
echo "=========================================="
echo "Finance Tracker Application Started"
echo "=========================================="
echo "Backend:  http://localhost:8080"
echo "Frontend: http://localhost:3000"
echo "Logs:     $LOGS_DIR"
echo "PIDs:     backend=$BACKEND_PID frontend=$FRONTEND_PID"
echo "Reload:   ./scripts/hot-reload.sh"
echo "Restart:  ./scripts/hot-reload.sh --restart"
echo "Stop with: ./scripts/stop.sh"
echo "=========================================="
