echo "*** now executing .bash_profile"

# ensure that we load .bashrc
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# shell coloration (disabled)
#export PS1="\w\$ "
#export CLICOLORS=1
#export LS_COLORS=ExFxBxDxCxegedabagacad
