#!/usr/bin/env zsh
#
# 按 link.map 把仓库里的配置链接到 $HOME。
#
# 与旧版的两处区别：
#   1. 落点不再硬编码在本文件里 —— 读仓库根目录的 link.map（唯一一份声明）
#   2. 不再 `rm -rf` 目标 —— 先移到备份目录，路径会打印出来
#
# 仍然只做一件事：让 $HOME 下的落点指向仓库。它不安装软件、不改系统偏好。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"
MAP_FILE="$ROOT_DIR/link.map"

assert_safe_dest() {
  local dest="$1"

  if [[ -z "${HOME:-}" ]]; then
    echo "Error: HOME is not set; refusing to link dotfiles." >&2
    exit 1
  fi

  if [[ -z "$dest" ]]; then
    echo "Error: empty destination path; refusing to remove/link." >&2
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
    *)
      echo "Error: destination must be under HOME: $dest" >&2
      exit 1
      ;;
  esac
}

os_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) echo "unknown" ;;
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

# 一次运行里的备份根目录。**只算一次** —— 否则同一轮里被替换的几个落点
# 会因为跨秒而散进不同的时间戳目录，事后不好找。
BACKUP_ROOT=""

# 目标已存在时不再直接删除，而是移到带时间戳的备份目录。
# 路径会打印出来 —— 「退得回」是这个仓库的硬要求。
#
# 目标名已存在就加 .1 / .2 后缀：否则把 DOTFILES_BACKUP_DIR 设成一个固定目录时，
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

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "Skip (source missing): $src"
    return
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest" || true)"
    if [[ "$current" == "$src" ]]; then
      echo "Already linked: $dest -> $src"
      return
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
  src="$(pick_source "$rel")" || {
    echo "Skip (source not found in src/{common,$(os_id)}): $rel"
    return 0
  }
  link_path "$src" "$dest"
}

main() {
  if [[ ! -f "$MAP_FILE" ]]; then
    echo "Error: $MAP_FILE not found; nothing to link." >&2
    exit 1
  fi

  BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

  local os
  os="$(os_id)"
  local src_rel dest_rel plat

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue

    src_rel=""
    dest_rel=""
    plat=""
    read -r src_rel dest_rel plat <<< "$line"
    [[ -z "$src_rel" || -z "$dest_rel" ]] && continue

    if [[ -n "$plat" && "$plat" != "$os" ]]; then
      echo "Skip (platform $plat): $dest_rel"
      continue
    fi

    link_rel "$src_rel" "$HOME/$dest_rel"
  done < "$MAP_FILE"
}

main "$@"
