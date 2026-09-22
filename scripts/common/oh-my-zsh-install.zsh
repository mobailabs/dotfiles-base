#!/usr/bin/env zsh

set -euo pipefail

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  echo "Oh My Zsh already installed at $HOME/.oh-my-zsh, skipping."
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git not found, cannot install Oh My Zsh automatically." >&2
  exit 1
fi

echo "Installing Oh My Zsh into $HOME/.oh-my-zsh ..."

git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"

echo "Oh My Zsh installed."

