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

  # 判 ~/.tmux.conf 而不是 ~/.config/tmux/tmux.conf：
  # 这是本仓库的约定，因为 ~/.tmux.conf 一定会被链接（见 DOTFILE_LINKS 的
  # 'tmux/tmux.conf|.tmux.conf'）。⚠️ TPM 自己**不**看这个 —— 它的
  # _get_user_tmux_conf 优先 XDG 路径（~/.config/tmux/tmux.conf）。
  # 这里只是「配置到位了没」的代理判断：两条落点一起建，判哪个都行，
  # 选了个更老的入口。别删这条链接 —— 删了这里就会静默跳过插件安装。
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
