#!/usr/bin/env zsh
#
# 预检：在装任何东西**之前**，把「走不下去」的原因一次说清。
#
# ## 为什么要有这个文件
#
# `install.zsh` 是 `set -e` 一条路走到底。以前依赖缺失会在中途某一步炸：
# 走到第 7 步的 mise-setup 才发现没有 mise，前面的功夫白费，
# 而且报错是那一步自己的语言，不是「这台机器缺了什么」。
#
# 这里把关键依赖集中检查，**失败在第一步就发生**，且一次列全。
#
# ## 分级
#
#   - 硬依赖（缺了就没法继续）：macOS、git、网络
#   - 软依赖（缺了由后续脚本自己引导）：brew、mise
#     —— brew 由 scripts/macos/brew-bootstrap.zsh 自动装，
#        mise 由 brew 装（在 packages/common/brew-cli.txt 里），
#        所以它们**缺失是正常的**，这里只提示会怎么补，不报错。

set -uo pipefail

fatal=()
warn=()

# ---- 硬依赖 ----
if [[ "$(uname -s)" != "Darwin" ]]; then
  fatal+=("这台是 $(uname -s)，仓库只做 macOS")
else
  if command -v sw_vers >/dev/null 2>&1; then
    echo "macOS version: $(sw_vers -productVersion)"
  else
    echo "Running on Darwin (sw_vers not found)."
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  fatal+=("找不到 git（链接配置、装插件都要用）")
fi

# 网络：能连到 github 就行（brew / git clone 都依赖它）。
# 用 curl 短超时，别让预检本身卡住。
if command -v curl >/dev/null 2>&1; then
  if ! curl -fsSL --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
    warn+=("连不上 github.com —— 后面的 brew / git clone 很可能失败")
  fi
fi

# ---- 软依赖（会被自动补） ----
if ! command -v brew >/dev/null 2>&1; then
  warn+=("没有 Homebrew —— brew-install 会先自动安装它")
fi

if ! command -v mise >/dev/null 2>&1; then
  warn+=("没有 mise —— 它会在 brew 阶段被装上，之后才跑 mise install")
fi

# ---- 汇报 ----
if (( ${#warn[@]} > 0 )); then
  echo
  echo "提示："
  printf '  - %s\n' "${warn[@]}"
fi

if (( ${#fatal[@]} > 0 )); then
  echo
  echo "无法继续：" >&2
  printf '  - %s\n' "${fatal[@]}" >&2
  exit 1
fi

echo "预检通过。"
