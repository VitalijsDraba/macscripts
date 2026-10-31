# macscripts

## convert_homevideo.sh
simple script to convert input video file(s) via ffmpeg

## Convert home videos.alfredworkflow
Alfred 3 workflow to run ffmpeg convertation for each selected file

## delete old TimeMachine backups
``` bash
> sudo su
> IFS=$'\n';for f in \$(tmutil listbackups | grep '2017'); do tmutil delete "$f"; done
```