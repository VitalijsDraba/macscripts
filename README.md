# macscripts

## convert_homevideo.sh
simple script to convert input video file(s) via ffmpeg

## Convert home videos.alfredworkflow
Alfred 3 workflow to run ffmpeg convertation for each selected file

## mbp_wifi5ghz_region_code_patch.md
To solve the MBP connection to 5GHz WiFi issue (wrong region code)

## delete old TimeMachine backups
> sudo su
> IFS=$'\n';for f in $(tmutil listbackups | grep '2017'); do tmutil delete "$f"; done