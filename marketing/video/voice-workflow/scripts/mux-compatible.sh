#!/usr/bin/env bash
set -euo pipefail
ffmpeg -hide_banner -loglevel error -i out/SayKuku-final-render.mp4 -i public/score-final.wav -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -profile:a aac_low -b:a 192k -ar 48000 -ac 2 -disposition:a:0 default -metadata:s:a:0 handler_name="Stereo Music" -movflags +faststart -video_track_timescale 60000 -y out/SayKuku-final.mp4
ffmpeg -hide_banner -loglevel error -i out/SayKuku-final.mp4 -vn -c:a libmp3lame -b:a 192k -ar 48000 -ac 2 -y out/SayKuku-final-soundtrack.mp3
