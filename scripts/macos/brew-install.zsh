#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# **执行**而不是 source：bootstrap 里有 `exit`，
# source 进来会把本脚本一起结束，后面的装包就不会跑了。
# 执行是子进程，它 export 的变量不会带回来 —— 所以它自己 eval brew shellenv 就够了，
# 本脚本拿到的 PATH 由下面的 brew-env 兜底。
"$ROOT_DIR/scripts/macos/brew-bootstrap.zsh"

# bootstrap 装完 brew 后，新 shell 里才有 /opt/homebrew/bin。
# 这里用共享的 brew-env 把 brew 环境补进本进程（同一套探测，不各写一份），
# 保证后续脚本在本进程里能找到 brew。
source "$ROOT_DIR/scripts/macos/brew-env.zsh" || true

if ! command -v brew >/dev/null 2>&1; then
  echo "brew-install: 引导后仍找不到 brew。" >&2
  exit 1
fi

# 修掉 Homebrew 留下的「补全目录 group 可写」—— 否则每次开 shell 都会看到
# oh-my-zsh 的 insecure directories 警告。原因、为什么这么修见该脚本顶部注释。
# 放在装包**之前**：这样后面的步骤（以及用户装完第一次开 shell）都不带警告。
# 用 `|| true`：这是锦上添花的修补，失败不该让装包这步失败。
"$ROOT_DIR/scripts/macos/brew-fix-completions-perms.zsh" || true

WITH_CASK=1 "$ROOT_DIR/scripts/macos/brew-packages-install.zsh"
