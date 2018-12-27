# echo "*** now executing .bashrc"

########################
### load extensions ###
########################

source "$HOME/.bin/git-completion.sh"
# source "$HOME/.bin/git-prompt.sh"
source "$HOME/.bin/rake_autocomplete.sh"
source "$HOME/.bin/bash_prompt.sh"

#####################
### ENV variables ###
#####################

# look for commands in these places
export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"
export PATH="~/.bin:$PATH"

# make vim the default text editor
export EDITOR="vim"

# shortened prompt that includes git branch info
# RED='\[\e[0;31m\]'
# WHITE='\[\e[0;37m\]'
# RESET='\[\e[0m\]'
# export PS1="$RED\w$WHITE\$(__git_ps1)$RED\$$RESET "

#############
### other ###
#############

# initialize rbenv
eval "$(rbenv init -)"

# initialize nodenv
eval "$(nodenv init -)"

# initialize node version manager (disabled)
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# load aliases
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# load any local configuration
[[ -f "$HOME/.bashrc.local" ]] && source "$HOME/.bashrc.local"

# heroku autocomplete setup
HEROKU_AC_BASH_SETUP_PATH=/Users/me/Library/Caches/heroku/autocomplete/bash_setup && test -f $HEROKU_AC_BASH_SETUP_PATH && source $HEROKU_AC_BASH_SETUP_PATH;

# prior attempt at doing dotfiles via git (disabled) -- https://medium.hackinrio.com/how-to-manage-your-dotfiles-with-git-f7aeed8adf8b
# alias config='/usr/bin/git --git-dir=/Users/me/.cfg/ --work-tree=/Users/me'

