#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"

main() {
  "$SCRIPT_DIR/scripts/common/brew-private-install.zsh"

  # Optional: reveal and install secrets (best-effort)
  if [[ "${SKIP_SECRETS:-0}" != "1" ]]; then
    if [[ -d "$SCRIPT_DIR/.git" && -d "$SCRIPT_DIR/.gitsecret" && -f "$SCRIPT_DIR/scripts/secret-helper.zsh" ]]; then
      if command -v git-secret >/dev/null 2>&1; then
        zsh "$SCRIPT_DIR/scripts/secret-helper.zsh" reveal-install || {
          echo "Warning: secrets reveal/install failed (continuing). Set SKIP_SECRETS=1 to skip." >&2
        }
      else
        echo "Warning: git-secret not found; skipping secrets. (Install via brew: git-secret)" >&2
      fi
    fi
  fi

  "$SCRIPT_DIR/scripts/common/link-private.zsh"
}

main "$@"
