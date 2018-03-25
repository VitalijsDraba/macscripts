#!/bin/sh

FILES=$@

for F in $FILES; do
    fnameext=$(basename $F)
    fname=${fnameext%.*}
    ffmpeg -y -i $F -c:v libx264 -crf 23 -c:a aac -b:a 192k ${fname}.264.mp4
done;