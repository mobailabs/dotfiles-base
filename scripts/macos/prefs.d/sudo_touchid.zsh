#!/usr/bin/env bash

set -euo pipefail

echo "  sudo Touch ID"

if [[ -f "/etc/pam.d/sudo" ]] && ! grep -q "pam_tid.so" "/etc/pam.d/sudo"; then
  echo "Enabling Touch ID for sudo (requires admin password)..."
  sudo sh -c 'echo "auth sufficient pam_tid.so" >> /etc/pam.d/sudo'
else
  echo "Touch ID for sudo already configured or /etc/pam.d/sudo not found."
fi

