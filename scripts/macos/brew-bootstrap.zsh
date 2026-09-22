#!/usr/bin/env zsh

set -euo pipefail

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
  return 0 2>/dev/null || exit 0
fi

echo "Homebrew not found, installing..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

if [[ -x "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
else
  echo "Homebrew install finished but 'brew' is still not available." >&2
  return 1 2>/dev/null || exit 1
fi
