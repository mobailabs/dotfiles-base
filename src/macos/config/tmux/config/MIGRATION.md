# tmux 配置迁移说明

## 📝 变更摘要

为了更好的模块化和组织，tmux 相关的 shell 别名和辅助函数已从 `.aliases` 文件迁移到独立的配置文件中。

---

## 🔄 变更内容

### 之前的结构
```
~/.dotfiles/
├── .aliases              # 包含所有别名（包括 tmux）
└── .config/tmux/
    ├── tmux.conf
    └── bin/
```

### 现在的结构
```
~/.dotfiles/
├── .aliases              # 通用别名，引用 tmux aliases
└── .config/tmux/
    ├── tmux.conf
    ├── aliases.sh        # ✨ 新增：tmux 专用别名
    ├── ALIASES.md        # ✨ 新增：别名使用文档
    ├── MIGRATION.md      # ✨ 新增：迁移说明（本文档）
    └── bin/
```

---

## ✅ 迁移的功能

以下别名和函数已迁移到 `~/.config/tmux/aliases.sh`：

### 基础别名
- `t`, `tls`, `ta`, `tn`, `tA`, `tk`, `tks`, `tr`

### 原有函数
- `tcd()` - 基于目录创建会话
- `tal()` - 附着到最近会话
- `tsel()` - 交互式会话选择

### 新增功能 ⭐
- `tnew()` - 在指定目录创建会话
- `tkill()` - 交互式结束会话
- `tdev()` - 创建开发环境布局
- `tinfo()` - 显示配置信息
- `tclean()` - 清理死会话
- `trename()` - 重命名当前会话
- `tsave` / `trestore` - 会话持久化

---

## 🚀 升级步骤

### 1. 拉取最新配置（已完成）

```bash
cd ~/.dotfiles
git pull
```

### 2. 重新加载 shell 配置

```bash
# 对于 zsh
source ~/.zshrc

# 对于 bash
source ~/.bashrc

# 或者重启终端
```

### 3. 验证迁移

```bash
# 检查别名是否加载
type tcd tal tsel

# 检查新功能
type tdev tinfo tclean

# 测试基础功能
tinfo
```

---

## 📦 兼容性

### ✅ 完全兼容
所有原有的别名和函数保持**完全相同的行为**，无需修改任何脚本或工作流。

### 加载方式

#### 方式 1: 通过 .aliases（推荐，自动迁移）
```bash
# .aliases 文件已自动更新为：
source ~/.config/tmux/aliases.sh
```

如果你的 shell 配置中有 `source ~/.dotfiles/.aliases`，则无需任何改动。

#### 方式 2: 直接加载（可选）
```bash
# 在 ~/.zshrc 或 ~/.bashrc 中
source ~/.config/tmux/aliases.sh
```

---

## 🎯 优势

### 1. 更好的模块化
- tmux 相关配置集中在 `.config/tmux/` 目录
- 便于查找和维护
- 符合 XDG 配置规范

### 2. 独立文档
- [ALIASES.md](./ALIASES.md) - 详细的使用文档
- [KEYBINDINGS.md](./KEYBINDINGS.md) - 快捷键速查表
- [README.md](./README.md) - 完整配置说明

### 3. 扩展性
- 新增了多个实用函数
- 更容易添加自定义功能
- 更好的代码注释和文档

### 4. 灵活性
- 可以选择性加载
- 便于在不同环境中使用
- 支持本地覆盖配置

---

## 📚 文档索引

| 文档 | 内容 |
|------|------|
| [README.md](./README.md) | tmux 配置完整说明 |
| [KEYBINDINGS.md](./KEYBINDINGS.md) | 快捷键速查表 |
| [ALIASES.md](./ALIASES.md) | Shell 别名使用指南 |
| [aliases.sh](./aliases.sh) | 别名源代码 |

---

## 🆘 需要帮助？

### 问题：别名不工作

```bash
# 检查是否加载
type tcd

# 手动加载
source ~/.config/tmux/aliases.sh

# 永久加载（添加到 .zshrc）
echo 'source ~/.config/tmux/aliases.sh' >> ~/.zshrc
```

### 问题：找不到旧的别名

所有旧的别名都保留了，位置在 `~/.config/tmux/aliases.sh`。

### 问题：想要恢复旧版本

```bash
cd ~/.dotfiles
git log --oneline .aliases        # 查看历史
git show <commit>:.aliases        # 查看旧版本
```

---

## 📝 变更日志

### 2024-01-XX
- ✅ 将 tmux 别名迁移到 `.config/tmux/aliases.sh`
- ✅ 创建详细的使用文档 `ALIASES.md`
- ✅ 新增 7 个实用函数
- ✅ 更新 README.md 添加别名说明
- ✅ 保持完全向后兼容

---

**迁移完成！享受更好的 tmux 体验！** 🎉
