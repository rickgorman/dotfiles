#!/usr/bin/env bash

# borrowed from
# https://codeberg.org/EvanHahn/dotfiles/raw/commit/843b9ee13d949d346a4a73ccee2a99351aed285b/home/bin/bin/emoji

emoji() {
  local emoji_data_file="$HOME/dotfiles-local/data/emoji.txt"

  if [[ ! -f "$emoji_data_file" ]]; then
    echo "Error: emoji data file not found at $emoji_data_file"
    echo ""
    echo "Create the file with lines like:"
    echo "😃 smiley awesome face grin happy mouth open smile smiling smiling face with open mouth teeth yay"
    echo "💩 hankey bs comic doo doo dung face fml monster pile of poo poo poop smelly smh stink stinks stinky turd shit"
    return 1
  fi

  if [[ $# == 1 ]]; then
    local results=$(grep -i --color=never "$1" "$emoji_data_file")
    local count=$(echo "$results" | grep -c '^')

    if [[ $count -eq 0 ]]; then
      echo "No emoji found matching: $1"
      return 1
    elif [[ $count -eq 1 ]]; then
      echo "$results" | awk '{print $1}'
    else
      echo "$results" | awk '{print NR " " $1}'
    fi
  elif [[ $# == 2 ]]; then
    local results=$(grep -i --color=never "$1" "$emoji_data_file")
    local count=$(echo "$results" | grep -c '^')
    local index=$2

    if [[ $index -lt 1 || $index -gt $count ]]; then
      echo "Error: index $index out of range (1-$count)"
      return 1
    fi

    echo "$results" | sed -n "${index}p" | awk '{print $1}'
  else
    echo "Usage: emoji [search_term] [index]"
    return 1
  fi
}
