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

| macview 的动作 | 调的命令 | tty | 退出码 | 现状 |
|---|---|---|---|---|
| 一键配置(全套) | `zsh install.zsh` | **要** | 0 / 1 | ✅ 已有 |
| 只链接配置 | `zsh install.zsh link` | 不要 | 0 | ✅ 已有 |
| 只应用偏好 | `zsh install.zsh prefs` | **要** | 0 / 1 | ✅ 已有 |
| 装软件(brew+cask) | `zsh scripts/macos/brew-install.zsh` | **要** | 0 / 1 | ✅ 已有 |
| 对账(只读) | `zsh install.zsh audit` | 不要 | **0 / 1** | ✅ 已有 |
| 仓库自检(只读) | `zsh install.zsh check` | 不要 | 0 / 1 | ✅ 已有 |
| 装开发环境 | `zsh scripts/macos/mise-setup.zsh` | 通常不要 | 0 / 1 | ✅ 已有 |
| 链私有 overlay | **缺** —— 见 §3.4 | 不要 | ? | ❌ 要新增 |

**契约**:上表 ✅ 的命令**以后不改名、不改语义**。
改了 macview 会报「脚本不在」(启动检测),不会静默。

### 1.1 tty 列 —— 这是执行侧最容易做错的一件事

`prompt-once.zsh:71` 用 `[[ -t 0 ]]` 判断「有没有终端」:

```zsh
interactive=1
[[ -t 0 ]] || interactive=0      # 没有 tty → 完全跳过提问
```

**macview 用 `Process` 起的子进程默认没有 tty**(fd 0 不是终端)。
没有 tty 时会发生什么,**取决于命令**:

| 命令 | 没 tty 时的实际行为 | 危害 |
|---|---|---|
| `install.zsh`(base) | prompt-once **静默跳过** git 身份、sudo 预授权 | **身份没配也不说**,之后 commit 全失败 |
| `install.zsh prefs` | `scripts/macos/prefs.d/sudo_touchid.zsh` 的 `sudo install` 报「a terminal is required」→ 该步失败 | 报错,但**原因会被淹没**在输出里 |
| `brew-install.zsh` | 装 Homebrew 要密码 → 无 tty 时失败 | 装不上 |
| 查询类(`*--json`) | 完全不受影响(它们本来就不提问) | 无 |

所以规则是:

> **标了「tty 要」的命令,macview 必须给它在「有控制终端」的上下文里跑。**

macview 侧的实现选择(本次已定,**A**):**给子进程分配 PTY**。
不是「丢给 Terminal.app」,也不是「不处理」。

#### 为什么是 PTY 而不是别的

| 方案 | 为什么不选 |
|---|---|
| 直接 `Process` + 继承 stdin | 从 GUI 起时 fd 0 是 `/dev/null`,行为和不指定一样 —— 见下 |
| 继承 stdin + 不指定 | 旧代码踩过:从终端跑 CLI 时是 tty、从 app 跑时是 `/dev/null`,**同一命令两处行为不同**,表现为「偶尔挂住」,极难查(`SoftwareApply.swift:122` 的注释记着) |
| `standardInput = /dev/null`(旧代码的做法) | **不挂住,但也不提问** —— 需要密码的步骤直接失败。旧代码只是回避了问题 |
| 丢给 Terminal.app | 用户能看见,但 macview **看不到输出、拿不到退出码**,「实时显示结果」这条就废了 |
| **PTY**(选它) | 子进程以为自己在一个真终端里:`[[ -t 0 ]]` 真、`sudo` 能弹密码、macview 又能读全部输出 |

#### macview 侧怎么开 PTY(实现要点,给 macview 的实现者)

macOS 有现成的原语(`/usr/include/util.h`、`sys/ttycom.h`,已在 SDK 里确认):

- `openpty(&master, &slave, ...)` —— 开一对 pty。
- `posix_spawn` —— **不要用 `forkpty`**。
  理由:Foundation 的 GUI App 是**多线程**的;`fork()` 之后子进程只能调
  async-signal-safe 的函数,而 `forkpty` 之后通常要立刻 `exec`,
  中间那一步在 Swift 里很容易踩到不可 fork 的东西。`posix_spawn` 没有这个约束。
- 把 `slave` 作为子进程的 stdin/stdout/stderr;`master` 由 macview 读。
- 子进程要 `setsid()`(或 `posix_spawn` 的 `POSIX_SPAWN_SETSID`)成为会话首进程,
  再让 pty 成为控制终端(`TIOCSCTTY`)—— 否则 `sudo` 找不到 `/dev/tty`。
- 读 `master` 时**要处理 `\r\n`**:pty 会把 `\n` 翻译成 `\r\n`,直接显示会出现「每行多一个 ^M」。
- 用户输入密码时回显关掉了,但 macview 仍要把 master 上的字节**转给用户**看
  (至少要把密码提示显示出来)。

⚠️ **PTY 下没有超时这回事。** 人在输密码,不能掐。所以需要 PTY 的步骤
**不设自动超时**(或者给一个很长的、以「人在打字」为前提的值 ——
旧代码用的是 5 分钟,见 `SoftwareApply.swift:275`)。

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

- 统一用 `--json` 参数(和 `private-state.zsh` 的 `--stdout` 对齐,见下)。
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

### 2.7 偏好状态 —— **暂不提供**(见下)

`prefs.d/*.zsh` 是 `defaults write` 的**文本**,而 `defaults read` 是**值**。
要判「这一组对不对」,得把两者对上 —— 而「哪个 key 属于哪个主题文件」这件事,
**除了解析那些 `.zsh`,没有别的地方能拿到**。

三个选择:

| 选项 | 代价 |
|---|---|
| 查询脚本解析 `prefs.d/*.zsh` | 又回到「复刻文本解析」,脆 |
| 让每个 `prefs.d/*.zsh` **自己**报告「我要设哪些键」 | 要改 9 个文件,但**这是唯一不漂移的做法** |
| **不做**(只提供「跑 prefs」按钮) | 最诚实 |

**这一版倾向「不做」**,理由是项目纪律:**看不见的失败等于没失败过,
而假消息比没有更糟。** 一个半准不准的「偏好已应用」绿勾,会让人以为配好了。
留待实施时决定。

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

### §3.4 缺的那条:私有 overlay 的独立入口

现状:私有 overlay 的**五个落点**(`~/.gitconfig.local` / `~/.zshrc.local` /
`~/.envconfig.local` / `~/.ssh/config.local` / `~/.aliases`,也是五个槽位)
**没有独立的公开入口** —— `link-private.zsh` 在私有仓库里,macview 够不着。

**契约要补**:公开仓库提供一个稳定的入口,让 macview 能单独触发「链私有 overlay」。
两个选择:

| 选项 | 代价 |
|---|---|
| 新增 `install.zsh private-link` | 要调私有仓库的脚本,得知道私有仓库在不在(前提检查已覆盖) |
| 让 `install.zsh base` 顺带做 | 不独立,但 macview 就没有「只链私有源」这个按钮 |

**建议前者**(新增子命令),因为它让「配置」页的私有源那一块能有自己的应用按钮。

⚠️ 但私有 overlay 的链接脚本**在私有仓库里**,不在本仓库。
公开仓库的新子命令不能假设它一定在 —— 要在它不在时**明确报出来**
(「没找到私有仓库,无法链 overlay」),不是静默。

---

## 四、macview 写死的结构(它会复制一份,你要同步)

macview **不读**本仓库的结构,它**写死**一份(定位:脚本控制器 + 结构写死)。
这份写死的描述和本仓库会漂移 —— 但漂移是**可检测、会报错**的。

macview 写死的东西:

| 写死什么 | 本仓库对应 |
|---|---|
| 入口脚本名(`install.zsh` + 子命令) | `install.zsh:325` |
| 要调的脚本路径 | `scripts/macos/*.zsh`(清单见契约 §1) |
| **每个命令要不要 tty** | 契约 §1 表格的 `tty` 列 |
| 落点数(19) | `link-dotfiles.zsh:34` 的 `DOTFILE_LINKS` |
| 私有源 5 个落点/槽位 | `private.md:194` |
| 包清单路径 | `packages/macos/brew-*.txt` |
| prefs 主题数(9) | `prefs.zsh:39` 的 `PREF_ORDER` |

**你在本仓库改了这些,macview 要跟着改。** 不同步的后果:

| 你改了 | macview(没同步)的反应 | 好不好 |
|---|---|---|
| 重命名脚本 | 启动检测报「脚本不在」 | ✅ 会报错 |
| 改落点(加一行) | 落点查询脚本从 `DOTFILE_LINKS` 读 —— **自动跟上** | ✅ 不漂移 |
| 改某个命令要不要 tty | 该问密码的步骤静默失败(或凭空挂住) | ❌ **会静默漂移** |
| 加一个 `prefs.d` 主题 | 不影响(本版不做偏好状态,没有东西可漂) | ✅ 无影响 |

「要不要 tty」那一行是**唯一会静默漂移的地方** —— 所以它必须和
§1 的表格**同时改**。改了契约不改 macview,macview 会用错的路径跑命令
(该给 PTY 的没给 → 静默跳过提问)。

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

### 本次新拍板的两条(从「没定」移过来)

- **tty / PTY**(§1.1)—— 已定:macview 给需要终端命令开 **PTY**。
  `ScriptRunner` 要有 `runCaptured`(无 tty)和 `runInteractive`(PTY)两条路径。
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
