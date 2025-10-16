#!/bin/bash

movie() {
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
  if [ ${#files[@]} -eq 0 ]; then
    echo "NONE - No MOV files found on Desktop from the last $minutes minutes"
    return 1
  fi

  # Display the list
  echo "Recent MOV files on Desktop (last $minutes minutes):"
  for i in "${!files[@]}"; do
    local display_num=$((i + 1))
    local file_basename=$(basename "${files[$i]}")
    if [ $i -eq 0 ]; then
      echo "  $display_num) $file_basename (default)"
    else
      echo "  $display_num) $file_basename"
    fi
  done

  # Prompt for selection
  echo -n "Select file [1]: "
  read selection

  # Default to 1 if no input
  if [ -z "$selection" ]; then
    selection=1
  fi

  # Validate selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#files[@]} ]; then
    echo "Invalid selection"
    return 1
  fi

  # Get the selected file (adjust for 0-based array)
  local selected_file="${files[$((selection - 1))]}"
  local dir_name=$(dirname "$selected_file")
  local base_name=$(basename "$selected_file")
  local name_without_ext="${base_name%.*}"
  local extension="${base_name##*.}"

  # Remove spaces from filename
  local new_name="${name_without_ext:gs/ /_}.${extension}"
  local new_path="$dir_name/$new_name"

  # Rename if necessary
  if [ "$selected_file" != "$new_path" ]; then
    mv "$selected_file" "$new_path"
    echo "Renamed to: $new_name"
  fi

  # Run ffmpeg_two_pass on the file
  ffmpeg_two_pass "$new_path"

  # Output the full path to the created file
  local output_file="${new_path%.*}_pass_2.mp4"
  echo "$output_file"
  echo "$output_file" | pbcopy
}
