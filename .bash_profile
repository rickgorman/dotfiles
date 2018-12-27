export BASH_CONF="bash_profile"

# ensure that we load .bashrc
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# shell coloration
#export PS1="\w\$ "
#export CLICOLORS=1
#export LS_COLORS=ExFxBxDxCxegedabagacad

alias ls='ls -GFh'

# git aliases
alias gad='git add . && git status'
alias gadot='echo "deprecated -- use gad instead"; git add . && git status'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcmmm='commit -m && git push'
alias gs='git status'
alias ga='git add'
alias gd='git diff'
alias gp='git push'
alias gds='git diff --staged'
alias gm='git checkout master && git pull origin master && bundle && yarn install && SKIP_YARN=1 be rake db:drop db:create && SKIP_YARN=1 be rake db:migrate && ENV_RAILS=test SKIP_YARN=1 be rake db:migrate'
alias gpm='git push origin master'
alias gsl='git stash list'
alias gf='git fetch'
alias nb='git checkout -b'

# hub aliases
alias prl='hub pr list'

# edit aliases
alias ba='vim ~/.bash_profile && source ~/.bash_profile'

# bundle
alias be='bundle exec'
alias bes='bundle exec spring'
alias beg='be guard -P livereload'
alias brc='be rails c'
alias brdbm='be rake db:migrate'

# heroku aliases
CURRENT_BRANCH=`git rev-parse --abbrev-ref HEAD`
alias gph='git push heroku $CURRENT_BRANCH:master'
alias h='heroku run'
alias hrc='heroku run bundle exec rails c -a cmn-admin'

# killing things
alias killpuma="ps -ef | grep puma | grep -v grep | grep -v killpuma | awk '{print $2}' | xargs kill -9"

# nodenv stuff
eval "$(nodenv init -)"
