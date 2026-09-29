#!/usr/bin/env zsh
#
# 建好三份「私有配置」的空壳（空文件 + 注释）—— **只在文件不存在时建**，
# 已存在的一个字都不动。幂等，随便重跑。
#
# ## 为什么是这三份
#
# 它们是公开仓库留的**通用加载口**的落点，私有内容（git 身份 / ssh 主机 /
# shell 片段 / token…）就地放在这里，不进任何 git 仓库：
#
#   ~/.config/dotfiles/conf.d/private.zsh   ← ~/.zshrc 里的 conf.d/*.zsh
#   ~/.config/git/config                    ← git 自己读（全局配置的 XDG 位置）
#   ~/.ssh/config                           ← ssh 自己读
#
# ## 只建空壳，内容归别人
#
# macview 的「私有」页只负责**打开编辑器改内容**，不代建；建空壳这一步
# 放在这里（安装时跑一次）。所以本脚本只写初始注释，从不覆盖已存在的文件。
#
# ⚠️ 这三条路径和 macview（`Sources/MacViewCore/Script/PrivateConfig.swift`
# 里的 `specs`）**必须是同一个位置** —— 那边靠这几条路径检测「在不在」。
# 改这里要同步改那边。

set -euo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; refusing to seed private config." >&2
  exit 1
fi

conf_d_private="$HOME/.config/dotfiles/conf.d/private.zsh"
git_config="$HOME/.config/git/config"
ssh_config="$HOME/.ssh/config"

created=0
skipped=0

# 需要时建父目录。返回 0 = 文件不存在（该建）、1 = 已经在了（不动）。
#
# ⚠️ 变量**不能叫 `path`** —— 那是 zsh 的保留变量（和 `PATH` 绑定），
# `local path=…` 会把 `PATH` 清空，然后 `mkdir` 就「command not found」。
ensure_missing() {
  local dest="$1"
  if [[ -e "$dest" ]]; then
    echo "  已经在了，不动：${dest/#$HOME/~}"
    skipped=$((skipped + 1))
    return 1
  fi
  mkdir -p "${dest:h}"
  return 0
}

echo "私有配置空壳："

# ── shell 片段 ─────────────────────────────────────────────────────────
if ensure_missing "$conf_d_private"; then
  cat > "$conf_d_private" <<'EOF'
# 本机私有的 shell 片段 —— 环境变量 / 别名 / 函数 / token 写在这里。
#
# 这个文件由 dotfiles 安装建好（空壳 + 这段注释），内容自己填；
# 它不在任何 git 仓库里，~/.zshrc 会自动 source 它，改完开新 shell 生效。
# 也可以在 macview 的「私有」页打开编辑，和另一台机器同步。
EOF
  echo "  建好：${conf_d_private/#$HOME/~}"
  created=$((created + 1))
fi

# ── git 身份 / 全局配置 ────────────────────────────────────────────────
if ensure_missing "$git_config"; then
  cat > "$git_config" <<'EOF'
# 本机私有的 git 配置 —— 身份、凭据等写在这里。
#
# 这个文件由 dotfiles 安装建好（空壳 + 这段注释），内容自己填；
# 它不在任何 git 仓库里，git 会自动读它（全局配置的 XDG 位置）。
# 也可以在 macview 的「私有」页打开编辑，和另一台机器同步。
#
# 填身份示例（去掉行首的 # 再填）：
# [user]
#     name = 你的名字
#     email = 你的邮箱
EOF
  echo "  建好：${git_config/#$HOME/~}"
  created=$((created + 1))
fi

# ── ssh 主机 ───────────────────────────────────────────────────────────
if ensure_missing "$ssh_config"; then
  cat > "$ssh_config" <<'EOF'
# 本机私有的 ssh 配置 —— 主机、跳板机、代理等写在这里。
#
# 这个文件由 dotfiles 安装建好（空壳 + 这段注释），内容自己填；
# 它不在任何 git 仓库里，ssh 自己会读它。
# 也可以在 macview 的「私有」页打开编辑，和另一台机器同步。
EOF
  chmod 600 "$ssh_config"
  chmod 700 "$HOME/.ssh"
  echo "  建好：${ssh_config/#$HOME/~}（0600）"
  created=$((created + 1))
fi

echo "私有配置空壳：建好 $created 份，已有 $skipped 份没动。"
