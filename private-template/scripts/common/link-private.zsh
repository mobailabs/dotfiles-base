#!/usr/bin/env zsh
#
# 把私有仓库里的 overlay 链接到 $HOME。
#
# 覆盖的三个落点是公开仓库的加载点读取的：
#   ~/.gitconfig.local   ← 被 ~/.gitconfig 的 [include] 读取
#   ~/.zshrc.local       ← 被 ~/.zshrc 第 30 行 source
#   ~/.envconfig.local   ← 被 ~/.envconfig 条件 source
#
# **不直接删除目标**。旧版这里是 `rm -rf "$dest"`，而 ~/.envconfig.local
# 在很多机器上是一个装着机器专属变量的真文件 —— 跑一次就没了。
# 现在改为先备份到 ~/.dotfiles-backup/<时间戳>/，路径会打印出来。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 一次运行只算一个时间戳，否则同一轮里被替换的几个落点会散进不同目录
BACKUP_ROOT=""

os_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
}

pick_source() {
  local rel="$1"
  local os
  os="$(os_id)"

  local os_path="$ROOT_DIR/src/$os/config/$rel"
  local common_path="$ROOT_DIR/src/common/config/$rel"

  if [[ -e "$os_path" || -L "$os_path" ]]; then
    echo "$os_path"
    return 0
  fi
  if [[ -e "$common_path" || -L "$common_path" ]]; then
    echo "$common_path"
    return 0
  fi
  return 1
}

assert_safe_dest() {
  local dest="$1"
  if [[ -z "${HOME:-}" || -z "$dest" ]]; then
    echo "Error: unsafe destination" >&2
    exit 1
  fi
  if [[ "$dest" == "/" || "$dest" == "$HOME" ]]; then
    echo "Error: unsafe destination: $dest" >&2
    exit 1
  fi
  # 挡住 `..` —— 只检查 `$HOME/*` 前缀的话，`$HOME/../etc/passwd` 是能溜过去的。
  # 用 `/` 包住再匹配 `/../`，这样 `.config/my..dir` 这种合法名字不会被误伤。
  case "/$dest/" in
    *"/../"*) echo "Error: destination must not contain '..': $dest" >&2; exit 1 ;;
  esac
  case "$dest" in
    "$HOME"/*) ;;
    *) echo "Error: destination must be under HOME: $dest" >&2; exit 1 ;;
  esac
}

# 目标已存在时先搬走，不删除。
# 目标名已存在就加 .1 / .2 后缀 —— 否则把 DOTFILES_BACKUP_DIR 设成固定目录时，
# 第二次运行会静默覆盖第一次的备份。
backup_dest() {
  local dest="$1"
  local flat="${dest#"$HOME"/}"
  flat="${flat//\//__}"
  local target="$BACKUP_ROOT/$flat"
  local i=1

  while [[ -e "$target" ]]; do
    target="$BACKUP_ROOT/$flat.$i"
    i=$((i + 1))
  done

  mkdir -p "$BACKUP_ROOT"
  mv "$dest" "$target"
  echo "Backed up: $dest -> $target"
}

link_path() {
  local src="$1"
  local dest="$2"

  assert_safe_dest "$dest"

  [[ -e "$src" || -L "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest" || true)"
    if [[ "$current" == "$src" ]]; then
      return 0
    fi
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    backup_dest "$dest"
  fi

  ln -s "$src" "$dest"
  echo "Linked: $dest -> $src"
}

link_rel() {
  local rel="$1"
  local dest="$2"
  local src
  src="$(pick_source "$rel")" || return 0
  link_path "$src" "$dest"
}

main() {
  BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

  # 公开仓库的加载点会读取这三个 overlay
  link_rel "git/gitconfig.local" "$HOME/.gitconfig.local"
  link_rel "zsh/zshrc.local" "$HOME/.zshrc.local"
  link_rel "env/envconfig.local" "$HOME/.envconfig.local"
}

main "$@"
