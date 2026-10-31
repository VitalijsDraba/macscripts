#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Compress Pending Videos (HEVC)
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🗜️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Dry run (list candidates)", "value": "dry"}, {"title": "Test 5 files", "value": "test5"}, {"title": "Compress all", "value": "all"}] }

# Documentation:
# @raycast.description Re-encode videos in Pending_Video to HEVC (VideoToolbox) and save as yyyyMMdd_HHmmss_hevc.mp4
# @raycast.author VitalijsDraba
# @raycast.authorURL https://github.com/VitalijsDraba

DEST_VIDEOS="$HOME/Library/CloudStorage/OneDrive-Personal/Videos/Pending_Video"
MIN_SIZE_BYTES=5000000     # Skip files < 5 MB (already small / messenger clips)
MAX_HEVC_BITRATE=8000000   # Skip HEVC re-encode if bitrate <= 8 Mbps (remux to _hevc.mp4)
MODE="${1:-dry}"
LOG_FILE="$HOME/Desktop/compress-videos-$(date '+%Y%m%d-%H%M%S')-${MODE}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

for cmd in ffmpeg ffprobe; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ $cmd not found. Install via Homebrew."
    exit 1
  fi
done

if [ ! -d "$DEST_VIDEOS" ]; then
  echo "❌ Folder not found: $DEST_VIDEOS"
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'kill 0 2>/dev/null; exit 130' INT TERM HUP
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Mode: ${MODE} | Folder: ${DEST_VIDEOS} | Log: ${LOG_FILE}"

done_count=0; skip_count=0; fail_count=0; saved_bytes=0
limit=0
[ "$MODE" = "test5" ] && limit=5

# Build target *_hevc.mp4 path from old yyyyMMdd_HHmmss_<size>.<ext> name
target_hevc_path() {
  local f="$1" name base stem dir i=1
  dir=$(dirname "$f")
  name=$(basename "$f")
  base="${name%.*}"
  if [[ "$base" =~ ^([0-9]{8}_[0-9]{6})_[0-9]+$ ]]; then
    stem="${BASH_REMATCH[1]}_hevc"
  elif [[ "$base" =~ _hevc$ ]]; then
    stem="$base"
  else
    stem="${base}_hevc"
  fi
  local out="${dir}/${stem}.mp4"
  while [ -e "$out" ] && [ "$out" != "$f" ]; do
    out="${dir}/${stem}_${i}.mp4"
    i=$((i + 1))
  done
  echo "$out"
}

while IFS= read -r -d '' f; do
  name=$(basename "$f")
  orig_size=$(stat -f %z "$f")
  target=$(target_hevc_path "$f")
  target_name=$(basename "$target")

  # 1. Fast skip small clips (< 5 MB) without downloading from OneDrive
  if [ "$orig_size" -lt "$MIN_SIZE_BYTES" ]; then
    skip_count=$((skip_count + 1))
    continue
  fi

  if [ "$MODE" = "dry" ]; then
    printf "  • candidate: %s -> %s (%.1f MB)\n" "$name" "$target_name" "$(echo "$orig_size / 1048576" | bc -l)"
    done_count=$((done_count + 1))
    continue
  fi

  mkdir -p "$TMP_DIR"

  # 2. Probe codec & bitrate (triggers OneDrive download if cloud-only)
  vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null | head -n1)
  vbr=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$f" 2>/dev/null | head -n1)

  tmp_out="${TMP_DIR}/${target_name}"

  if { [ "$vcodec" = "hevc" ] && [[ "$vbr" =~ ^[0-9]+$ ]] && [ "$vbr" -le "$MAX_HEVC_BITRATE" ]; } || \
     { [[ "$vbr" =~ ^[0-9]+$ ]] && [ "$vbr" -le 4000000 ]; }; then
    echo "  = skip (already low bitrate $((vbr / 1000)) kbps, untouched): $name"
    skip_count=$((skip_count + 1))
    continue
  fi

  printf "  ▶ %s -> %s (%s, %.1f MB) ... " "$name" "$target_name" "${vcodec:-?}" "$(echo "$orig_size / 1048576" | bc -l)"

  if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$f" \
    -map "0:v:0" -map "0:a:0?" \
    -c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 \
    -c:a copy \
    -map_metadata 0 -movflags +use_metadata_tags+faststart \
    "$tmp_out" </dev/null 2>/dev/null; then

    new_size=$(stat -f %z "$tmp_out")
    if [ "$new_size" -gt 0 ] && [ "$new_size" -lt "$orig_size" ]; then
      touch -r "$f" "$tmp_out"
      if mv -f "$tmp_out" "$target" && [ -s "$target" ]; then
        [ "$target" != "$f" ] && rm -f "$f"
        diff_bytes=$((orig_size - new_size))
        saved_bytes=$((saved_bytes + diff_bytes))
        printf "✅ %.1f MB (-%d%%)\n" "$(echo "$new_size / 1048576" | bc -l)" "$((diff_bytes * 100 / orig_size))"
        done_count=$((done_count + 1))
      else
        rm -f "$tmp_out"
        echo "❌ move failed"
        fail_count=$((fail_count + 1))
      fi
    else
      rm -f "$tmp_out"
      printf "⏭ kept original (new %.1f MB >= orig)\n" "$(echo "$new_size / 1048576" | bc -l)"
      skip_count=$((skip_count + 1))
    fi
  else
    rm -f "$tmp_out"
    echo "❌ encode failed"
    fail_count=$((fail_count + 1))
  fi

  if [ "$limit" -gt 0 ] && [ "$done_count" -ge "$limit" ]; then
    echo "⏹ Reached test limit (${limit})."
    break
  fi
done < <(find "$DEST_VIDEOS" -mindepth 1 -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mp4" \) ! -iname "*_hevc.mp4" -print0 | sort -z)

echo
printf "✅ Done (${MODE}): processed %d, skipped %d, failed %d, saved %.2f GB\n" \
  "$done_count" "$skip_count" "$fail_count" "$(echo "$saved_bytes / 1073741824" | bc -l)"
echo "📄 Log saved: $LOG_FILE"
