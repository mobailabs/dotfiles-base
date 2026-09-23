#!/usr/bin/env zsh
#
# 确保 brew 可用；没有就先装。
#
# ## 为什么这里还自己探测路径
#
# 仓库里 Homebrew 探测的**共享实现**是 scripts/common/brew-env.zsh。
# 本文件是**唯一不能复用它**的地方：它要在 brew 还没装时先装 brew —— 鸡生蛋问题，
# 它引用的 helper 本身也得先找到 brew。
# 所以这里保留一份最小探测。装完 brew 后，后续步骤一律走 brew-env.zsh。
#
# 另一处不经过 brew-env 的是 src/macos/config/ghostty/start-tmux.sh ——
# 那是 Ghostty 从 launchd 启动的 GUI 上下文，不经过任何 shell 启动文件。
# （.zshenv 里也有一份，那是给普通交互 shell 用的；它只设路径不执行 brew 命令。）

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
