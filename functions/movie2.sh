#!/bin/zsh

movie2() {
  local selected_file
  selected_file=$(_movie_select_file "$1") || return 1

  local encoded_file
  encoded_file=$(_ffmpeg_two_pass "$selected_file" "800k" "400k")

  _movie_finalize "$selected_file" "$encoded_file"
}
