#!/usr/bin/env zsh
#
# 把仓库里的配置链接到 $HOME。落点声明就在本文件下面（`DOTFILE_LINKS`）。
#
# 仍然只做一件事：让 $HOME 下的落点指向仓库。它不安装软件、不改系统偏好。
#
# ## 为什么落点声明在这个文件里，而不是一份 link.map
#
# 曾经有一份 `link.map`，理由是「落点声明只写一处、不在脚本里硬编码」。
# 现在收回本文件，因为：
#
#   1. 这个仓库只有一个使用者（自己的机器），不是要分发的通用工具。
#      「别处也能读这份声明」这个好处从来没有兑现过。
#   2. 读它要复刻 zsh 的 `read -r a b c` 语义（最后一个变量吃整行）、
#      `#` 从第一个截断、平台列匹配 —— 一整套规则，只为了从文件里读回
#      本可以直接写下的东西。
#   3. 声明在文件里，改落点时不用再想「格式对不对」。
#
# macview（图形界面）自己维护一份落点清单，两边会漂移 —— 但那个漂移
# **是可检测的**：仓库里有源、$HOME 里没有链接，对账时会报出来。
#
# ## 只有 macOS，没有平台回退
#
# 配置源全部在 `src/macos/config/`。以前分 `src/common/config/` 和
# `src/{macos,linux}/config/`，链接时按平台回退 —— 现在只有 macOS 一个平台，
# 那套回退逻辑没有意义，已删除。落点直接写全相对路径。
#
# ## 不再 `rm -rf` 目标
#
# 目标存在时移到备份目录，路径会打印出来。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# ── 落点声明 ────────────────────────────────────────────────────────────
#
# 每行两个字段，用 `|` 分隔：`<仓库内相对路径>|<$HOME 内相对路径>`
#
#   路径都相对于 `src/macos/config/`，源写全相对路径（没有平台回退 —— 这个
#   仓库只有 macOS 一个平台，回退逻辑已经没有意义）。
#
# ⚠️ **改这里就够了。** 这个数组是唯一的声明。
#
# 加一条：在这里加一行，然后确认 src/macos/config/ 下真的有对应的源。
DOTFILE_LINKS=(
  'zsh/zshenv|.zshenv'
  'zsh/zprofile|.zprofile'
  'zsh/zshrc|.zshrc'
  'aliases|.aliases'
  'env/exports|.exports'
  'shell/funcs|.funcs'
  'zsh/oh-my-zsh.sh|.oh-my-zsh.sh'
  'zsh/os.zsh|.config/dotfiles/os.zsh'
  'zsh/ohmyzsh.plugins.zsh|.config/dotfiles/ohmyzsh.plugins.zsh'
  'tmux/tmux.conf|.tmux.conf'
  'tmux/config|.config/tmux'
  'nvim|.config/nvim'
  'git/gitconfig|.gitconfig'
  'mise/config.toml|.config/mise/config.toml'
  'env/envconfig|.envconfig'
  'shell/bash_profile|.bash_profile'
  'ghostty|.config/ghostty'
)

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

  local src="$ROOT_DIR/src/macos/config/$rel"
  link_path "$src" "$dest"
}

main() {
  BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

  local entry src_rel dest_rel

  for entry in "${DOTFILE_LINKS[@]}"; do
    # `|` 分隔而不是空白：路径里可能有空格（`Application Support` 之类），
    # 而用空白分隔就必须靠「几个空格」来对齐，改一条就得重排整块。
    src_rel="${entry%%|*}"
    dest_rel="${entry#*|}"

    link_rel "$src_rel" "$HOME/$dest_rel"
  done
}

main "$@"
