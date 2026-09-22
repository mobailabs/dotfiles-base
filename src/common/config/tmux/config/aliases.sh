#!/bin/bash

# tmux aliases and helper functions
# Source this file in your shell configuration

# ========================================
# 基础快捷键
# ========================================

alias t='tmux'
alias tls='tmux ls'                       # 列出所有会话
alias ta='tmux attach -t'                 # 附着到指定会话
alias tn='tmux new-session -s'            # 创建指定名称的会话
alias tA='tmux new-session -A -s'         # 若存在则附着，否则创建
alias tk='tmux kill-session -t'           # 结束指定会话
alias tks='tmux kill-server'              # 结束 tmux 服务器
alias treload='tmux source-file ~/.config/tmux/tmux.conf \; display-message "tmux config reloaded"'

# ========================================
# 智能函数
# ========================================

# tcd - 以当前目录名为会话名，存在则附着，否则创建；也可手动传入会话名
# 用法:
#   tcd           # 使用当前目录名作为会话名
#   tcd myproject # 使用指定名称 "myproject"
tcd() {
  local name="${1:-$(basename "$(pwd)")}"
  tmux new-session -A -s "$name"
}

# tal - 附着到最近使用的会话；若没有会话则创建一个名为 main 的会话
# 用法:
#   tal           # 附着到最近会话或创建 main 会话
tal() {
  tmux attach 2>/dev/null || tmux new-session -s main
}

# tsel - 使用 fzf 交互选择会话（若已安装 fzf）
# 用法:
#   tsel          # 打开交互式会话选择器
# 行为:
#   - 在 tmux 内部：切换到选择的会话
#   - 在 tmux 外部：附着到选择的会话
if command -v fzf >/dev/null 2>&1; then
    tsel() {
      local s
      s="$(tmux ls -F '#{session_name}' 2>/dev/null | fzf --height 40% --reverse --prompt='tmux> ')" || return
      [ -z "$s" ] && return
      if [ -n "$TMUX" ]; then
        tmux switch-client -t "$s"   # 在 tmux 内：切换会话
      else
        tmux attach -t "$s"          # 在 tmux 外：附着会话
      fi
    }
fi

# ========================================
# 高级函数
# ========================================

# tnew - 在指定目录创建新会话
# 用法:
#   tnew ~/projects/myapp           # 在指定目录创建会话
#   tnew ~/projects/myapp myproject # 在指定目录创建指定名称的会话
tnew() {
  local dir="${1:-.}"
  local name="${2:-$(basename "$dir")}"
  tmux new-session -s "$name" -c "$dir"
}

# tkill - 交互式结束会话（使用 fzf）
# 用法:
#   tkill         # 选择并结束会话
if command -v fzf >/dev/null 2>&1; then
    tkill() {
      local s
      s="$(tmux ls -F '#{session_name}' 2>/dev/null | fzf --height 40% --reverse --prompt='Kill session> ')" || return
      [ -z "$s" ] && return
      tmux kill-session -t "$s"
      echo "✓ Killed session: $s"
    }
fi

# tsave - 手动保存当前 tmux 会话（需要 tmux-resurrect）
# 用法:
#   tsave         # 保存当前会话状态
alias tsave='tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh'

# trestore - 手动恢复 tmux 会话（需要 tmux-resurrect）
# 用法:
#   trestore      # 恢复上次保存的会话
alias trestore='tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh'

# ========================================
# 调试与信息
# ========================================

# tinfo - 显示 tmux 配置信息
# 用法:
#   tinfo         # 显示当前 tmux 配置摘要
tinfo() {
  echo "=== tmux Configuration Info ==="
  echo "Version: $(tmux -V)"
  echo "Config: ~/.tmux.conf"
  echo "Prefix: $(tmux show-options -g prefix | awk '{print $2}')"
  echo "Sessions: $(tmux ls 2>/dev/null | wc -l | tr -d ' ')"
  echo "Plugins: $(ls -1 ~/.tmux/plugins 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "$TMUX" ]; then
    echo "Current session: $(tmux display-message -p '#S')"
    echo "Current window: $(tmux display-message -p '#I:#W')"
  else
    echo "Not in tmux session"
  fi
}

# tkeys - 显示所有自定义快捷键
# 用法:
#   tkeys         # 列出所有 tmux 快捷键绑定
alias tkeys='tmux list-keys'

# ========================================
# 快速启动模板
# ========================================

# tdev - 创建开发环境布局（编辑器 + 终端 + 日志）
# 用法:
#   tdev          # 在当前目录创建开发布局
#   tdev myapp    # 为指定项目创建开发布局
tdev() {
  local name="${1:-$(basename "$(pwd)")}"
  tmux new-session -d -s "$name" -c "$(pwd)"
  tmux split-window -v -p 30 -t "$name"
  tmux split-window -h -p 50 -t "$name"
  tmux select-pane -t "$name":1.1
  tmux attach -t "$name"
}

# ========================================
# 实用工具
# ========================================

# tclean - 清理所有已结束的会话
# 用法:
#   tclean        # 清理所有死会话
tclean() {
  local count=0
  for session in $(tmux ls 2>/dev/null | grep '(dead)' | cut -d: -f1); do
    tmux kill-session -t "$session"
    ((count++))
  done
  if [ $count -eq 0 ]; then
    echo "✓ No dead sessions found"
  else
    echo "✓ Cleaned $count dead session(s)"
  fi
}

# trename - 重命名当前会话
# 用法:
#   trename newname    # 重命名当前会话
trename() {
  if [ -z "$1" ]; then
    echo "Usage: trename <new-name>"
    return 1
  fi
  if [ -n "$TMUX" ]; then
    tmux rename-session "$1"
    echo "✓ Session renamed to: $1"
  else
    echo "✗ Not in a tmux session"
    return 1
  fi
}
