#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

is_linux() {
  [ "$(uname -s 2>/dev/null || echo)" = "Linux" ]
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

main() {
  if ! is_linux; then
    echo "install.sh is intended for Ubuntu/Debian Linux bootstrap only." >&2
    echo "On macOS, run: zsh install.zsh" >&2
    exit 1
  fi

  if [ ! -f /etc/os-release ]; then
    echo "Cannot detect distro: /etc/os-release not found." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *)
      echo "Only Ubuntu/Debian are supported (ID=$ID)." >&2
      exit 1
      ;;
  esac

  missing=""
  for cmd in zsh git curl cc make file ps; do
    if ! require_cmd "$cmd"; then
      missing="$missing $cmd"
    fi
  done

  if [ -n "$missing" ]; then
    if ! require_cmd apt-get; then
      echo "apt-get not found; expected Ubuntu/Debian." >&2
      exit 1
    fi

    if require_cmd sudo; then
      sudo apt-get update
      sudo apt-get install -y zsh git curl ca-certificates build-essential procps file ncurses-term
    else
      apt-get update
      apt-get install -y zsh git curl ca-certificates build-essential procps file ncurses-term
    fi
  fi

  exec zsh "$ROOT_DIR/install.zsh" base
}

main "$@"
