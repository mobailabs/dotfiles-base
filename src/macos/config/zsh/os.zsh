#!/usr/bin/env zsh

# macOS 专属的 shell 调整。
#
# 这是**刻意的空文件**，不是没写完 —— `~/.zshrc` 会在最后条件 source 它
# （`[[ -f "$HOME/.config/dotfiles/os.zsh" ]] && source ...`）。
#
# 为什么要留这么个空壳：把「跨平台共性」和「只在 macOS 生效的东西」分开。
# 需要塞点只在这台 Mac 上做的事时（某个只有 macOS 有的命令行、某个
# brew 装出来的路径），写在这里，而不要混进 ~/.zshrc。
#
# 同理还有 ~/.config/dotfiles/ohmyzsh.plugins.zsh（只加 macOS 的 omz 插件）。

