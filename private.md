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

5. **读取方永远不需要「推断」。**
   每个判断依据都必须是字段本身，而不是字段的组合推理或外部约定。
   反例（已避免）：「`~/.ssh/config.local` 不存在」到底算 `absent` 还是
   `incomplete`？光看 target 无法判断 —— 必须有 `source_rel` 作为依据。

6. **向后兼容、向前可扩展。**
   加字段不破坏旧读取方；`version` 变化才是不兼容（读取规则见下）。

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

  // 什么时候、被谁写的。时间戳用 Unix 秒（整数），避免各家日期格式不一致：
  // macview 是 Swift，ISO8601DateFormatter 默认不接受小数秒，容易解析失败。
  "checked_at": 1790147806,
  "generated_by": "private-state.zsh",   // 产出脚本名

  // 私有源本身（数据从哪来）
  "source": {
    "kind": "none",          // none | git | dir | cloud
    "path": null,            // git/dir 时的本地绝对路径（无 ~，读取方直接可用）
    "remote": null,          // git/cloud 时的远程地址
    "present": false,        // 本地是否已经拿到
    "detail": null           // 与源整体相关的补充说明（失败原因等），见「detail 的语义」
  },

  // 四个落点，每个一条。数组有序，展示顺序即此顺序。
  "slots": [
    {
      "id": "zshrc",
      "source_rel": "zshrc.local",     // 源内相对路径；据此判断「源声明了这一项吗」
      "target": "/Users/you/.zshrc.local",  // 绝对路径（读取方直接用，不做 ~ 展开）
      "loaded_by": "/Users/you/.zshrc",     // 谁来读它（帮助用户理解）
      "status": "absent",              // ok | absent | incomplete | placeholder
      "effect": null                   // status=ok 时才有意义，见下
    }
    // …gitconfig / envconfig / ssh，共四条
  ]
}
```

### `slots[].source_rel`：契约的核心字段

**「源里有没有这一项」只能靠它判断** —— 这正是 `absent` 和 `incomplete`
能区分开的原因。

检测器逻辑一句话：

```
源里 <source.path>/<source_rel> 存在吗？
  ├─ 不存在            → 源没声明这一项 → absent
  └─ 存在              → 声明了 → 再看有没有落到 target → ok / incomplete / placeholder
```

为什么用「每个槽位带源内相对路径」而不是「源级一个 declares 列表」：

- 不需要在检测器里硬编码「id → 源内路径」的映射表
- 能表达**任意嵌套** —— `ssh` 是 `ssh/config.local`（带子目录），
  其它是平铺一个文件，同一个字段两种都写得出来
- 加第五个槽位时只加一条 slot，不动源级字段

### `version`：读取方遇到不认识的版本怎么办

原则 6 说「加字段不破坏旧读取方」—— 那是指**同一 version 内**加字段。
跨 version 必须显式处理：

- **读取方看到 `version` > 自己已知的** → **不要尝试解析**，显示
  「状态文件来自更新的版本，请升级 macview」，并提供「重新检测」按钮。
  宁可说不知道，也不要误报。
- **`version` < 已知** → 尽力解析；缺的字段按 `null` / 空处理。
- **没有 `version` 字段** → 视为损坏，同「文件不存在」处理。

这就是为什么 `version` 必须是**整数且从 1 起递增**，而不是字符串。

### `detail` 的语义

`source.detail` **只放与整个源相关的说明**，典型就是「源拿不到」的原因：

```jsonc
{ "kind": "git", "present": false,
  "detail": "git clone 失败：Repository not found" }
```

- **它不是「错误字段」** —— `present = true` 时通常是 `null`。
- 槽位级的失败**不要**写这里 —— 用该槽位的 `status = "incomplete"`，
  文案由 macview 自己组织。`detail` 只是给「源整体」兜底的自由文本。
- 需要更细的机器可读错误码时再扩展，当前保持自由文本。

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
| `ok` | target 在，且**效果**验证通过 | ✅ 正常 |
| `absent` | **源里没这一项**（`source_rel` 不存在） | ⚪ 可选（不是错误） |
| `incomplete` | 源里**有**，但没落到 target（链接断 / 复制失败 / 权限不对） | 🔴 这是 bug，要修 |
| `placeholder` | target 在，但内容还是占位 / 模板值 | 🟡 提醒用户去填 |

判定表（检测器按下表产出，无歧义）：

| 源里有 `source_rel` 吗 | target 在吗 | 内容有效吗 | status |
|---|---|---|---|
| 否 | — | — | `absent` |
| 是 | 否 | — | `incomplete` |
| 是 | 是 | 占位 / 模板值 | `placeholder` |
| 是 | 是 | 有效 | `ok` |

**`absent` 和 `incomplete` 的区别是这份契约存在的全部理由。**

- `absent`：源里压根没有 → 用户没打算配 → **不该报警**
- `incomplete`：源里**有**，但没落到 `$HOME` → **这是配置错误，必须显式报出来**
  （对应 `greened` 的 `stale link` 报告）

#### 「根本没配私有源」怎么表示

**没有单独的 status 值。** 它就是 `source.kind == "none"` + **所有 slot 都是 `absent`**。

不把「没配源」塞进某个 slot 的 status，因为它是**源级**的事实，不是槽位级的事实。
macview 的判断规则（一条）：

```
if source.kind == "none"  → 显示「还没设置私有源（可选）」+ 引导
elif 存在 status == "incomplete" → 显示为 bug
...
```

这样 macview 永远不需要「推断」，只需按字段读。

### `slots[].effect`：验证「真的生效了吗」

`status = ok` 时填一个**实际解析出来的值**，而不是「文件存在」。

**`effect` 的约定（这是硬约定，不是示意）：**

> `effect` 是一个 **string → string 的扁平对象**，键是「可被一条命令验证的配置项」，
> 值是该命令在当前机器上**实际取到的值**。macview 只负责显示 `键: 值`，
> **不需要理解每个键的语义**。

```jsonc
// gitconfig 槽位：键就是 git config 的键名
{ "id": "gitconfig", "status": "ok",
  "effect": { "user.email": "cole@example.com", "user.name": "cole" } }

// ssh 槽位：私有 host 名，逗号分隔（扁平对象里不放数组）
{ "id": "ssh", "status": "ok",
  "effect": { "hosts": "github-work,internal-git" } }

// zshrc / envconfig 槽位：放一个能证明「真被加载了」的探针值
{ "id": "zshrc", "status": "ok",
  "effect": { "DOTFILES_PRIVATE_LOADED": "1" } }
```

- **值是 string**：类型统一，macview 不用分支处理数组 / 数字 / 布尔。
  需要表达列表时用**分隔字符串**（如上面的 `hosts`）。
- **不要放统计量**（如「导出了几个变量」）—— 那是健康度指标，不是「配置生效」
  的证据，塞进来会让读取方无法统一渲染。要统计量就另开字段（当前不需要）。
- **键必须是可验证的** —— 检测器要能真的跑出这个值来。填不出来的槽位
  `effect` 保持 `null`。

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

契约文件由**一个脚本**产出，两个调用方：

| 产出时机 | 谁调 | 覆盖哪些槽位 |
|---|---|---|
| `install.zsh` 的 prompt-once 步骤 | `prompt-once.zsh` 调 `private-state.zsh --write` | 全部（此时刚处理完 gitconfig / ssh） |
| macview 主动检测 | macview 调 `private-state.zsh --stdout` | 全部（只读，不落盘） |

`scripts/common/private-state.zsh` 只做一件事：检查四个槽位 → 输出 / 写入状态。
它**不装东西、不改 `$HOME`**（除了 `--write` 时的状态文件本身），
和 `brew-audit.zsh` 是同一类「只读检测器」。

---

## macview 这一侧要怎么用（暂未实施）

1. 读 `~/.config/dotfiles/private-state.json`（文件不存在 → 见第 2 步）
2. 文件**不存在 / 无 `version` / `version` 高于已知** → 显示「还没检测过」或
   「请升级 macview」，**不要**当成「没配私有源」
3. **`source.kind == "none"` 且所有 slot 为 `absent`** → 「还没设置私有源（可选）」
4. 按 `slots[].status` 做**四态**渲染（见上表）；`incomplete` 标成 bug
5. `source.kind = cloud` 时走服务的 UI（将来）
6. **不要自己推断** —— 有契约就信契约，没契约就显示「未知」

---

## 已决定 / 尚未决定

### 已决定

- [x] `slots` 用**数组**（有序；macview 是列表 UI，顺序本身是信息）
- [x] 「源声明了什么」用 **`slots[].source_rel`**，不用源级 `declares` 列表
      （免硬编码映射，且能表达 ssh 的嵌套）
- [x] `missing` 拆成 **`absent`**；「没配源」由 `source.kind == none` 表达
- [x] `effect` 是**扁平 string→string 对象**，只放可验证的配置键值
- [x] `checked_at` 用 **Unix 秒（整数）**
- [x] `target` / `loaded_by` 用**绝对路径**（读取方不做 `~` 展开）
- [x] `version` 的读取规则（高版本 → 拒绝解析并提示升级）
- [x] 检测入口：**独立脚本 `scripts/common/private-state.zsh`**，双 flag
      （`--write` 落盘给 prompt-once 用，`--stdout` 输出给 macview 用），
      一份检测逻辑两个调用方；**不做** `install.zsh private` 子命令
      （那会让 install 变成 macview 的入口，职责混乱）

### 尚未决定

- [ ] `generated_by` 的版本怎么取（仓库没有版本号 → 先写脚本名，不带版本）
- [ ] 槽位 `loaded_by` 在 target 尚未链接时填什么（源里的期望值？留 null？）
- [ ] `placeholder` 的判定标准（怎么算「占位」—— 字符串匹配？还是显式标记？）

---

## 参考

这份契约的设计依据来自 `macview` 的调研文档
（`macview/notes/public-base-private-overlay-research.md`），关键几条：

- **§7.1** 公开仓库不点名私有文件 → 用 glob（→ 本文「设计原则 1」、SSH 改造）
- **§7.2** 验证效果而非文件存在 →（→ 本文 `effect` 字段）
- **§7.3** 两级报告：未安装 vs 装了但不全 →（→ 本文 `absent` vs `incomplete`）
- **§3** 业界普遍没有 overlay 验证器，`greened` 的 stale-link 报告是例外 → 这正是 macview 的机会
