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
不进这个仓库 —— 它们属于**私有仓库**（单独一个 git 仓库，不在本仓库内），
通过三个 `.local` 落点被这里的加载点读进来。

---

## 新机器：两步

```sh
# 1. 克隆（路径随意，脚本按自身位置定位，不依赖固定目录）
git clone <this-repo> ~/dotfiles
cd ~/dotfiles

# 2. 装
zsh install.zsh              # 全部：check → brew → 插件 → 链接 → mise → 系统偏好
```

机器专属的东西（Git 身份 / SSH / token）另外放在一个私有仓库里，通过三个
`.local` 落点被加载（见下面「加载点」）。**没有这个私有仓库也不会报错** ——
加载点全是条件加载，缺了就静默跳过。所以「私有仓库在不在」是 macview 要提醒你的事。

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
├── packages/                ← 要装什么
│   ├── common/brew-cli.txt
│   └── macos/{brew-cli,brew-cask}.txt
├── scripts/
│   ├── common/              ← brew / 插件 / 链接 / mise / 对账
│   │   └── brew-env.zsh     ← 把 homebrew 环境补进当前进程（被 source）
│   └── macos/check.zsh, brew-install.zsh, prefs.d/  ← 系统偏好，一个文件一个主题
├── src/macos/config/        ← 配置源（只有 macOS，没有平台分层）
```

`src/` 里的东西**不直接生效** —— 它们是源，被链接到 `$HOME` 才生效。

---

## 包清单的格式（**别改**）

`packages/*/brew-*.txt` 的格式由 `scripts/common/brew-packages-install.zsh`
（装）和 `scripts/common/brew-audit.zsh`（对账）共同解析。规则：

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

---

## 要改东西，改哪里

| 想改什么 | 改哪 |
|---|---|
| 加一个要链接的配置文件 | `scripts/common/link-dotfiles.zsh` 的 `DOTFILE_LINKS` 加一行 + 在 `src/macos/config/` 放源 |
| 加一个要装的软件 | `packages/{common,macos}/brew-*.txt` |
| 改 shell 别名 | `src/macos/config/aliases`（一行别名）/ `src/macos/config/shell/funcs`（函数） |
| 改系统偏好 | `scripts/macos/prefs.d/*.zsh` |
| 改工具版本 | `src/macos/config/mise/config.toml` |
| 加一个 Homebrew 里**没有**的 zsh 插件 | `scripts/common/zsh-plugins-install.zsh` 的 `ZSH_PLUGINS` + `src/macos/config/zsh/zshrc` 里的 source 行 |
| 加一个机器专属的东西 | 私有仓库，**不是这里** |

判断标准：**两台机器应该一样的 → 属于这个仓库；只有一台该有的 → 属于私有仓库。**

---

## 落点声明：写在哪

落点声明**就在 `scripts/common/link-dotfiles.zsh` 里**（`DOTFILE_LINKS` 数组）。
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

## 需要手动做的一件事

`~/.ssh/config` 是本机的私密文件（由 git-secret 管），不在这个仓库里。
它需要**手动加一行**，`~/.ssh/config.local` 才会生效：

```sshconfig
Include ~/.ssh/config.local
```

放在文件最上面。`Include` 一个不存在的文件会被 ssh 静默忽略（已验证），所以这行永远安全。
