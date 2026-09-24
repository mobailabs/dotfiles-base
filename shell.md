# shell 说明

这个仓库里所有和 shell 有关的东西 —— **启动链、环境变量、别名、函数、PATH** ——
都在 `src/macos/config/` 下的这几个文件里：

```
src/macos/config/
├── zsh/
│   ├── zshenv               → ~/.zshenv      （所有 shell 都加载）
│   ├── zprofile             → ~/.zprofile    （登录 shell）
│   ├── zshrc                → ~/.zshrc       （交互 shell）
│   ├── oh-my-zsh.sh         → ~/.oh-my-zsh.sh
│   ├── ohmyzsh.plugins.zsh  → ~/.config/dotfiles/ohmyzsh.plugins.zsh
│   └── os.zsh               → ~/.config/dotfiles/os.zsh
├── env/
│   ├── envconfig            → ~/.envconfig   （环境配置 + Python 别名）
│   └── exports              → ~/.exports     （导出变量）
├── aliases                  → ~/.aliases     （命令别名）
└── shell/
    ├── funcs                → ~/.funcs       （自定义函数）
    └── bash_profile         → ~/.bash_profile（bash 兼容 + 切 zsh）
```

另外还有一个**间接**参与 shell 的文件（不在上面的树里，因为它属于 tmux 配置）：

```
src/macos/config/tmux/config/aliases.sh  →  ~/.config/tmux/aliases.sh
```

它由 `~/.zshrc` 末尾 source，内容是 tmux 相关的短命令与函数
（`t`/`ta`/`tn`/`tk` 这类别名，以及 `tcd`、`tal` 等智能会话函数）。
之所以单独放，是因为它和 `tmux.conf` 同属一套 tmux 配置，跟着 tmux 目录一起被链接。
注意它是 `#!/bin/bash` —— 内容只用 POSIX 兼容语法，zsh 里 source 也没问题。

想改 shell 行为，改这里的源文件。**不要**直接改 `~/.zshrc` 之类的 —— 那是软链接。

---

## 启动链：谁先谁后

zsh 的加载顺序是固定的（`zshenv` → `zprofile` → `zshrc`），本仓库按这个顺序分工：

```
.zshenv     所有 shell（交互/非交互/登录/非登录）
   │        ├─ EDITOR / VISUAL / LC_ALL / LANG
   │        ├─ PATH 组装
   │        └─ Homebrew 探测（只设路径，不跑 brew 命令）
   ▼
.zprofile   仅登录 shell
   │        └─ eval `brew shellenv`（补全 / man path 的 shell 集成）
   ▼
.zshrc      仅交互 shell
            ├─ zsh-completions 加进 fpath —— 必须在 oh-my-zsh 之前
            ├─ source ~/.oh-my-zsh.sh
            ├─ ~/.exports   → 导出变量
            ├─ ~/.aliases   → 命令别名
            ├─ ~/.funcs     → 自定义函数
            ├─ ~/.envconfig → 环境配置
            ├─ ~/.config/dotfiles/os.zsh
            ├─ ~/.zshrc.local → 本机私有（不存在就跳过）
            └─ ~/.config/tmux/aliases.sh → tmux 相关别名
```

### 三条硬规矩

1. **`.zshenv` 里不许有任何输出。**
   它在**非交互** shell（脚本、命令替换、`git commit` 的编辑器调用）里也会加载。
   多打一行字就会污染 `$(...)` 的结果。要输出只能进 `.zshrc`。

2. **交互 shell 的 load 点必须写成 `[[ -f 文件 ]] && source 文件`。**
   不能裸 `source` —— 文件不存在时它会报错，在非交互场景可能让调用方出错。
   反过来，**文件里也不要写 `return` 去“提前结束”** —— 当它被 `source`
   而不是当顶层 zshrc 执行时，`return` 会终止**调用者**的加载，后面全丢且静默。

3. **Homebrew 环境探测只有一份（`.zshenv`）。**
   别的文件别再写 `/opt/homebrew` / `/usr/local` 判断来决定 `HOMEBREW_PREFIX` 或 PATH。
   加一台不同路径的机器本来要改 4 处、漏一处就静默失效 —— 现在收敛到：
   - 交互 shell → `.zshenv`
   - 非交互脚本 / 子进程 → `scripts/macos/brew-env.zsh`
   - 唯一例外 → `scripts/macos/brew-bootstrap.zsh`（要**装** brew，鸡生蛋）

   > ⚠️ `.zshenv` 里的探测门开在「brew 的 bin 在不在 PATH 里」，**不是**
   > 「`HOMEBREW_PREFIX` 设没设」。后者会让「环境里有变量但没有 brew PATH」
   > 的情况整段跳过 —— brew 命令找不到、`MANPATH` 不设，且不报错。
   > 改这一段时别把门开回去。

   > 有两个**看起来像例外、实际不是**的地方，别误改：
   > - `tmux.conf` 里的 `default-shell` 判断：它不决定 PATH，只是按优先级挑一个
   >   存在的 `zsh`（brew 的优先，找不到退回系统 zsh）。找不到也不会静默失效。
   > - `gitconfig` 的注释：只是说明「不写死 gpg 路径，靠 PATH 找」，没有判断逻辑。

---

## 环境变量

| 变量 | 值 | 在哪 |
|---|---|---|
| `EDITOR` / `VISUAL` | `nvim` | `zshenv` |
| `LC_ALL` / `LANG` | `en_US.UTF-8` | `zshenv` |
| `MANPAGER` | `less -X` | `zshenv` |
| `TERM` | **不设**（只在为空时兜底 `xterm-256color`） | `env/envconfig` |
| `HOMEBREW_*` | 按探测结果 | `zshenv` |
| `MANPATH` / `INFOPATH` | 把 brew 的 man / info 页加进去 | `zshenv`（仅在探测到 brew 时） |

**`TERM` 为什么不写死**：终端自己会设（Ghostty 设 `xterm-ghostty`，iTerm 设
`xterm-256color`）。写死会盖掉终端的专有 terminfo，导致 tmux 的
`terminal-overrides ",ghostty:Tc"` 永远匹配不上。只在 `TERM` 完全为空
（cron/daemon 那种极端上下文）时才兜底。

`HOMEBREW_REPOSITORY` 有个坑：Apple Silicon 上等于 prefix（`/opt/homebrew`），
Intel 上是 prefix 下的 `Homebrew`（`/usr/local/Homebrew`）。所以按 `uname -m` 分辨。

---

## PATH 的组装

**PATH 只有一个归属：`.zshenv`。** 其它文件不再各自手拼 PATH。

在 `.zshenv` 里，顺序是刻意排的：

```
最前面（_pre，越靠前优先级越高）
  ~/.bin  ·  ~/.local/bin          ← 自己装的 CLI 要先于系统的
紧接着（brew 装好后）
  $HOMEBREW_PREFIX/bin  ·  sbin    ← 用 path=(...) 前置（不是 append）
中间
  系统默认（/usr/bin 等）
末尾（append）
  ~/go/bin  ~/.go/bin  ~/.cargo/bin  ~/.config/tmux/bin  ~/.bun/bin
  ~/.npm-global/bin  ~/.lmstudio/bin  ~/.cache/lm-studio/bin
```

- **brew 的 bin 是前置的**，不是「中间」——`.zshenv` 里写的是
  `path=("$HOMEBREW_PREFIX/bin" $path)`。因为它在 `_pre` 之后执行，
  最终优先级是：`_pre` 的两项 > brew > 系统默认 > 末尾追加项。
  这样 `brew install` 的东西会盖过系统自带的同名命令（预期行为）。
- **brew 探测的门开在「brew 的 bin 在不在 PATH 里」，不是「`HOMEBREW_PREFIX` 设没设」。**
  这两个不等价：环境里可能有个 `HOMEBREW_PREFIX`（GUI 启动、继承来的）而 PATH
  里没有 brew。旧写法用后者当门，后果是整段被跳过 → brew 命令找不到、
  `MANPATH`/`CELLAR` 全不设，且不报错。现在先定 prefix、再**逐项补齐缺的**。
- **末尾追加项全在 `.zshenv`**。以前 `.npm-global/bin`、`.lmstudio/bin` 在
  `.zshrc`，`.cache/lm-studio/bin` 只在 `.bash_profile` —— 同一个程序的位置
  散在两套逻辑里（一套 `path+=` + `typeset -U` 去重，一套手拼 `$PATH:...`
  不去重），加一处必漏一处。现在收进 `.zshenv`：所有 shell 都加载它，
  `bash_profile` 弹进 zsh 后也一定拿得到。
- **每个目录都带存在性判断**。不存在的目录进 PATH 不报错，但会让你以为那里有东西
  （历史上就踩过：`$HOME/.dotfiles/bin` 指向一个从不存在的目录）。
- 用 `typeset -U path` 去重。
- `_pre` 是先把要前置的攒好、再整体前置 —— 直接 `path+=(...)` 追加到末尾
  会把优先级降到最低，你自己装的 CLI 会被系统同名命令遮住。
- 私有源的 `bin` 不在这里处理，它在 `~/.zshrc.local` 里（那才是它的归属）。

> 自检查这一条（`check_path_ownership`）：`zshrc` / `bash_profile` 里再出现
> 手拼的 `export PATH=...$PATH...` 就报错。**加 PATH 条目只改 `.zshenv`。**

---

## 别名（`~/.aliases`）

| 组 | 别名 |
|---|---|
| 核心 | `c`=clear · `h`=history |
| 安全 | `rm`/`cp`/`mv` 加 `-i` · `grep --color=auto` |
| 现代替代 | `ls`=`eza` · `ll`=eza 长格式 · `lt`=eza 树 · `cat`=`bat`（**有才生效**） |
| Git | `g` `gs` `ga` `gaa` `gc` `gco` `gp` `gl` `gd` `glo` |
| 导航 | `..` `...` `....` · `~` · `-` |
| Docker | `d` · `dc` |
| 其它 | `m`=mise · `v`=nvim · `hp`=python http server |
| Python（在 `envconfig`） | `pyv` `pya` `pyd` `pyi` |

`ls`/`cat` 这类用了条件判断：只有在 `eza` / `bat` 存在时才覆盖，否则保留原命令
（`ls`/`cat` 变成**没有别名**，也就是直接用系统命令 —— 效果上等于「保留原命令」）。
注意三种情况并不一样：

| 命令 | eza/bat 存在 | 不存在 |
|---|---|---|
| `ls` | `eza` | 无别名 → 系统 `ls` |
| `cat` | `bat` | 无别名 → 系统 `cat` |
| `ll` | `eza -l --icons --git -a` | `ls -lah`（有兜底） |
| `lt` | `eza --tree --level=2` | **没有这个别名**（敲 `lt` 会 `command not found`） |

所以 **brew 还没装时不会一进来就 `command not found`** —— 除了 `lt`，
它只在装了 `eza` 之后才存在。

---

## 函数（`~/.funcs`）

目前是**空骨架**（只有注释示例），因为别名够用。需要带参数、分支、循环的
复杂逻辑时写这里，而不是别名。

分工：`aliases` = 一行命令的别名；`funcs` = 真函数。

> 注意：「函数都写在 `.funcs`」是**约定**，不是现状 —— 仓库里目前真正定义函数的
> 只有 `tmux/config/aliases.sh`（`tcd`、`tal` 等会话函数），因为它们和 tmux
> 配置强耦合。`~/.config/dotfiles/os.zsh` 同样是**刻意的空骨架**（只加载、
> 没内容），用途见下。

---

## macOS 专属的扩展点（两个空文件）

`~/.config/dotfiles/os.zsh` 和 `~/.config/dotfiles/ohmyzsh.plugins.zsh` 内容都很少，
但**不是没写完** —— 它们是刻意留出来的「只在这台 Mac 上生效」的隔离区：

| 文件 | 作用 | 为什么单独放 |
|---|---|---|
| `os.zsh` | 放 macOS 专属的 shell 片段 | 不污染 `~/.zshrc`；需要「只在 Mac 上做某件事」时写这里 |
| `ohmyzsh.plugins.zsh` | 追加 macOS 专属的 OmZ 插件（当前加 `macos`） | 插件列表主体在 `oh-my-zsh.sh`，平台差异外置 |

两者都由 `~/.zshrc` / `~/.oh-my-zsh.sh` 条件 source。

---

## Oh My Zsh

| 项 | 值 | 位置 |
|---|---|---|
| 主题 | `gnzh`（两行、浅灰前景，配深色终端） | `zsh/oh-my-zsh.sh` |
| 大小写补全 | `CASE_SENSITIVE="false"` | 同上 |
| 插件 | `git` `npm` `node` `rust` `golang` `brew` `colored-man-pages` `command-not-found` + `macos` | 同上 |

- **`z` 插件故意不启用**：`zshrc` 里已经 `eval "$(zoxide init zsh)"`，
  两个都注册 `z` 函数会互相覆盖，且各维护一份数据。统一用 zoxide。
- `macos` 插件在 `ohmyzsh.plugins.zsh` 里 `plugins+=(macos)` 追加。
- 补全目录（`zsh-completions`）**必须在 `oh-my-zsh` 之前**加进 `fpath`，
  否则 OmZ 的 `compinit` 跑的时候看不到它 —— 见 `zshrc` 顶部。
- **不要再手动跑 `compinit`**，OmZ 已经跑过了。

---

## bash 兼容（`~/.bash_profile`）

- 只做**一件事**：交互式且当前不是 zsh 且 zsh 存在 → `exec zsh -l` 切到 zsh。
- 它以前还管 LM Studio 的 PATH，那部分已收进 `~/.zshenv`（PATH 唯一归属）。
  在那里重复加没有好处，只会造成两套逻辑（一套去重一套不去重）不同步；
  而且 `exec zsh -l` 之后 `.zshenv` 一定会加载，本来也拿得到。
- 不动 PATH 还有个好处：万一 zsh 不存在或 `exec` 失败，这个文件不会在
  bash 里留下半套环境。
- 这文件主要是给「某些程序硬调 bash」兜底用。

> 自检查这一条（`check_path_ownership`）：`.bash_profile` 里再出现手拼的
> `export PATH=...$PATH...` 就报错。

---

## 本机私有配置（不进仓库）

| 文件 | 用途 | 加载点 | 谁创建 |
|---|---|---|---|
| `~/.gitconfig.local` | 机器专属 / 含 token | `gitconfig` 的 `[include]` | `install.zsh` 开头问一次（或 `--name/--email`） |
| `~/.zshrc.local` | 机器专属 / 含 token | `zshrc` 末尾 | 你自己 / 私有源 |
| `~/.envconfig.local` | 私有环境变量 | `env/envconfig` | 你自己 / 私有源 |

`~/.gitconfig.local` 在 `install.zsh` 跑的时候会被自动写好。给
`install.zsh` 传 `--name/--email`（或 `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`
环境变量）就完全不问。细节见 `README.md` 的「新机器：一条命令」一节。

**加私有文件时，必须同时在标准文件里加加载点。** 只加一半等于没加 ——
文件会被创建、但没人读，而且不报错。这是这个仓库最容易踩的坑，
完整的加载点清单见根 `README.md` 的「加载点：什么靠什么生效」一节。

---

## 自检

```sh
zsh -n src/macos/config/zsh/zshenv    # 语法
zsh -i -c 'echo $EDITOR'              # 交互链
zsh -c 'echo READY'                   # 非交互应干净（只有 READY）
```

改完 `.zshenv` / `.zshrc` 后，新开一个终端或 `exec zsh` 验证，
别在当前 shell 里 `source .zshrc` —— 重复加载 `compinit`、插件会出怪问题。
