#!/usr/bin/env bash

set -euo pipefail

echo "  Finder"

defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.finder WarnOnEmptyTrash -bool false
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder NewWindowTarget -string "PfDe"
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/Desktop/"

defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

defaults write com.apple.finder ShowRecentTags -bool false
defaults write -g AppleShowAllExtensions -bool true

# 图标显示相关设置
/usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:iconSize 72' \
  "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Set :StandardViewSettings:IconViewSettings:iconSize 72' \
  "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null || true

killall "Finder" >/dev/null 2>&1 || true
killall "cfprefsd" >/dev/null 2>&1 || true

