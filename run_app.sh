#!/bin/bash

# Terminate background jobs on exit
trap 'kill $(jobs -p) 2>/dev/null' EXIT

echo "Starting Local Image Saver Server..."
python3 save_image_server.py &

echo "Starting Flutter Web application..."
flutter run -d chrome --web-browser-flag "--disable-web-security"
