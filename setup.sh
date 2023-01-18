#!/bin/sh

##########
# iTerm2 #
##########

# Specify the preferences directory and tell iTerm2 to load those prefs
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "~/dotfiles/iterm2"
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
