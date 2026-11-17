#!/bin/zsh
set -euo pipefail

if (( $# < 2 )); then
  print "usage: scripts/clip-to-gif.sh <input.mov> <output.gif> [width=720] [start=0] [duration=all] [fps=20] [crop=w:h:x:y]"
  exit 1
fi

input=$1 output=$2 width=${3:-720} start=${4:-0} duration=${5:-} fps=${6:-20} crop=${7:-}
trim=(-ss "$start")
[[ -n $duration ]] && trim+=(-t "$duration")
palette=$(mktemp -t dzhmil-palette).png
filters="fps=$fps,scale=$width:-1:flags=lanczos"
[[ -n $crop ]] && filters="crop=$crop,$filters"

ffmpeg -v error -y $trim -i "$input" -vf "$filters,palettegen=max_colors=${COLORS:-96}:stats_mode=diff" "$palette"
ffmpeg -v error -y $trim -i "$input" -i "$palette" \
  -lavfi "$filters [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$output"
rm -f "$palette"
ls -lh "$output"
