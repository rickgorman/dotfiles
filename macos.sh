#!/usr/bin/env bash

echo "Starting macOS configuration..."
osascript -e 'tell application "System Preferences" to quit'
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

###############################################################################
echo "Modifying screen and font rendering settings..."
###############################################################################

echo "  [✓] Enabling subpixel font rendering for non-apple displays..."
defaults write -g CGFontRenderingFontSmoothingDisabled -bool NO
defaults write NSGlobalDomain AppleFontSmoothing -int 1

###############################################################################
echo "Modifying Finder settings..."
###############################################################################

echo "  [✓] Showing Finder status bar..."
defaults write com.apple.finder ShowStatusBar -bool true

echo "  [✓] Showing Finder path bar..."
defaults write com.apple.finder ShowPathbar -bool true

echo "  [✓] Expanding save dialogs..."
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true

echo "  [✓] Showing all filename extensions..."
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

echo "  [✓] Setting Finder to list view..."
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

echo "  [✓] Showing hidden files..."
defaults write com.apple.finder AppleShowAllFiles YES

echo "  [✓] Unhiding ~/Library..."
chflags nohidden ~/Library

echo "  [✓] Unhiding /Volumes..."
sudo chflags nohidden /Volumes

echo "  [✓] Disabling .DS_Store file creation on network volumes..."
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

echo "  [✓] Disabling .DS_Store file creation on USB volumes..."
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

echo "  [✓] Showing full POSIX path in Finder title..."
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

###############################################################################
echo "Modifying keyboard and input settings..."
###############################################################################

echo "  [✓] Setting initial key repeat delay..."
defaults write -g InitialKeyRepeat -int 15

echo "  [✓] Setting key repeat rate..."
defaults write -g KeyRepeat -int 1

echo "  [✓] Disabling press-and-hold..."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

echo "  [✓] Enabling full keyboard access (Tab navigation)..."
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

echo "  [✓] Disabling smart quotes..."
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

echo "  [✓] Disabling smart dashes..."
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

echo "  [✓] Disabling auto-correct..."
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

echo "  [✓] Disabling global spelling correction..."
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

###############################################################################
echo "Modifying screenshot behavior..."
###############################################################################

echo "  [✓] Changing screenshot save location to ~/Screenshots..."
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots

###############################################################################
echo "Modifying app-specific settings..."
###############################################################################

echo "  [✓] Disabling Slack auto-updates..."
defaults write com.tinyspeck.slackmacgap SlackNoAutoUpdates -bool YES

###############################################################################
echo "Restarting affected apps..."
###############################################################################

for app in Safari Finder Dock Mail SystemUIServer; do
  killall "$app" >/dev/null 2>&1
done

echo "Done. Some changes may require logout or restart."

