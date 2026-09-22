#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# **执行**而不是 source：bootstrap 里有 `exit`，
# source 进来会把本脚本一起结束，后面的装包就不会跑了。
# 执行是子进程，它 export 的变量不会带回来 —— 所以它自己 eval brew shellenv 就够了，
# 本脚本拿到的 PATH 由下面的 `command -v brew` 兜底。
"$ROOT_DIR/scripts/macos/brew-bootstrap.zsh"

if ! command -v brew >/dev/null 2>&1; then
  # bootstrap 装完 brew 后，新 shell 里才有 /opt/homebrew/bin。
  # 这里补一次，保证同一进程里后续脚本能找到 brew。
  for prefix in /opt/homebrew /usr/local; do
    if [[ -x "$prefix/bin/brew" ]]; then
      eval "$("$prefix/bin/brew" shellenv)"
      break
    fi
  done
fi

WITH_CASK=1 "$ROOT_DIR/scripts/common/brew-packages-install.zsh"
