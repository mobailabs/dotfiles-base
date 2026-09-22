#!/usr/bin/env zsh

# ============================================
# Oh My Zsh 配置文件
# ============================================

# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

# ============================================
# 主题配置
# ============================================
# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"

# ============================================
# 补全配置
# ============================================
# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

CASE_SENSITIVE="false"
DISABLE_UPDATE_PROMPT=true

# ============================================
# 插件配置
# ============================================
# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.

plugins=(
  git           # Git 别名和补全
  # docker        # Docker 命令补全
  # docker-compose # Docker Compose 补全
  npm           # npm 命令补全
  node          # Node.js 补全
  rust          # Rust 补全
  golang        # Go 补全
  brew          # Homebrew 补全和别名
  colored-man-pages  # 彩色 man 页面
  command-not-found  # 命令未找到时提供安装建议
  z             # z 命令快速跳转（如果不用 zoxide）
)

# OS-specific plugin overlay (optional)
if [[ -f "$HOME/.config/dotfiles/ohmyzsh.plugins.zsh" ]]; then
  source "$HOME/.config/dotfiles/ohmyzsh.plugins.zsh"
fi

# ============================================
# 加载 Oh My Zsh（若未安装则整段跳过，不中断调用者）
# ============================================
#
# 以前这里用文件末尾的 `return 0 || exit 0` 来「没装 omz 也不报错」，
# 那是个隐患：当本文件被 `source`（而不是作为顶层 zshrc 执行）时，
# `return` 会**提前终止调用者的加载**，后面的配置全部丢失且静默。
# 现在改成把加载逻辑整段包进 if，不存在就什么都不做。
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ZSH/oh-my-zsh.sh"
fi
