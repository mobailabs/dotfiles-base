#!/usr/bin/env bash

set -euo pipefail

echo "  TextEdit"

defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
defaults write com.apple.TextEdit RichText -int 0

killall "TextEdit" >/dev/null 2>&1 || true

