#!/bin/bash

# Terminate background jobs on exit
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Check if port 5001 is already in use
if lsof -i :5001 >/dev/null 2>&1; then
    echo "Local Image Saver Server is already running on port 5001."
else
    echo "Starting Local Image Saver Server..."
    python3 save_image_server.py &
fi

echo "Starting Flutter Web application..."
flutter run -d chrome --web-browser-flag "--disable-web-security"
