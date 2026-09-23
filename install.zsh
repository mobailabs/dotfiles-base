#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: zsh install.zsh [command]

Commands:
  (empty) | base   Run setup: OS check, Homebrew + packages, oh-my-zsh,
                   zsh plugins, link dotfiles, tmux plugins, mise, macOS prefs
  prefs            Apply macOS preferences only (re-runnable, idempotent)
  link             Link dotfiles only
  audit            Report declared-but-not-installed brew packages (read-only)
  help             Show this help

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
  local cmd="${1:-base}"

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
