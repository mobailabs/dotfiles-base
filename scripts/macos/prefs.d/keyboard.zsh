#!/usr/bin/env bash

set -euo pipefail

echo "  Keyboard"

defaults write -g AppleKeyboardUIMode -int 3
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write -g InitialKeyRepeat_Level_Saved -int 10
defaults write -g KeyRepeat -int 1

defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false

defaults write com.apple.HIToolbox AppleFnUsageType -int 2

