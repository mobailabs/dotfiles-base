#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { echo "[brew] $*"; }
die() { echo "[brew] $*" >&2; exit 1; }

os_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) die "Unsupported OS: $(uname -s)" ;;
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

install_formula() {
  local pkg="$1"
  if brew list --formula "$pkg" >/dev/null 2>&1 < /dev/null; then
    log "formula already installed: $pkg"
  else
    log "installing formula: $pkg"
    brew install "$pkg" < /dev/null
  fi
}

install_cask() {
  local pkg="$1"
  if brew list --cask "$pkg" >/dev/null 2>&1 < /dev/null; then
    log "cask already installed: $pkg"
  else
    log "installing cask: $pkg"
    brew install --cask "$pkg" < /dev/null
  fi
}

main() {
  if ! command -v brew >/dev/null 2>&1; then
    die "brew not found in PATH; run OS brew bootstrap first."
  fi

  local os
  os="$(os_id)"

  local with_cask="${WITH_CASK:-0}"

  local common_cli="$ROOT_DIR/packages/common/brew-cli.txt"
  local os_cli="$ROOT_DIR/packages/$os/brew-cli.txt"
  local macos_cask="$ROOT_DIR/packages/macos/brew-cask.txt"

  log "running: brew update"
  brew update

  local pkgs
  pkgs="$( { read_list "$common_cli"; read_list "$os_cli"; } | sort -u )"
  if [[ -n "$pkgs" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      install_formula "$p"
    done <<<"$pkgs"
  fi

  if [[ "$os" == "macos" && "$with_cask" == "1" ]]; then
    local casks
    casks="$(read_list "$macos_cask" | sort -u)"
    if [[ -n "$casks" ]]; then
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        install_cask "$c"
      done <<<"$casks"
    fi
  fi
}

main "$@"

