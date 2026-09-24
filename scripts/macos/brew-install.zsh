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

WITH_CASK=1 "$ROOT_DIR/scripts/macos/brew-packages-install.zsh"
