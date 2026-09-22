#!/usr/bin/env zsh

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This Linux setup expects Linux." >&2
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "Cannot detect distro: /etc/os-release not found." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
  ubuntu|debian) ;;
  *)
    echo "Only Ubuntu/Debian are supported (ID=${ID:-unknown})." >&2
    exit 1
    ;;
esac

echo "Linux detected: ${PRETTY_NAME:-$ID}"

for cmd in curl git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    echo "Tip: on Ubuntu/Debian, run: ./install.sh" >&2
    exit 1
  fi
done
