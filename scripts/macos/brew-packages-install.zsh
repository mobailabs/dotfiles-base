#!/usr/bin/env zsh
#
# 按 packages/*/brew-*.txt 装包。
#
# ## 文件格式（**不要改** —— macview 用同一套解析规则读它）
#
#   - 一行一个包；`#` 之后是注释
#   - 取每行第一个空白分隔字段
#   - 带 tap 的写全路径：`user/tap/formula`（brew 会顺带自动 tap）
#
# macview 的解析器（Sources/MacViewCore/Diff/Software.swift）就是这三条，
# 并把 `user/tap/formula` 取 basename 得到 `formula` 去和 `brew list` 比。
# 所以**不要**引入 `tap:`、`mas:` 之类的前缀语法 —— 那会让两边漂移。
#
# ## 这次补的能力
#
#   1. 「已安装」检查用 basename：`brew list` 只认包名本身（`foo`），
#      不认带 tap 的全路径（`user/tap/foo`）。以前直接拿整行去查，带 tap 的包
#      每次都判为「没装」→ 每次都重装。现在查用 basename、装用全路径。
#   2. 失败汇总：默认跳过失败项继续，结束后统一报告（见 EXIT 段），
#      不再因为一个包失败就中断整轮 —— 但用 `set -o pipefail` 保住错误可见。
#   3. `--dry-run` / `DRY_RUN=1`：只打印将要做什么，不真的装。
#
# 退出码：全部成功 0；有失败 1。便于 install.zsh 和 CI 判断。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { echo "[brew] $*"; }
die() { echo "[brew] $*" >&2; exit 1; }

DRY_RUN="${DRY_RUN:-0}"

# 这个仓库只做 macOS。不假装能跑别的平台 —— 和 check.zsh / brew-audit.zsh 一致。
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "Unsupported OS: $(uname -s)（这个仓库只做 macOS）"
fi
readonly OS_ID="macos"

# 取路径最后一段：`user/tap/formula` → `formula`。
# 与 macview 的 basename() 保持一致 —— 两边的「这个包叫什么」必须同一个答案。
basename_of() {
  local name="$1"
  echo "${name##*/}"
}

read_list() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line pkg
  while IFS= read -r line; do
    pkg="${line%%#*}"
    # 先 ltrim 再取第一个字段，和 macview 的 Swift `split(whereSeparator:)` 一致：
    # 直接 `${pkg%%[[:space:]]*}` 会把 `  zsh` 这种前导空白的行读成空串。
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%%[[:space:]]*}"
    [[ -n "$pkg" ]] || continue
    echo "$pkg"
  done <"$file"
}

install_formula() {
  local pkg="$1"
  local base
  base="$(basename_of "$pkg")"

  if brew list --formula "$base" >/dev/null 2>&1 </dev/null; then
    log "formula already installed: $base"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "would install formula: $pkg"
    return 0
  fi

  log "installing formula: $pkg"
  # 用全路径装：brew 会顺带 tap（`user/tap/formula`）。
  brew install "$pkg" </dev/null
}

install_cask() {
  local pkg="$1"
  local base
  base="$(basename_of "$pkg")"

  if brew list --cask "$base" >/dev/null 2>&1 </dev/null; then
    log "cask already installed: $base"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "would install cask: $pkg"
    return 0
  fi

  log "installing cask: $pkg"
  brew install --cask "$pkg" </dev/null
}

main() {
  if ! command -v brew >/dev/null 2>&1; then
    # 非交互 shell 的 PATH 里可能没有 homebrew（见 brew-env.zsh）。
    source "$SCRIPT_DIR/brew-env.zsh" 2>/dev/null || true
  fi

  if ! command -v brew >/dev/null 2>&1; then
    die "brew not found in PATH; run OS brew bootstrap first."
  fi

  local os="$OS_ID"

  local with_cask="${WITH_CASK:-0}"

  # 仓库只做 macOS，所以不再分 common / macos 两份清单 —— 就一个 brew-cli.txt。
  # （原先的 packages/common/brew-cli.txt 与 packages/macos/brew-cli.txt 已合并。）
  local os_cli="$ROOT_DIR/packages/$os/brew-cli.txt"
  local macos_cask="$ROOT_DIR/packages/macos/brew-cask.txt"

  log "running: brew update"
  [[ "$DRY_RUN" == "1" ]] || brew update

  # 收集失败项，最后一并报告 —— 一个包失败不该让其余的不装。
  local -a failed=()

  local pkgs
  pkgs="$(read_list "$os_cli" | sort -u)"
  if [[ -n "$pkgs" ]]; then
    local p
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      install_formula "$p" || failed+=("formula:$p")
    done <<<"$pkgs"
  fi

  if [[ "$os" == "macos" && "$with_cask" == "1" ]]; then
    local casks
    casks="$(read_list "$macos_cask" | sort -u)"
    if [[ -n "$casks" ]]; then
      local c
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        install_cask "$c" || failed+=("cask:$c")
      done <<<"$casks"
    fi
  fi

  if (( ${#failed[@]} > 0 )); then
    echo "" >&2
    echo "[brew] 完成，但 ${#failed[@]} 个包失败：${failed[*]}" >&2
    echo "[brew] 可以单独重试，或先看上面的报错。" >&2
    exit 1
  fi

  log "全部完成。"
}

main "$@"
