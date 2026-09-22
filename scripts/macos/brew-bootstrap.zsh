#!/usr/bin/env zsh
#
# 确保 brew 可用；没有就先装。
#
# ## 为什么这里还自己探测路径
#
# README 说「Homebrew 探测只写一处（.zshenv）」。本文件是**唯一例外**，
# 而且是必须的：它在 `install.zsh` 里跑，这时候新机器可能
#   1. 还没装 Homebrew，或
#   2. 装了但本 shell 还没 source 过 .zshenv（install.zsh 不是交互 shell）
# 所以它得自己找。装完 brew 后，后续 shell 就都由 .zshenv 接管了。
#
# 另一处例外是 src/macos/config/ghostty/start-tmux.sh ——
# 那是 Ghostty 从 launchd 启动的 GUI 上下文，同样不经过 .zshenv。

set -uo pipefail

# 已经能用就什么都不做（eval shellenv 把 HOMEBREW_* 和 PATH 补齐）。
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
  exit 0
fi

echo "Homebrew not found, installing..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

if [[ -x "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
else
  echo "Homebrew install finished but 'brew' is still not available." >&2
  exit 1
fi
