# tmux 快速参考卡片

快速查找最常用的 tmux 操作。

---

## ⌨️ 核心快捷键

**前缀键**: `Ctrl+B`

| 操作 | 快捷键 |
|------|--------|
| **窗口管理** | |
| 新窗口 | `prefix c` |
| 切换窗口 | `prefix 1-9` |
| 上/下个窗口 | `prefix p/n` |
| **面板操作** | |
| 水平分割 | `prefix %` |
| 垂直分割 | `prefix "` |
| 导航 | `prefix hjkl` |
| 缩放 | `prefix z` |
| **会话管理** | |
| 会话列表 | `prefix S` |
| 新会话 | `prefix N` |
| 分离 | `prefix d` |

---

## 🚀 常用别名

| 别名 | 说明 |
|------|------|
| `tcd` | 基于目录创建会话 |
| `tal` | 附着到最近会话 |
| `tsel` | 交互选择会话 (fzf) |
| `tdev` | 创建开发布局 |
| `tinfo` | 显示配置信息 |

---

## 📚 完整文档

- [完整配置说明](./README.md)
- [快捷键速查表](./KEYBINDINGS.md)
- [Shell 别名指南](./ALIASES.md)
- [迁移说明](./MIGRATION.md)

---

**提示**: 在 tmux 中按 `prefix ?` 查看所有快捷键
