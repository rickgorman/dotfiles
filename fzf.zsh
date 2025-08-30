# Setup fzf
# ---------
if [[ ! "$PATH" == */Users/me/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/Users/me/.fzf/bin"
fi

source <(fzf --zsh)
