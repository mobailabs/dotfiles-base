# tmux Shell 别名使用指南

本文档介绍 tmux 配置提供的所有 shell 别名和辅助函数。

> **配置文件**: `~/.config/tmux/aliases.sh`

---

## 📦 安装

### 方式 1: 通过 .aliases 统一加载（推荐）

```bash
# 在 ~/.zshrc 或 ~/.bashrc 中
source ~/.dotfiles/.aliases
```

`.aliases` 文件会自动加载 tmux aliases。

### 方式 2: 直接加载

```bash
# 在 ~/.zshrc 或 ~/.bashrc 中
source ~/.config/tmux/aliases.sh
```

### 验证安装

```bash
# 检查别名是否加载成功
type tcd tal tsel

# 应该显示函数定义
```

---

## 🎯 快速参考

### 基础操作

| 别名 | 说明 | 示例 |
|------|------|------|
| `t` | tmux 简写 | `t` |
| `tls` | 列出所有会话 | `tls` |
| `ta <name>` | 附着到指定会话 | `ta work` |
| `tn <name>` | 创建新会话 | `tn myproject` |
| `tA <name>` | 创建或附着 | `tA dev` |
| `tk <name>` | 结束会话 | `tk old-session` |
| `tks` | 结束 tmux 服务器 | `tks` |
| `treload` | 重新加载配置并显示提示 | `treload` |

### 智能函数

| 函数 | 说明 | 示例 |
|------|------|------|
| `tcd [name]` | 基于目录创建会话 | `tcd` 或 `tcd myapp` |
| `tal` | 附着到最近会话 | `tal` |
| `tsel` | 交互选择会话 | `tsel` |
| `tnew <dir> [name]` | 在指定目录创建会话 | `tnew ~/projects/app` |
| `tkill` | 交互结束会话 | `tkill` |
| `tdev [name]` | 创建开发布局 | `tdev` |
| `tinfo` | 显示配置信息 | `tinfo` |
| `tclean` | 清理死会话 | `tclean` |
| `trename <name>` | 重命名当前会话 | `trename newname` |

### 会话持久化

| 别名 | 说明 | 示例 |
|------|------|------|
| `tsave` | 手动保存会话 | `tsave` |
| `trestore` | 恢复会话 | `trestore` |

### 调试工具

| 别名 | 说明 | 示例 |
|------|------|------|
| `tkeys` | 列出所有快捷键 | `tkeys` |
| `tinfo` | 显示配置摘要 | `tinfo` |

---

## 📚 详细说明

### 1. `tcd` - 智能会话创建

**功能**: 基于当前目录名自动创建或附着到会话。

**用法**:
```bash
# 使用当前目录名作为会话名
cd ~/projects/myapp
tcd                    # 创建/附着到 "myapp" 会话

# 指定自定义会话名
tcd work              # 创建/附着到 "work" 会话
```

**特点**:
- 会话已存在：直接附着
- 会话不存在：自动创建
- 默认使用当前目录名

---

### 2. `tal` - 快速附着

**功能**: 附着到最近使用的会话，如果没有会话则创建 `main` 会话。

**用法**:
```bash
tal                   # 一键附着或创建
```

**使用场景**:
- 打开终端后快速进入 tmux
- 不需要记住会话名
- 自动创建默认会话

---

### 3. `tsel` - 交互式选择器 ⭐

**功能**: 使用 fzf 交互式选择 tmux 会话。

**依赖**: 需要安装 `fzf`
```bash
brew install fzf
```

**用法**:
```bash
tsel                  # 打开会话选择器
# 使用方向键选择会话
# 按 Enter 确认
```

**智能行为**:
- **在 tmux 内部**: 切换到选择的会话
- **在 tmux 外部**: 附着到选择的会话

**交互界面**:
```
tmux>
  main
> work
  myproject
  dev
  3/4
```

---

### 4. `tnew` - 指定目录创建会话

**功能**: 在指定目录创建新会话。

**用法**:
```bash
# 在指定目录创建会话（使用目录名作为会话名）
tnew ~/projects/myapp

# 在指定目录创建会话（自定义会话名）
tnew ~/projects/myapp work

# 在当前目录创建会话
tnew .
```

**与 `tcd` 的区别**:
- `tcd`: 会话存在则附着，不存在则创建
- `tnew`: 始终创建新会话

---

### 5. `tkill` - 交互式结束会话

**功能**: 使用 fzf 交互式选择并结束会话。

**依赖**: 需要安装 `fzf`

**用法**:
```bash
tkill                 # 选择要结束的会话
```

**安全提示**:
- 可以使用 `Esc` 或 `Ctrl+C` 取消操作
- 支持模糊搜索会话名

---

### 6. `tdev` - 开发环境布局 🚀

**功能**: 创建预定义的 3 面板开发布局。

**布局**:
```
┌─────────────────────────────────┐
│  面板 1: 编辑器 (70%)            │
├──────────────┬──────────────────┤
│  面板 2:     │  面板 3:         │
│  终端 (30%)  │  日志/服务 (30%) │
└──────────────┴──────────────────┘
```

**用法**:
```bash
# 使用当前目录名作为会话名
cd ~/projects/myapp
tdev

# 指定自定义会话名
tdev myproject
```

**工作流**:
1. 创建新会话
2. 垂直分割（上 70% / 下 30%）
3. 下方水平分割（左右各 50%）
4. 自动附着到会话
5. 焦点在面板 1（编辑器）

**适用场景**:
- 编辑代码 + 运行命令 + 查看日志
- 前端开发（编辑器 + dev server + 测试）
- 后端开发（编辑器 + API + 数据库）

---

### 7. `tinfo` - 配置信息

**功能**: 显示当前 tmux 配置摘要。

**用法**:
```bash
tinfo
```

**输出示例**:
```
=== tmux Configuration Info ===
Version: tmux 3.3a
Config: ~/.tmux.conf
Prefix: C-b
Sessions: 3
Plugins: 5
Current session: work
Current window: 1:nvim
```

**显示内容**:
- tmux 版本
- 配置文件位置
- 前缀键
- 会话数量
- 插件数量
- 当前会话和窗口（如果在 tmux 内）

---

### 8. `tclean` - 清理死会话

**功能**: 自动清理所有已结束的会话。

**用法**:
```bash
tclean
```

**输出示例**:
```
✓ Cleaned 2 dead session(s)
```

**使用场景**:
- 会话异常退出后清理
- 定期维护
- 释放资源

---

### 9. `trename` - 重命名会话

**功能**: 重命名当前 tmux 会话。

**用法**:
```bash
# 必须在 tmux 会话内使用
trename newname
```

**示例**:
```bash
# 在 tmux 会话内
trename work-backend
# ✓ Session renamed to: work-backend
```

**错误提示**:
```bash
# 在 tmux 外部使用
trename test
# ✗ Not in a tmux session
```

---

### 10. `tsave` / `trestore` - 会话持久化

**功能**: 手动保存和恢复 tmux 会话。

**依赖**: 需要 `tmux-resurrect` 插件（已在配置中安装）

**用法**:
```bash
# 保存当前所有会话
tsave

# 恢复上次保存的会话
trestore
```

**注意**:
- `tmux-continuum` 已启用自动保存（每 15 分钟）
- 手动保存适用于重要操作前备份
- 恢复会保留：
  - 会话结构
  - 窗口和面板布局
  - 工作目录
  - 面板内容和历史

---

## 🎨 工作流示例

### 场景 1: 每日启动

```bash
# 打开终端后
tal                   # 附着到最近会话或创建 main 会话
```

### 场景 2: 项目开发

```bash
# 进入项目目录
cd ~/projects/myapp

# 创建开发环境
tdev                  # 创建 3 面板布局

# 在面板 1 打开编辑器
nvim

# Ctrl+B j (切换到面板 2)
npm run dev

# Ctrl+B l (切换到面板 3)
npm run test:watch
```

### 场景 3: 多项目切换

```bash
# 快速切换项目
tsel                  # 使用 fzf 选择会话

# 或创建新项目会话
cd ~/projects/newapp
tcd                   # 自动创建 "newapp" 会话
```

### 场景 4: 会话管理

```bash
# 查看所有会话
tls

# 选择并结束不需要的会话
tkill

# 清理死会话
tclean

# 查看配置信息
tinfo
```

### 场景 5: 远程开发

```bash
# SSH 到远程服务器
ssh server

# 快速附着或创建会话
tal

# 创建项目会话
cd /var/www/app
tcd

# 保存会话状态
tsave

# 断开连接
exit

# 下次连接时恢复
ssh server
tal                   # 自动恢复之前的会话
```

---

## 💡 使用技巧

### 1. 与 Vim/Neovim 集成

```bash
# 使用 tdev 创建开发环境
cd ~/project
tdev

# 在面板 1 打开 nvim
nvim

# 使用 Ctrl+B hjkl 在面板间导航
# 或在 nvim 中使用 vim-tmux-navigator 无缝导航
```

### 2. 会话命名规范

建议的命名规范：
- **项目名**: `myapp`, `website`, `api`
- **任务类型**: `work`, `dev`, `test`
- **临时任务**: `tmp`, `scratch`, `debug`

```bash
# 好的命名
tcd myapp-backend
tcd work-urgent

# 避免的命名
tcd "my app with spaces"  # 空格会导致问题
tcd 123                   # 纯数字不直观
```

### 3. 自动化脚本

在脚本中使用别名：

```bash
#!/bin/bash
# deploy.sh

# 确保加载别名
source ~/.config/tmux/aliases.sh

# 创建部署会话
tcd deploy

# 在会话中执行命令
tmux send-keys "git pull" C-m
tmux send-keys "npm install" C-m
tmux send-keys "npm run build" C-m
```

### 4. 结合其他工具

```bash
# 结合 fzf 查找项目并创建会话
project=$(find ~/projects -maxdepth 1 -type d | fzf)
cd "$project"
tcd

# 结合 git worktree
cd ~/projects/myapp
git worktree add ../myapp-feature feature-branch
cd ../myapp-feature
tcd myapp-feature
```

---

## 🔧 自定义

### 添加自己的别名

在 `~/.zshrc` 或 `~/.bashrc` 中添加：

```bash
# 加载 tmux aliases
source ~/.config/tmux/aliases.sh

# 添加自定义别名
alias twork='tA work'              # 快速进入 work 会话
alias ttest='tA test'              # 快速进入 test 会话
alias tlog='tmux pipe-pane -o "cat >> ~/tmux-log.txt"'  # 记录面板输出
```

### 修改 tdev 布局

复制 `tdev` 函数并修改布局：

```bash
# 2 面板水平布局
tdev2() {
  local name="${1:-$(basename "$(pwd)")}"
  tmux new-session -d -s "$name" -c "$(pwd)"
  tmux split-window -h -p 50 -t "$name"
  tmux select-pane -t "$name":1.1
  tmux attach -t "$name"
}
```

---

## 🐛 故障排查

### 问题 1: 别名不工作

**症状**: 输入 `tcd` 提示命令不存在

**解决方案**:
```bash
# 检查是否加载了别名文件
type tcd

# 如果未加载，手动加载
source ~/.config/tmux/aliases.sh

# 确保在 .zshrc 中添加了 source 命令
echo 'source ~/.config/tmux/aliases.sh' >> ~/.zshrc
```

### 问题 2: tsel 不可用

**症状**: `tsel` 命令不存在

**原因**: 未安装 fzf

**解决方案**:
```bash
brew install fzf
```

### 问题 3: tsave/trestore 不工作

**症状**: 保存/恢复会话失败

**解决方案**:
```bash
# 检查插件是否安装
ls ~/.tmux/plugins/tmux-resurrect

# 如果未安装，安装插件
# 在 tmux 中按: prefix + I
```

### 问题 4: tdev 布局不对

**症状**: 面板布局与预期不符

**解决方案**:
```bash
# 检查 tmux 版本
tmux -V

# 需要 tmux 2.9+
# 如果版本过低，升级 tmux
brew upgrade tmux
```

---

## 📚 相关文档

- [tmux 配置说明](./README.md)
- [tmux 快捷键速查表](./KEYBINDINGS.md)
- [主配置文件](./.tmux.conf)

---

## 🤝 贡献

欢迎添加更多实用的别名和函数！

编辑文件：
```bash
vim ~/.config/tmux/aliases.sh
```

测试后提交：
```bash
cd ~/.dotfiles
git add .config/tmux/aliases.sh
git commit -m "Add new tmux alias"
```

---

**维护者**: （可选）请替换为你自己的维护者信息
**最后更新**: 2024  
**版本**: 1.0
