#!/usr/bin/env zsh
#
# 统一「怎么调 sudo」。被 `source`，不是被执行。
#
# ⚠️ **zsh / bash 双兼容** —— `prefs.d/sudo_touchid.zsh` 是 bash 脚本，
# 它也要 source 本文件。所以这里只用两种 shell 都认的语法：
#   · `typeset -ga`（两边的全局数组）
#   · `[[ ]]`、`-t 0`、`${VAR+x}`
# 不要在这里用 zsh 专有语法（`(N)` glob、`${(j:…:)…}` 等）。
#
# ## 它解决什么
#
# 这个仓库的脚本要在**两种完全不同的环境**下都能提到权：
#
# | 环境 | 有终端吗 | 密码怎么来 |
# |---|---|---|
# | 人在终端里敲 `zsh install.zsh` | 有 | sudo 自己弹终端提示 |
# | macview 里按「一键配置」 | **没有** | `SUDO_ASKPASS` 弹原生密码框 |
#
# 上一版只考虑了第一种：到处都是**裸 `sudo`**（终端里有提示就够），
# 判定用 `sudo -n true`。**第二种环境下这套是坏的** —— 实测：
#
#   · 裸 `sudo` 在「无 tty + 只有 SUDO_ASKPASS」时不弹框，直接报
#     「a terminal is required to read the password」；
#   · `sudo -n true` 也**不会**用 SUDO_ASKPASS（`-n` 就是「绝不提问」，
#     它连 askpass 都不调）→ 判定永远失败 → 脚本以为「没授权」→ 跳过。
#
# 具体后果（都实测过）：`prompt-once` 报「未预授权，跳过需要 sudo 的步骤」，
# `brew-bootstrap` 直接 `exit 1` 说「没有终端可输入密码」——Homebrew 装不上。
#
# ## 怎么解：一个 `SUDO` 变量
#
# 定义 `SUDO`（**数组**，因为可能要带 `-A` 这个参数），所有调用点用
# `"${SUDO[@]}"` 代替裸 `sudo`。一处定义、处处统一。
#
# ⚠️ 为什么是**数组**不是字符串：`SUDO="sudo -A"` 再 `$SUDO cmd` 会靠
# shell 分词，一旦哪天参数里带空格就散架。数组没这个问题。
#
# ## 怎么判断要不要 `-A`
#
# 只有 `SUDO_ASKPASS` 非空、而且**当前没有 tty** 时才加 `-A`。理由：
#   · 有 tty 时 sudo 本来就能自己弹提示，加 `-A` 反而绕开终端提示、去调
#     那个助手（可能根本没有），是**退步**；
#   · 没 `SUDO_ASKPASS` 时加 `-A` 会报「no askpass program specified」。
#
# 所以「有没有 `SUDO_ASKPASS`」是唯一可靠的信号 —— 它由 macview 注入
# （见 `ScriptRunner` 的 `Privilege`），终端用户不会设它。
#
# ## 用法
#
#     source "$ROOT_DIR/scripts/macos/sudo-env.zsh"   # 定义 SUDO / sudo_check / sudo_authorize
#     if sudo_check; then "  ...   # 已经授权了（没打扰用户）
#     else sudo_authorize  || echo "没授权，跳过"     # 弹框（终端提示 或 askpass）
#     fi
#     "${SUDO[@]}" install -m 644 ...                 # 真正需要 root 的动作
#
# `set -u` 下也安全。

# ── 决定 SUDO ────────────────────────────────────────────────────────────
#
# ⚠️ `typeset -ga`（全局数组）：本文件被 `source`，若用裸 `local` 或
# `typeset`（不带 -g），在函数上下文里 source 时会退化成局部变量，出了
# 作用域就没了 —— 调用方 `"${SUDO[@]}"` 会因未绑定而报错（`set -u` 下）。

# 已经定过就别重复定义（可能被 source 多次）。
if [[ -z "${SUDO+x}" ]]; then
  typeset -ga SUDO
  if [[ -n "${SUDO_ASKPASS:-}" && ! -t 0 ]]; then
    # macview 环境：无终端、有个弹原生密码框的助手 → 必须显式 -A。
    SUDO=(sudo -A)
  else
    # 终端环境：让 sudo 自己弹提示，行为和你手敲时一模一样。
    SUDO=(sudo)
  fi
fi

# ── 判定：现在有没有有效的 sudo 授权（**不打扰用户**）────────────────────
#
# ⚠️ 必须用 `-n`：这一步的唯一目的是「悄悄问一句」，不该弹任何东西。
# 但 `-n` 会无视 SUDO_ASKPASS（实测），所以它**只回答「已经有了吗」**，
# 不回答「能不能拿到」——「能不能拿到」是 `sudo_authorize` 的事。
#
# 返回 0 = 已有有效授权；非 0 = 没有（调用方决定是弹框还是跳过）。
sudo_check() {
  "${SUDO[@]}" -n true 2>/dev/null
}

# ── 授权：去拿一次 sudo 授权（**可能会弹框**）────────────────────────────
#
# `-v` 会刷新凭据时间戳，需要密码时就用 `SUDO_ASKPASS`（无 tty）
# 或终端提示（有 tty）。实测 `sudo -A -v` 确实会调 askpass。
#
# ⚠️ 它**不是**「保证之后一直有效」—— macOS 默认 5 分钟过期，
# 装东西动辄几十分钟。所以真正的兜底仍是：每个需要 root 的动作
# 自己就近用 `"${SUDO[@]}"`（同一时间戳下不必再输）。
#
# 返回 0 = 拿到了；非 0 = 用户取消 / 没有终端且没有 askpass。
sudo_authorize() {
  "${SUDO[@]}" -v
}

# ── 真需要 root 时的推荐写法 ─────────────────────────────────────────────
#
# 有些动作（写 /etc/pam.d/…）就是得 root。直接 `"${SUDO[@]}"` 即可 ——
# 若凭据过期且是终端环境，sudo 会就地弹一次提示（会等你输入）；
# macview 环境则弹 askpass。**两种情况都不会静默卡住。**
