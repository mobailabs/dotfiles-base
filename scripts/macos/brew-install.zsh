#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/macos/brew-bootstrap.zsh"

WITH_CASK=1 "$ROOT_DIR/scripts/common/brew-packages-install.zsh"
