#!/bin/zsh

_movie_select_file() {
  local minutes="${1:-75}"
  local desktop_path="$HOME/Desktop"
  local cutoff_time=$(date -v"-${minutes}M" +%s)
  local files=()

  # Find MOV files modified in the last N minutes, sorted by newest first
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$desktop_path" -maxdepth 1 -name "*.MOV" -o -name "*.mov" | while read -r f; do
    mod_time=$(stat -f "%m" "$f")
    if [ "$mod_time" -ge "$cutoff_time" ]; then
      echo "$mod_time|$f"
    fi
  done | sort -rn | cut -d'|' -f2)

  # Check if any files were found
  if [ "${#files[@]}" -eq 0 ]; then
    echo "NONE - No MOV files found on Desktop from the last $minutes minutes" >&2
    return 1
  fi

  # Display the list
  echo "Recent MOV files on Desktop (last $minutes minutes):" >&2
  for i in {1.."${#files[@]}"}; do
    local file_basename=$(basename "${files[$i]}")
    if [ $i -eq 1 ]; then
      echo "  $i) $file_basename (default)" >&2
    else
      echo "  $i) $file_basename" >&2
    fi
  done

  # Prompt for selection
  echo -n "Select file [1]: " >&2
  read selection

  # Default to 1 if no input
  if [ -z "$selection" ]; then
    selection=1
  fi

  # Validate selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#files[@]}" ]; then
    echo "Invalid selection" >&2
    return 1
  fi

  echo "${files[$selection]}"
}

_movie_finalize() {
  local selected_file="$1"
  local encoded_file="$2"

  local dir_name=$(dirname "$selected_file")
  local base_name=$(basename "$selected_file")
  local name_without_ext="${base_name%.*}"
  local normalized_name="$(echo "$name_without_ext" | tr ' ' '_')"

  local final_output="$dir_name/${normalized_name}.mp4"
  mv "$encoded_file" "$final_output"
  mv "$selected_file" ~/.Trash/

  echo "$final_output"
  echo "$final_output" | pbcopy
}

_ffmpeg_two_pass() {
  local input_file="$1"
  local pass1_bitrate="$2"
  local pass2_bitrate="$3"
  local base_name="${input_file%.*}"
  local temp_output="${base_name}_temp.mp4"
  local pass2_output="${base_name}_pass_2.mp4"
  local temp_files=("ffmpeg2pass-0.log" "ffmpeg2pass-0.log.mbtree")

  ffmpeg -i "$input_file" -pass 1 -r 15 -c:v h264 -c:a aac -b:v "$pass1_bitrate" -strict normal "$temp_output"
  ffmpeg -i "$temp_output" -pass 2 -r 15 -c:v h264 -c:a aac -b:v "$pass2_bitrate" -strict normal "$pass2_output"

  rm "$temp_output"
  for temp_file in "${temp_files[@]}"; do
    [ -f "$temp_file" ] && rm "$temp_file"
  done

  echo "$pass2_output"
}

_ffmpeg_crf_screen() {
  local input_file="$1"
  local crf="$2"
  local maxrate="$3"
  local base_name="${input_file%.*}"
  local output="${base_name}_crf.mp4"

  ffmpeg -i "$input_file" \
    -c:v libx264 \
    -preset slow \
    -tune stillimage \
    -crf "$crf" \
    -maxrate "$maxrate" \
    -bufsize "$(echo "$maxrate" | sed 's/k//')k" \
    -pix_fmt yuv420p \
    -c:a aac \
    -b:a 128k \
    "$output"

  echo "$output"
}
