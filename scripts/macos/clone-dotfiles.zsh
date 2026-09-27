#!/usr/bin/env zsh
#
# 把 dotfiles 仓库 clone 到本机。**这是 macview 那个「下载仓库」能力背后的
# 全部实现** —— macview 自己不跑 git、不写磁盘（契约 §三），只按这个按钮。
#
# ## 为什么这个脚本存在
#
# macview 定位是「脚本控制器」：它显示状态、按按钮调脚本。它**没有 clone
# 仓库的能力**，而一台新电脑上打开它，第一件事就是「没找到 dotfiles 仓库」——
# 没有这条路，用户只能自己去终端敲 git clone。所以能力落在本仓库这边。
#
# ## ⚠️ 它**只**做 clone，不做任何别的事
#
# clone 完就停。**不跑 install.zsh、不链接配置、不改偏好** —— 那些是
# 「配置这台 Mac」按钮的事（`install.zsh`）。把两件事混在一起会让人以为
# 「下载仓库」= 把这台机器配好了，而它其实只是把文件拿到手。
#
# ## URL 为什么是参数而不是写死
#
# 写死一个 URL 的话：别人的 fork、镜像、内网地址全都用不了，而报错信息
# （「repository not found」）会让人以为是网络问题。所以默认给本仓库的
# 公开地址，但**允许改**——macview 那边应该让用户能填。
#
# ## 安全性：绝不覆盖已有目录
#
# 这是最要紧的一条。`git clone` 到一个**已存在的非空目录**会失败，但
# **万一它失败的方式是合并**（或者将来 git 改了行为），用户已有的配置就
# 完了。所以这里在 clone 之前自己先查：目录存在且非空 → **拒绝，不动它**。
# 「下载仓库」按错了的代价（毁掉一台机器的配置）远大于收益。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 默认 URL。**可以覆盖**（`--url`），理由见文件头。
DEFAULT_URL="https://github.com/mobailabs/dotfiles-base.git"

usage() {
  cat <<EOF
Usage: zsh scripts/macos/clone-dotfiles.zsh [options]

Options:
  --url <地址>   从哪个仓库 clone（默认：$DEFAULT_URL）
  --dest <目录>  clone 到哪（默认：\$HOME/dotfiles）
  --force        目标目录**存在但为空**时也继续（默认会拒绝，见下）
  -h, --help     显示这段

退出码：
  0  成功
  1  失败（网络 / 目录不安全 / 目标非空 / git 不在）
  2  用法错（未知参数）
EOF
}

url="$DEFAULT_URL"
dest="$HOME/dotfiles"
force=0

while (( $# > 0 )); do
  case "$1" in
    --url)  url="${2:-}"; shift 2 ;;
    --dest) dest="${2:-}"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── 参数校验 ─────────────────────────────────────────────────────────────

if [[ -z "$url" ]]; then
  echo "Error: --url 给了空地址。" >&2
  exit 2
fi

# 目标绝对化（还没建目录，所以不用 -realpath）
if [[ "$dest" != /* ]]; then
  dest="$PWD/$dest"
fi

# `assert_safe_dest` 那套检查：绝不 clone 到 / 或 $HOME 本身，绝不带 `..`。
# 抄 link-dotfiles.zsh 的判据（那里是为了不 rm 错，这里是为了不写错地方）。
if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME 没设；不克隆。" >&2
  exit 1
fi
if [[ "$dest" == "/" || "$dest" == "$HOME" ]]; then
  echo "Error: 目标目录不安全：$dest" >&2
  exit 1
fi
case "/$dest/" in
  *"/../"*) echo "Error: 目标目录不能含 '..'：$dest" >&2; exit 1 ;;
esac
if [[ "$dest" != "$HOME"/* && "$dest" != "$HOME" ]]; then
  # 只允许落在 $HOME 底下 —— clone 到 /tmp 或 /usr/local 明显不是用户的意思。
  echo "Error: 目标目录必须在 \$HOME 底下：$dest" >&2
  exit 1
fi

# ── 前置：git 在不在 ─────────────────────────────────────────────────────
#
# 问不出来（`unknown`）时**不**当成「没有」—— 那会让一台装好的机器去重装
# git。这里只在真的确认「没有」时才停。
if ! command -v git >/dev/null 2>&1; then
  echo "Error: 这台机器上没有 git，clone 不了。" >&2
  echo "       先装命令行工具（xcode-select --install），装完再来。" >&2
  exit 1
fi

# ── 目标目录检查（安全的关键一步）─────────────────────────────────────────
#
# 三种情况：
#   · 不在            → 直接 clone
#   · 在但是空目录     → clone（`--force` 才放行空目录的情况下面注释有解释）
#   · 在而且非空       → **拒绝**，一个字都不动
if [[ -e "$dest" ]]; then
  if [[ ! -d "$dest" ]]; then
    echo "Error: $dest 已经存在，而且不是目录。没动它。" >&2
    exit 1
  fi

  # 非空判定：目录里有**任何**一个条目（含隐藏文件）就算非空。
  # 不用 `find`（慢且会跟着符号链接走），用 glob 配 nullglob。
  setopt local_options nullglob
  entries=("$dest"/* "$dest"/.[!.]* "$dest"/..?*)
  if (( ${#entries} > 0 )); then
    echo "Error: $dest 已经存在而且不是空目录 —— **没动它**。" >&2
    echo "       那里可能已经是一份配置了，clone 进去会毁掉它。" >&2
    echo "       要换地方就指定 --dest；要更新已有的仓库用 git -C \"$dest\" pull。" >&2
    exit 1
  fi

  # 空目录。clone 本身对空目录是安全的，但这里仍然要求 --force ——
  # 「空」可能是用户刚 mkdir 出来准备放别的东西，误装了不好收拾。
  if (( ! force )); then
    echo "Error: $dest 已存在（空目录）。加 --force 才继续。" >&2
    exit 1
  fi
fi

# ── clone ────────────────────────────────────────────────────────────────
#
# 进度直接透给上层（macview 那边会实时显示），不自己包装。
echo "Cloning from: $url"
echo "         to:   $dest"
echo

# `--depth=1` 还是完整 clone？
#   · 完整：用户之后能看历史、能改能提 PR、能切分支
#   · 浅：快、省磁盘，但**提不了 PR、只能看当前那一个版本**
#
# dotfiles 是「配置即代码」，用户很可能会改它并提 PR —— 所以**要完整历史**。
# 这也是为什么这一条要在注释里说清：省那点磁盘换来「不能改自己的配置」不值。
if ! git clone "$url" "$dest"; then
  # ⚠️ **不能在这里读 `$?` 报「退出码 N」。**
  # 进了 `if ! cmd` 这个分支之后 `$?` 是**取反之后**的值（几乎总是 0），
  # 拿它当 git 的退出码会报出「clone 失败（退出码 0）」这种自相矛盾的话
  # （踩过）。git 的话术已经在上面那一屏里了，这里不再复述一个错的数。
  echo >&2
  echo "Error: clone 失败。" >&2
  # 失败之后 git 有可能留下半个目录 —— 说清楚它是什么，别让用户以为是「好了」。
  if [[ -d "$dest" ]]; then
    echo "       目标目录 $dest 还在（可能是 clone 的一半），" >&2
    echo "       要重来的话先把它删掉，或者换个 --dest。" >&2
  fi
  echo "       常见原因：网络不通 / 地址不对 / 没有那个仓库的权限。" >&2
  echo "       git 自己说的话在上面那几行里。" >&2
  exit 1
fi

# ── 验一下拿到手的东西对不对 ──────────────────────────────────────────────
#
# clone 退出 0 **不等于**拿到的是 dotfiles。空仓库、或者地址指到别的东西，
# 都会安静地「成功」。所以确认几个标记文件在。
#
# 这一步是「clone 成功」和「拿到能用的 dotfiles」的区别 —— 界面接下来会
# 拿它跑 preflight，所以这里先说清楚，别让用户走到下一步才发现。
missing=()
[[ -f "$dest/install.zsh" ]]            || missing+=("install.zsh")
[[ -d "$dest/scripts/macos" ]]          || missing+=("scripts/macos/")
[[ -d "$dest/src/macos/config" ]]        || missing+=("src/macos/config/")

if (( ${#missing} > 0 )); then
  echo "Warning: clone 完成了，但里面不像是一份 dotfiles —— 缺：" >&2
  printf '  · %s\n' "${missing[@]}" >&2
  echo "       地址可能指到了别的仓库。确认一下 $dest 里的东西。" >&2
  # ⚠️ 仍然 exit 0：clone **确实**成功了。「不像 dotfiles」是提醒，不是失败 ——
  # 退出码非 0 会让 macview 显示成「clone 失败」，那是假消息。
  exit 0
fi

echo
echo "Done: $dest"
echo "仓库只是**拿到手**了 —— 配置还没生效。要链接配置、应用偏好、装软件，"
echo "回 macview 点「配置这台 Mac」（或者终端里跑 zsh $dest/install.zsh）。"
