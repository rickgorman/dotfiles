#!/bin/bash

# Toggle clamshell-mode sleep — keep mac awake with lid closed on battery.
# Wraps `pmset -b disablesleep`, which lid-close-sleep policy honors on Apple Silicon.
#
# Usage:
#   clamshell           toggle current state
#   clamshell on        disable battery sleep (stay awake lid-closed)
#   clamshell off       restore default sleep behavior
#   clamshell status    show current state

clamshell() {
  local current action
  current=$(pmset -g custom | awk '/Battery Power/{f=1} f && /disablesleep/{print $2; exit}')
  action="${1:-toggle}"

  if [ "$action" = "toggle" ]; then
    if [ "$current" = "1" ]; then
      action="off"
    else
      action="on"
    fi
  fi

  case "$action" in
    on)
      sudo pmset -b disablesleep 1 && echo "clamshell: ON  — lid-closed wake enabled on battery"
      ;;
    off)
      sudo pmset -b disablesleep 0 && echo "clamshell: OFF — default sleep restored"
      ;;
    status)
      if [ "$current" = "1" ]; then
        echo "clamshell: ON"
      else
        echo "clamshell: OFF"
      fi
      ;;
    *)
      echo "usage: clamshell [on|off|status]  (no arg = toggle)" >&2
      return 1
      ;;
  esac
}
