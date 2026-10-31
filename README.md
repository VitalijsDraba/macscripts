# macscripts

## Raycast Scripts (`raycast-scripts/`)
- **`synology-photo-backup.sh`** — Copy/move photos and videos from Synology SMB share to OneDrive (`Pending_Pictures/YYYY/` and `Pending_Video/`), converting HEIC to JPG and encoding heavy videos to HEVC (`hevc_videotoolbox -q:v 65`).
- **`compress-pending-videos.sh`** — Re-encode existing heavy videos in `Pending_Video` to HEVC (`*_hevc.mp4`) using Apple Silicon VideoToolbox.
- **`sort-pending-by-year.sh`** — Move photos from `Pending_Pictures` root into `YYYY/` subfolders based on the filename date prefix.

## `convert_homevideo.sh`
Convert input video file(s) to HEVC (`.hevc.mp4`) via `ffmpeg` + `hevc_videotoolbox`.

## `alfred.workflows/`
Exported Alfred workflows (video conversion, Wi-Fi restart, Roborock sound installer, etc.).

## `keyboard layouts/`
Russian phonetic keyboard layout (`Russian.bundle`).

## Delete old TimeMachine backups
```bash
> sudo su
> IFS=$'\n';for f in $(tmutil listbackups | grep '2017'); do tmutil delete "$f"; done
```
