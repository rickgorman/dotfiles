#echo "*** now executing .bash_profile"

# redirect all bash setup to live in .bashrc
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
