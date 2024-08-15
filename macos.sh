#!/usr/bin/env bash

# Close any open System Preferences panes, to prevent them from overriding
# settings we’re about to change
osascript -e 'tell application "System Preferences" to quit'

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.macos` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

###############################################################################
# Screen                                                                      #
###############################################################################

# Enable subpixel font rendering on non-Apple LCDs
# Reference: https://github.com/kevinSuttle/macOS-Defaults/issues/17#issuecomment-266633501
defaults write -g CGFontRenderingFontSmoothingDisabled -bool NO
defaults write NSGlobalDomain AppleFontSmoothing -int 1

###############################################################################
# Finder                                                                      #
###############################################################################

# Finder: show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Finder: show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Finder: Expand save dialog by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true

# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Use list view in all Finder windows by default
# Four-letter codes for the other view modes: `icnv`, `clmv`, `Flwv`
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles YES

# Show the ~/Library folder
chflags nohidden ~/Library

# Show the /Volumes folder
sudo chflags nohidden /Volumes

# Disable creation of .DS_store files
defaults write com.apple.desktopservices DSDontWriteNetworkStores true

###############################################################################
# Keyboard / Input                                                            #
###############################################################################

# Shorten initial key repeat delay. Normal minimum is 15 (225 ms). Increments of 15ms.
defaults write -g InitialKeyRepeat -int 15

# Increase repeat rate. Normal minimum is 2 (30 ms). Increments of 15ms.
defaults write -g KeyRepeat -int 1

# Favor key repeat over key hold
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

###############################################################################
# App-specific Settings
###############################################################################

# Disble slack auto-updates (mostly to disable annoying notifications)
defaults write com.tinyspeck.slackmacgap SlackNoAutoUpdates -bool YES

###############################################################################
###############################################################################

# Kill affected apps
for app in Safari Finder Dock Mail SystemUIServer; do killall "$app" >/dev/null 2>&1; done

echo "Done. Note that some of these changes require a logout/restart to take effect."
