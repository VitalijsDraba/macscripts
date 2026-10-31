#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Backup Photos from Synology
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📸
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Dry run", "value": "dry"}, {"title": "Copy (keep source)", "value": "copy"}, {"title": "Move (delete source)", "value": "move"}] }

# Documentation:
# @raycast.description Copy/move photos & videos from Synology share to OneDrive Pending folders with date-based renaming and HEVC VideoToolbox encoding
# @raycast.author VitalijsDraba
# @raycast.authorURL https://github.com/VitalijsDraba

# ---------- Config ----------
NAS_HOST="192.168.50.101"
NAS_SHARE="photo"
MOUNT_POINT="/Volumes/${NAS_SHARE}"
PROCESS_CHILD_FOLDERS=true   # source root + first-level subfolders
DEST_IMAGES="$HOME/Library/CloudStorage/OneDrive-Personal/Pictures/Pending_Pictures"
DEST_VIDEOS="$HOME/Library/CloudStorage/OneDrive-Personal/Videos/Pending_Video"
# ----------------------------

MODE="${1:-dry}"
LOG_FILE="$HOME/Desktop/synology-backup-$(date '+%Y%m%d-%H%M%S')-${MODE}.log"
log() { echo "$*" | tee -a "$LOG_FILE"; }
logn() { printf "%s" "$*" | tee -a "$LOG_FILE"; }

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

for cmd in exiftool ffmpeg ffprobe; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "❌ $cmd not found. Install via Homebrew."
    exit 1
  fi
done

log "Mode: ${MODE} | Log: ${LOG_FILE}"

# ---------- Mount ----------
if ! nc -z -G 3 "$NAS_HOST" 445 >/dev/null 2>&1; then
  log "❌ NAS ${NAS_HOST} unreachable."
  exit 1
fi

MOUNTED_BY_US=false
if [ ! -d "$MOUNT_POINT" ] || ! mount | grep -q " on ${MOUNT_POINT} "; then
  log "🔌 Mounting smb://${NAS_HOST}/${NAS_SHARE} ..."
  if ! osascript -e "mount volume \"smb://${NAS_HOST}/${NAS_SHARE}\"" >/dev/null 2>&1; then
    log "❌ Mount failed."
    exit 1
  fi
  MOUNTED_BY_US=true
fi

TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
  if [ "$MOUNTED_BY_US" = true ]; then
    log "⏏️ Unmounting ${MOUNT_POINT}"
    diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1
  fi
}
trap 'exit 130' INT TERM HUP
trap cleanup EXIT

mkdir -p "$DEST_IMAGES" "$DEST_VIDEOS"

# ---------- Helpers ----------
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# Resolve destination conflicts for images. Echoes final path, or empty if same file already backed up.
# $1 = file to compare by size (for HEIC: the converted temp JPG), $2 = desired destination.
resolve_dest() {
  local cmp="$1" dest="$2"
  if [ -e "$dest" ]; then
    if [ "$(stat -f %z "$cmp")" = "$(stat -f %z "$dest")" ]; then
      echo ""
      return
    fi
    local dir base ext i=1
    dir=$(dirname "$dest"); base=$(basename "$dest"); ext="${base##*.}"; base="${base%.*}"
    while [ -e "${dir}/${base}_${i}.${ext}" ]; do i=$((i + 1)); done
    dest="${dir}/${base}_${i}.${ext}"
  fi
  echo "$dest"
}

process_file() {
  local src="$1" name ext dest_name dest date_src="mtime" cmp="$1" tmp_file="" is_video=false v_action="copy"
  name=$(basename "$src")
  ext=$(lower "${name##*.}")

  case "$ext" in
    jpg|jpeg|png|heic)
      local stamp
      stamp=$(exiftool -s3 -d '%Y%m%d%H%M' -CreateDate "$src" 2>/dev/null)
      if [[ "$stamp" =~ ^[0-9]{12}$ ]]; then
        date_src="exif"
      else
        stamp=$(stat -f %Sm -t '%Y%m%d%H%M' "$src")
      fi
      dest_name="$name"
      if [ "$ext" = "heic" ]; then
        dest_name="${name%.*}.jpg"
        mkdir -p "$TMP_DIR"
        tmp_file="${TMP_DIR}/${dest_name}"
        if ! sips -s format jpeg "$src" --out "$tmp_file" >/dev/null 2>&1 || [ ! -f "$tmp_file" ]; then
          log "  ❌ failed (convert): $name"
          rm -f "$tmp_file"
          return
        fi
        touch -r "$src" "$tmp_file"
        cmp="$tmp_file"
      fi
      dest="${DEST_IMAGES}/${stamp:0:4}/${stamp}_${dest_name}"
      ;;
    mp4|mov)
      is_video=true
      local vstamp
      vstamp=$(stat -f %Sm -t '%Y%m%d_%H%M%S' "$src")
      dest="${DEST_VIDEOS}/${vstamp}_hevc.mp4"
      ;;
    *)
      log "  ? unknown type: $name"
      return
      ;;
  esac

  if [ "$is_video" = true ]; then
    local existing_vid
    existing_vid=$(find "$DEST_VIDEOS" -maxdepth 1 -type f \( -iname "${vstamp}_hevc.*" -o -iname "${vstamp}_[0-9]*.*" -o -iname "${vstamp}.*" \) -print -quit)
    if [ -n "$existing_vid" ]; then
      log "  = exists: $name -> $(basename "$existing_vid")"
      [ "$MODE" = "move" ] && rm -f "$src"
      return
    fi

    local vcodec vbr
    vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$src" 2>/dev/null | head -n1)
    vbr=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$src" 2>/dev/null | head -n1)
    # Encode only if bitrate > 4 Mbps (and not already low-bitrate HEVC); otherwise plain copy as-is
    if [ "$vcodec" != "hevc" ] && { ! [[ "$vbr" =~ ^[0-9]+$ ]] || [ "$vbr" -gt 4000000 ]; }; then
      v_action="hevc_vt"
    elif [ "$vcodec" = "hevc" ] && [[ "$vbr" =~ ^[0-9]+$ ]] && [ "$vbr" -gt 8000000 ]; then
      v_action="hevc_vt"
    else
      v_action="copy"
      dest="${DEST_VIDEOS}/${vstamp}.${name##*.}"
    fi

    local orig_size
    orig_size=$(stat -f %z "$src")
    local orig_mb
    orig_mb=$(printf "%.1f" "$(echo "$orig_size / 1048576" | bc -l)")

    if [ "$MODE" = "dry" ]; then
      log "  + $name -> $(basename "$dest") [${v_action}, ${orig_mb} MB]"
      return
    fi

    mkdir -p "$(dirname "$dest")" "$TMP_DIR"
    local ok=false
    if [ "$v_action" = "hevc_vt" ]; then
      logn "  + $name -> $(basename "$dest") [hevc_vt, ${orig_mb} MB -> "
      tmp_file="${TMP_DIR}/$(basename "$dest")"
      if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$src" \
        -map "0:v:0" -map "0:a:0?" \
        -c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 \
        -c:a copy \
        -map_metadata 0 -movflags +use_metadata_tags+faststart \
        "$tmp_file" </dev/null 2>/dev/null && [ -s "$tmp_file" ]; then
        local enc_size
        enc_size=$(stat -f %z "$tmp_file")
        if [ "$enc_size" -ge "$orig_size" ]; then
          # Re-encoded file grew larger — discard and copy original untouched
          rm -f "$tmp_file"
          dest="${DEST_VIDEOS}/${vstamp}.${name##*.}"
          if cp -p "$src" "$dest" && [ -s "$dest" ]; then
            log "${orig_mb} MB (kept original -> $(basename "$dest"))]"
            [ "$MODE" = "move" ] && rm -f "$src"
          else
            log "FAILED]"
            log "  ❌ failed: $name"
            rm -f "$dest"
          fi
          return
        fi
        touch -r "$src" "$tmp_file"
        mv "$tmp_file" "$dest" && ok=true
      fi
      if [ "$ok" = true ] && [ -s "$dest" ]; then
        local new_size new_mb pct
        new_size=$(stat -f %z "$dest")
        new_mb=$(printf "%.1f" "$(echo "$new_size / 1048576" | bc -l)")
        pct=$(( (new_size - orig_size) * 100 / orig_size ))
        log "$(printf "%s MB (%+d%%)]" "$new_mb" "$pct")"
        [ "$MODE" = "move" ] && rm -f "$src"
      else
        log "FAILED]"
        log "  ❌ failed: $name"
        rm -f "$dest" "$tmp_file"
      fi
    else
      log "  + $name -> $(basename "$dest") [copy, ${orig_mb} MB]"
      if cp -p "$src" "$dest" && [ -s "$dest" ]; then
        [ "$MODE" = "move" ] && rm -f "$src"
      else
        log "  ❌ failed: $name"
        rm -f "$dest"
      fi
    fi
    return
  fi

  local final
  final=$(resolve_dest "$cmp" "$dest")
  if [ -z "$final" ]; then
    log "  = exists: $name -> ${dest#"$DEST_IMAGES"/}"
    [ "$MODE" = "move" ] && rm -f "$src"
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    return
  fi

  log "  + $name -> ${final#"$DEST_IMAGES"/} [${date_src}]"
  if [ "$MODE" = "dry" ]; then
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    return
  fi

  local ok=false
  mkdir -p "$(dirname "$final")"
  if [ -n "$tmp_file" ]; then
    mv "$tmp_file" "$final" && ok=true
  else
    cp -p "$src" "$final" && ok=true
  fi

  if [ "$ok" = true ] && [ -s "$final" ]; then
    [ "$MODE" = "move" ] && rm -f "$src"
  else
    log "  ❌ failed: $name"
    rm -f "$final" "$tmp_file"
  fi
}

process_folder() {
  local folder="$1" f
  log "📁 $folder"
  shopt -s nullglob
  for f in "$folder"/*; do
    [ -f "$f" ] || continue
    process_file "$f"
  done
}

# ---------- Run ----------
process_folder "$MOUNT_POINT"
if [ "$PROCESS_CHILD_FOLDERS" = true ]; then
  shopt -s nullglob
  for d in "$MOUNT_POINT"/*/; do
    d="${d%/}"
    base=$(basename "$d")
    [[ "$base" == @* || "$base" == "#recycle" ]] && continue
    process_folder "$d"
  done
fi

log ""
log "✅ Done (${MODE}): new $(grep -c '^  + ' "$LOG_FILE"), exists $(grep -c '^  = ' "$LOG_FILE"), unknown $(grep -c '^  ? ' "$LOG_FILE"), failed $(grep -c '❌ failed' "$LOG_FILE")"
log "📄 Log saved: $LOG_FILE"
