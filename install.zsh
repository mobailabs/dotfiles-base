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

run_base() {
  # 只有 macOS。以前支持 Linux 服务器，那条路已经删了 —— 见 README
  # 「只做 macOS」那一节。
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Unsupported OS: $(uname -s)（这个仓库只做 macOS）" >&2
    exit 1
  fi

  "$SCRIPT_DIR/scripts/macos/check.zsh"
  "$SCRIPT_DIR/scripts/macos/brew-install.zsh"

  # ⚠️ 关键：brew-install 是**子进程**，它在自己里面 eval 的 `brew shellenv`
  # 不会回传到本进程。本进程是非交互的，PATH 还是 launchd 的最小值，
  # 所以后面的 mise / tmux 都看不见 homebrew 装的东西 ——
  # mise-setup 会 `command -v mise` 失败并 exit 1，而本脚本是 set -e，
  # 整个 base 流程会在那一步中止（系统偏好排在后面，全部不生效）。
  # 这里把 homebrew 环境补进当前进程，堵上这个缺口。
  source "$SCRIPT_DIR/scripts/common/brew-env.zsh" || true

  "$SCRIPT_DIR/scripts/common/oh-my-zsh-install.zsh"
  "$SCRIPT_DIR/scripts/common/zsh-plugins-install.zsh"
  "$SCRIPT_DIR/scripts/common/link-dotfiles.zsh"
  "$SCRIPT_DIR/scripts/common/tmux-plugins-install.zsh"
  "$SCRIPT_DIR/scripts/common/mise-setup.zsh"

  # 偏好放在最后，而且**失败不中断**：
  # 它可能要求 sudo，你按了取消也不该让前面装好的东西白费。
  # 这是旧仓库最大的坑 —— prefs.zsh 一直没进 base 流程，
  # 结果是 78 条偏好里 61 条从未生效，而没有任何提示。
  "$SCRIPT_DIR/scripts/macos/prefs.zsh" || {
    echo "" >&2
    echo "warn: 有些偏好没应用成功，见上面输出。" >&2
    echo "      可以单独重跑：zsh install.zsh prefs" >&2
  }
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
