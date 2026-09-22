#!/usr/bin/env zsh

set -euo pipefail

log() { echo "[tmux] $*"; }

main() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  local tpm_repo="https://github.com/tmux-plugins/tpm"

  if ! command -v tmux >/dev/null 2>&1; then
    log "tmux not found, skip TPM/plugin installation"
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    log "git not found, skip TPM/plugin installation"
    return 0
  fi

  if [[ ! -d "$tpm_dir" ]]; then
    log "installing TPM: $tpm_dir"
    mkdir -p "$(dirname "$tpm_dir")"
    git clone "$tpm_repo" "$tpm_dir"
  else
    log "TPM already installed: $tpm_dir"
  fi

  if [[ ! -f "$HOME/.tmux.conf" ]]; then
    log "~/.tmux.conf not found, skip plugin installation"
    return 0
  fi

  if [[ ! -x "$tpm_dir/bin/install_plugins" ]]; then
    log "TPM install script not found, skip plugin installation"
    return 0
  fi

  log "installing tmux plugins from ~/.tmux.conf"
  export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/"
  "$tpm_dir/bin/install_plugins"

  log "tmux plugins installation finished"
}

main "$@"
