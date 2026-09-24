#!/usr/bin/env zsh
#
# 确保 brew 可用；没有就先装。
#
# ## 为什么这里还自己探测路径
#
# 仓库里 Homebrew 探测的**共享实现**是 scripts/macos/brew-env.zsh。
# 本文件是**唯一不能复用它**的地方：它要在 brew 还没装时先装 brew —— 鸡生蛋问题，
# 它引用的 helper 本身也得先找到 brew。
# 所以这里保留一份最小探测。装完 brew 后，后续步骤一律走 brew-env.zsh。
#
# （.zshenv 里也有一份，那是给交互 shell 用的；它只设路径、不执行 brew 命令。）

set -uo pipefail

# 已经能用就什么都不做（eval shellenv 把 HOMEBREW_* 和 PATH 补齐）。
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
  exit 0
fi

echo "Homebrew not found, installing..."

# ⚠️ 装之前**确认有 sudo 授权**。
#
# 为什么单独这一步：下面的 install.sh 带了 `NONINTERACTIVE=1`，它**绝不会
# 提示密码** —— 没有缓存时它会直接失败退出，而且**不会停下来等你**
# （"Input is required, but 'NONINTERACTIVE' is set" 之类）。
# 所以这里是全流程唯一「必须提前拿到授权」的地方。
#
# 有终端就就地弹一次密码（会等你输入）；拿不到就**明确报错**，
# 不要假装在装、最后丢一个看不懂的 Homebrew 报错。
if ! sudo -n true 2>/dev/null; then
  if [[ -t 0 ]]; then
    echo "安装 Homebrew 需要管理员权限，请输入密码："
    if ! sudo -v; then
      echo "brew-bootstrap: 未获得管理员权限，无法安装 Homebrew。" >&2
      echo "  可以手动安装后重跑：https://brew.sh" >&2
      exit 1
    fi
  else
    echo "brew-bootstrap: 需要管理员权限安装 Homebrew，但当前没有终端可输入密码。" >&2
    echo "  请在有终端的交互 shell 里重跑，或先手动安装 Homebrew：https://brew.sh" >&2
    exit 1
  fi
fi

# NONINTERACTIVE=1：install.sh 不提问、不要求按回车确认。
# 这是「一条命令后走开」的前提 —— 否则会在「Press RETURN to continue」处卡住。
# sudo 授权由上面那一步保证（开头 prompt-once 的预授权可能已过期，
# 后台 keep-alive 也未必刷得动 —— 所以这里就近再确认一次，不指望它们）。
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
