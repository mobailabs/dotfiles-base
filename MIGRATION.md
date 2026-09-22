# 迁移记录

`dotfiles-base` 从 `~/dotfiles` 复制而来，保留了全部个人偏好，改动了下面这些。
记录的目的：以后回头看时知道哪一行是谁改的、为什么。

来源：`~/dotfiles`（公共）+ `~/private-dotfiles`（私有，只取了结构与模板）
复制时间：2026-09-11

---

## 一、修掉「标准腐烂」—— 四类，全部实测到

### 1. 已废弃的包

`gemini-cli` 同时躺在两份清单里，brew 已明确提示将在 2026-12-18 停用。
**两份清单里都删掉了。**

> 官方替换是 `brew install --cask antigravity-cli`。没有替你加 —— 你现在用的是
> `antigravity` 这个 cask，要不要换是你的事。

### 2. 包名写错 —— 其实是两处，不是一处

`tailscale` 和 `xcodes` 都是 **formula 名**，却被写进了 cask 清单。
（体检报告只报了 `tailscale`，`xcodes` 被当成「没装」漏掉了。）

已用 `brew info` 核实：

| 名字 | 真实类型 | 处理 |
|---|---|---|
| `tailscale` | formula 1.102.4 | **删掉** —— `tailscale-app` cask 已经带了 CLI，两个都装会冲突 |
| `xcodes` | formula 2.0.3 | **移到 `packages/macos/brew-cli.txt`** —— CLI 和 `xcodes-app` GUI 是互补的 |

### 3. 清单内重复

- `mise` 在 `packages/common/brew-cli.txt` 出现两次 → 删掉一个
- `antigravity` 在 `packages/macos/brew-cask.txt` 出现两次 → 删掉一个
- 顺带：`bat` / `jq` 在 common 和 macos 两份里都有 → 从 macos 删掉（common 已经覆盖）

### 4. 改了没提交

`src/common/config/mise/config.toml` 有未提交改动：`bun 1.3→1.4`、`rust 1.89.0→1.98.1`，
还加了一个**空的 `[env]` 段**。

- 版本升级**保留**（和本机 `mise current` 一致，是对的）
- 空的 `[env]` 段**删掉**（没有内容，只是噪音）

---

## 二、修掉结构问题

### 1. `prefs` 不在安装流程里 ← 最重要的一个

旧 `install.zsh` 的 base 流程是
`check → brew → oh-my-zsh → zsh-plugins → link → tmux-plugins → mise`，
**没有 prefs**。

后果是实测出来的：78 条偏好里 **61 条从未生效**，5 条和标准相反，
其中一条是天天在用的触控板轻点。而且没有任何提示 —— 因为没人检查过。

现在 `prefs` 进了 base 流程，放在**最后**，并且**失败不中断**
（它可能要 sudo，你按了取消不该让前面装好的东西白费）。

### 2. `prefs.zsh` 一个文件失败会拖垮全部

旧版有 `set -euo pipefail`，`sudo_touchid.zsh` 要密码，你按取消 → 整个脚本退出，
后面的偏好全都不执行。

改成：逐文件执行、**去掉 `set -e`**、失败计数、结束时报告哪些失败并给出重跑命令。

### 3. 落点映射有三份副本

`link-dotfiles.zsh` 里硬编码一份、体检脚本里一份、macview 的差异计算器里一份。
三份迟早对不上。

现在有 **`link.map`** —— 唯一一份声明，安装脚本读它。
（macview 那一侧还没接上，见「遗留」。）

### 4. `rm -rf "$dest"` 无条件删除

旧 `link-dotfiles.zsh` 第 85 行：目标存在就 `rm -rf`，没有备份、没有确认。
一次误操作就没了。

改成：**移到 `~/.dotfiles-backup/<时间戳>/`**，路径打印出来。
一次运行只用一个时间戳目录（不是每个文件算一次时间）。

已在隔离的 HOME 里验证：普通文件、整个目录都能完整保留，然后再建链接。

### 5. `zshenv` 里有一条永远不存在的 PATH

```zsh
path=(
  $HOME/.bin
  $HOME/.dotfiles/bin   # ← 这个目录从来没有存在过
  $HOME/.local/bin
  $path
)
```

而且 `~/.dotfiles` 这个仓库名在本机也不存在（真实是 `~/dotfiles`）。

改成全部加存在性判断，并去掉那条。私有仓库的 bin 本来就不该在这里处理 ——
`~/.zshrc.local` 里已经用 `$DOTFILES_PRIVATE_ROOT/bin` 条件加过了。

### 6. `~/.ssh/config` 没有加载点

`~/.gitconfig`、`~/.zshrc`、`~/.envconfig` 都有加载点，只有 `~/.ssh/config` 没有。
所以写进 `~/.ssh/config.local` 的值永远不会生效 —— 而那个文件本来也不存在，
是「双重失效」。

模板里补上了 `Include ~/.ssh/config.local`。
已实测：Include 一个不存在的文件会被 ssh 静默忽略（退出码 0），所以这行永远安全。

> **已经装好的机器要手动补这一行** —— `~/.ssh/config` 是 git-secret 管的私密文件，
> 不在这个仓库里，我改不到。

---

## 三、没动的

- 所有个人偏好：别名、tmux 配置与函数、nvim 配置、ghostty 主题、
  `prefs.d/` 的 9 个文件内容、mise 的工具清单
- `~/private-dotfiles` 一个文件都没碰（这个仓库本来就不含私密内容）
- `scripts/` 下其他脚本的逻辑

`~/dotfiles/docs/private-repo-template/` 没有复制 —— 它是 `private-template/` 的
**旧版本**：少了 `.gitignore`、`bin/`（9 个脚本）、`secrets/`、`secret-helper.zsh`，
README 和 `install.zsh` 也更旧。`private-template/` 是它的超集，所以不复制不丢东西。

> 一开始我把这个判断写成了「重复副本」，不准确 —— 它们是两份内容不同的文件，
> 只是旧的被新的取代了。

---

## 四、review 时又发现的（同日补修）

建完之后逐个复核，又找到 5 处 —— **其中 3 处是这次改动自己引入的**。

### 1. `zshenv` 的 PATH 顺序被改反了 ← 自己引入的

原来这两个目录是**前置**的：

```zsh
path=( $HOME/.bin $HOME/.dotfiles/bin $HOME/.local/bin $path )
```

我改成了 `path+=(...)`，变成**追加到末尾** —— 优先级降到最低。
后果是你自己装的 CLI 会被系统里的同名命令遮住。

已改回前置：用 `_pre` 数组攒好再整体前置，顺序与原版一致（已实测）。

### 2. 私有侧 `link-private.zsh` 仍是 `rm -rf` ← 漏改

修了公共侧的 `link-dotfiles.zsh`，**但私有模板里的同一行没动**。
那边风险更高：它链的是 `~/.envconfig.local`，这个文件在很多机器上是装着
机器专属变量的**真文件**（本机 2433 字节）—— 跑一次 `install.zsh` 就没了。

已改成同样的备份机制。

### 3. 备份会静默覆盖 ← 自己引入的

`backup_dest` 用固定文件名 `$BACKUP_ROOT/$flat`。默认时间戳每次不同所以没事，
但**README 里主动引导用户设 `DOTFILES_BACKUP_DIR`** —— 一旦设成固定目录，
第二次运行的备份就会覆盖第一次的。

已改成目标名存在时加 `.1` / `.2` 后缀。

### 4. `ghostty/config` 新克隆时不存在 ← 继承的

它被 `.gitignore` 排除（`eink-on/off` 用 `ln -sf` 切它，提交了每次切主题都会
弄脏工作区）。代价是**新克隆的仓库里没有这个文件**，ghostty 以默认配置启动。

已在 `install.zsh` 里补一步：没有当前主题时创建 `config -> config-dark`。

### 5. `assert_safe_dest` 挡不住 `..` ← 继承的

只检查 `$HOME/*` 前缀的话，`$HOME/../etc/passwd` 能溜过去。
已加 `/../` 分量检查（用 `/` 包住再匹配，`.config/my..dir` 这种合法名字不会误伤）。

### 核实过、确认没问题的

- `xcodes` 在 `homebrew/core` 里，可以直接 `brew install`，不需要额外 tap
- `prefs.zsh` 的空数组 + `set -u` 安全
- `install.zsh` 里 `cmd || { ... }` 在 `set -e` 下安全
- `link.map` 遇到缺字段的行会跳过，不会误链接
- `~/dotfiles/docs/` 下只有那个旧模板，排除 `docs/` 没丢东西

---

## 五、遗留

1. **macview 还没读 `link.map`** —— `crates/engine/src/diff.rs` 里的
   `CONFIG_MAPPINGS` 仍是硬编码的一份。下一步应该改成读 `link.map`，
   三份副本才算真正消掉。
2. **`~/.ssh/config` 的那行要手动补**（见上）。
3. **私有仓库里的 4 条漂移**（`config` / `conym.dat` / `totp` / `jump` 内容与仓库不一致）
   —— 需要决定：回写仓库，还是重新从仓库安装。
4. **`~/.envconfig.local` 是普通文件**（2433B），不是 symlink ——
   机器专属变量没有归宿。这是设计文档里「机器差异没有归宿」的实例。
