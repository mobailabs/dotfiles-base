#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

os_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
}

read_list() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line pkg
  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg%%[[:space:]]*}"
    [[ -n "$pkg" ]] || continue
    echo "$pkg"
  done <"$file"
}

main() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found in PATH; install Homebrew/Linuxbrew first." >&2
    exit 1
  fi

  local os
  os="$(os_id)"

  local common_cli="$ROOT_DIR/packages/common/brew-cli.private.txt"
  local os_cli="$ROOT_DIR/packages/$os/brew-cli.private.txt"
  local macos_cask="$ROOT_DIR/packages/macos/brew-cask.private.txt"

  if [[ "${BREW_UPDATE:-1}" == "1" ]]; then
    brew update
  fi

  local pkgs
  pkgs="$( { read_list "$common_cli"; read_list "$os_cli"; } | sort -u )"
  if [[ -n "$pkgs" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if brew list --formula "$p" >/dev/null 2>&1; then
        echo "brew formula already installed: $p"
      else
        echo "Installing brew formula: $p"
        brew install "$p"
      fi
    done <<<"$pkgs"
  fi

  if [[ "$os" == "macos" ]]; then
    local casks
    casks="$(read_list "$macos_cask" | sort -u)"
    if [[ -n "$casks" ]]; then
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        if brew list --cask "$c" >/dev/null 2>&1; then
          echo "brew cask already installed: $c"
        else
          echo "Installing brew cask: $c"
          brew install --cask "$c"
        fi
      done <<<"$casks"
    fi
  fi
}

main "$@"
