#!/bin/bash

# Start Finance Tracker Application
# Defaults to RELEASE mode. Pass --debug for hot-reloadable Flutter debug builds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LOCAL_DIR")"
LOGS_DIR="$LOCAL_DIR/logs"
BUILD_DIR="$LOCAL_DIR/build"
ENV_FILE="$LOCAL_DIR/env/backend.env"
PID_FILE="$LOGS_DIR/.app.pids"
BACKEND_BIN="$BUILD_DIR/financetracker"

DEBUG=0
for arg in "$@"; do
  case "$arg" in
    --debug|-Debug) DEBUG=1 ;;
    --release|-Release) ;; # default; accepted for backwards compatibility
  esac
done

mkdir -p "$LOGS_DIR" "$BUILD_DIR"

echo "Stopping any existing instance..."
"$SCRIPT_DIR/stop.sh"

# The backend reads .env from its own working directory, so the local environment
# file is copied in on every start. This keeps OCI values from ever reaching a
# local run, even if backend/.env was edited by hand.
if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$PROJECT_DIR/backend/.env"
  echo "Using local environment from $ENV_FILE"
else
  echo "WARNING: no local env file at $ENV_FILE. Copy local/env/backend.env.example and fill it in."
fi

echo "Building Go backend..."
cd "$PROJECT_DIR/backend"
if [[ "$DEBUG" -eq 1 ]]; then
  go build -o "$BACKEND_BIN" .
else
  go build -ldflags="-s -w" -o "$BACKEND_BIN" .
fi
if [[ $? -ne 0 ]]; then
  echo "Backend build failed"
  exit 1
fi

if [[ "$DEBUG" -eq 1 ]]; then
  unset GIN_MODE
  echo "Starting Go backend on port 8080..."
else
  export GIN_MODE=release
  echo "Starting Go backend on port 8080 (GIN_MODE=release)..."
fi
cd "$PROJECT_DIR/backend"
"$BACKEND_BIN" > "$LOGS_DIR/backend.log" 2>&1 &
BACKEND_PID=$!

echo "Waiting for backend to start..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:8080/api/v1/portfolio/summary" >/dev/null 2>&1 || \
     (command -v lsof >/dev/null 2>&1 && lsof -ti:8080 >/dev/null 2>&1); then
    break
  fi
  sleep 0.5
done

MODE_LABEL="release"
FLUTTER_ARGS=(-d chrome --web-port=3000)
if [[ "$DEBUG" -eq 1 ]]; then
  MODE_LABEL="debug"
else
  FLUTTER_ARGS+=(--release)
fi

echo "Starting Flutter frontend on web (port 3000, $MODE_LABEL)..."
cd "$PROJECT_DIR/frontend"
FLUTTER_PID_FILE="$LOGS_DIR/flutter.pid"
rm -f "$FLUTTER_PID_FILE"
flutter run "${FLUTTER_ARGS[@]}" --pid-file "$FLUTTER_PID_FILE" > "$LOGS_DIR/frontend.log" 2>&1 &
FRONTEND_PID=$!

printf "%s\n%s\n" "$BACKEND_PID" "$FRONTEND_PID" > "$PID_FILE"

echo ""
echo "=========================================="
echo "Finance Tracker Application Started ($MODE_LABEL)"
echo "=========================================="
echo "Backend:  http://localhost:8080"
echo "Frontend: http://localhost:3000"
echo "Mode:     $MODE_LABEL"
echo "Logs:     $LOGS_DIR"
echo "PIDs:     backend=$BACKEND_PID frontend=$FRONTEND_PID"
if [[ "$DEBUG" -eq 1 ]]; then
  echo "Reload:   ./local/scripts/hot-reload.sh"
  echo "Restart:  ./local/scripts/hot-reload.sh --restart"
else
  echo "Restart:  ./local/scripts/stop.sh --restart"
fi
echo "Stop with: ./local/scripts/stop.sh"
echo "=========================================="
