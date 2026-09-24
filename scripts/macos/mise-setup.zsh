#!/usr/bin/env zsh

set -euo pipefail

if ! command -v mise >/dev/null 2>&1; then
  echo "mise not installed. This setup requires mise (install via brew)." >&2
  exit 1
fi

echo "mise detected: $(command -v mise)"

echo "Running 'mise install'..."
mise install

