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
                 \`~\` 会展开；软链接会解析后再判（在 \$HOME 下才放行）
  -h, --help     显示这段

退出码：
  0  成功（含「拿到了不像 dotfiles 的东西」那种警告）
  1  失败（网络 / 目录不安全 / 目标非空或读不了 / git 不在）
  2  用法错（未知参数 / 空地址 / 地址以 '-' 开头）
EOF
}

url="$DEFAULT_URL"
dest="$HOME/dotfiles"

while (( $# > 0 )); do
  case "$1" in
    --url)  url="${2:-}"; shift 2 ;;
    --dest) dest="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── 参数校验 ─────────────────────────────────────────────────────────────

if [[ -z "$url" ]]; then
  echo "Error: --url 给了空地址。" >&2
  exit 2
fi

# ⚠️ **地址不能以 `-` 开头**（review 抓到）。
# url 是 `git clone` 的**第一个位置参数**，排在 `--upload-pack` 后面 ——
# `git clone --upload-pack=<命令> <url> <dest>` 是历史上出名的执行面。
# 从网页复制地址一般不会这样，但它是个输入，不该指望用户不手滑。
if [[ "$url" == -* ]]; then
  echo "Error: 仓库地址不能以 '-' 开头 —— git 会把它当成选项，而不是仓库。" >&2
  exit 2
fi

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME 没设；不克隆。" >&2
  exit 1
fi

# ── 目标路径：展开 `~` → 绝对化 → 解析软链接 ─────────────────────────────
#
# ⚠️ **三步都要做，而且判据和执行必须用同一个串**（review 一次抓到三处）。
#
# 1. **`~` 展开**：任何 mac 用户最自然的输入是 `~/dotfiles`。不展开的话它
#    既过不了「在 $HOME 下」这条，还会**被当成一个字面量目录名** ——
#    实测 `--dest '~/x'` 会去 clone 到 `./~/x`，在当前目录里造一个名叫 `~`
#    的文件夹。`--dest` 目标绝对化那行处理不了它（`~` 不是相对路径，
#    以 `/` 开头也不行，所以它原样留着）。
# 2. **绝对化**：相对路径按当前目录解释。GUI 里 CWD 可能是 `/`，
#    所以相对路径几乎肯定不是用户的意思，但也不该崩。
# 3. **解析软链接**：`~/link -> /Users/Shared` 时，`~/link/evil` **词法上**
#    在 $HOME 下，**实际写到 /Users/Shared/evil**。必须解析完再判。
case "$dest" in
  "~")      dest="$HOME" ;;
  "~/"*)    dest="$HOME/${dest#\~/}" ;;
  /*)       ;;
  *)        dest="$PWD/$dest" ;;
esac

# 吸收 `//`、`.`、尾斜杠 —— 不做的话 `/Users/x/` ≠ `/Users/x`，
# 「目标 = $HOME」那条会被尾斜杠绕过。
dest="${dest%/}"
while [[ "$dest" == *//* ]]; do dest="${dest//\/\///}"; done

# 解析**已存在那一段前缀**的软链接。用 python3 是因为 macOS 自带、
# 而 zsh 没有内建的 realpath。拿不到就**不解析**（下面的判据仍然生效，
# 只是软链接那条会漏判 —— 宁可漏判也不要在这里崩掉）。
if command -v python3 >/dev/null 2>&1; then
  dest="$(python3 -c '
import os, sys
p = sys.argv[1]
# realpath 会解析**已存在**的那一段；后面不存在的部分原样留着。
print(os.path.realpath(p))
' "$dest" 2>/dev/null)" || dest="$dest"
fi

# 判据（抄 link-dotfiles.zsh 的 `assert_safe_dest` —— 那里是为了不 rm 错，
# 这里是为了不写错地方）。**全部拿解析后的 `dest` 判。**
if [[ "$dest" == "/" || "$dest" == "$HOME" ]]; then
  echo "Error: 目标目录不安全：$dest" >&2
  exit 1
fi
case "/$dest/" in
  *"/../"*) echo "Error: 目标目录不能含 '..'：$dest" >&2; exit 1 ;;
esac
if [[ "$dest" != "$HOME"/* ]]; then
  # 只允许落在 $HOME 底下 —— clone 到 /tmp 或 /usr/local 明显不是用户的意思。
  # ⚠️ 报的是**解析后**的路径：软链接写到哪去了，用户要看得见。
  echo "Error: 目标目录必须在 \$HOME 底下（它实际指向 $dest）。" >&2
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
# 四种情况：
#   · 不在              → 直接 clone
#   · 在但是空目录       → clone（**没有东西可毁**，所以放行）
#   · 在而且非空         → **拒绝**，一个字都不动
#   · 在但读不了         → **拒绝**（见下，这是 review 补的第四种）
if [[ -e "$dest" || -L "$dest" ]]; then
  if [[ -L "$dest" && ! -d "$dest" ]]; then
    # 断掉的软链接：`lstat` 说在、`stat` 说不在。
    echo "Error: $dest 是断掉的软链接。没动它。" >&2
    exit 1
  fi
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

  # ⚠️ **读不出来 ≠ 空**（review 抓到）。glob 在没权限时**不报错**，只是
  # 匹配不到任何东西 —— 于是「读不了的目录」会被当成「空目录」放行，
  # 那正是本仓库到处在守的「问不出来 ≠ 没有」。
  # 所以这里**显式问一次**：能不能列它。
  if ! ls -A "$dest" >/dev/null 2>&1; then
    echo "Error: $dest 那个目录我读不了 —— 没法判断里面有没有东西，**没敢动它**。" >&2
    exit 1
  fi

  # 空目录 → 放行。
  # ⚠️ 早先这里要求 `--force`，而**那个参数从设计上就没被 UI 传过**，
  # 于是这条拒绝永远走不出去、话术还叫用户「再点一次」—— 点一万次也一样。
  # 空目录里没有任何东西可毁，放行才是对的。已删 --force（review 抓到）。
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
