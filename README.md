# dotfiles-base

新机器的起点。macOS + Ubuntu/Debian（Linuxbrew）/ Zsh / tmux / Neovim / mise。

一次 `zsh install.zsh` 之后，这台机器就按同一套标准被配置好：软件装齐、配置链接到位、
系统偏好应用、开发环境版本对齐。

---

## 这是什么，不是什么

**是**：一台新机器从零到可用的起点，也是「标准」的唯一存放处。
配置改在这里，机器上的改动才有归宿。

**不是**：某台机器的快照。机器专属的东西（Git 身份、SSH Host、token、公司内网变量）
不进这个仓库 —— 它们属于私有仓库，通过 `private-template/` 起。

---

## 新机器：三步

```sh
# 1. 克隆（路径随意，脚本按自身位置定位，不依赖固定目录）
git clone <this-repo> ~/dotfiles-base
cd ~/dotfiles-base

# 2. 装
zsh install.zsh              # 全部：check → brew → 插件 → 链接 → mise → 系统偏好

# 3. 起私有仓库（放身份信息 / SSH / token）
cp -R private-template ~/private-dotfiles
cd ~/private-dotfiles && git init && zsh install.zsh
```

`install.zsh` 还可以单独跑某一步：

| 命令 | 作用 |
|---|---|
| `zsh install.zsh` | 全套（`base`） |
| `zsh install.zsh link` | 只重新链接配置（读 `link.map`） |
| `zsh install.zsh prefs` | 只重新应用 macOS 偏好（幂等，可随时重跑） |

> Linux 服务器用 `sh install.sh` 走 apt 引导，再进 `install.zsh`。

---

## 目录结构

```text
.
├── link.map                 ← 落点的唯一声明（改这里，不要改脚本）
├── install.zsh              ← macOS 入口
├── install.sh               ← Linux 引导
├── packages/                ← 要装什么
│   ├── common/brew-cli.txt
│   └── macos/{brew-cli,brew-cask}.txt
├── scripts/
│   ├── common/              ← 跨平台：check / brew / 插件 / 链接 / mise
│   └── macos/prefs.d/       ← 系统偏好，一个文件一个主题
├── src/
│   ├── common/config/       ← 所有平台共用的配置源
│   └── {macos,linux}/config/← 平台覆盖（同名文件优先于 common）
└── private-template/        ← 起私有仓库用的脚手架
```

`src/` 里的东西**不直接生效** —— 它们是源，被链接到 `$HOME` 才生效。

---

## 加载点：什么靠什么生效

这是最容易出错的地方。往 `.local` 文件里写了值，**但标准文件里没人读它**，
值就永远不生效，而且不报错。

| 你写的文件 | 靠什么被加载 | 在哪 |
|---|---|---|
| `~/.gitconfig.local` | `[include] path = ~/.gitconfig.local` | `src/common/config/git/gitconfig` |
| `~/.zshrc.local` | `[[ -f ~/.zshrc.local ]] && source` | `src/common/config/zsh/zshrc` |
| `~/.envconfig.local` | `if [[ -f ~/.envconfig.local ]]; then source` | `src/common/config/env/envconfig` |
| `~/.ssh/config.local` | `Include ~/.ssh/config.local` | `private-template/src/common/config/ssh/config` |

**加一个新的 `.local` 落点时，必须同时在标准文件里加加载点。** 只加一半等于没加。

`Include` 一个不存在的文件会被 ssh 静默忽略（已验证），所以这一行永远安全。

---

## 要改东西，改哪里

| 想改什么 | 改哪 |
|---|---|
| 加一个要链接的配置文件 | `link.map` 加一行 + 在 `src/**/config/` 放源 |
| 加一个要装的软件 | `packages/{common,macos}/brew-*.txt` |
| 改 shell 别名 | `src/common/config/aliases` |
| 改系统偏好 | `scripts/macos/prefs.d/*.zsh` |
| 改工具版本 | `src/common/config/mise/config.toml` |
| 加一个机器专属的东西 | 私有仓库，**不是这里** |

判断标准：**两台机器应该一样的 → 属于这个仓库；只有一台该有的 → 属于私有仓库。**

---

## link.map：落点的唯一声明

```text
# <仓库内相对路径>  <$HOME 内相对路径>  [平台]
zsh/zshrc         .zshrc
ghostty           .config/ghostty     macos
```

- 平台列留空 = 所有平台；写 `macos` / `linux` 则只在那个平台链接
- 源按 `src/{平台}/config/` → `src/common/config/` 查找（平台覆盖通用）
- 安装脚本读它，macview 也读它

**改落点只改这里。** 以前这份映射在安装脚本里硬编码过一份，结果和检查脚本对不上。

替换已有文件时**不再直接删除**，而是移到 `~/.dotfiles-backup/<时间戳>/`，
路径会打印出来。想改备份位置就设 `DOTFILES_BACKUP_DIR`。

---

## 和 macview 的关系

[macview](https://github.com/zhaopengme/macview) 是这套标准的图形界面：
**看见差异 → 一键对齐 → 可撤回**。

它读的就是这个仓库 —— `link.map`、`packages/*.txt`、`scripts/macos/prefs.d/*.zsh`
都是它的输入。所以这里的东西越规整，macview 能看见的就越多。

两者不冲突：`install.zsh` 是命令行版本，macview 是图形版本，改的是同一批文件。

---

## 需要手动做的一件事

`~/.ssh/config` 是本机的私密文件（由 git-secret 管），不在这个仓库里。
它需要**手动加一行**，`~/.ssh/config.local` 才会生效：

```sshconfig
Include ~/.ssh/config.local
```

放在文件最上面。模板 `private-template/src/common/config/ssh/config` 里已经有这行了，
但已经装好的机器要自己补。
