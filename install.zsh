#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: zsh install.zsh [command] [options]

Commands:
  (empty) | base   Run setup: OS check, Homebrew + packages, oh-my-zsh,
                   zsh plugins, link dotfiles, tmux plugins, mise, macOS prefs
  prefs            Apply macOS preferences only (re-runnable, idempotent)
  link             Link dotfiles only
  audit            Report declared-but-not-installed brew packages (read-only)
  help             Show this help

Options（用于 base，实现零交互）:
  --name  <名字>   git 提交名字（跳过交互提问）
  --email <邮箱>   git 提交邮箱（跳过交互提问）
  --yes, -y        不提问，全部取参数/环境变量/已有配置
                   适合脚本化、CI、远程 curl | zsh

## 全自动怎么用

  zsh install.zsh
    开头**一次性**问完 git 身份 + 管理员密码，之后零交互，人可以走开。

  zsh install.zsh --name "你的名字" --email "you@example.com"
    完全不提问（sudo 若已预授权则全程无交互）。

  GIT_AUTHOR_NAME=X GIT_AUTHOR_EMAIL=Y zsh install.zsh --yes
    纯环境变量驱动。

后续所有定制通过编辑 src/**/config/*、packages/*.txt 完成。
EOF
}

# 跑一步，失败**只记录、不中断**。
#
# ## 为什么不是裸调用 + set -e
#
# 裸调用时，任何一步非 0 都会让整个 base 立刻停止 —— 包括后面
# 「链接配置」「应用偏好」这些**与装包无关、且最该保证**的步骤。
#
# 真实场景：某个 cask 装不上（cask 失效 / 网络抖动 / 公司网络拦了下载），
# brew-packages-install 按设计 exit 1 报告失败 ——
# 然后 set -e 让 install.zsh 停在装包这步：
#   ✗ ~/.zshrc、~/.config/nvim、~/.config/tmux … 一个都不链接
#   ✗ oh-my-zsh / tmux 插件 / mise / macOS 偏好 全部不执行
# 机器看起来「装过了」，其实配置根本没生效，而且没有醒目的提示。
#
# 所以：每步独立容错，最后统一报告失败项 + 退出码。
# 有失败 → 整体 exit 1（CI 能判断），但**该做的都做过了**。
_failed_steps=()

# 传给 prompt-once 的参数（--name/--email/--yes）。顶层声明成空数组，
# 这样 `"${INSTALL_ARGS[@]}"` 在 set -u 下也不会因「未定义」而报错。
INSTALL_ARGS=()

# 后台刷新 sudo 时间戳的 PID（0 = 没在跑）。
_SUDO_KEEPALIVE_PID=0

# ── sudo keep-alive ─────────────────────────────────────────────────────
#
# 为什么需要：macOS 默认 timestamp_timeout 是 **5 分钟**，而完整 base 流程
# （装几十个 cask + mise 工具）动辄十几分钟到半小时。只在开头 `sudo -v` 一次
# 是不够的 —— 时间戳过期后，后面的 prefs（Touch ID for sudo）会**再次弹密码**，
# 人就守在旁边等着了，「走开」就失败。
#
# 所以：每 60 秒 `sudo -n true` 刷一次（-n = 不提问；过了期就静默失败、不卡住）。
# 全部结束时 kill 掉。用 `sudo -n`（而非 `sudo -v`）保证后台进程**永远不会
# 弹提示**——它弹了也没人看得到，只会挂住。
start_sudo_keepalive() {
  # 没有预授权就不必开（否则只是个空转的循环）
  sudo -n true 2>/dev/null || return 0

  (
    while true; do
      sudo -n true 2>/dev/null || exit 0
      sleep 60
    done
  ) &
  _SUDO_KEEPALIVE_PID=$!
  echo "sudo 预授权已保持（后台每 60s 刷新）。"
}

stop_sudo_keepalive() {
  if (( _SUDO_KEEPALIVE_PID > 0 )); then
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    _SUDO_KEEPALIVE_PID=0
  fi
}

run_step() {
  local desc="$1"; shift
  echo ""
  echo ">>> $desc"
  if "$@"; then
    return 0
  fi
  _failed_steps+=("$desc")
  echo "!! 这一步没成功（继续后面的步骤）：$desc" >&2
}

run_base() {
  # 只有 macOS。以前支持 Linux 服务器，那条路已经删了 —— 见 README
  # 「只做 macOS」那一节。
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Unsupported OS: $(uname -s)（这个仓库只做 macOS）" >&2
    exit 1
  fi

  # check 是**唯一**硬前置：它失败说明这台机器根本走不下去
  # （非 macOS / 没 git），继续做只会产生一串无意义的失败。
  "$SCRIPT_DIR/scripts/macos/check.zsh" || exit 1

  # 把所有需要人参与的事情**集中到这里一次问完**（git 身份、sudo 预授权、
  # ssh include）。之后每一步都是零交互 —— 这样你可以敲一条命令然后走开，
  # 不用守在旁边等某个 sudo 提示。
  run_step "一次性设置（身份 / 权限 / ssh）" \
    "$SCRIPT_DIR/scripts/common/prompt-once.zsh" "${INSTALL_ARGS[@]}"

  # prompt-once 可能刚做了 sudo 预授权。装包动辄十几分钟，而时间戳默认
  # 5 分钟就过期 —— 开个后台循环持续刷新，否则 prefs 那步会重新弹密码。
  # 无论中途怎么退出（成功/失败/被 kill）都要收掉这个后台进程。
  trap 'stop_sudo_keepalive' EXIT INT TERM
  start_sudo_keepalive

  run_step "Homebrew + 包" "$SCRIPT_DIR/scripts/macos/brew-install.zsh"

  # ⚠️ 关键：上面是**子进程**，它在自己里面 eval 的 `brew shellenv`
  # 不会回传到本进程。本进程是非交互的，PATH 还是 launchd 的最小值，
  # 所以后面的 mise / tmux 都看不见 homebrew 装的东西。
  # 这里把 homebrew 环境补进当前进程，堵上这个缺口。
  source "$SCRIPT_DIR/scripts/common/brew-env.zsh" || true

  run_step "oh-my-zsh"            "$SCRIPT_DIR/scripts/common/oh-my-zsh-install.zsh"
  run_step "zsh 插件"              "$SCRIPT_DIR/scripts/common/zsh-plugins-install.zsh"
  # 链接配置放在装包之后、但不受装包失败影响 —— 这是本流程最该保证的一步。
  run_step "链接配置文件"           "$SCRIPT_DIR/scripts/common/link-dotfiles.zsh"
  run_step "tmux 插件（TPM）"       "$SCRIPT_DIR/scripts/common/tmux-plugins-install.zsh"
  run_step "mise 工具"             "$SCRIPT_DIR/scripts/common/mise-setup.zsh"
  # 偏好可能要求 sudo 密码；你按了取消也不该让前面装好的东西白费。
  run_step "macOS 系统偏好"         "$SCRIPT_DIR/scripts/macos/prefs.zsh"

  # ---- 汇总 ----
  echo ""
  if (( ${#_failed_steps[@]} == 0 )); then
    echo "全部完成。"
    echo "有些改动需要重启 App 或重新登录才生效。"
    return 0
  fi

  echo "完成，但有 ${#_failed_steps[@]} 步没成功：" >&2
  printf '  - %s\n' "${_failed_steps[@]}" >&2
  echo "" >&2
  echo "其余步骤都执行过了；失败的多半是网络或需要 sudo。" >&2
  echo "可以重跑整套（幂等）：zsh install.zsh" >&2
  return 1
}

main() {
  local cmd="base"
  INSTALL_ARGS=()

  # 第一个非选项参数是命令；其余 --name/--email/--yes 原样转给 prompt-once。
  while (( $# > 0 )); do
    case "$1" in
      --name|--email)
        # 带值的选项：连值一起收进 INSTALL_ARGS
        INSTALL_ARGS+=("$1" "${2:-}")
        shift 2
        ;;
      --yes|-y)
        INSTALL_ARGS+=("$1")
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        cmd="$1"
        shift
        ;;
    esac
  done

  case "$cmd" in
    base) run_base ;;
    prefs) "$SCRIPT_DIR/scripts/macos/prefs.zsh" ;;
    link) "$SCRIPT_DIR/scripts/common/link-dotfiles.zsh" ;;
    audit) "$SCRIPT_DIR/scripts/common/brew-audit.zsh" ;;
    help|-h|--help) usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
