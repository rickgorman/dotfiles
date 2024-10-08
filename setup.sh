#!/bin/sh

# todo: check that this script is being called from the dotfiles-local dir
# spawn_dir=$(dirname -- $(readlink -f ${BASH_SOURCE}))
# spawn_dir=$(pwd)
# expected_dir="${HOME}/dotfiles-local"
# if [ $spawn_dir != $expected_dir ]; then
#   echo "this script must be run from the dotfiles-local/ directory"
#   exit
# fi

# todo: make sure that the zsh/ scripts are being called (just chpwd for now)

################
# Add symlinks #
################

# things sourced/included from thoughtbot dotfiles
# ln -s ~/dotfiles-local/aliases.local ~/.aliases.local
# ln -s ~/dotfiles-local/gitconfig.local ~/.gitconfig.local
# ln -s ~/dotfiles-local/gitignore.local ~/.gitignore.local
# ln -s ~/dotfiles-local/tmuz.conf.local ~/.tmux.conf.local
# ln -s ~/dotfiles-local/zshrc.local ~/.zshrc.local

# and everything else
ln -s ~/dotfiles-local/p10k.zsh ~/.p10k.zsh
ln -s ~/dotfiles-local/pryrc ~/.pryrc
ln -s ~/dotfiles-local/rspec ~/.rspec
ln -s ~/dotfiles-local/config/karabiner ~/.config/karabiner

# VSCode things
mv ~/Library/Application\ Support/Code/User/keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json.bak
ln -s ~/dotfiles-local/code/keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
mv ~/Library/Application\ Support/Code/User/settings.json ~/Library/Application\ Support/Code/User/settings.json.bak
ln -s ~/dotfiles-local/code/settings.json ~/Library/Application\ Support/Code/User/settings.json


# this will rebuild symlinks; use from cli when needed
rcup

########
# Brew #
########

# install everything from the Brewfile
brew bundle

########
# asdf #
########

asdf plugin add ruby

##########
# iTerm2 #
##########

# Specify the preferences directory and tell iTerm2 to load those prefs
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "~/dotfiles-local/iterm2"
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true

#############
# oh my zsh #
#############

# install it!
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# add autocomplete
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# p10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
cp -n fonts/*.ttf ~/Library/Fonts/

# fzf-tab
git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab

# alias-tips
git clone https://github.com/djui/alias-tips.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/alias-tips

########################
# rails autocompletion #
########################

cd ~/temp
gh repo clone mernen/completion-ruby
cp completion-ruby/completion-ruby-all ~/dotfiles-local/
rm -rf completion-ruby/
