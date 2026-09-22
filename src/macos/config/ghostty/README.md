# Ghostty 终端配置

深度集成 tmux 的 Ghostty 终端配置。Ghostty 默认只提供外观和快捷键映射，不会自动启动 tmux。

## ✨ 特性

- 🎨 **统一配色** - Ghostty 使用 Monokai Pro Ristretto，和 tmux 状态栏保持接近的深色风格
- ⌨️ **快捷键映射** - 常用 tmux 操作映射到 `⌘ Command` 键
- 🧩 **手动进入 tmux** - 默认不自动启动 tmux，需要先进入 tmux 会话后快捷键才会生效
- 🪟 **极简界面** - 无标题栏、无边框，专注代码
- 🔧 **可选启动脚本** - 保留 `start-tmux.sh`，需要自动启动时可以手动启用

## 📦 依赖安装

```bash
# 安装 tmux
brew install tmux

# 安装 fzf（tmux 命令弹窗和会话选择依赖）
brew install fzf

# 安装 Nerd Font（推荐）
brew tap homebrew/cask-fonts
brew install font-jetbrains-mono-nerd-font
```

## 🎨 主题配色

Ghostty 使用 `Monokai Pro Ristretto` 主题。tmux 状态栏也使用接近的深色背景和暖橙强调色，放在一起不会跳色。

## ⌨️ 快捷键

> **tmux 前缀键**: `Ctrl+B`  
> 所有快捷键已映射到 macOS `⌘ Command` 键

### 窗口管理
```
⌘T          新建窗口
⌘1-9        切换到窗口 1-9
⌘[          上一个窗口
⌘]          下一个窗口
⌘,          重命名窗口
```

### 面板操作
```
⌘Enter      左右分屏
⌘D          上下分屏
⌘H/J/K/L    切换面板（Vim 风格）
⌘W          关闭面板
⌘Z          面板缩放/全屏
⌘;          切换到上一个活动面板
```

### 面板调整
```
⌘⇧H         向左扩展
⌘⇧J         向下扩展
⌘⇧K         向上扩展
⌘⇧L         向右扩展
```

### 会话管理
```
⌘N          新建会话
⌘O          会话列表
⌘⇧X         关闭会话
⌘P          Popup 会话
⌘⇧I         同步面板输入
```

### 其他
```
⌘R          命令弹窗
⌘E          进入复制模式
⌘C          复制到剪贴板
⌘V          从剪贴板粘贴
```

完整快捷键列表：[KEYBINDINGS.md](./KEYBINDINGS.md)

## 📁 文件说明

```
~/.config/ghostty/
├── config              # 主配置文件
├── start-tmux.sh       # 可选 tmux 启动脚本，默认不启用
├── ghostty-white.icns  # 自定义图标
├── README.md           # 本文档
└── KEYBINDINGS.md      # 快捷键速查表
```

## 🔧 自定义

### 修改字体大小
编辑 `config`:
```
font-size = 14  # 改为你喜欢的大小
```

### 手动进入 tmux
默认不会自动启动 tmux。打开 Ghostty 后，可以手动进入一个固定会话：
```bash
tmux new -A -s main
```

也可以在项目目录里用目录名作为会话名：
```bash
tmux new -A -s "$(basename "$PWD")"
```

### 可选启用 tmux 自动启动
如果以后想恢复打开 Ghostty 自动进入 tmux，可以在 `config` 里添加：
```
command = ~/.config/ghostty/start-tmux.sh
```

### 修改配色
编辑 `config` 中的 `theme` 配置。

## 🐛 常见问题

### Q: 快捷键不工作？
**A:** 这些 `⌘` 快捷键本质上是给 tmux 发送 `Ctrl+B` 命令，先确认当前 shell 已经在 tmux 里：
```bash
echo $TMUX  # 应该有输出
tmux show-options -g | grep prefix  # 应显示 prefix C-b
```

### Q: 字体显示异常？
**A:** 确认字体已安装：
```bash
fc-list | grep -i "jetbrains"
# 或重新安装
brew install font-jetbrains-mono-nerd-font
```

### Q: 想使用可选启动脚本时 tmux 启动失败？
**A:** 检查启动脚本权限：
```bash
chmod +x ~/.config/ghostty/start-tmux.sh
# 手动运行查看错误
~/.config/ghostty/start-tmux.sh
```

### Q: 会话名显示为 "main"？
**A:** 只有使用 `start-tmux.sh` 时，会话名才会基于当前目录生成。默认手动启动 tmux 时，会话名取决于你执行的 `tmux new -A -s <name>`。

## 🔄 更新配置

```bash
# 如果使用 dotfiles 仓库
cd ~/.dotfiles
git pull

# 重启 Ghostty
killall ghostty
```

## 📚 参考

- [Ghostty 官方文档](https://ghostty.org)
- [tmux 配置](../../.tmux.conf)
- [快捷键速查](./KEYBINDINGS.md)

---

**维护**: （通用模板已移除个人链接）  
**更新**: 2024
