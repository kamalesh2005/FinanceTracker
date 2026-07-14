#!/bin/bash

# Start Finance Tracker Application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Starting Finance Tracker application..."

# Start Go backend
echo "Starting Go backend on port 8080..."
cd "$PROJECT_DIR/backend"
go run main.go &
BACKEND_PID=$!
echo "Backend started with PID: $BACKEND_PID"

# Wait for backend to be ready
echo "Waiting for backend to start..."
sleep 3

# Start Flutter frontend on web
echo "Starting Flutter frontend on web..."
cd "$PROJECT_DIR/frontend"
flutter run -d web-server &
FRONTEND_PID=$!
echo "Frontend started with PID: $FRONTEND_PID"

echo ""
echo "=========================================="
echo "Finance Tracker Application Started"
echo "=========================================="
echo "Backend: http://localhost:8080"
echo "Frontend: Check terminal for web server URL"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop both services"
echo ""

# Wait for both processes
wait $BACKEND_PID $FRONTEND_PID
