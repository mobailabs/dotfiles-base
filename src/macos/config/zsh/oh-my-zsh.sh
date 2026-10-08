#!/usr/bin/env zsh

# ============================================
# Oh My Zsh 配置文件
# ============================================

# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

# ============================================
# 主题配置
# ============================================
# ⚠️ **主题交给 powerlevel10k，不走 OmZ 的 ZSH_THEME 机制**。
#
# 早先用 `ZSH_THEME="gnzh"`（OmZ 自带主题）。改成 p10k 的原因：p10k 是
# 独立的提示符引擎（自己管 git 状态、目录截断、瞬态提示符），它要在
# **所有插件之后**手动 source（见 `zshrc` 底部），不能用 ZSH_THEME 加载。
#
# 所以这里**留空** —— 空串时 OmZ 不加载任何主题，只加载下面的 plugins。
# 设回 "gnzh" 就能退回旧主题（那样 p10k 那两行 source 要删掉，二选一）。
ZSH_THEME=""

# ============================================
# 补全配置
# ============================================
# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

CASE_SENSITIVE="false"

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
  # z             # 目录跳转 —— 不用它：zshrc 里启用了 zoxide，
  #               # 两个都注册 `z` 函数会互相覆盖（zoxide 后加载胜出），
  #               # 且各自维护一份数据文件。统一用 zoxide。
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
