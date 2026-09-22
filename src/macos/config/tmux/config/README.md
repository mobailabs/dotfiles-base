# tmux 配置说明

这是一个高度优化的 tmux 配置，采用 **Neo-Geometric Dark（冷青极客风）** 主题。

---

## ✨ 特性

- 🎨 **统一主题**: 冷青主色 (#32ade6) 极客风配色
- ⌨️ **Vim 风格**: 完整的 hjkl 导航和操作
- 🔧 **标准前缀**: 使用默认的 `Ctrl+B` 前缀键
- 📋 **剪贴板集成**: 原生 macOS 剪贴板支持（pbcopy/pbpaste）
- 🪟 **智能弹窗**: 命令选择器、会话管理、临时终端
- 💾 **会话持久化**: 自动保存和恢复会话（tmux-resurrect + continuum）
- 🖱️ **鼠标支持**: 点击、拖拽、滚动全支持
- 🚀 **高性能**: 优化的状态栏刷新和脚本调用

---

## 📦 依赖项

### 必需
- **tmux**: 终端复用器（2.9+）
  ```bash
  brew install tmux
  ```
- **zsh**: Shell（macOS 自带）

### 推荐
- **TPM (tmux Plugin Manager)**: 插件管理器
  ```bash
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  ```
- **pbcopy/pbpaste**: 剪贴板工具（macOS 自带）

### 可选依赖
- **fzf**: 模糊查找工具（用于交互式会话选择）
  ```bash
  brew install fzf
  ```
- **外部脚本**:
  - `~/.config/tmux/bin/tmux-commands` - 命令选择器
  - `~/.config/tmux/bin/tmux-sessions` - 会话选择器
  - `~/.config/tmux/bin/git-branch` - Git 分支显示
  - `~/.config/tmux/bin/sysinfo` - 系统信息显示

---

## 🛠️ 安装步骤

### 1. 安装 tmux
```bash
brew install tmux
```

### 2. 克隆配置
```bash
# 如果使用 dotfiles 仓库
cd ~/.dotfiles
git pull

# 创建符号链接（如果需要）
ln -sf ~/.dotfiles/.tmux.conf ~/.tmux.conf
```

### 3. 安装 TPM（插件管理器）
```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### 4. 启动 tmux 并安装插件
```bash
# 启动 tmux
tmux

# 按快捷键安装插件
# Ctrl+\ + I (大写 i)
```

### 5. 加载 Shell 别名（可选但推荐）
```bash
# 在 ~/.zshrc 或 ~/.bashrc 中添加
    source ~/.config/tmux/aliases.sh

# 或者通过 .aliases 统一加载（推荐）
source ~/.dotfiles/.aliases
```

### 6. 验证安装
```bash
# 检查 tmux 版本
tmux -V

# 检查前缀键
tmux show-options -g | grep prefix

# 检查插件
ls ~/.tmux/plugins/

# 检查别名是否加载
type tcd tal tsel
```

---

## 📁 文件结构

```
~/.dotfiles/
├── .tmux.conf                              # 主配置文件
└── .config/tmux/
    ├── README.md                           # 本文档
    ├── KEYBINDINGS.md                      # 快捷键速查表
    ├── aliases.sh                          # Shell 别名和辅助函数
    ├── bin/
    │   ├── tmux-commands                   # 命令选择器脚本
    │   ├── tmux-sessions                   # 会话选择器脚本
    │   ├── git-branch                      # Git 分支显示脚本
    │   └── sysinfo                         # 系统信息脚本
    └── sessions/
        └── popup.tmux.conf                 # Popup 会话配置
```

---

## 🔧 Shell 别名与辅助函数

tmux 配置包含了一组强大的 shell 别名和辅助函数，位于 `~/.config/tmux/aliases.sh`。

### 基础别名

| 别名 | 完整命令 | 说明 |
|------|---------|------|
| `t` | `tmux` | tmux 简写 |
| `tls` | `tmux ls` | 列出所有会话 |
| `ta` | `tmux attach -t` | 附着到指定会话 |
| `tn` | `tmux new-session -s` | 创建指定名称的会话 |
| `tA` | `tmux new-session -A -s` | 存在则附着，否则创建 |
| `tk` | `tmux kill-session -t` | 结束指定会话 |
| `tks` | `tmux kill-server` | 结束 tmux 服务器 |
| `treload` | `tmux source-file ~/.config/tmux/tmux.conf` | 重新加载配置并显示提示 |

### 智能函数

| 函数 | 用法 | 说明 |
|------|------|------|
| `tcd` | `tcd [name]` | 基于当前目录名创建/附着会话 |
| `tal` | `tal` | 附着到最近会话或创建 main 会话 |
| `tsel` | `tsel` | 使用 fzf 交互式选择会话 |
| `tnew` | `tnew <dir> [name]` | 在指定目录创建新会话 |
| `tkill` | `tkill` | 使用 fzf 交互式结束会话 |
| `tdev` | `tdev [name]` | 创建开发环境布局 |
| `tinfo` | `tinfo` | 显示 tmux 配置信息 |
| `tclean` | `tclean` | 清理所有已结束的会话 |
| `trename` | `trename <name>` | 重命名当前会话 |

**使用示例**:
```bash
# 基于目录名快速创建会话
cd ~/projects/myapp
tcd                    # 创建/附着到 "myapp" 会话

# 交互式选择会话（需要 fzf）
tsel                   # 打开会话选择器

# 创建开发环境布局
tdev myproject        # 创建 3 面板布局：编辑器 + 终端 + 日志

# 查看配置信息
tinfo                 # 显示版本、前缀键、会话数等
```

详细说明请查看 `~/.config/tmux/aliases.sh` 文件。

---

## ⌨️ 快捷键概览

> 详细列表请查看 [KEYBINDINGS.md](./KEYBINDINGS.md)

### 前缀键
- **前缀**: `Ctrl+B` (tmux 默认前缀)

### 常用操作
| 快捷键 | 功能 |
|--------|------|
| `prefix + c` | 新建窗口 |
| `prefix + 1-9` | 切换窗口 |
| `prefix + p/n` | 上一个/下一个窗口 |
| `prefix + %` | 水平分割面板 |
| `prefix + "` | 垂直分割面板 |
| `prefix + hjkl` | Vim 风格面板导航 |
| `prefix + HJKL` | 调整面板大小 |
| `prefix + z` | 面板缩放/全屏 |
| `prefix + [` | 进入复制模式 |
| `prefix + ]` | 粘贴 |

### 高级功能
| 快捷键 | 功能 |
|--------|------|
| `prefix + N` | 新建会话 |
| `prefix + S` | 会话列表 |
| `prefix + R` | 命令选择器 |
| `prefix + g` | 临时终端（popup）|
| `prefix + G` | Git 状态 |
| `prefix + M` | man 手册 |

---

## 🎨 主题配色

### 配色方案
| 名称 | 颜色值 | 用途 |
|------|--------|------|
| 主色 | `#32ade6` | 状态栏强调、活动窗口 |
| 亮青 | `#5ac8fa` | 活动面板边框 |
| 背景 | `#1d1d1f` | 状态栏背景 |
| 前景 | `#f5f5f7` | 文本颜色 |
| 二级灰 | `#2c2c2e` | 未激活窗口背景 |
| 次文字 | `#8e8e93` | 次要信息 |
| 分隔符 | `#3a3a3c` | 状态栏分隔符 |
| 系统黄 | `#ffd60a` | 前缀指示器 |

### 状态栏布局
```
┌─────────────────────────────────────────────────────────────┐
│ 会话名 | 窗口数 | [PFX] | [@主机]    时间 | 项目 | 分支 | 状态 │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔌 插件说明

### 已安装插件
1. **tpm**: 插件管理器（必需）
2. **tmux-sensible**: 合理的默认配置
3. **tmux-resurrect**: 会话持久化
4. **tmux-continuum**: 自动保存和恢复会话
5. **tmux-yank**: 增强的复制体验

### tmux-resurrect 功能
- 保存和恢复会话、窗口、面板布局
- 保存面板内容和历史
- 支持 vim/nvim 会话恢复
- 手动保存: `prefix + Ctrl+S`
- 手动恢复: `prefix + Ctrl+R`

### tmux-continuum 功能
- 自动每 15 分钟保存会话
- tmux 启动时自动恢复上次会话
- 无需手动操作，后台静默工作

### 插件管理
```bash
# 安装新插件
# 1. 在 .tmux.conf 中添加: set -g @plugin '...'
# 2. 重新加载配置: tmux source-file ~/.tmux.conf
# 3. 安装插件: prefix + I

# 更新插件
prefix + U

# 卸载插件
# 1. 从 .tmux.conf 中删除插件配置
# 2. 重新加载配置
# 3. 卸载: prefix + Alt+U
```

---

## 🔧 自定义配置

### 修改前缀键
如果想使用其他前缀键（如 `Ctrl+A` 或 `Ctrl+\`）：
```bash
# 编辑 ~/.config/tmux/tmux.conf
# 例如改为 Ctrl+A:
set-option -g prefix C-a
unbind-key C-b
bind-key C-a send-prefix

# 或改为 Ctrl+\ (反斜杠):
set-option -g prefix 'C-\'
unbind-key C-b
bind-key 'C-\' send-prefix
```

### 调整状态栏刷新频率
```bash
# 默认 15 秒，可以改为 5 秒（更频繁但耗电）
set-option -g status-interval 5
```

### 禁用鼠标支持
```bash
set-option -g mouse off
```

### 修改面板大小调整步长
```bash
# 默认 5，可以改为 10（更大步调整）
bind-key -r H resize-pane -L 10
bind-key -r J resize-pane -D 10
bind-key -r K resize-pane -U 10
bind-key -r L resize-pane -R 10
```

### 添加本地覆盖配置
创建 `~/.tmux.conf.local` 文件，添加你的个性化配置：
```bash
# 本地配置示例
set-option -g status-interval 5
set-option -g mouse off
```

---

## 🐛 故障排查

### 问题 1: tmux 启动失败
**症状**: 提示配置文件错误

**解决方案**:
```bash
# 检查配置语法
tmux -f ~/.tmux.conf start-server

# 查看详细错误
tmux -vv
```

### 问题 2: 插件不工作
**症状**: TPM 插件未加载

**解决方案**:
```bash
# 检查 TPM 是否安装
ls ~/.tmux/plugins/tpm

# 如果没有，安装 TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 重启 tmux
tmux kill-server && tmux

# 安装插件
# prefix + I
```

### 问题 3: 复制到剪贴板失败
**症状**: 复制后无法在其他应用粘贴

**解决方案**:
```bash
# 检查 pbcopy 是否可用
which pbcopy

# 测试剪贴板
echo "test" | pbcopy && pbpaste

# 如果不工作，检查配置
tmux show-options -g | grep clipboard
```

### 问题 4: 状态栏显示异常
**症状**: Git 分支或系统信息不显示

**解决方案**:
```bash
# 检查脚本是否存在
ls -l ~/.config/tmux/bin/

# 检查脚本是否可执行
chmod +x ~/.config/tmux/bin/*

# 手动测试脚本
~/.config/tmux/bin/git-branch "$(pwd)"
~/.config/tmux/bin/sysinfo
```

### 问题 5: 前缀键冲突
**症状**: `Ctrl+B` 在某些应用中有冲突（如 Vim 的向上翻页）

**解决方案**: 修改前缀键为其他键（如 `Ctrl+A` 或 `Ctrl+\`），参考上面的"修改前缀键"部分

### 问题 6: 会话恢复失败
**症状**: tmux-resurrect 无法恢复会话

**解决方案**:
```bash
# 检查保存目录
ls ~/.tmux/resurrect/

# 手动恢复
prefix + Ctrl+R

# 检查 continuum 状态
tmux show-option -g @continuum-restore
```

---

## 💡 使用技巧

### 1. 快速项目切换
```bash
# 方法 1: 使用会话选择器
prefix + S

# 方法 2: 使用自定义脚本
prefix + T
```

### 2. 高效复制粘贴
```bash
# 进入复制模式
prefix + [

# Vim 风格操作
v          # 开始选择
y          # 复制到系统剪贴板
/pattern   # 搜索
n/N        # 下一个/上一个匹配

# 粘贴
prefix + ]         # tmux 缓冲区
prefix + P         # 系统剪贴板
Command + V        # macOS 原生粘贴
```

### 3. 面板布局保存
```bash
# 保存当前布局
prefix + Ctrl+S

# 恢复布局
prefix + Ctrl+R
```

### 4. 同步输入到所有面板
```bash
# 开启/关闭同步
prefix + I

# 用途：在多个服务器上执行相同命令
```

### 5. 临时终端（Scratch Pad）
```bash
# 打开浮动终端
prefix + g

# 执行命令后自动关闭
exit
```

### 6. 快速查看 man 手册
```bash
# 打开 man 弹窗
prefix + M

# 输入命令名
git
```

### 7. 项目 Git 状态
```bash
# 查看 git 状态
prefix + G

# 显示当前目录的 git 状态
```

---

## 🔄 终端集成

本 tmux 配置可以与各种终端完美配合：

### 基本使用
- **前缀键**: `Ctrl+B`（tmux 标准前缀）
- **兼容性**: 适用于所有终端（iTerm2, Alacritty, Ghostty, Kitty 等）
- **主题**: 冷青极客风配色，256 色和真彩色支持

### 可选：终端快捷键映射
如果你的终端支持自定义快捷键，可以映射 `Command` 键到 tmux 命令：

| 建议快捷键 | tmux 命令 | 功能 |
|-----------|----------|------|
| `⌘T` | `send-keys C-b c` | 新窗口 |
| `⌘1-9` | `send-keys C-b 1-9` | 切换窗口 |
| `⌘[/]` | `send-keys C-b p/n` | 上/下个窗口 |
| `⌘Enter` | `send-keys C-b %` | 水平分割 |
| `⌘D` | `send-keys C-b "` | 垂直分割 |
| `⌘W` | `send-keys C-b x` | 关闭面板 |
| `⌘Z` | `send-keys C-b z` | 面板缩放 |

**提示**: 以上快捷键需要在终端配置中手动设置。

---

## 📚 参考资料

### 官方文档
- [tmux 官方 Wiki](https://github.com/tmux/tmux/wiki)
- [tmux man 手册](https://man.openbsd.org/tmux)
- [TPM 仓库](https://github.com/tmux-plugins/tpm)

### 插件文档
- [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible)
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum)
- [tmux-yank](https://github.com/tmux-plugins/tmux-yank)

### 相关配置
- [Zsh 配置说明](../../TMUX_ZSH_INTEGRATION.md)
- [tmux 快捷键](./KEYBINDINGS.md)
- [快速入门指南](../../QUICKSTART.md)

---

## 📝 变更日志

### 2024-01 (当前版本)
- ✅ 修复脚本路径不一致问题
- ✅ 添加 macOS 剪贴板集成（pbcopy/pbpaste）
- ✅ 增强复制模式（搜索、选择、Vim 风格）
- ✅ 添加窗口切换快捷键（p/n）
- ✅ 添加窗口重新排序（</>）
- ✅ 添加更多 popup 功能（临时终端、man、git）
- ✅ 优化状态栏性能（刷新间隔 15 秒）
- ✅ 添加 TPM 插件管理器
- ✅ 添加会话持久化（resurrect + continuum）
- ✅ 创建完整文档和快捷键速查表

---

## 🤝 贡献

欢迎提出改进建议！如果你有好的想法或发现问题，请：
1. 修改 `~/.tmux.conf.local` 测试
2. 验证功能正常
3. 分享你的改进

---

**维护者**:（通用模板已移除个人链接）
**最后更新**: 2024  
**版本**: 2.0  
**License**: MIT

---

## 🎓 学习资源

### 初学者
- [tmux 入门教程](https://www.hamvocke.com/blog/a-quick-and-easy-guide-to-tmux/)
- [tmux Cheat Sheet](https://tmuxcheatsheet.com/)

### 进阶
- [tmux 高级配置](https://www.barbarianmeetscoding.com/blog/jaimes-guide-to-tmux-the-most-awesome-tool-you-didnt-know-you-needed)
- [tmux 源码解析](https://github.com/tmux/tmux)

### 视频教程
- [tmux 快速入门](https://www.youtube.com/watch?v=Yl7NFenTgIo)
- [tmux 进阶技巧](https://www.youtube.com/watch?v=bdumjiHabhQ)

---

**享受你的 tmux 之旅！** 🚀
