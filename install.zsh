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

  "$SCRIPT_DIR/scripts/common/oh-my-zsh-install.zsh"
  "$SCRIPT_DIR/scripts/common/zsh-plugins-install.zsh"
  "$SCRIPT_DIR/scripts/common/link-dotfiles.zsh"
  "$SCRIPT_DIR/scripts/common/tmux-plugins-install.zsh"
  "$SCRIPT_DIR/scripts/common/mise-setup.zsh"

  # ghostty 的 `config` 是「当前主题」的指针，被 .gitignore 排除 ——
  # 因为 eink-on/off 用 `ln -sf` 切它，提交了每次切主题都会弄脏工作区。
  # 代价是：新克隆的仓库里没有这个文件，ghostty 会以默认配置启动。
  # 这里补一个默认值。
  ghostty_dir="$SCRIPT_DIR/src/macos/config/ghostty"
  if [[ ! -e "$ghostty_dir/config" && -e "$ghostty_dir/config-dark" ]]; then
    ln -s config-dark "$ghostty_dir/config"
    echo "ghostty: 没有当前主题，已设为 config-dark"
  fi

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
    help|-h|--help) usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
