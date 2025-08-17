#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Convert to H.264
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🎞️

# Documentation:
# @raycast.description Convert all files in a folder to H.264 .mp4
# @raycast.author You
# @raycast.authorURL https://github.com/you

# Ask user to pick a folder via macOS folder picker
FOLDER=$(osascript -e 'POSIX path of (choose folder with prompt "Select a folder to convert videos")')

if [ -z "$FOLDER" ]; then
  echo "❌ No folder selected."
  exit 1
fi

FILES=$(find "$FOLDER" -type f)

for F in $FILES; do
  fnameext=$(basename "$F")
  fname="${fnameext%.*}"
  echo "▶️ Converting: $F → ${fname}.264.mp4"
  ffmpeg -y -i "$F" -c:v libx264 -crf 23 -c:a aac -b:a 192k "${FOLDER}/${fname}.264.mp4"
done

echo "✅ Conversion finished."
