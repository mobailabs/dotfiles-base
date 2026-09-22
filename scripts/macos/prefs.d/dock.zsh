#!/usr/bin/env bash

set -euo pipefail

echo "  Dock"

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock minimize-to-application -bool true
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock show-process-indicators -bool true
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock showhidden -bool true
defaults write com.apple.dock tilesize -int 60
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-bl-corner -int 0
defaults write com.apple.dock wvous-br-corner -int 0

killall "Dock" >/dev/null 2>&1 || true

