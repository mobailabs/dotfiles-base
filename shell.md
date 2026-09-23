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
            └─ ~/.zshrc.local → 本机私有（不存在就跳过）
```

### 三条硬规矩

1. **`.zshenv` 里不许有任何输出。**
   它在**非交互** shell（脚本、命令替换、`git commit` 的编辑器调用）里也会加载。
   多打一行字就会污染 `$(...)` 的结果。要输出只能进 `.zshrc`。

2. **交互 shell 的 load 点必须写成 `[[ -f 文件 ]] && source 文件`。**
   不能裸 `source` —— 文件不存在时它会报错，在非交互场景可能让调用方出错。
   反过来，**文件里也不要写 `return` 去“提前结束”** —— 当它被 `source`
   而不是当顶层 zshrc 执行时，`return` 会终止**调用者**的加载，后面全丢且静默。

3. **Homebrew 探测只有一份（`.zshenv`）。**
   别的文件别再写 `/opt/homebrew` / `/usr/local` 判断。加一台不同路径的机器
   本来要改 4 处、漏一处就静默失效 —— 现在收敛到：
   - 交互 shell → `.zshenv`
   - 非交互脚本 / 子进程 → `scripts/common/brew-env.zsh`
   - 唯一例外 → `scripts/macos/brew-bootstrap.zsh`（要**装** brew，鸡生蛋）

---

## 环境变量

| 变量 | 值 | 在哪 |
|---|---|---|
| `EDITOR` / `VISUAL` | `nvim` | `zshenv` |
| `LC_ALL` / `LANG` | `en_US.UTF-8` | `zshenv` |
| `MANPAGER` | `less -X` | `zshenv` |
| `TERM` | **不设**（只在为空时兜底 `xterm-256color`） | `env/envconfig` |
| `HOMEBREW_*` | 按探测结果 | `zshenv` |

**`TERM` 为什么不写死**：终端自己会设（Ghostty 设 `xterm-ghostty`，iTerm 设
`xterm-256color`）。写死会盖掉终端的专有 terminfo，导致 tmux 的
`terminal-overrides ",ghostty:Tc"` 永远匹配不上。只在 `TERM` 完全为空
（cron/daemon 那种极端上下文）时才兜底。

`HOMEBREW_REPOSITORY` 有个坑：Apple Silicon 上等于 prefix（`/opt/homebrew`），
Intel 上是 prefix 下的 `Homebrew`（`/usr/local/Homebrew`）。所以按 `uname -m` 分辨。

---

## PATH 的组装

在 `.zshenv` 里，顺序是刻意排的：

```
最前面（_pre，越靠前优先级越高）
  ~/.bin  ·  ~/.local/bin          ← 自己装的 CLI 要先于系统的
中间
  $HOMEBREW_PREFIX/bin  ·  sbin  ·  系统默认
末尾
  ~/go/bin  ~/.go/bin  ~/.cargo/bin  ~/.config/tmux/bin  ~/.bun/bin
```

- **每个目录都带存在性判断**。不存在的目录进 PATH 不报错，但会让你以为那里有东西
  （历史上就踩过：`$HOME/.dotfiles/bin` 指向一个从不存在的目录）。
- 用 `typeset -U path` 去重。
- `_pre` 是先把要前置的攒好、再整体前置 —— 直接 `path+=(...)` 追加到末尾
  会把优先级降到最低，你自己装的 CLI 会被系统同名命令遮住。
- 私有仓库的 `bin` 不在这里处理，它在 `~/.zshrc.local` 里（那才是它的归属）。

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
（`ll` 会退回 `ls -lah`）。所以 **brew 还没装时不会一进来就 `command not found`**。

---

## 函数（`~/.funcs`）

目前是**空骨架**（只有注释示例），因为别名够用。需要带参数、分支、循环的
复杂逻辑时写这里，而不是别名。

分工：`aliases` = 一行命令的别名；`funcs` = 真函数。

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

- 两处 LM Studio CLI 路径（`.cache/lm-studio/bin` 和 `.lmstudio/bin`），
  哪个存在加哪个。
- 交互式且当前不是 zsh 且 zsh 存在 → `exec zsh -l` 切到 zsh。
- 这文件主要是给「某些程序硬调 bash」兜底用。

---

## 本机私有配置（不进仓库）

| 文件 | 用途 | 加载点 |
|---|---|---|
| `~/.zshrc.local` | 机器专属 / 含 token | `zshrc` 末尾 |
| `~/.envconfig.local` | 私有环境变量 | `env/envconfig` |

**加私有文件时，必须同时在标准文件里加加载点。** 只加一半等于没加 ——
文件会被创建、但没人读，而且不报错。这是这个仓库最容易踩的坑，
完整的加载点清单见根 `README.md` 的「加载点」一节。

---

## 自检

```sh
zsh -n src/macos/config/zsh/zshenv    # 语法
zsh -i -c 'echo $EDITOR'              # 交互链
zsh -c 'echo READY'                   # 非交互应干净（只有 READY）
```

改完 `.zshenv` / `.zshrc` 后，新开一个终端或 `exec zsh` 验证，
别在当前 shell 里 `source .zshrc` —— 重复加载 `compinit`、插件会出怪问题。
