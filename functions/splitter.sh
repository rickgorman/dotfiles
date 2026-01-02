#!/usr/bin/env bash

splitter() {
  local delimiter="$1"
  local input
  read -r input

  if [[ -z "$delimiter" ]]; then
    local non_alnum
    non_alnum=$(printf '%s' "$input" | tr -d '[:alnum:]' | fold -w1 | sort -u | tr -d '\n')

    if [[ ${#non_alnum} -eq 0 ]]; then
      echo "$input"
      return 0
    elif [[ ${#non_alnum} -eq 1 ]]; then
      delimiter="$non_alnum"
    else
      echo "Error: multiple delimiters found. Try one of:"
      for (( i=0; i<${#non_alnum}; i++ )); do
        char="${non_alnum:$i:1}"
        echo "echo \"$input\" | splitter '$char'"
      done
      return 1
    fi
  fi

  printf '%s' "$input" | tr "$delimiter" ' '
  echo
}
