#!/bin/bash

ffmpeg_two_pass() {
  local input_file="$1"
  local base_name="${input_file%.*}"
  local temp_output="${base_name}_temp.mp4"
  local final_output="${base_name}_pass_2.mp4"
  local temp_files=("ffmpeg2pass-0.log" "ffmpeg2pass-0.log.mbtree")

  # First pass
  ffmpeg -i "$input_file" -pass 1 -r 15 -c:v h264 -c:a aac -b:v 200k -strict normal "$temp_output"

  # Second pass
  ffmpeg -i "$temp_output" -pass 2 -r 15 -c:v h264 -c:a aac -b:v 100k -strict normal "$final_output"

  # Clean up temporary files
  rm "$temp_output"
  for temp_file in "${temp_files[@]}"; do
    [ -f "$temp_file" ] && rm "$temp_file"
  done

  echo "Processing complete. Output file: $final_output"
}