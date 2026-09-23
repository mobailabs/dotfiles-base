#!/usr/bin/env zsh
#
# 一次性收集「脚本无法自动猜到」的信息，之后全流程不再交互。
#
# ## 为什么需要这个
#
# 前面的步骤已经能做到无人值守，但有三件事脚本**必须**向人要：
#
#   1. git 身份（name/email）—— 猜不出来。gitconfig 里 `useConfigOnly = true`
#      会禁用自动探测，没有它一次 commit 都提交不了。而用户名/邮箱是私密的，
#      不该进公共仓库。
#   2. Touch ID for sudo —— 要写 /etc/pam.d/sudo，需要管理员权限。
#   3. （可选）某些 cask 安装时也会弹密码。
#
# 集中在这里问一次，比装到一半突然卡住好得多 —— 这是「全自动」的关键：
# **所有交互都前置**，之后的步骤零交互，人可以走开。
#
# ## 非交互场景
#
# 如果 stdin 不是 tty（CI / 远程 pipe），或者传了 --yes，就完全跳过提问，
# 用以下来源按优先级取值：
#   git 身份:  --name/--email 参数 > 环境变量 > 已有的全局 git 配置
#   都取不到 → 保留现状（不建 .gitconfig.local），只提示，不阻断。
#
# 这样 `curl ... | zsh` 也能跑，只是身份需要事后补。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# ── 参数 ────────────────────────────────────────────────────────────────
# 允许 `zsh install.zsh --name X --email Y` 这种零交互用法。
GIT_NAME=""
GIT_EMAIL=""
ASSUME_YES=0

while (( $# > 0 )); do
  case "$1" in
    --name)  GIT_NAME="${2:-}";  shift 2 ;;
    --email) GIT_EMAIL="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    *) shift ;;
  esac
done

# 环境变量兜底（GIT_AUTHOR_* 是 git 认的标准名）
GIT_NAME="${GIT_NAME:-${GIT_AUTHOR_NAME:-}}"
GIT_EMAIL="${GIT_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"
# 都没有就读已有的全局配置（比如老机器上已经设过）
GIT_NAME="${GIT_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"

# 有没有可交互的终端
interactive=1
[[ -t 0 ]] || interactive=0
(( ASSUME_YES )) && interactive=0

# ── 1. git 身份 ────────────────────────────────────────────────────────
setup_git_identity() {
  if [[ -f "$HOME/.gitconfig.local" ]] && \
     grep -q '^\s*email' "$HOME/.gitconfig.local" 2>/dev/null; then
    echo "  git 身份已存在，跳过。"
    return 0
  fi

  if (( interactive )); then
    echo ""
    echo "git 提交身份（写进 ~/.gitconfig.local，不进仓库）"
    echo "  留空则跳过 —— 但之后一次 commit 都提交不了，需要自己补。"
    if [[ -z "$GIT_NAME" ]]; then
      printf "  名字: "
      read -r GIT_NAME || GIT_NAME=""
    fi
    if [[ -z "$GIT_EMAIL" ]]; then
      printf "  邮箱: "
      read -r GIT_EMAIL || GIT_EMAIL=""
    fi
  fi

  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    echo "  ! 没有 git 身份；跳过（之后可建 ~/.gitconfig.local 补上）。"
    return 0
  fi

  # 已有文件就只更新 user 段，不覆盖别的设置（比如你加了 gpgsign）。
  if [[ -f "$HOME/.gitconfig.local" ]] && \
     grep -q '\[user\]' "$HOME/.gitconfig.local" 2>/dev/null; then
    git config --file "$HOME/.gitconfig.local" user.name  "$GIT_NAME"
    git config --file "$HOME/.gitconfig.local" user.email "$GIT_EMAIL"
    echo "  已更新 ~/.gitconfig.local 的 user 段。"
  else
    {
      echo "[user]"
      printf '\tname = %s\n'  "$GIT_NAME"
      printf '\temail = %s\n' "$GIT_EMAIL"
    } >> "$HOME/.gitconfig.local"
    echo "  已写入 ~/.gitconfig.local。"
  fi
}

# ── 2. sudo 预授权 ─────────────────────────────────────────────────────
# 一次 sudo -v 会把凭据缓存约 15 分钟，之后 prefs / cask 的 sudo 不再弹窗。
# 这是「人可以走开」的前提 —— 否则会卡在某个 sudo 提示上。
preauth_sudo() {
  if ! sudo -n true 2>/dev/null; then
    if (( interactive )); then
      echo ""
      echo "管理员权限（一次，之后自动保持到安装结束）"
      echo "  用于：Touch ID for sudo、少数需要管理员权限的 cask。"
      echo "  macOS 默认 5 分钟就过期 —— install.zsh 会起一个后台循环持续刷新，"
      echo "  所以这里输一次就够了，之后不会再问。"
      echo "  不输直接回车 = 跳过所有需要 sudo 的步骤。"
      if sudo -v 2>/dev/null; then
        echo "  已授权。"
      else
        echo "  ! 未授权；需要 sudo 的步骤会被跳过（不影响其余）。"
      fi
    else
      echo "  非交互且未预授权 sudo；需要 sudo 的步骤会跳过。"
    fi
  else
    echo "  sudo 已预授权。"
  fi
}

# ── 3. ssh 的 Include ──────────────────────────────────────────────────
# ~/.ssh/config 是本机私密文件，不在仓库里 —— 所以链接流程碰不到它。
# 但 `Include ~/.ssh/config.local` 这一行不加，私有 ssh 配置就永远不生效，
# 且不报错。自动加上（幂等），省掉 README 里那条手动步骤。
setup_ssh_include() {
  local ssh_dir="$HOME/.ssh"
  local ssh_config="$ssh_dir/config"
  local line="Include ~/.ssh/config.local"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir" 2>/dev/null || true

  if [[ -f "$ssh_config" ]] && grep -qxF "$line" "$ssh_config" 2>/dev/null; then
    echo "  ssh Include 已存在，跳过。"
    return 0
  fi

  if [[ -f "$ssh_config" ]]; then
    # 插到最上面（Include 必须在其它 Host 段之前才有效）。
    # 用临时文件原地替换，保留原有权限位。
    local tmp="$ssh_config.dotsu.$$"
    { echo "$line"; cat "$ssh_config"; } > "$tmp"
    chmod --reference="$ssh_config" "$tmp" 2>/dev/null || chmod 600 "$tmp"
    mv "$tmp" "$ssh_config"
    echo "  已把 Include 插到 ~/.ssh/config 顶部。"
  else
    printf '%s\n' "$line" > "$ssh_config"
    chmod 600 "$ssh_config"
    echo "  已创建 ~/.ssh/config 并写入 Include。"
  fi
}

# ── 主流程 ─────────────────────────────────────────────────────────────
main() {
  echo ""
  echo ">>> 一次性设置（之后全自动，不再询问）"
  setup_git_identity
  preauth_sudo
  setup_ssh_include
}

main "$@"
