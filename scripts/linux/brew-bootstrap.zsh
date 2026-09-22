#!/usr/bin/env zsh

set -euo pipefail

BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

if [[ -x "$BREW_BIN" ]]; then
  eval "$("$BREW_BIN" shellenv)"
  return 0 2>/dev/null || exit 0
fi

echo "Homebrew (Linuxbrew) not found at /home/linuxbrew/.linuxbrew, installing..."

NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

if [[ -x "$BREW_BIN" ]]; then
  eval "$("$BREW_BIN" shellenv)"
else
  echo "Homebrew install finished but brew is still not found at $BREW_BIN." >&2
  return 1 2>/dev/null || exit 1
fi
