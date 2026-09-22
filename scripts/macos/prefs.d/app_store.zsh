#!/usr/bin/env bash

set -euo pipefail

echo "  App Store"

defaults write com.apple.appstore ShowDebugMenu -bool true
defaults write com.apple.commerce AutoUpdate -bool true
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1

killall "App Store" >/dev/null 2>&1 || true

