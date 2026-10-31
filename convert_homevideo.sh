#!/bin/sh

for F in "$@"; do
  fnameext=$(basename "$F")
  fname="${fnameext%.*}"
  dir=$(dirname "$F")
  out="${dir}/${fname}.hevc.mp4"
  ffmpeg -hide_banner -loglevel error -stats -y -i "$F" \
    -map "0:v:0" -map "0:a:0?" \
    -c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 \
    -c:a aac -b:a 192k \
    -map_metadata 0 -movflags +use_metadata_tags \
    "$out" && touch -r "$F" "$out"
done
