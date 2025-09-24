#!/bin/bash

# Generic spinner function
# Usage: show_spinner <pid> [message]
# Example: show_spinner $background_pid "Processing data"
show_spinner() {
  local pid=$1
  local message=${2:-"Processing"}

  # Show usage if called without required arguments
  if [ -z "$pid" ]; then
    echo "Usage: show_spinner <pid> [message]"
    echo "  pid: Process ID to monitor (required)"
    echo "  message: Display message (optional, defaults to 'Processing')"
    echo "Example: show_spinner \$background_pid 'Generating description'"
    return 1
  fi

  local delay=0.05
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local colors=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201)
  local color_idx=0
  local iterations=0

  tput civis
  printf "$message  "
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    color_idx=$((iterations % ${#colors[@]}))
    local temp=${spinstr#?}
    printf "\b\b\033[38;5;${colors[$color_idx]}m %s\033[0m" "${spinstr:0:1}"
    spinstr=$temp${spinstr:0:1}
    sleep $delay
    ((iterations++))
  done
  printf "\b\b ✓\n"
  tput cnorm
}
