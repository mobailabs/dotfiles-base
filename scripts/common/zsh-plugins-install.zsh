#!/usr/bin/env zsh
#
# 装「Homebrew 里没有」的 zsh 插件。
#
# ## 为什么还留着一份 git clone
#
# zsh 插件有两条来源，**分工是刻意的**：
#
#   1. Homebrew 有 formula 的（zsh-autosuggestions、zsh-completions、
#      zsh-syntax-highlighting…）→ 走 `packages/*/brew-cli.txt`，
#      因为 brew 能升级、能对账（macview 看得见）。
#   2. Homebrew 没有的 → 只能 git clone，就是本文件。
#
# 目前只有 sunlei/zsh-ssh（ssh host 补全）属于第 2 类。
# 判据很简单：`brew info <name>` 找得到就走 brew，找不到才加到这里。
#
# ## 落点
#
# 装到 `$HOME/.zsh/<name>/`，由 `~/.zshrc` 条件 source：
#
#     [[ -f "$HOME/.zsh/<name>/<entry>" ]] && source ...
#
# 加新插件时**别只加这里** —— 还要在 `src/macos/config/zsh/zshrc`
# 里加对应的 source 行，否则装了也不会生效（见 README 的「加载点」）。

set -uo pipefail

# 声明：`名字|仓库|被 zshrc source 的入口文件（相对仓库根）`
# 第三段只是用来在装完后校验入口真的存在，避免 clone 到一个空壳。
ZSH_PLUGINS=(
  'zsh-ssh|https://github.com/sunlei/zsh-ssh.git|zsh-ssh.zsh'
)

ZSH_PLUGINS_DIR="$HOME/.zsh"

install_plugin() {
  local name="$1" repo="$2" entry="$3"
  local dest="$ZSH_PLUGINS_DIR/$name"

  if [[ -d "$dest" ]]; then
    echo "Plugin '$name' already installed at $dest, skipping."
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git not found, cannot install plugin '$name' (skipping)." >&2
    return 0
  fi

  echo "Installing plugin '$name' into $dest ..."
  mkdir -p "$ZSH_PLUGINS_DIR"

  if ! git clone --depth=1 "$repo" "$dest"; then
    echo "Failed to clone plugin '$name' (skipping)." >&2
    return 0
  fi

  # clone 成功但入口不存在 = 装了个不会生效的东西，趁现在说出来。
  if [[ -n "$entry" && ! -f "$dest/$entry" ]]; then
    echo "warn: '$name' cloned but entry '$entry' not found." >&2
    echo "      ~/.zshrc 里 source 它的那行不会生效。" >&2
    return 0
  fi

  echo "Plugin '$name' installed."
}

main() {
  local spec name repo entry
  for spec in "${ZSH_PLUGINS[@]}"; do
    name="${spec%%|*}"
    repo="${${spec#*|}%%|*}"
    entry="${spec##*|}"
    install_plugin "$name" "$repo" "$entry"
  done
}

main "$@"
