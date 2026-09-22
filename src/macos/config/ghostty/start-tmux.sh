#!/usr/bin/env zsh

# Ghostty tmux 启动脚本
# 功能：安全启动 tmux，支持多种路径和降级机制

# 确保 GUI 启动时也能获取 Homebrew 环境（含 /opt/homebrew/bin）
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$('/opt/homebrew/bin/brew' shellenv)"
fi

# 查找 tmux 路径（支持 Apple Silicon 和 Intel Mac）
TMUX_PATH=""

if [[ -x "/opt/homebrew/bin/tmux" ]]; then
    # Apple Silicon Mac
    TMUX_PATH="/opt/homebrew/bin/tmux"
elif [[ -x "/usr/local/bin/tmux" ]]; then
    # Intel Mac
    TMUX_PATH="/usr/local/bin/tmux"
elif command -v tmux &>/dev/null; then
    # 使用 PATH 中的 tmux
    TMUX_PATH=$(command -v tmux)
fi

# 如果找到 tmux，则启动会话
if [[ -n "$TMUX_PATH" ]]; then
    # 基于当前目录生成会话名
    # 清理特殊字符，最多 20 个字符
    SESSION_NAME=$(basename "$PWD" | sed "s/[^a-zA-Z0-9_-]//g" | cut -c1-20)
    
    # 如果目录名为空或太短，使用默认名称
    if [[ -z "$SESSION_NAME" ]] || [[ ${#SESSION_NAME} -lt 1 ]]; then
        SESSION_NAME="main"
    fi
    
    # 附加到同名会话，或创建新会话
    exec "$TMUX_PATH" new-session -A -s "$SESSION_NAME"
else
    # 降级：tmux 不存在时，启动普通 zsh
    echo "⚠️  tmux not found, starting zsh without tmux"
    echo "   Install tmux: brew install tmux"
    exec /bin/zsh -l
fi
