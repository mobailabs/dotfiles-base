#!/usr/bin/env bash

set -euo pipefail

echo "  UI & UX"

defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture location -string "$HOME/Desktop"
defaults write com.apple.screencapture show-thumbnail -bool false
defaults write com.apple.screencapture type -string "png"

defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

defaults write -g AppleFontSmoothing -int 2
defaults write -g AppleShowScrollBars -string "Always"
defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
defaults write -g NSDisableAutomaticTermination -bool true
defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
defaults write -g PMPrintingExpandedStateForPrint -bool true
defaults write -g QLPanelAnimationDuration -float 0

killall "SystemUIServer" >/dev/null 2>&1 || true

