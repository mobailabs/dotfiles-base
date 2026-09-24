# dotfiles-base

新机器的起点。macOS / Zsh / tmux / Neovim / mise。

一次 `zsh install.zsh` 之后，这台机器就按同一套标准被配置好：软件装齐、配置链接到位、
系统偏好应用、开发环境版本对齐。

> **只做 macOS。** 以前还支持 Ubuntu/Debian 服务器（Linuxbrew + apt 引导），
> 那条路已经删了 —— 见下面「为什么删掉 Linux」。

---

## 这是什么，不是什么

**是**：一台新机器从零到可用的起点，也是「标准」的唯一存放处。
配置改在这里，机器上的改动才有归宿。

**不是**：某台机器的快照。机器专属的东西（Git 身份、SSH Host、token、公司内网变量）
不进这个仓库 —— 它们属于**私有源**（用户自己的数据，可以是私有 git 仓库、
普通目录，将来也可以是 macview 的云服务），通过几个 `.local` 落点被这里的
加载点读进来。**没有私有源也完全能跑** —— 加载点全是条件加载，缺了就跳过。

「公开仓库 / 私有源」之间的接口（谁读谁、怎么判断装没装好）见
**[`private.md`](private.md)** —— 那也是 macview 读的状态契约。

---

## 新机器：一条命令

```sh
# 1. 克隆（路径随意，脚本按自身位置定位，不依赖固定目录）
git clone <this-repo> ~/dotfiles
cd ~/dotfiles

# 2. 装（全部：check → 身份/权限 → brew → 插件 → 链接 → mise → 系统偏好）
zsh install.zsh
```

**它只在开头问你一次**（git 名字/邮箱 + 管理员密码），之后全程零交互 ——
你可以敲完然后走开。脚本无法自动猜的东西都集中在这一步问完，
不会装到一半突然卡在某个提示上。

想完全零交互（CI / 远程）：

```sh
zsh install.zsh --name "你的名字" --email "you@example.com"
# 或者
GIT_AUTHOR_NAME=X GIT_AUTHOR_EMAIL=Y zsh install.zsh --yes
```

`--yes` 表示不提问，全部从参数 / 环境变量 / 已有配置取值；取不到就跳过
（不阻断其它步骤）。

机器专属的东西（Git 身份 / SSH / token）另外放在一个**私有源**里，通过几个
`.local` 落点被加载（见下面「加载点」，接口定义见 [`private.md`](private.md)）。
**没有私有源也不会报错** —— 加载点全是条件加载，缺了就静默跳过。
所以「私有源在不在、装全了没有」是 macview 要告诉你的事。

### install.zsh 做了什么

| 步骤 | 内容 |
|---|---|
| check | 预检（macOS / git / 网络），唯一会硬性中止的一步 |
| **一次性设置** | git 身份写 `~/.gitconfig.local`、`sudo -v` 预授权、ssh `Include` 自动加 |
| Homebrew + 包 | 没 brew 就先用 `NONINTERACTIVE=1` 自动装（装前会再确认一次管理员权限），再装 `packages/macos/brew-*.txt` |
| oh-my-zsh / zsh 插件 | 装 `~/.oh-my-zsh` 与 brew 里没有的插件 |
| 链接配置 | 19 个落点链到 `$HOME` |
| tmux 插件 / mise | TPM 及插件；按 `mise/config.toml` 装工具 |
| macOS 偏好 | 9 个 `prefs.d`；这步前会再补一次 `sudo`（失效时让你再输一次，不会卡住） |

**单步失败不会中断**：每步独立容错，最后汇总失败项并以非 0 退出。
所以就算某个 cask 装不上，配置链接和系统偏好照样完成。

装完还有两件「需要重启才生效」：**新开一个终端**、部分 App 要重启。

`install.zsh` 还可以单独跑某一步：

| 命令 | 作用 |
|---|---|
| `zsh install.zsh` | 全套（`base`） |
| `zsh install.zsh link` | 只重新链接配置 |
| `zsh install.zsh prefs` | 只重新应用 macOS 偏好（幂等，可随时重跑） |
| `zsh install.zsh audit` | **对账**：清单里声明、这台没装的包（只读，不改机器） |
| `zsh install.zsh help` | 用法 |

`audit` 读 `packages/*.txt`，用和安装脚本同一套解析规则，报告
「声明了但没装」「清单内重复」「本机多出来的」。只读，不改机器。

---

## 目录结构

```text
.
├── install.zsh              ← 入口（macOS）
├── README.md                ← 本文件：装什么、怎么装、改哪里
├── shell.md                 ← shell 加载链的完整说明（PATH/环境变量/别名/函数）
├── private.md               ← 公开仓库↔私有源的接口契约（macview 读的状态格式）
├── packages/                ← 要装什么（仓库只做 macOS，所以没有平台分层）
│   └── macos/{brew-cli,brew-cask}.txt
├── scripts/
│   └── macos/               ← 全部脚本（brew / 插件 / 链接 / mise / 对账 / 私有源状态）
│       ├── brew-env.zsh     ← 把 homebrew 环境补进当前进程（被 source）
│       ├── private-state.zsh ← 产出私有源状态（契约见 private.md，macview 读）
│       ├── prompt-once.zsh  ← 开头一次性问完身份/权限/ssh（全自动的关键）
│       ├── check.zsh, brew-install.zsh
│       └── prefs.d/         ← 系统偏好，一个文件一个主题
├── src/macos/config/        ← 配置源（只有 macOS，没有平台分层）
│   ├── zsh/  env/  shell/   ← .zshenv/.zshrc/别名/函数/导出变量
│   ├── git/                 ← gitconfig + 全局 gitignore/gitattributes
│   ├── tmux/  ghostty/      ← 终端与复用器
│   └── nvim/  mise/         ← 编辑器与工具版本
```

> **为什么没有 `common/` 分层**：这个仓库**只做 macOS**（Linux 支持已删，
> 见下面「只做 macOS」）。因此 `packages/common/` 和 `scripts/common/`
> 的存在只会在每个文件上多问一句「这算通用还是 macOS 专属」——而答案永远
> 不影响任何行为。已合并进 `macos/`。

`src/` 里的东西**不直接生效** —— 它们是源，被链接到 `$HOME` 才生效。

---

## 包清单的格式（**别改**）

`packages/*/brew-*.txt` 的格式由 `scripts/macos/brew-packages-install.zsh`
（装）和 `scripts/macos/brew-audit.zsh`（对账）共同解析。规则：

- 一行一个包，`#` 之后是注释，取每行**第一个空白分隔**的字段
- 带 tap 的写全路径 `user/tap/formula`（brew 会顺带自动 tap）；
  比对「装没装」时取 **basename**（`formula`）去和 `brew list` 比
- 行首可以有空白，解析会先去掉再取字段

---

## 加载点：什么靠什么生效

这是最容易出错的地方。往 `.local` 文件里写了值，**但标准文件里没人读它**，
值就永远不生效，而且不报错。

| 你写的文件 | 靠什么被加载 | 在哪 |
|---|---|---|
| `~/.gitconfig.local` | `[include] path = ~/.gitconfig.local` | `src/macos/config/git/gitconfig` |
| `~/.gitignore`（全局忽略） | `[core] excludesfile = ~/.gitignore` | `src/macos/config/git/gitconfig` |
| `~/.gitattributes`（全局属性） | `[core] attributesfile = ~/.gitattributes` | `src/macos/config/git/gitconfig` |
| `~/.zshrc.local` | `[[ -f ~/.zshrc.local ]] && source` | `src/macos/config/zsh/zshrc` |
| `~/.envconfig.local` | `if [[ -f ~/.envconfig.local ]]; then source` | `src/macos/config/env/envconfig` |
| `~/.ssh/config.local` | `Include ~/.ssh/config.local` | `~/.ssh/config`（本机私密文件，不在仓库里） |

反向也要成立：**标准文件里 source 的每个文件，都必须真有一个源**。
`~/.exports` 和 `~/.funcs` 曾经是悬空的（zshrc 在 source，但源不存在），
现在已在 `env/exports`、`shell/funcs` 补上并登记进 `DOTFILE_LINKS`。

**加一个新的 `.local` 落点时，必须同时在标准文件里加加载点。** 只加一半等于没加。

`Include` 一个不存在的文件会被 ssh 静默忽略（已验证），所以这一行永远安全。

> shell 这一侧的完整加载链（`.zshenv → .zprofile → .zshrc` 的顺序、
> 每个文件里 PATH / 环境变量 / 别名 / 函数分别在哪、为什么这么分），
> 见 **[`shell.md`](shell.md)**。README 只讲「谁读谁」，`shell.md` 讲「为什么」。

---

## 改完跑一下自检

```sh
zsh install.zsh check
```

它把仓库里的**交叉引用**全查一遍（只读，不联网，不改东西）：

- `DOTFILE_LINKS` 声明的落点 ←→ `src/macos/config/` 下真的有源（**两个方向都查**）
- 文档里写到的仓库路径 ←→ 文件真的存在
- `install.zsh` 调用的每个脚本 ←→ 存在
- `install.zsh help` 的步骤说明 ←→ `run_base` 实际步骤（**会说会问密码的那一步在不在**）
- `prefs.d/` 的顺序表 ←→ 磁盘上的文件（两个方向）
- PATH 归属：只有 `.zshenv` 能手拼 PATH
- `private.md` 的槽位 ←→ `private-state.zsh` 里的 `SLOTS`
- 所有 `.zsh` / `prefs.d/*.zsh` 的语法
- `private-state.zsh` 产出的 JSON 合法

**为什么要有它**：上面这些都是「改了 A 忘了 B → A 照跑、B 静默失效」的关系。
没有自检时只能靠人肉眼对 —— 于是「我觉得对」就等于对。
加了新东西（落点、偏好、脚本）之后跑一下，有问题会指名道姓说哪一条。

---

## 要改东西，改哪里

| 想改什么 | 改哪 |
|---|---|
| 加一个要链接的配置文件 | `scripts/macos/link-dotfiles.zsh` 的 `DOTFILE_LINKS` 加一行 + 在 `src/macos/config/` 放源 |
| 加一个要装的软件 | `packages/macos/brew-cli.txt`（formulae）或 `packages/macos/brew-cask.txt`（cask） |
| 改 shell 别名 | `src/macos/config/aliases`（一行别名）/ `src/macos/config/shell/funcs`（函数） |
| 改系统偏好 | `scripts/macos/prefs.d/*.zsh` |
| 改开头那几个提问 | `scripts/macos/prompt-once.zsh` |
| 改工具版本 | `src/macos/config/mise/config.toml` |
| 加一个 Homebrew 里**没有**的 zsh 插件 | `scripts/macos/zsh-plugins-install.zsh` 的 `ZSH_PLUGINS` + `src/macos/config/zsh/zshrc` 里的 source 行 |
| 加一个机器专属的东西 | 私有源，**不是这里**（接口见 `private.md`） |
| **改完任何东西** | 跑 `zsh install.zsh check`（见下面「改完跑一下自检」） |

判断标准：**两台机器应该一样的 → 属于这个仓库；只有一台该有的 → 属于私有源。**

---

## 落点声明：写在哪

落点声明**就在 `scripts/macos/link-dotfiles.zsh` 里**（`DOTFILE_LINKS` 数组）。
每行两个字段，用 `|` 分隔：

```zsh
DOTFILE_LINKS=(
  'zsh/zshrc|.zshrc'
  'ghostty|.config/ghostty'
)
```

- 左边是 `src/macos/config/` 下的相对路径，右边是 `$HOME` 下的相对路径
- 没有平台回退 —— 这个仓库只有 macOS，源都在 `src/macos/config/` 下，直接写全路径

**加一条落点只改这里**，然后确认 `src/macos/config/` 下真的有对应的源。

替换已有文件时**不再直接删除**，而是移到 `~/.dotfiles-backup/<时间戳>/`，
路径会打印出来。想改备份位置就设 `DOTFILES_BACKUP_DIR`。

---

## 和 macview 的关系

[macview](https://github.com/mobailabs/macview) 是这套标准的图形界面：
**看见差异 → 一键对齐**。

它读的就是这个仓库 —— `packages/*.txt`、`scripts/macos/prefs.d/*.zsh`
都是它的输入。所以这里的东西越规整，macview 能看见的就越多。

**私有源**这一块，两边靠 [`private.md`](private.md) 定义的状态契约交接：
macview 读 `~/.config/dotfiles/private-state.json`，就能区分「没有私有源」
（正常）和「有但没装好」（要修）。

这个文件由 `scripts/macos/private-state.zsh` 产出，两个调用方：

- `install.zsh` 的 prompt-once 步骤跑 `--write`（每次安装后刷新）
- macview 需要时可跑 `--stdout`（只读，不落盘）

**dotfiles 侧已实现；macview 侧的读取还没做**（见 `private.md` 的
「macview 这一侧要怎么用」）。

落点清单是**两边各维护一份**：`link-dotfiles.zsh` 的 `DOTFILE_LINKS` 是命令行版
依据，macview 自己另存一份。两边可能漂移，但漂移**可检测** —— 仓库里有源、
`$HOME` 里没链接，对账时会报出来，不是静默失效。

两者不冲突：`install.zsh` 是命令行版本，macview 是图形版本，改的是同一批文件。

---

## 为什么删掉 Linux

以前这个仓库同时管 macOS 和 Ubuntu/Debian 服务器（`install.sh` 走 apt 引导，
`scripts/linux/`、`packages/linux/`、`src/linux/` 各有一份对应物）。

删掉的理由：**这个仓库只有一个使用者，而他只在这台 macOS 上用。** Linux 那条路没有真实
需求支撑，却要在每个脚本里留一份分支、在每个配置文件里留一份平台判断。留着只会让
「标准」有两个版本，而且是其中一个从没被验证过的版本。

现在 `uname -s` 不是 Darwin，安装脚本会直接报错退出 —— 不会静默走到一半。

---

## 之前需要手动、现在已自动

`~/.ssh/config` 是本机的私密文件（由 git-secret 管），不在这个仓库里。
它需要一行 `Include ~/.ssh/config.local`，`~/.ssh/config.local` 才会生效。

**这一行现在由 `prompt-once.zsh` 自动加**（插到最上面、幂等、保留原权限）。
以前是 README 里的一步手动操作 —— 忘了就静默不生效，是最隐蔽的坑之一。

同理，`~/.gitconfig.local`（git 身份）现在也会在 `install.zsh` 开头问你并写好，
不再需要事后手建。

```sshconfig
Include ~/.ssh/config.local
```

`Include` 一个不存在的文件会被 ssh 静默忽略（已验证），所以这一行永远安全。

---

## 全自动：哪些能自动、哪些不能

| 项 | 自动 | 说明 |
|---|---|---|
| brew / 所有 CLI / cask | ✅ | `NONINTERACTIVE=1`；少数 cask 自身仍可能要密码 |
| 19 个配置落点 | ✅ | |
| oh-my-zsh / zsh 插件 / tmux 插件 / mise | ✅ | |
| macOS 偏好 | ⚠️ | 需要 sudo；开头授权后**可能**还要再输一次（见下） |
| git 身份 | ✅ | 开头问一次，或用 `--name/--email`、环境变量 |
| ssh `Include` | ✅ | 自动插入 |
| **sudo 密码** | ❌ | 需要时**一定会等你输入**（不会卡死）；失效就再输一次 |
| **私有源 / token** | ❌ | 不在本仓库，需用户自备（可以是私有 git 仓库 / 目录，将来可接 macview 云服务；见 `private.md`）
