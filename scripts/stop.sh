#!/bin/bash

# Stop Finance Tracker Application

echo "Stopping Finance Tracker application..."

# Kill any running Go backend processes
echo "Stopping Go backend..."
pkill -f "go run main.go" 2>/dev/null || true

# Kill any process using port 8080
echo "Stopping processes on port 8080..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true

# Kill any Flutter processes
echo "Stopping Flutter frontend..."
pkill -f "flutter" 2>/dev/null || true

echo "All processes stopped."
