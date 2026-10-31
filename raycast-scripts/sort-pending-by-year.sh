#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sort Pending Pictures by Year
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🗂️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Dry run", "value": "dry"}, {"title": "Move", "value": "move"}] }

# Documentation:
# @raycast.description Move files from Pending_Pictures root into YYYY subfolders (year taken from the yyyyMMddHHmm_ filename prefix)
# @raycast.author VitalijsDraba
# @raycast.authorURL https://github.com/VitalijsDraba

DEST_IMAGES="$HOME/Library/CloudStorage/OneDrive-Personal/Pictures/Pending_Pictures"
MODE="${1:-dry}"
LOG_FILE="$HOME/Desktop/sort-pending-$(date '+%Y%m%d-%H%M%S')-${MODE}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

if [ ! -d "$DEST_IMAGES" ]; then
  echo "❌ Folder not found: $DEST_IMAGES"
  exit 1
fi

echo "Mode: ${MODE} | Log: ${LOG_FILE}"
moved=0; dup=0; conflict=0; skipped=0

while IFS= read -r -d '' f; do
  name=$(basename "$f")
  # Expect names like 202405121830_IMG_1234.jpg
  if [[ ! "$name" =~ ^([0-9]{4})[0-9]{8}_ ]]; then
    echo "  ? no date prefix: $name"
    skipped=$((skipped + 1))
    continue
  fi
  year="${BASH_REMATCH[1]}"
  target="${DEST_IMAGES}/${year}/${name}"

  if [ -e "$target" ]; then
    if [ "$(stat -f %z "$f")" = "$(stat -f %z "$target")" ]; then
      echo "  = duplicate (left in root): $name"
      dup=$((dup + 1))
    else
      echo "  ! conflict, different size (left in root): $name"
      conflict=$((conflict + 1))
    fi
    continue
  fi

  echo "  → ${year}/${name}"
  if [ "$MODE" = "move" ]; then
    mkdir -p "${DEST_IMAGES}/${year}"
    mv -n "$f" "$target"
  fi
  moved=$((moved + 1))
done < <(find "$DEST_IMAGES" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -print0)

echo
echo "✅ Done (${MODE}): moved ${moved}, duplicates ${dup}, conflicts ${conflict}, no prefix ${skipped}"
echo "📄 Log saved: $LOG_FILE"
