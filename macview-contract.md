# macview 接口契约

> 本文是**接口规格**,不是使用说明。它规定 macview(那个 GUI)和本仓库之间
> 怎么交接:**macview 调什么、读什么、能改什么**,以及为此本仓库要提供什么。
>
> 状态:**草案(v1 未冻结)。** 格式定下来之后,仓库侧和 macview 侧各自实现;
> 冻结前两边都别把它当稳定接口。
>
> 配套文档:macview 侧的设计在它自己的仓库
> (`macview/docs/design/2026-09-24-重新设计-脚本控制器.md`)。

---

## 为什么要有这份契约

macview 的新定位是**脚本控制器**:它自己**不判断差异、不改磁盘** ——
它只显示状态、按按钮调脚本、展示结果。真正干活的是本仓库的脚本。

这个定位有一个直接后果:

> **macview 需要知道「这台机器现在什么样」,而这件事只有本仓库的脚本知道。**

旧版 macview 的做法是**自己再实现一遍**(解析 `link.map`、复刻 zsh 的 `read`
语义、复刻 `defaults` 的 `sed` 怪癖)。那是错的:两份实现必然漂移,
而漂移不报错 —— 正好是这个项目最想消灭的一类问题
(见 `README.md` 开头那段)。

所以改成:**本仓库提供「只读查询」的出口,输出稳定的 JSON;macview 只读它。**

---

## 设计原则

1. **判断和执行都在本仓库。** macview 不做任何「哪一项不一致」的判断 ——
   它读 JSON。查询脚本说「drift」,它就显示 drift。

2. **查询脚本只读。** 所有 `--json` 出口**绝不写磁盘、绝不改 $HOME**。
   它们和 `brew-audit.zsh`、`private-state.zsh --stdout` 是同一类东西。
   (这条是从 `private-state.zsh:19` 抄的,那条注释很硬:「不装东西、
   不改 $HOME 里的任何配置」。)

3. **JSON 受自检保护。** 每个查询脚本的产出都由 `selfcheck.zsh` 校验
   「是合法 JSON + 必填字段在」(照 `check_private_json` 的做法)。
   格式漂了会**报错**,不是静默。

4. **没有「差不多」的字段。** 能表达「问不出来」就必须表达 ——
   不许把「没查成」写成「没有」。这是全仓库的通则
   (见 `private.md` 的四态、`PrereqState` 的三态)。

5. **能不改脚本就不改。** 现有脚本已经能用的(`private-state.zsh --stdout`),
   macview 直接读,不为它新造格式。

---

## 一、macview 会调的命令(执行侧)

这些是**会改动磁盘**的入口。macview 按按钮 = 调它们。

| macview 的动作 | 调的命令 | 要提权? | 退出码 | 现状 |
|---|---|---|---|---|
| 一键配置(全套) | `zsh install.zsh` | **是** | 0 / 1 | ✅ 已有 |
| 只链接配置 | `zsh install.zsh link` | 否 | 0 | ✅ 已有 |
| 只应用偏好 | `zsh install.zsh prefs` | **是** | 0 / 1 | ✅ 已有 |
| 装软件(brew+cask) | `zsh scripts/macos/brew-install.zsh` | **是** | 0 / 1 | ✅ 已有 |
| 对账(只读) | `zsh install.zsh audit` | 否 | **0 / 1** | ✅ 已有 |
| 仓库自检(只读) | `zsh install.zsh check` | 否 | 0 / 1 | ✅ 已有 |
| 装开发环境 | `zsh scripts/macos/mise-setup.zsh` | 否 | 0 / 1 | ✅ 已有 |
| 链私有 overlay | **不做** —— 见 §3.4（走 `install.zsh base`） | 否 | — | ⛔ 已定不做 |

**契约**:上表 ✅ 的命令**以后不改名、不改语义**。
改了 macview 会报「脚本不在」(启动检测),不会静默。

### 1.1 「要提权」列 —— 这是执行侧最容易做错的一件事

**这一节是实测的,不是推演的。** 原来的稿子写「macview 给子进程开 PTY」——
实测证明**那条路在 Swift 里走不通**,所以整节重写了。过程见 §1.1.4。

#### 1.1.1 分成两件互不相干的事

旧稿把「没有终端」当成一个笼统的问题,其实它是**两个**:

| 问题 | 谁需要 | 怎么解 |
|---|---|---|
| **A. sudo 要密码** | 装 Homebrew、`prefs` 里的 Touch ID 步骤 | `SUDO_ASKPASS`(原生密码框)——**不需要终端** |
| **B. 脚本自己要 `read`** | `prompt-once.zsh` 问 git 身份 | **不走 `read`** —— 用 `--name`/`--email` 预填 |

分开看就清楚了:**两件事都不需要 PTY。**

#### 1.1.2 A:sudo 用 `SUDO_ASKPASS`,不是 PTY

`sudo` 拿密码有三条路:读控制终端(`/dev/tty`)、读 stdin(`-S`)、
调 `SUDO_ASKPASS` 指向的程序(`-A`)。图形界面没有终端,所以走第三条:
一个弹 **macOS 原生密码框**的助手(`osascript display dialog … with hidden answer`)。

⚠️ **一个实测出来的硬事实:没有 tty 时,`sudo` 不会自动去用 `SUDO_ASKPASS`,
必须显式给 `-A`。**(在 macOS 自带的 sudo 1.9.17p2 上实测:
同样设了 `SUDO_ASKPASS`、同样无 tty,不给 `-A` 报
「a terminal is required … configure an askpass helper」,给了 `-A` 才弹。)

这就决定了「谁需要改」:

| 谁在调 sudo | 它会不会自己加 `-A` | 要谁改 |
|---|---|---|
| macview 自己发的 sudo | —— | **macview**(发命令时带 `-A`) |
| Homebrew 的 `install.sh` | **会**(`execute_sudo` 见 `SUDO_ASKPASS` 非空就加 `-A`) | **不用改** —— 只把 `SUDO_ASKPASS` 放进子进程环境 |
| **本仓库脚本里的 `sudo`** | —— | **本仓库,已改**(见下) |

**最后一行已经修了**(`scripts/macos/sudo-env.zsh`)。做法就是上表倾向的
第二条「统一变量」，而且它在实测里又暴露了**第二个、更靠前的洞**:

⚠️ **`sudo -n` 不认 `SUDO_ASKPASS`。** 脚本原来用 `sudo -n true` 判断
「有没有 sudo 授权」—— 但 `-n` 的语义是「**绝不提问**」，
它连 `SUDO_ASKPASS` 都不调（实测:同样有 `SUDO_ASKPASS`、同样无 tty，
`sudo -n true` 报 `a password is required`;`sudo -A -v` 才弹出密码框）。
后果比裸 `sudo` 更坏，因为它是**判定**:

  - `prompt-once.zsh` 的 `preauth_sudo` → 永远判定「未授权」→ 报
    「跳过需要 sudo 的步骤」→ **Homebrew、Touch ID 全被静默跳过**;
  - `brew-bootstrap.zsh:33` → `exit 1` 说「没有终端可输入密码」→ **装不上**。

所以修法不只是「裸 sudo 换成 `$SUDO`」，还要把**判定**从 `sudo -n true`
换成「`sudo_check`（静默问）失败 → `sudo_authorize`（去拿，可能弹框）」。
这正是 `sudo-env.zsh` 提供的那对函数。

| 文件 | 原来 | 现在 |
|---|---|---|
| `scripts/macos/sudo-env.zsh` | ——(**新增**) | 定义 `SUDO`/`sudo_check`/`sudo_authorize` |
| `prompt-once.zsh:141,149` | `sudo -n true` / `sudo -v` | `sudo_check` / `sudo_authorize` |
| `brew-bootstrap.zsh:33,36` | `sudo -n true` / `sudo -v` | `sudo_check` / `sudo_authorize` |
| `install.zsh:88,120,274` | `sudo -n true` / `sudo -v` | `sudo_check` / `sudo_authorize` |
| `scripts/macos/prefs.d/sudo_touchid.zsh:52,62,64` | 裸 `sudo install/cp/sh` | `"${SUDO[@]}" install/cp/sh` |

`sudo-env.zsh` 只在 `SUDO_ASKPASS` 非空**且无 tty**时用 `sudo -A`;
终端环境下仍是裸 `sudo`（让 sudo 自己弹终端提示）—— 所以**手敲
`zsh install.zsh` 的行为一个字都没变**。

> **顺带一提**:`brew-install.zsh` 那条**不用改**。它跑的是 Homebrew 自己的
> `install.sh`,而那个脚本自己认 `SUDO_ASKPASS`。macview 只要把
> `SUDO_ASKPASS` 放进环境即可 —— 这正是旧代码做的(`SoftwareApply.swift:864-866`
> 的 `SudoCredential.env`)。

#### 1.1.3 B:git 身份用参数预填,不走 `read`

`prompt-once.zsh:71` 用 `[[ -t 0 ]]` 判断要不要问 git 身份。macview 起的子进程
没有 tty → **它会静默跳过提问**,于是 `.gitconfig.local` 不建,**之后 commit 全失败**。

但 `prompt-once.zsh` 本来就支持**不问**:`--name`/`--email` 或环境变量
`GIT_NAME`/`GIT_EMAIL`(见 `prompt-once.zsh:62-64、22-24`)。

所以 macview **不靠 tty**,而是:
1. 界面上直接问用户「git 名字/邮箱」,或者读已有的 `~/.gitconfig`;
2. 把值用 `--name`/`--email` 传给 `zsh install.zsh`。

这样「一键配置」在**完全没有终端**的情况下也能把身份配好。
(旧代码没有这个问题,因为它**从不跑 `install.zsh`**、只做只读解析。)

#### 1.1.4 为什么不是 PTY(实测记录,免得下次又想走这条)

「给子进程开 PTY」听起来最干净,实测**在 Swift 里做不到**:

1. **Swift 明确禁止 `fork()`** —— 编译期报
   `'fork()' is unavailable: Please use threads or posix_spawn*()`。
   而唯一能把 pty 变成**控制终端**的原语是 `login_tty()`,它**必须**在
   `fork()` 出来的子进程里调。
2. **`posix_spawn` 没有「exec 前跑代码」的钩子**,所以调不了 `login_tty`。
3. **`posix_spawn` + `POSIX_SPAWN_SETSID` 拿不到控制终端**。实测:
   子进程里 `ps -o tpgid,tty` 显示 `TPGID=0`、`TTY=??`;
   而用 `login_tty` 的对照组是 `TPGID=<pid>`、`TTY=ttysNNN`。
   `sudo` 因此照样报「a terminal is required」。
4. 让子进程**自己 open 从端**(`posix_spawn_file_actions_addopen`)也一样 ——
   实测仍是 `TPGID=0`。macOS 不像某些系统那样「会话首进程 open 一个 tty
   就自动成为控制终端」。
5. `script(1)` 能开真 pty,但**会往 stdout 混入自己的 `^D\b\b`**、
   且 stdin 重定向不直达子进程 —— 不适合拿来抓输出。

**结论**:PTY 这条路的性价比最差(要么加一个 C helper、要么忍 `script` 的脏输出),
而它对**两个真实需求**都不必要(见 §1.1.1)。

#### 1.1.5 那「实时显示 sudo 密码框」怎么做到

`SUDO_ASKPASS` 弹的是**原生 macOS 对话框**(`osascript`),不是终端里的提示。
所以「macview 拿不到输出」这个担心**不存在** —— 密码框由 `osascript` 自己弹,
macview 照常收命令的 stdout/stderr。

⚠️ 但有一点要写死:**`SUDO_ASKPASS` 助手要活到整批操作跑完,不能提前删。**
macOS 的 sudo 凭据默认 **5 分钟**过期,而装 Homebrew 能跑 **20 分钟**;
脚本内部还有好几次 sudo。助手提前删了,那些 sudo 会报
`no tty present and no askpass program specified`。旧代码把这条踩明白过
(`SoftwareApply.swift:846-855`),照抄即可。

### 1.2 退出码列 —— 「有缺失」不是「崩了」

⚠️ **`brew-audit.zsh` 有缺失时退出码是 1**(`brew-audit.zsh:331`),
**这是正常的业务结果,不是错误**。

macview **不能**把「非零 = 出错」当通则。判据是:

- **`--json` 类命令**:看 JSON 内容(有没有 `missing`),**不看退出码**。
  退出码只用来区分「脚本真的没跑起来」和「跑起来了」。
- **动作类命令**(`install.zsh` 等):退出码 0 = 全部成功,
  非零 = 有步骤失败(输出里会列)。这时才报错。

这条必须写死,否则「有 3 个包没装」会在界面上显示成「对账脚本崩了」——
用户会去修一个根本没坏的东西。

---

## 二、只读查询出口(状态侧)

macview 显示状态靠这些。**格式都是我定的**,改格式 = 改契约。

约定:

- 统一用 `--json` 参数。**唯一的例外是 `private-state.zsh --stdout`** ——
  它比这套约定早，而且它有两个模式（`--write` 给 `prompt-once` 落盘、
  `--stdout` 给 macview 打印），`--stdout` / `--write` 是对成对的词，
  改名叫 `--json` 反而让那一对变别扭。**所以不改它，而是把例外写在这里。**
  （原先本节写「统一用 `--json`」、§2.4 写 `--stdout`，两处矛盾 ——
  现在以本行为准：`private-state.zsh` 用 `--stdout`，其余用 `--json`。）
- 输出**只有一个 JSON 对象到 stdout**;**日志/警告一律走 stderr**。
  (这条很硬:`private-state.zsh:198` 的注释记着一个坑 —— 有一处输出
   直接 `echo` 到了 stdout,污染了 JSON,而且是静默的。)
- 顶层必须有 `version`(整数)、`checked_at`(Unix 秒)、`generated_by`。
- `version` 不匹配时,macview **不装作看得懂** —— 它应该停止解析并报错
  (照 `private.md:241` 的读规则)。
- **每个脚本的产出都由 `selfcheck.zsh` 校验**(`check_macview_query_json`):
  跑它的 `--json`、要求合法 JSON、要求必填顶层字段都在。格式漂了会**报错**。

> ⚠️ **实现状态**:下面 2.1 / 2.2 / 2.3 / 2.5 / 2.6 的脚本**已经建好骨架并跑通**
> (2026-09-24),它们的 `--json` 产出已进 `selfcheck`。2.4 用现成的。
> 字段以本节的 JSON 为准 —— 与早期草稿的字段名(`state` 的取值、`missing` 项的
> 形状等)有出入时,**以本节为准**,因为本节是从真实产出抄的。

### 2.1 前提检查 `scripts/macos/preflight.zsh --json`(✅ 已建)

macview 启动时调一次。回答「这台机器能不能开工」。

```json
{
  "version": 1,
  "checked_at": 1758700000,
  "generated_by": "preflight.zsh",
  "dotfiles": { "state": "present", "path": "/Users/you/dotfiles" },
  "private":  { "state": "absent",  "path": "/Users/you/private-dotfiles" },
  "scripts": [
    { "name": "install.zsh",      "path": "install.zsh",                    "state": "present" },
    { "name": "brew-install.zsh", "path": "scripts/macos/brew-install.zsh", "state": "absent" }
  ],
  "package_lists": [
    { "name": "brew-cli.txt", "path": "packages/macos/brew-cli.txt", "state": "present" }
  ],
  "tools": { "git": "present", "homebrew": "present" }
}
```

- `state` 三态:`present` / `absent` / `unknown`(理由见 `private.md` 的四态精神:
  问不出来必须能表达)。
- **不查网络、不查磁盘**(旧文档 §4 的时机表:日常看的时候一次网络探测都不该发)。
- 「脚本在不在」单列,是因为**它会变** —— 你在仓库里重命名一个脚本,
  macview 得**报出来**,而不是「点了没反应」。
- `package_lists` 查的是**软件页和配置页依赖的文件**(两份 brew 清单 + `mise/config.toml`)。
  它们不在时那一页会是空的 —— 而「空」和「仓库坏了」在界面上长得一样,所以单独报。
- `tools` **自带 PATH 增强**(脚本内部 `source brew-env.zsh`)—— 因为 GUI App 的
  PATH 是 launchd 的最小值,不补会对着一台装好 brew 的机器**误报「没装」**。
  macview 侧不用为这个查询再自己补 PATH。
- 当前 `tools` 只报 `git` 和 `homebrew`。**没报 `command_line_tools`** ——
  那个要起 `xcode-select` 且会超时,属于「动手前才查」,不该在启动时查。
  真要补,加在 macview 的「点按钮前」路径里。

### 2.2 落点状态 `scripts/macos/link-status.zsh --json`(✅ 已建)

回答「19 个配置落点现在什么样」。这是现在**完全没有**的能力
(`link-dotfiles.zsh` 只负责链,不负责报)。

```json
{
  "version": 1,
  "checked_at": 1758700000,
  "generated_by": "link-status.zsh",
  "targets": [
    { "src": "zsh/zshrc", "dest": "/Users/you/.zshrc",       "state": "linked" },
    { "src": "aliases",   "dest": "/Users/you/.aliases",     "state": "drift" },
    { "src": "nvim",      "dest": "/Users/you/.config/nvim", "state": "absent" }
  ],
  "counts": { "linked": 17, "drift": 1, "absent": 1, "other": 0 }
}
```

- 落点清单**从 `link-dotfiles.zsh` 的 `DOTFILE_LINKS` 读**
  —— 不复刻一份(避免两份漂移)。抠不出数组时**报错退出**,不给空数组
  (空数组会被 macview 当成「一个落点都没有、全没问题」的假消息)。
- `dest` 是**绝对路径**(和 `private-state.zsh` 的 `json_home_path` 一致),
  不是 `~` —— JSON 里 `~` 不会被任何标准工具展开。
- `state` 四态:`linked` / `drift`(指向别处)/ `absent`(本机没有)/
  `other`(是个真文件,不是链接 —— 不能碰)。

### 2.3 软件对账 `scripts/macos/brew-audit.zsh --json`(✅ 已加参数)

`brew-audit.zsh` 默认仍输出**人读文本**;加 `--json` 输出结构化结果。
两种模式**共用同一份算出来的结果**,不是各算一遍 —— 判据只有一处。

```json
{
  "version": 1,
  "checked_at": 1758700000,
  "generated_by": "brew-audit.zsh",
  "declared":  { "cli": 35, "cask": 2 },
  "installed": { "cli": 81, "cask": 2 },
  "missing":   [ { "label": "公共 / formulae", "kind": "formula", "name": "jq" } ],
  "duplicate": [ { "label": "公共 / casks",     "kind": "cask",    "name": "bar" } ],
  "extra":     [ { "kind": "formula", "name": "foo" } ]
}
```

- `label` 是给人看的清单名前缀(带中文),`kind` 是机器判据(`formula` / `cask`)。
  两者都留 —— 因为 label 的中文**将来可能改字**,不能靠它反推 kind。
- `extra` **只有 formula**(cask 太多系统自带/手动装的,报了是噪音)。
- 退出码语义与文本模式一致:有缺失 → 1。
- ⚠️ 已知差异:只覆盖公共仓库的 2 份清单,私有源的 `*.private.txt` 读不到。

### 2.4 私有源状态 `scripts/macos/private-state.zsh --stdout`(✅ 已有)

**直接读现有的这个**,不新造。格式见 `private.md`。

### 2.5 开发环境 `scripts/macos/mise-status.zsh --json`(✅ 已建,可缓)

mise 声明的工具 vs 实装。

```json
{
  "version": 1,
  "checked_at": 1758700000,
  "generated_by": "mise-status.zsh",
  "mise_present": true,
  "mise_ok": true,
  "tools": [ { "name": "node", "declared": "25", "installed": "25.9.0", "state": "ok" } ]
}
```

- `mise_ok` 三态:`true` / `false`(有 mise 但问不出来)/ `null`(压根没 mise)。
  它和 `mise_present` 一起,让 macview 能区分「没装 mise」和「装了但查不到」。
- `state`:`ok`(声明的大版本对得上)/ `drift`(装了但版本对不上)/
  `absent`(没装)/ `unknown`(问不出来)。**`unknown` 绝不当成 `absent`。**
- `installed` 对 `unknown` 是 `null`。
- ⚠️ `mise ls` 可能慢,这个查询**懒查 + 可缓存**(缓存在 macview 侧)。

### 2.6 仓库状态 `scripts/macos/repo-status.zsh --json`(✅ 已建)

```json
{
  "version": 1,
  "checked_at": 1758700000,
  "generated_by": "repo-status.zsh",
  "is_git": true,
  "branch": "master",
  "dirty": true,
  "ahead": 0,
  "behind": 0,
  "upstream": "origin/master",
  "upstream_stale": false,
  "changed_files": ["packages/macos/brew-cli.txt"]
}
```

- **不 `fetch`** —— 不发网络请求,也就不静默改 `.git/refs/remotes`。
  所以 `ahead`/`behind` 是相对**本地已有远端引用**算的,可能不是远端此刻的真相。
- `dirty` **包含未跟踪文件**(`??`)—— 「仓库里有没被 git 管的东西」正是最该看到的。
- `upstream_stale`:本地远端引用是否可能过期(用于提醒用户「数字未必是最新的」)。
  当一个简单的陈旧提示用,不保证精确。
- `changed_files` 只报**前 50 个** —— 仓库可能有几千个改动,列表不该被撑爆。
- 不是 git 工作树时只有 `is_git: false` 和 `detail`;**连 git 都没装**时
  `is_git: null`(问不出来),不谎报 `false`。
- ⚠️ 路径含空格/特殊字符时 git 会给路径加引号,本脚本已剥掉外层引号;
  但更复杂的转义(非 ASCII 的八进制转义)暂不还原 —— 已知限制。

### 2.7 偏好状态 —— **本版不提供**(见下)

`prefs.d/*.zsh` 是 `defaults write` 的**文本**,而 `defaults read` 是**值**。
要判「这一组对不对」,得把两者对上 —— 而「哪个 key 属于哪个主题文件」这件事,
**除了解析那些 `.zsh`,没有别的地方能拿到**。

三个选择:

| 选项 | 代价 |
|---|---|
| 查询脚本解析 `prefs.d/*.zsh` | 又回到「复刻文本解析」,脆 |
| 让每个 `prefs.d/*.zsh` **自己**报告「我要设哪些键」 | 要改 9 个文件,但**这是唯一不漂移的做法** |
| **不做**(只提供「跑 prefs」按钮) | 最诚实 |

**这一版决定「不做」**,理由是项目纪律:**看不见的失败等于没失败过,
而假消息比没有更糟。** 一个半准不准的「偏好已应用」绿勾,会让人以为配好了。
所以只给「跑 prefs」按钮,不显示逐项状态。

将来若要做,**唯一不漂移的做法**是让每个 `prefs.d/*.zsh` 自己报告
「我要设哪些键」,而不是 macview 去解析它们(见 §六)。

---

## 三、macview 会改的东西(编辑侧)

macview 能编辑文本文件。**只改本仓库里的源文件**,不改 `$HOME` 下的落点。

| 可编辑 | 不可编辑(理由) |
|---|---|
| `packages/macos/brew-{cli,cask}.txt` | `~/.zshrc` —— 那是链接,改它 = 隐式改仓库源 |
| `mise/config.toml` | `~/.gitconfig` 同上 |
| 其它 `src/macos/config/**` | |

**关键纪律**:改完**不等于生效**。用户改了 `brew-cli.txt` 要**点「应用」**
让脚本去装。界面必须让人看见「改了但没应用」这个中间态。

### 3.1 commit —— 唯一一个「macview 自己动手写磁盘」的例外

⚠️ **本仓库没有任何 git 辅助脚本**(`scripts/` 下没有 commit/add/push 逻辑),
而 `repo-status.zsh` 只能报「哪些文件脏」、**报不出 diff**。

所以 commit 那一页,macview 要**自己拼 `git add` / `git commit` / `git push`**。
这和「macview 只调脚本、不自己动手」的定位**是冲突的** —— 必须把它当成
**明写的例外**,并配纪律,否则它会变成一条没人管的旁路。

macview 侧的纪律(照 DOTFILES 的既有规矩):

1. **commit 前显示要改什么**(`git status` + diff),不给人看就不提交。
2. **push 单独一步**,不跟 commit 捆在一起 —— push 是真正不可逆的那个。
3. **不在本仓库没有任何改动时提交**(避免空提交)。
4. 提交信息由用户写,macview 不自动生成。

**为什么不在本仓库加个 commit 子命令**:加也可以,但那会变成一个
「什么都干」的假 installer 子命令;git 是标准工具,macview 用标准工具没有错。
**纪律在 macview 侧,不在命令侧。**

### 3.2 打开文件 —— 编辑的兜底

除了内置编辑器,macview 还应能用**默认 App / 终端**打开某个源文件
(比如 `open -t ~/dotfiles/packages/macos/brew-cli.txt`)。
这条不用写进契约 —— 它不碰 dotfiles 的接口。但设计文档里要有
(macview 设计文档 §2.1 的「打开」)。

### §3.4 私有 overlay 的独立入口 —— **已定：不做**

现状:私有 overlay 的**五个落点**(`~/.gitconfig.local` / `~/.zshrc.local` /
`~/.envconfig.local` / `~/.ssh/config.local` / `~/.aliases`,也是五个槽位)
**没有独立的公开入口** —— `link-private.zsh` 在私有仓库里,macview 够不着。

原先这里建议「新增 `install.zsh private-link`」。**最终决定不做** ——
`private.md` 的「已决定」里已经写死了这条(`private.md:678`):

> 检测入口:独立脚本 `private-state.zsh`,双 flag (`--write` / `--stdout`),
> 一份检测逻辑两个调用方;**不做** `install.zsh private` 子命令
> (那会让 install 变成 macview 的入口,职责混乱)。

两条文档原先矛盾(本节建议做、`private.md` 决定不做)。**以 `private.md` 为准**,
理由是它说的对:私有 overlay 的链接本来就是 `install.zsh base` 的一部分,
用户跑过一次 base 就链好了;为它单开一个子命令,等于让公开仓库
去调私有仓库的脚本 —— 那是**反过来**把依赖写反了。

**所以「配置」页的私有源那一块只显示状态,不给「链私有 overlay」按钮。**
要链就走 `install.zsh base`(一键配置里已经包含)。

> 契约 §二 的查询约定里,`private-state.zsh` 用 `--stdout`(不是 `--json`)——
> 唯一的例外,理由见 §二。

---

## 四、macview 写死的结构(它会复制一份,你要同步)

macview **不读**本仓库的结构,它**写死**一份(定位:脚本控制器 + 结构写死)。
这份写死的描述和本仓库会漂移 —— 但漂移是**可检测、会报错**的。

macview 写死的东西:

| 写死什么 | 本仓库对应 |
|---|---|
| 入口脚本名(`install.zsh` + 子命令) | `install.zsh:325` |
| 要调的脚本路径 | `scripts/macos/*.zsh`(清单见契约 §1) |
| **每个命令要不要提权** | 契约 §1 表格的「要提权」列 |
| 落点数(19) | `link-dotfiles.zsh:34` 的 `DOTFILE_LINKS` |
| 私有源 5 个落点/槽位 | `private.md:194` |
| 包清单路径 | `packages/macos/brew-*.txt` |
| prefs 主题数(9) | `prefs.zsh:39` 的 `PREF_ORDER` |

**你在本仓库改了这些,macview 要跟着改。** 不同步的后果:

| 你改了 | macview(没同步)的反应 | 好不好 |
|---|---|---|
| 重命名脚本 | 启动检测报「脚本不在」 | ✅ 会报错 |
| 改落点(加一行) | 落点查询脚本从 `DOTFILE_LINKS` 读 —— **自动跟上** | ✅ 不漂移 |
| 改某个命令要不要提权 | 该弹密码框的没弹(macview 没注入 `SUDO_ASKPASS`)→ sudo 失败 | ❌ **会静默漂移** |
| 加一个 `prefs.d` 主题 | 不影响(本版不做偏好状态,没有东西可漂) | ✅ 无影响 |

「要不要提权」那一行是**唯一会静默漂移的地方** —— 它必须和 §1 的表格
**同时改**。改了契约不改 macview,需要密码的步骤会**静默失败**。

---

## 五、时机(什么时候查什么)

照旧文档 §4 的时机表(那一节的判断是对的):

| 时机 | 查什么 | 不查什么 |
|---|---|---|
| **启动 / 打开主窗口** | 前提检查、落点状态 | ❌ 网络、磁盘、CLT |
| **显示某一页** | 那一页需要的(懒查) | ❌ 其余 |
| **点了「动手」按钮** | 网络 + 磁盘(要下载才查);要装东西前查**命令行工具**(`xcode-select`,会超时) | — |

三条约束:

1. **日常「看」不发网络请求。**(旧代码那个 5 秒 `curl` 是纯开销。)
2. **`unknown` 永远不拦路。**(一次超时不该把整个功能锁死。)
3. **`checked_at` 会过期。** macview 要能看出状态是「刚才查的」还是「很久以前的」
   —— 过期状态要标出来,不能当成现在。

---

## 六、这份契约没定的东西(留给实施)

- **各查询脚本的具体字段**会随实施微调(只要守上面 4 条设计原则)。
- **偏好状态**(§2.7)—— **已定:这一版不做**,只给「跑 prefs」按钮。
  将来若要做,唯一不漂移的做法是让每个 `prefs.d/*.zsh` 自己报告键名。
- **撤回**(macview 设计文档 §5:macview 不自建撤回。如果将来要做,
  在本仓库加 `install.zsh restore`,读 `link-dotfiles.zsh` 自己的备份)。
- **`.envconfig.local` 的归宿**(`docs/design/2026-09-22-dotfiles-整理盘点.md` §3.3
  记的老问题)—— 那是本仓库自己的事,不是 macview 接口。
- ~~⚠️ **本仓库脚本里的裸 `sudo` 要认 `SUDO_ASKPASS`**(§1.1.2)—— **待办**。~~
  ✅ **已做**:新增 `scripts/macos/sudo-env.zsh`（`SUDO` / `sudo_check` /
  `sudo_authorize`),`prompt-once` / `brew-bootstrap` / `install.zsh` /
  `scripts/macos/prefs.d/sudo_touchid.zsh` 的 sudo 调用点全部改走它。连带修掉了一个
  更靠前的洞:原来的**判定** `sudo -n true` 不认 `SUDO_ASKPASS`(实测),
  会让 macview 环境**静默跳过** Homebrew 和 Touch ID。详见 §1.1.2。

### 本次新拍板的两条(从「没定」移过来)

- **提权(不是 tty)**(§1.1)—— 已定,而且**推翻了原稿的 PTY 方案**:
  macview 用 **`SUDO_ASKPASS` + 原生密码框**(`osascript display dialog`),
  **不开 PTY**。git 身份用 `--name`/`--email` 预填,也**不走 `read`**。
  原 PTY 方案在 Swift 里走不通(禁止 `fork()`,`posix_spawn` 拿不到控制终端),
  实测记录见 §1.1.4。
  **后果**:`ScriptRunner` 不再需要两条执行路径的区分,而是**一条** ——
  跑命令 + 可选注入 `SUDO_ASKPASS` 环境。
- **commit**(§3.1)—— 已定:macview 自己调 git,但配明确纪律
  (先给人看 diff、push 单独一步、空改动不提交)。这是「只调脚本」定位的
  唯一明写例外。

---

## 附:和现有文档的关系

| 文档 | 说什么 |
|---|---|
| `README.md` | 本仓库装什么、怎么装、改哪里 |
| `private.md` | 公开仓库 ↔ 私有源的接口(私有源状态那部分) |
| **本文** | 公开仓库 ↔ **macview** 的接口 |
| `shell.md` | shell 加载链 |
