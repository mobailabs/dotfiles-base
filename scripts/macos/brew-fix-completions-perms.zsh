#!/usr/bin/env zsh
#
# 修掉 Homebrew 留下的「补全目录 group 可写」，消除每次开 shell 的 oh-my-zsh 警告。
#
# ## 为什么需要这个
#
# oh-my-zsh 启动时会用 zsh 自带的 `compaudit` 审计补全目录：只要某个目录
# **group 或 other 可写**，它就拒绝从那里加载补全，并在每次开 shell 时打印
# 一大段 "Insecure completion-dependent directories detected" 警告。
#
# 而 Homebrew 官方安装脚本（非 .pkg）会把 `$(brew --prefix)/share` 建成
# `drwxrwxr-x <你>:admin` —— group（admin）可写，正好踩中 compaudit 的规则。
# 于是**每个用官方脚本装 Homebrew 的人**都会一直看到那段警告。
#
# 实测（macOS 26 + Homebrew 7.0.6 + zsh 5.9.2）：报出的是 `$(brew --prefix)/share`
# **它自己** —— 它是 fpath 里 `/opt/homebrew/share/zsh-completions` 等目录的**父目录**，
# 而 compaudit 会连带检查 fpath 项的父目录（防止有人在父目录里放 digest 文件，
# 冒充补全目录的可信签名）。所以即使 owner 是你，这个 group 可写的父目录照样被报。
#
# （题外：compaudit 源码里那个「owner 是你或 root 就放行」的例外，在 zsh 5.9.2 上
#  对 `u0u501` 这种拼法并不生效 —— 实测 `-u0u501` 两个 owner 都匹配不到。这也是
#  为什么这个警告在 macOS 上这么常见。不管例外生不生效，去掉 group 写权限都是对的。）
#
# ## 为什么在这里改、而不是让用户自己跑 compaudit
#
# 1. 这是 Homebrew 造成的、可预测的副作用，不是用户的配置问题 ——
#    安装流程顺手修掉，比让每个人去搜「oh-my-zsh insecure directories」好。
# 2. 改动**只去掉 group/other 的写权限**，不动 owner、不动内容：
#    - brew 自己一直用**你的账户**（owner）操作，不依赖 group 写权限 ——
#      实测修完 `brew doctor` 不报任何新问题，`brew update` 照常；
#    - 去掉的只是「admin 组里**别的**用户能改 brew」这一能力。单用户机器上，
#      这没有用；多用户机器上，让同组别人能改你的 brew 反而是风险。
# 3. 幂等：已经是 `g-w,o-w` 就什么都不做，可重复跑。
#
# ## 为什么用 compaudit 而不是硬编码 `chmod ... /opt/homebrew/share`
#
# 硬编码只能修今天这一个目录。compaudit 是 oh-my-zsh 判断「安全与否」的**同一份逻辑**，
# 用它就自动覆盖了：以后 brew 新增别的补全目录、或系统 zsh 目录出问题。
# 修完再跑一次 compaudit 校验，确认真的干净了 —— 不靠「我觉得修好了」。
#
# ⚠️ compaudit 只审计**当前 `fpath`**。非交互脚本的 fpath 默认不含 Homebrew 的
# 补全目录，直接跑会**漏报**。所以下面先把 Homebrew 的补全目录放进 fpath。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/macos/brew-env.zsh" || true

if ! command -v brew >/dev/null 2>&1; then
  # brew 不在就没什么可修的 —— 这是正常情况（比如 brew 装失败了），不报错。
  exit 0
fi

BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
[[ -n "$BREW_PREFIX" ]] || exit 0

# 把 Homebrew 的补全目录放进 fpath，让 compaudit 有东西可查。
# 用 glob 通配，将来 brew 换布局也不用改这里。
# ⚠️ 必须带 `(N)`（null glob）：zsh 默认遇到无匹配的 glob 会**报错中止**
#    （nomatch），`zsh/*/site-functions` 在本机就不存在 —— 不加 (N) 会直接失败。
for d in "$BREW_PREFIX"/share/zsh-completions \
         "$BREW_PREFIX"/share/zsh/site-functions \
         "$BREW_PREFIX"/share/zsh/*/site-functions(N); do
  [[ -d "$d" ]] && fpath=("$d" $fpath)
done

# compaudit 是 zsh 自带的（不是 oh-my-zsh 的）。autoload 失败就直接放弃，
# 不猜、不硬改 —— 修不了总比修错好。
if ! autoload -Uz compaudit 2>/dev/null; then
  exit 0
fi

insecure=()
for d in "${(@f)$(compaudit 2>/dev/null)}"; do
  [[ -n "$d" ]] && insecure+=("$d")
done

if (( ${#insecure[@]} == 0 )); then
  # 已经干净，什么都不用做（正常路径，安装时大多如此）。
  exit 0
fi

echo "修掉补全目录权限（消除 oh-my-zsh 的 insecure directories 警告）："
for d in "${insecure[@]}"; do
  # 只去 group/other 的写权限。owner 不动。
  # 需要写权限的目录可能是 root 所有（罕见，如 root 装的 brew）——
  # 那种情况 chmod 会失败，报出来但不中断。
  if chmod g-w,o-w "$d" 2>/dev/null; then
    echo "  ✓ $(stat -f '%Sp' "$d")  $d"
  else
    echo "  ! 改不动（可能属主是 root）：$d" >&2
    echo "    如需修复：sudo chmod g-w,o-w '$d'" >&2
  fi
done

# 校验：再跑一次 compaudit，确认真的干净。不靠「应该修好了」。
remaining=()
for d in "${(@f)$(compaudit 2>/dev/null)}"; do
  [[ -n "$d" ]] && remaining+=("$d")
done
if (( ${#remaining[@]} == 0 )); then
  echo "  ✓ 已确认 compaudit 无残留"
else
  echo "  ! 仍有目录未修复：${(j:、:)remaining}" >&2
fi
