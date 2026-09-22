#!/usr/bin/env zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This macOS setup expects macOS (Darwin)." >&2
  exit 1
fi

if command -v sw_vers >/dev/null 2>&1; then
  echo "macOS version: $(sw_vers -productVersion)"
else
  echo "Running on Darwin (sw_vers not found)."
fi

