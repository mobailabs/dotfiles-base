# tmux 配置

一份单文件、Vim 风格的 tmux 配置。

> **配色说明**：tmux 状态栏用的是 **Monokai Pro Ristretto** 暖色深色板
> （主色 `#FC9867` 橙）。Ghostty 终端用的是另一套 **Neo-Geometric Dark** 冷青色板
> （主色 `#32ade6` 青）—— 两者**不是同一套**，只是都偏深色，视觉上不打架。
> 想统一改哪套就改哪套：终端底色在 `ghostty/config`，tmux 状态栏在本文件。

> 这份文档是 tmux 配置的**唯一**说明。以前这里还有 `ALIASES.md`、
> `KEYBINDINGS.md`、`QUICKREF.md`、`MIGRATION.md` 四份（共 1100+ 行），
> 内容互相重叠、且部分与 `tmux.conf` 已经对不上（比如写的是 `Ctrl+\` 前缀，
> 实际是 `Ctrl+B`）。已合并到这里，只剩这一份，改配置时只改这里。

---

## 文件

```text
~/.config/tmux/
├── tmux.conf                 # 主配置（链接自 src/macos/config/tmux/config/）
├── aliases.sh                # shell 别名与函数，由 ~/.zshrc 加载
├── bin/
│   ├── tmux-commands         # 命令选择器（popup 用）
│   ├── tmux-sessions         # 会话选择器（popup 用）
│   ├── git-branch            # 状态栏：当前 git 分支
│   └── sysinfo               # 状态栏：系统信息
└── sessions/
    └── popup.tmux.conf       # popup 会话的独立配置

~/.tmux.conf                  # → 链接到上面的 tmux.conf
```

---

## 依赖

必需：

```sh
brew install tmux        # 已在 packages/common/brew-cli.txt
```

推荐（缺失时功能降级，不报错）：

- `fzf` —— `tsel` / `tkill` 的交互选择（已在 `packages/common/brew-cli.txt`）
- TPM —— 插件管理器，`install.zsh` 会自动装
- `pbcopy` / `pbpaste` —— macOS 自带

---

## 插件

`tmux.conf` 里声明、由 TPM 管理：

| 插件 | 作用 |
|---|---|
| tmux-sensible | 合理的默认值 |
| tmux-resurrect | 会话持久化 |
| tmux-continuum | 每 15 分钟自动保存 + 启动自动恢复 |
| tmux-yank | 增强复制 |

安装：`zsh install.zsh`（会自动装 TPM 与插件）。
注意 `prefix I` 被绑给了「同步面板」，不是 TPM 的安装键 —— 见下面「插件管理」。

---

## 快捷键

**前缀键：`Ctrl+B`**（tmux 默认；`Ctrl+B Ctrl+B` 发送字面 `Ctrl+B`）。

### 窗口

| 快捷键 | 功能 |
|---|---|
| `prefix c` | 新建窗口（保持当前目录） |
| `prefix 1-9` | 切到第 N 个窗口 |
| `prefix p` / `n` | 上一 / 下一个窗口 |
| `prefix ^` | 上一个窗口 |
| `prefix <` / `>` | 窗口左 / 右移 |
| `prefix &` | 关闭窗口 |

### 面板

| 快捷键 | 功能 |
|---|---|
| `prefix %` | 水平分割（左右，保持当前目录） |
| `prefix "` | 垂直分割（上下，保持当前目录） |
| `prefix h/j/k/l` | Vim 风格面板导航 |
| `prefix H/J/K/L` | 调整面板大小（每次 5） |
| `prefix Tab` | 上一个活动面板 |
| `prefix z` | 面板缩放 / 全屏 |
| `prefix {` / `}` | 与上 / 下面板交换位置 |
| `prefix x` | 关闭面板 |
| `prefix M-1..M-9` | 把当前面板并入第 N 个窗口 |

### 会话

| 快捷键 | 功能 |
|---|---|
| `prefix N` | 新建会话（以当前目录命名） |
| `prefix S` | 会话选择器（弹窗，fzf） |
| `prefix X` | 关闭会话 |
| `prefix P` | 切换 popup 会话 |
| `prefix d` | 分离（保持会话运行） |

### 复制模式（Vi）

进入：`prefix [`。进入后：

| 按键 | 功能 |
|---|---|
| `v` | 开始选择 |
| `y` | 复制并退出（写入系统剪贴板，OSC 52） |
| `/` `?` `n` `N` | 搜索 / 下一个 / 上一个 |
| `h/j/k/l` `w/b` `0/$` `g/G` | Vim 导航 |
| `q` / `Esc` | 退出 |

粘贴：`prefix ]`。

鼠标拖拽选择结束会自动复制到系统剪贴板。

### 弹窗与工具

| 快捷键 | 功能 |
|---|---|
| `prefix R` | 命令选择器 → 执行 |
| `prefix C` | 命令选择器 → 新窗口 |
| `prefix \|` | 命令选择器 → 垂直分割 |
| `prefix -` | 命令选择器 → 水平分割 |
| `prefix g` | 临时终端（浮动） |
| `prefix G` | 当前目录 git 状态 |
| `prefix M` | man 手册 |
| `prefix I` | 同步输入到所有面板（开关） |
| `prefix r` | 重新加载配置（TPM 提供） |
| `prefix ?` | 所有快捷键 |

### 插件管理（TPM）

> ⚠️ 本配置把 `prefix I` 绑给了「同步输入到所有面板」，**覆盖了 TPM 默认的安装键**。
> 所以装插件不能用 `prefix I`；用命令行或 TPM 的脚本。

| 方式 | 功能 |
|---|---|
| `~/.tmux/plugins/tpm/bin/install_plugins` | 安装配置里声明的插件 |
| `~/.tmux/plugins/tpm/bin/update_plugins all` | 更新插件 |
| `prefix Ctrl+S` / `Ctrl+R` | 手动保存 / 恢复会话（resurrect） |

---

## Shell 别名与函数

`aliases.sh` 由 `~/.zshrc` 加载。

**基础别名**

| 别名 | 完整命令 |
|---|---|
| `t` | `tmux` |
| `tls` | `tmux ls` |
| `ta <name>` | `tmux attach -t` |
| `tn <name>` | `tmux new-session -s` |
| `tA <name>` | `tmux new-session -A -s`（存在则附着） |
| `tk <name>` | `tmux kill-session -t` |
| `tks` | `tmux kill-server` |
| `treload` | 重新加载 tmux 配置 |
| `tsave` / `trestore` | 手动保存 / 恢复会话 |

**函数**

| 函数 | 说明 |
|---|---|
| `tcd [name]` | 以当前目录名（或指定名）创建 / 附着会话 |
| `tal` | 附着到最近会话，没有则建 `main` |
| `tsel` | fzf 交互选择会话 |
| `tnew <dir> [name]` | 在指定目录建会话 |
| `tkill` | fzf 交互结束会话 |
| `tdev [name]` | 建开发布局（编辑器 + 终端 + 日志） |
| `tinfo` | 显示 tmux 配置摘要 |
| `tclean` | 清理已结束的会话 |
| `trename <name>` | 重命名当前会话 |
| `tkeys` | `tmux list-keys` |

---

## 主题

Monokai Pro Ristretto 暖色深色调（状态栏在顶部）：

| 名称 | 颜色 | 用途 |
|---|---|---|
| 主色 | `#FC9867` | 状态栏强调、当前窗口、活动边框 |
| 前景 | `#FCFCFA` | 文本 |
| 背景 | `#2D2A2E` | 状态栏背景 |
| 二级背景 | `#403E41` | 非当前窗口 |
| 次文字 | `#939293` | 次要信息 |
| 前缀指示 | `#FFD866` | 按下前缀时的高亮 |

状态栏：左 = 会话名 / 窗口数 / 前缀指示；右 = 时间 / 项目名 / git 分支 / 系统信息 / 主机名。

---

## 自定义

**改前缀键**：编辑 `tmux.conf` 顶部：

```tmux
set-option -g prefix C-a
unbind-key C-b
bind-key C-a send-prefix
```

**本地覆盖**：tmux 本身没有 include-local 的机制，所以个人临时改动直接改
`tmux.conf`（它是链接，改的是仓库源文件）；不想进仓库的放 `~/.tmux.conf.local`
并在 `tmux.conf` 末尾 source —— 目前**没有**这个文件，别以为它自动生效。

---

## 故障排查

```sh
# 配置语法
tmux -f ~/.tmux.conf start-server

# 插件没加载
ls ~/.tmux/plugins/tpm        # 应存在；没有就 zsh install.zsh
# 然后跑 ~/.tmux/plugins/tpm/bin/install_plugins（prefix I 被同步面板占用，见上）

# 状态栏脚本不显示
ls -l ~/.config/tmux/bin/     # 应该是可执行文件
~/.config/tmux/bin/git-branch "$(pwd)"

# 剪贴板
echo test | pbcopy && pbpaste
tmux show-options -g | grep clipboard
```

---

## 参考

- [tmux Wiki](https://github.com/tmux/tmux/wiki)
- [TPM](https://github.com/tmux-plugins/tpm) ·
  [resurrect](https://github.com/tmux-plugins/tmux-resurrect) ·
  [continuum](https://github.com/tmux-plugins/tmux-continuum) ·
  [yank](https://github.com/tmux-plugins/tmux-yank)
