# 私有源（private source）契约

> 本文是**接口规格**，不是使用说明。它规定「公开仓库」和「用户的私有数据」
> 之间怎么交接，以及 macview 这个 GUI 怎么读到这件事。
>
> **状态：草案（v1 未冻结）。** 格式定下来之后，`install.zsh` 侧和 macview 侧
> 各自实现；在冻结前两边都别把它当稳定接口。

---

## 为什么要有这份契约

现在的情况：公开仓库有四个 `.local` 加载点（见 `README.md` 的「加载点」），
但它们全是**条件加载、缺失静默跳过**：

```sh
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
```

这个设计本身是对的 —— 「没有私有源也能用」必须成立。但它带来一个副作用：

> **「没有私有源」和「有私有源但链接断了」在当前实现里长得一模一样。**

两者都是「文件不存在 → 什么都不发生」。shell 端无所谓（本来就不该报错），
但 **macview 存在的意义恰恰是告诉用户这两者的区别** —— 它却无从判断，
只能靠「文件在不在」去猜，而猜不出「装了但没装满」。

所以需要一个显式的**状态契约**：shell 端跑的时候把「我看到了什么」写下来，
macview 直接读，不猜。

---

## 设计原则

1. **公开仓库不点名私有文件。**
   公开仓库里只出现**模式**（glob、目录），不出现具体的私有文件名。
   理由：具名等于把私有结构写进公开历史，而且加第二个来源时就要改公开文件。
   （这条是 `greened/dotfiles-public` 的做法，经过验证。）

2. **缺失是正常状态，不是错误。**
   私有可能整个不存在。契约必须能表达「没有」，且不把它当失败。

3. **报告「效果」，不只报告「文件存在」。**
   文件在、但内容是占位符（`cole@coles-Virtual-Machine.local`）等于没配。
   契约要能区分「有文件」和「真的生效了」。

4. **契约是数据，不是逻辑。**
   shell 端写、macview 读。macview 不需要执行 shell 就能知道状态。

5. **向后兼容、向前可扩展。**
   加字段不破坏旧读取方；`version` 变化才是不兼容。

---

## 契约文件的位置

```
~/.config/dotfiles/private-state.json
```

放在 `~/.config/dotfiles/` 下，和现有的 `os.zsh`、`ohmyzsh.plugins.zsh` 同目录。
它是**生成物**，不进仓库、不该手改（手改会被下次运行覆盖）。

- 权限：`0600`（内容可能含邮箱、主机名）
- 写入方式：**原子写**（`mktemp` + `mv`），避免 macview 读到半截

---

## 格式

```jsonc
{
  "version": 1,

  // 什么时候、被谁写的
  "checked_at": "2026-09-23T12:00:00Z",
  "generated_by": "install.zsh 1.0.0",   // 或 "prompt-once.zsh" 等

  // 私有源本身（数据从哪来）
  "source": {
    "kind": "none",          // none | git | dir | cloud
    "path": null,            // git/dir 时的本地路径
    "remote": null,          // git/cloud 时的远程地址
    "present": false,        // 本地是否已经拿到
    "detail": null           // 失败原因等自由文本，给界面显示
  },

  // 四个落点，每个一条
  "slots": [
    {
      "id": "zshrc",
      "target": "~/.zshrc.local",
      "loaded_by": "~/.zshrc",          // 谁来读它（帮助用户理解）
      "status": "missing",              // ok | missing | incomplete | placeholder
      "effect": null                    // status=ok 时才有意义，见下
    }
    // …gitconfig / envconfig / ssh，共四条
  ]
}
```

### `source.kind` 的含义

| 值 | 含义 | 对应现实 |
|---|---|---|
| `none` | 用户没配私有源 | 最常见、完全正常 |
| `git` | 私有源是一个 git 仓库（当前唯一实现的形态） | `~/dotfiles-local` 之类 |
| `dir` | 私有源是一个普通目录（没进 git） | 手动放的 |
| `cloud` | 私有源由云服务提供（**预留，未实现**） | 将来 macview 的服务 |

> `cloud` 现在**只占位**。契约里留好它，是为了将来接服务时 macview 不用改格式。
> 在实现之前，没有代码会产出这个值。

### `slots[].status` 的四个值

这是契约的核心 —— 四态，不是二态：

| status | 含义 | macview 该显示成 |
|---|---|---|
| `ok` | 文件在，且**效果**验证通过 | ✅ 正常 |
| `missing` | 私有源里没这一项，或没配私有源 | ⚪ 可选（不是错误） |
| `incomplete` | 该项**应该**在（源里声明了）但落地失败 / 链接悬空 | 🔴 这是 bug，要修 |
| `placeholder` | 文件在，但内容还是占位/模板值 | 🟡 提醒用户去填 |

**`missing` 和 `incomplete` 的区别是这份契约存在的全部理由。**

- `missing`：源里压根没有 → 用户没打算配 → 不该报警
- `incomplete`：源里**有**，但没落到 `$HOME`（链接断、复制失败、权限不对）
  → 这是配置错误，必须显式报出来（对应 `greened` 的 `stale link` 报告）

### `slots[].effect`：验证「真的生效了吗」

`status = ok` 时填一个**实际解析出来的值**，而不是「文件存在」：

```jsonc
// gitconfig 槽位
{ "id": "gitconfig", "status": "ok",
  "effect": { "user.email": "cole@example.com", "user.name": "cole" } }

// ssh 槽位
{ "id": "ssh", "status": "ok",
  "effect": { "hosts": ["github-work", "internal-git"] } }   // 私有 host 名列表

// zshrc / envconfig 槽位
{ "id": "zshrc", "status": "ok",
  "effect": { "exports": 12 } }      // 或者别的可验证的量化指标
```

这三个对象分别要塞进上面 `slots[]` 里对应元素的位置（上面为了简洁只留了
`zshrc` 一条）。

为什么要这样：研究里 chezmoi 的 `verify` 和 sops-nix 的求值期校验都说明 ——
**「文件存在」不等于「配置生效」**。占位邮箱的文件是存在的，但 commit 出来是错的。

---

## 公开仓库这一侧要怎么配合（改动清单，暂未实施）

契约要成立，公开仓库得先满足两个条件：

### 1. SSH 从具名改成 glob

**现在**（公开仓库点名了私有文件）：

```
Include ~/.ssh/config.local          # prompt-once.zsh 第 158 行
```

**改成**：

```
Include ~/.ssh/conf.d/*              # 私有源往 conf.d/ 里放任意多个文件
```

已验证（OpenSSH 10.2，本机）：

- ✅ glob 无匹配 → 静默忽略，不报错
- ✅ `conf.d/` 目录不存在 → 静默忽略，不报错
- ✅ 多个文件按**字典序**加载
- ⚠️ **`Include` 的位置决定优先级**（SSH 是 first-match-wins）：
  - 放**顶部** → 私有源里的 `Host` 块胜出
  - 放**底部** → 公开仓库的 `Host` 块胜出

  对「私有覆盖公开」的语义，应该放**顶部**。这一点必须在实施时写进注释。

> 迁移注意：已经装了 `~/.ssh/config.local` 的机器（比如本机），
> 改成 glob 后那个文件不再被读。实施时要处理迁移（检测到旧行就替换，
> 并把已有的 `config.local` 移进 `conf.d/`，或保留一条兼容 Include）。

### 2. 状态产出点

需要在「shell 端跑到相关步骤时」产出契约文件：

| 产出时机 | 谁写 | 覆盖哪些槽位 |
|---|---|---|
| `install.zsh` 的 prompt-once 步骤 | `prompt-once.zsh` | 全部（此时刚处理完 gitconfig / ssh） |
| 单独的检测命令（待定） | 新增脚本 | 全部（macview 主动调用时） |

---

## macview 这一侧要怎么用（暂未实施）

1. 读 `~/.config/dotfiles/private-state.json`
2. 文件**不存在** → 说明还没跑过 install → 显示「还没检测过」，而不是「没配」
3. 按 `slots[].status` 做**四态**渲染（见上表）
4. `source.kind = cloud` 时走服务的 UI（将来）
5. **不要自己推断** —— 有契约就信契约，没契约就显示「未知」

---

## 尚未决定的事

契约冻结前要拍板：

- [ ] `slots` 用数组还是对象（数组顺序稳定、对象查表快）
- [ ] `effect` 的字段是否要按槽位分别定义（现在比较自由）
- [ ] 检测命令的入口：`install.zsh private` 子命令？还是独立脚本？
- [ ] `generated_by` 的版本怎么取（仓库没有版本号）
- [ ] 契约文件不存在时，macview 的文案

---

## 参考

这份契约的设计依据来自 `macview` 的调研文档
（`macview/notes/public-base-private-overlay-research.md`），关键几条：

- **§7.1** 公开仓库不点名私有文件 → 用 glob（→ 本文「设计原则 1」、SSH 改造）
- **§7.2** 验证效果而非文件存在 →（→ 本文 `effect` 字段）
- **§7.3** 两级报告：未安装 vs 装了但不全 →（→ 本文 `missing` vs `incomplete`）
- **§3** 业界普遍没有 overlay 验证器，`greened` 的 stale-link 报告是例外 → 这正是 macview 的机会
