#!/bin/sh

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
echo "Note: you need to add zsh-autosuggestions to the plugins list in zshrc-local"

# p10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
echo "add this line to zshrc-local:\n  Set ZSH_THEME=\"powerlevel10k/powerlevel10k\""
