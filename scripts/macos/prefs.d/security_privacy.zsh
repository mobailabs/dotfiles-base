#!/usr/bin/env bash

set -euo pipefail

echo "  Security & Privacy"

defaults write com.apple.AdLib allowApplePersonalizedAdvertising -int 0

