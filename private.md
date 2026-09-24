# 私有源（private source）契约

> 本文是**接口规格**，不是使用说明。它规定「公开仓库」和「用户的私有数据」
> 之间怎么交接，以及 macview 这个 GUI 怎么读到这件事。
>
> **状态：草案（v1 未冻结）。** 格式定下来之后，`install.zsh` 侧和 macview 侧
> 各自实现；在冻结前两边都别把它当稳定接口。

---

## 为什么要有这份契约

现在的情况：公开仓库有几个 `.local` 加载点（见 `README.md` 的「加载点」），
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

  // 五个落点，每个一条。数组有序，展示顺序即此顺序。
  // id / name / source_rel / target / loaded_by 的完整取值见
  // 上面「五个槽位的完整映射」表 —— 实现时照抄，不要自己猜。
  "slots": [
    {
      "id": "aliases",
      "name": "别名",
      "source_rel": "aliases",
      "target": "/Users/you/.aliases",
      "loaded_by": "/Users/you/.zshrc",
      "status": "absent",              // ok | absent | incomplete | placeholder
      "effect": null,                  // 仅 status=ok 时非 null，见下
      "why": null                      // 仅 status=incomplete 时非 null，见下
    },
    {
      "id": "zshrc-local",
      "name": "常用目录",
      "source_rel": "zshrc.local",
      "target": "/Users/you/.zshrc.local",
      "loaded_by": "/Users/you/.zshrc",
      "status": "absent",
      "effect": null,
      "why": null
    },
    {
      "id": "envconfig-local",
      "name": "环境变量 · 服务 · 代理",
      "source_rel": "envconfig.local",
      "target": "/Users/you/.envconfig.local",
      "loaded_by": "/Users/you/.envconfig",
      "status": "absent",
      "effect": null,
      "why": null
    },
    {
      "id": "git-local",
      "name": "git",
      "source_rel": "gitconfig.local",
      "target": "/Users/you/.gitconfig.local",
      "loaded_by": "/Users/you/.gitconfig",
      "status": "absent",
      "effect": null,
      "why": null
    },
    {
      "id": "ssh-local",
      "name": "ssh",
      "source_rel": "ssh/config.local",
      "target": "/Users/you/.ssh/config.local",
      "loaded_by": "/Users/you/.ssh/config",
      "status": "absent",
      "effect": null,
      "why": null
    }
  ]
}
```

### 和 macview 既有模型的关系（不冲突，是互补的）

macview 已经有一套 `Slot` / `SlotState`（`Sources/MacViewCore/Diff/LoadPoint.swift`）。
两套东西**管的不是同一件事**，所以都要保留：

| | macview 的 `SlotState` | 本契约的 `slots[].status` |
|---|---|---|
| 回答的问题 | **宿主文件里有没有那一行加载语句？** | **落点文件本身有没有、对不对？** |
| 例子 | `~/.gitconfig` 里有没有 `[include] path = ~/.gitconfig.local` | `~/.gitconfig.local` 在不在、内容是真是占位 |
| 现状 | 已实现，`slotPresence()`（LoadPoint.swift:263） | 本契约新增 |

macview 的 `SlotState` 里有个 `unchecked(why:)` —— **那正是它承认自己没查的那一半**。
本契约补的就是这一半。

所以：

- **slot 的 `id` / `name` 直接复用 macview 的 `declaredSlots`**（不要新造命名）：
  `aliases` / `zshrc-local` / `envconfig-local` / `git-local` / `ssh-local`
  —— macview 拿到 `id` 就能和它自己的 `Slot` 对上，不用维护映射表。
- 本契约的 `status` **不与** `SlotState` 合并。两套状态同时存在，
  macview 展示时可以并排："加载点：有 / 落点：占位"。

> macview 侧的改动是：新增一个读 `private-state.json` 的入口 + 一个四态 enum。
> 这是**新增**，不推翻它现有的 `SlotState` 逻辑。

### 私有源放在哪

**路径约定复用 macview 已有的 `PRIVATE_DIR`：**

```
代码里的读取顺序（macview Diff/Collect.swift:53-59 已有此逻辑）：
  PRIVATE_DIR 环境变量   ？用它
  : 默认                 ~/private-dotfiles
```

- 本契约的 `source.path` 填**这个约定解析出的绝对路径**，不另立名字。

### 五个槽位的完整映射（实现时照抄，不要自己猜）

`source_rel` 是**源里的相对路径**；`target` / `loaded_by` 是 `$HOME` 下的
**绝对路径**（下表用 `~/` 示意，产出时展开）。

| `id` | `name` | `source_rel`（源内） | `target`（落点） | `loaded_by`（谁读） |
|---|---|---|---|---|
| `aliases` | 别名 | `aliases` | `~/.aliases` | `~/.zshrc` |
| `zshrc-local` | 常用目录 | `zshrc.local` | `~/.zshrc.local` | `~/.zshrc` |
| `envconfig-local` | 环境变量 · 服务 · 代理 | `envconfig.local` | `~/.envconfig.local` | `~/.envconfig` |
| `git-local` | git | `gitconfig.local` | `~/.gitconfig.local` | `~/.gitconfig`（`[include]`） |
| `ssh-local` | ssh | `ssh/config.local` | `~/.ssh/config.local` | `~/.ssh/config`（`Include`） |

> `aliases` 的源内文件名**没有 `.local` 后缀** —— 这是刻意的：它落到的
> `target` 本来就叫 `~/.aliases`，源里跟它同名即可，不要自作主张改成
> `aliases.local`。其它四个带 `.local`，是因为它们的 `target` 带 `.local`。
> **规则一句话：源内名 = `target` 的 basename。**（`ssh-local` 例外，
> 它多一层 `ssh/` 目录。）


### 状态文件为什么放在 `~/.config/dotfiles/`

macview 现有的三个 JSON 全在 `~/Library/Application Support/macview/`，
它**从不读外部脚本生成的 JSON** —— 所以这个文件是它要新增的一个读点。

即便如此仍放 `~/.config/dotfiles/`，理由：

- 它是 **dotfiles 侧的产物**（由 `private-state.zsh` 生成），不是 macview 的内部状态。
- 和已有的 `os.zsh` / `ohmyzsh.plugins.zsh` 同目录，语义一致（「dotfiles 放在这」）。
- 用户不装 macview 时它照样有效（install.zsh 会写），**不把数据绑死在 GUI 上**。
- macview 哪天卸载了，这个文件还在，命令行侧照常工作。

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
| `git` | 私有源是一个 git 仓库（当前唯一实现的形态） | `~/private-dotfiles`（`PRIVATE_DIR` 的默认值） |
| `dir` | 私有源是一个普通目录（没进 git） | 手动放的 |
| `cloud` | 私有源由云服务提供（**预留，未实现**） | 将来 macview 的服务 |

> 路径约定见上面「私有源放在哪」—— 复用 macview 的 `PRIVATE_DIR`（默认
> `~/private-dotfiles`），**不要另立名字**。
>
> `cloud` 现在**只占位**。契约里留好它，是为了将来接服务时 macview 不用改格式。
> 在实现之前，没有代码会产出这个值。

### `slots[].status` 的四个值

这是契约的核心 —— 四态，不是二态：

| status | 含义 | macview 该显示成 |
|---|---|---|
| `ok` | target 在，且**效果**验证通过（`effect` 能取到值） | ✅ 正常 |
| `absent` | **源里没这一项**（`source_rel` 不存在） | ⚪ 可选（不是错误） |
| `incomplete` | 源里**有**，但没落到 target；**或源整体没拿到** | 🔴 这是 bug，要修 |
| `placeholder` | 源里那份还是模板值（有哨兵） | 🟡 提醒用户去填 |

**检测的是「源」还是「target」—— 这是本契约最容易写错的地方，先记住：**

| 判定依据 | 读哪个文件 | 为什么 |
|---|---|---|
| 源里有没有这一项（`source_rel`） | **源** | 源的属性 |
| 内容是模板还是真值（哨兵） | **源** | 模板是源里的东西，`target` 是复制品时未必一样 |
| **`effect` 取到的值** | **`target`** | `ok` 要证明的是「**落到 `$HOME` 的这份真的生效了**」——源改好了但没链过去，不算 `ok` |

> 一句话：**「源里有没有」看源，「生效了吗」看 target。**
> 所以判定表第 4/5 行的 `effect`，读的是 `target` 文件（`~/.gitconfig.local` 等），
> 不是源里那份。否则「没链接」会被判成 `ok` —— 正好漏掉最该报的那个 bug。

判定表（检测器**按从上到下的顺序**判，先命中先定，无歧义）：

| # | 源拿到了吗 | 源里有 `source_rel` 吗 | 源文件有哨兵吗 | target 在吗 | `effect` 能取到值吗 | status |
|---|---|---|---|---|---|---|
| 0 | **否**（`present=false`） | — | — | — | — | **源级失败，见下** |
| 1 | 是 | 否 | — | — | — | `absent` |
| 2 | 是 | 是 | **有** | — | — | `placeholder` |
| 3 | 是 | 是 | 无 | **否** | — | `incomplete` |
| 4 | 是 | 是 | 无 | 是 | 能（至少一个非空值） | `ok` |
| 5 | 是 | 是 | 无 | 是 | 不能（全空 / 解析失败） | `incomplete` |

- **第 0 行（源没拿到）优先于一切。** `source.present = false` 时，
  检测器**无法判断**任何一个槽位「源里到底有没有」—— 因为源根本不在本地。
  所以**不能**把它们判成 `absent`（那会谎报成「用户没配这项」）。

  `present = false` 时，所有 slot 的 `status` 填 **`incomplete`**，
  并且 `source.detail` 写明原因（如 `git clone 失败：Repository not found`）。

  > ⚠️ **现实中这一行触发不了 —— 这是本契约的已知局限，不是 bug。**
  >
  > 「配了源但没 clone 下来」要能被认出来，本机必须**记得**这件事。
  > 但 `PRIVATE_DIR`（默认 `~/private-dotfiles`）只是一个**路径约定**：
  > 目录不在时，「配过但没了」和「从没配过」在磁盘上**一模一样**。
  > macview 也没有任何持久记录（`Diff/Collect.swift:57` 就是拼个默认路径）。
  >
  > 所以当前实现里：目录不在 ⇒ `kind = "none"` ⇒ 各槽位按「源里没有」走
  > （全 `absent`）。这是**诚实的**：本机确实没有任何证据说它曾经配过。
  > 想真正支持第 0 行，需要一个持久标记（比如把 `source.remote` 记在
  > 状态文件里、下次读回来）；那是**扩展**，`version` 不变，现在不做。
  >
  > 换言之：`source.detail` 当前只在「源在、但读它出问题」时才有值。
  这样 macview 一看就知道「源整体没拿到」，而不是「五项都没配」。

- **第 2 行优先于第 3 行**：源里那份还是模板 → 不管有没有链过去，都是
  `placeholder`。这样「复制了模板但还没链接」不会被误报成 `incomplete`
  （那会显得像 bug，实际只是还没填）。

- **第 3 行：target 不存在就到此为止，不再往后判。** 顺序是「**先看 target 在不在，
  在才去取 `effect`**」—— 不能先取 `effect` 再拿结果当判据：`effect` 是从
  `target` 读的，target 不在时它天然取不到值，先取就会把「没链接」和
  「链接了但内容空」**压成同一个 `incomplete`**，丢掉信息。两条判定各有各的
  含义，不要合并。

- **第 4/5 行**：`target` 在，才去**从 target** 取 `effect`。
  「取到至少一个非空值」就是 `ok`，取不到就是 `incomplete`（内容空 / 解析失败）。
  这是 `ok` 与 `incomplete` 的**唯一分界**，不需要另立「有效性」判据。

- **第 2 行与第 3/4/5 行的关系**：哨兵只在**源**里看。
  源里是模板 → `placeholder`，到此为止，不看 target、不取 `effect`
  （此时 `effect` 即使能取到也是假值，见「`slots[].effect`」一节）。

**`absent` 和 `incomplete` 的区别是这份契约存在的全部理由。**

- `absent`：源里压根没有 → 用户没打算配 → **不该报警**
- `incomplete`：源里**有**，但没落到 `$HOME` → **这是配置错误，必须显式报出来**
  （对应 `greened` 的 `stale link` 报告）

#### 「根本没配私有源」怎么表示

**没有单独的 status 值。** 它就是 `source.kind == "none"` + **所有 slot 都是 `absent`**。

不把「没配源」塞进某个 slot 的 status，因为它是**源级**的事实，不是槽位级的事实。

**注意与「配了但没拉下来」的区别** —— 后者是 `kind = "git"` 且
`present = false`，此时 slot 全是 `incomplete`（见判定表第 0 行），
**不会**满足下面这条规则。两者不会混淆：

| 情况 | `source.kind` | `source.present` | 所有 slot | macview 显示 |
|---|---|---|---|---|
| 没配私有源 | `none` | `false` | 全 `absent` | 「还没设置私有源（可选）」 |
| 配了但没拉下来 | `git` / `dir` | `false` | 全 `incomplete` | 「私有源拿不到」+ `source.detail` |
| 配了、拉下来了 | `git` / `dir` | `true` | 按判定表 | 逐项显示 |

macview 的判断规则：

```
if source.kind == "none" and 所有 slot == absent  → 「还没设置私有源（可选）」+ 引导
elif source.present == false                      → 「私有源拿不到」+ 显示 source.detail
elif 存在 status == "incomplete"                  → 显示为 bug
elif 存在 status == "placeholder"                 → 提醒去填
...
```

这样 macview 永远不需要「推断」，只需按字段读。

#### `placeholder` 的判定：显式哨兵

**问题**：怎么算「占位值」？靠猜值长什么样吗？

**答案：不猜。源里的模板文件自带一个哨兵注释，用户填完真值后删掉它。**
检测器只做一件事 —— **看哨兵在不在**。

哨兵是**文件第一行**的固定字符串：

```
# dotfiles:placeholder
```

**读哪个文件**：读**源里的**那个文件，即 `<source.path>/<source_rel>`；
**不读** `target`。理由：

- 哨兵是**源模板的属性**，不是落点文件的属性。
- `target` 是软链接时读它等于读源，但 `target` 是**复制**时就未必 ——
  依赖 `target` 会让结果随链接方式而变。
- 有了 `source_rel` 就能直接定位源文件，**不需要 readlink 跟随**，
  也避免了「target 是悬空链接」时的读取错误。

判定：

| 源文件里有哨兵吗 | status |
|---|---|
| 有 | `placeholder`（**只看源**：不管 target 在不在、内容如何，到此为止） |
| 无 | 继续按判定表走 —— **此时才去看 target**（`incomplete` / `ok`） |

> 两个问题读两个不同的文件，别混：**哨兵看源，生效看 target**。

**为什么用哨兵，而不是匹配 `Your Name` / `your@email.com` 这类已知占位串：**

- **黑名单永远不全。** 模板里的占位可能是 `Your Name`，也可能是 `张三`、
  `changeme`、`<你的邮箱>`…… 换个语言或换个模板就漏。检测器一旦漏判，
  用户就拿着一个「看起来 OK」的错配置在提交代码。
- **假阳性更糟。** 有人真叫 `Li Hua`、真用 `li@example.com`，被规则误判成
  「没填」，用户会学会忽略这个警告 —— 警告就废了。
- **哨兵是确定的。** 在 → 一定没填；不在 → 一定填过（或用户从没用过模板）。
  零猜测、零假阳性、语言无关。

**为什么哨兵用注释：**

- gitconfig / zshrc / envconfig / ssh config **四种语法里 `#` 都是注释**
  （已实测；ssh 的注释须在行首，所以哨兵固定放**第一行**）。
- 带哨兵的文件**功能完全正常** —— git / zsh / ssh 都会忽略它。
  所以「用户先复制模板、晚点再填」这个中间状态不会把任何东西弄坏，
  只是状态显示为 `placeholder`（🟡）。

**用户视角**：复制模板 → 状态黄（提醒填）→ 填真值 + 删哨兵 → 状态绿。
删哨兵这一步比「记得把每个值都改对」容易得多，而且**不删就一直黄**，
不会静默滑过去。

> 模板由私有源提供（不在公开仓库里，见设计原则 1），但公开仓库的文档
> 会告诉用户哨兵这个约定 —— 它是**公开协议**，不是私有约定。

### `slots[].why`：为什么是 `incomplete`

**只在 `status = incomplete` 时非 null，其余三态一律 `null`。**

`incomplete` 有**四种**成因，光看 status 分不出来，而用户的下一步动作不同：

| 何时 | `why` 举例 | 用户该做什么 |
|---|---|---|
| 源里有、target 没有 | `源里有，但没落到 /Users/you/.gitconfig.local` | 跑 install / 检查链接 |
| target 在、内容取不到值 | `target 在，但取不到任何验证值（内容为空 / 解析失败）` | 填值 |
| 源整体没拿到 | `私有源已被配置，但本地不存在` | 拉私有源 |

> 这是设计原则 5「读取方永远不需要推断」的落实：macview 要显示
> 「为什么红」，就该有个字段直接告诉它，而不是让它按 status 去猜。
>
> 它是**给人看的自由文本**，不是机读错误码。需要机读码时再扩展，
> `version` 不变。macview 不认识这个字段时忽略即可（向后兼容）。

### `slots[].effect`：验证「真的生效了吗」

**`effect` 只在 `status = ok` 时非 null。** 其它三个状态（`absent` /
`incomplete` / `placeholder`）一律填 `null`：

| status | `effect` |
|---|---|
| `ok` | 对象，至少一个非空值 |
| `absent` / `incomplete` / `placeholder` | `null` |

> 为什么 `placeholder` 也是 `null`：源里那份还是模板，探针取到的值没有意义
> （取到的会是 `your@email.com` 这种假值）。填了反而误导 macview
> 「看起来有值」。**没填好就是没填好，不给部分结果。**

**`effect` 从 `target` 取，不从源取。** 理由：`ok` 的含义是「**落到 `$HOME` 的
那份真的生效了**」。源改好了、但没链过去（或链的是旧副本），不算 `ok`。
从源取值会把这种情况判成 `ok`，正好漏掉最该报的 bug。

**`effect` 也是判定 `ok` / `incomplete` 的唯一依据** —— 见判定表第 4/5 行：

> 「`effect` 能取到至少一个非空值」 ⇔ `ok`
> 「取不到（全空 / 解析失败）」 ⇔ `incomplete`

所以检测器**不需要**另写一套「内容有效性」判据 —— `effect` 能不能产出，
就是那个判据。这两个东西是同一件事，不要实现成两套。

> 注意判定顺序：**先确认 target 在，才去取 `effect`**（判定表第 3 行在前）。
> 顺序反了会把「没链接」和「链接了但内容空」压成同一个 `incomplete`。

**`effect` 的约定（这是硬约定，不是示意）：**

> `effect` 是一个 **string → string 的扁平对象**，键是「可被一条命令验证的配置项」，
> 值是该命令在当前机器上**实际取到的值**。macview 只负责显示 `键: 值`，
> **不需要理解每个键的语义**。

```jsonc
// git-local 槽位：键就是 git config 的键名
{ "id": "git-local", "status": "ok",
  "effect": { "user.email": "cole@example.com", "user.name": "cole" } }

// ssh-local 槽位：私有 host 名，空格分隔（扁平对象里不放数组）
{ "id": "ssh-local", "status": "ok",
  "effect": { "hosts": "github-work internal-git" } }

// zshrc-local / envconfig-local 槽位：放一个能证明「真被加载了」的探针值
{ "id": "zshrc-local", "status": "ok",
  "effect": { "DOTFILES_PRIVATE_LOADED": "1" } }

// aliases 槽位：**没有探针**（它是别名清单，本来就该一直有内容）。
// 生效判据 = 能从 target 里解析出别名。值先给个数 + 前几个名字。
{ "id": "aliases", "status": "ok",
  "effect": { "aliases": "12: gs,ga,gc 等" } }
```

- **值是 string**：类型统一，macview 不用分支处理数组 / 数字 / 布尔。
  需要表达列表时用**分隔字符串**（如上面的 `hosts`）。
- **不要放统计量**（如「导出了几个变量」）—— 那是健康度指标，不是「配置生效」
  的证据，塞进来会让读取方无法统一渲染。要统计量就另开字段（当前不需要）。
- **键必须是可验证的** —— 检测器要能真的跑出这个值来。跑不出来的槽位
  就是 `incomplete`（`effect` 为 `null`），不会是 `ok`。

**每个槽位怎么证明「生效了」—— 三种，别混：**

| 槽位 | 判据 | 为什么是它 |
|---|---|---|
| `zshrc-local` / `envconfig-local` | 真的 source 一遍，取 `DOTFILES_PRIVATE_LOADED` | 这两个文件的内容本来就是「填进去的变量」，探针顺理成章 |
| `git-local` | `git config --file <target> --get user.name / user.email` | 用 git 自己解析，不手写 INI |
| `ssh-local` | 从 target 里解析 `Host` 名（排除 `*` 通配） | 只读一行字，不验证连通性 |
| `aliases` | 从 target 里解析 `alias <名>=<命令>`，数出至少一个 | **它没有「填了没」的问题** —— 别名文件本来就有内容；判据只能是「解析得出来吗」 |

> `aliases` 的解析规则**和 macview 的 `parseAliases`
> （`Settings/Inspect.swift:438`）保持一致**：跳过 `#` 行、要求行首是
> `alias `、可有可无的 `--`、取第一个 `=` 左边。两边不一致 → 界面数字对不上。

为什么要这样：研究里 chezmoi 的 `verify` 和 sops-nix 的求值期校验都说明 ——
**「文件存在」不等于「配置生效」**。占位邮箱的文件是存在的，但 commit 出来是错的。

### `loaded_by`：target 还没链接时填什么

`loaded_by` 是**静态约定**，不是运行时事实 —— 它表达「这一项设计上由谁读」，
和当前有没有链接成功**无关**。取值见上面「五个槽位的完整映射」表。

理由：

- **它是给用户看的解释**（「我往 `.zshrc.local` 写了东西，谁读它？」）。
  即使这一项是 `absent` / `incomplete`，这个解释**依然成立**、依然有用。
- 如果「没链接时留 null」，macview 就得为每个状态分支处理 `loaded_by` 的
  空值，而它本来是个常量 —— 徒增复杂度。
- `loaded_by` 用**绝对路径**（同 `target` 的约定，读取方不展开 `~`）。

> 一句话：`loaded_by` 描述**设计**，`status` 描述**现状**。两者互不影响。

### `generated_by`：不带版本号

仓库当前**没有版本号**机制，为契约单独造一个是过度设计。规定：

```jsonc
"generated_by": "private-state.zsh"    // 就是脚本名，不带版本
```

- 只用来**排查问题**（「这个文件是哪个脚本写的」），不参与任何逻辑判断。
- 将来若真有了版本号机制，再改成 `"private-state.zsh 1.2"`，
  **不破坏读取方**（它只显示字符串）。
- 读取方**不要**对它做任何解析或断言。

---

## 公开仓库这一侧要怎么配合（改动清单，暂未实施）

契约要成立，公开仓库得先满足两个条件：

### 1. SSH 具名 → glob（**暂缓：跨仓库，需两边一起改**）

**这条不能单方面改。** macview 的 `sshIncludePaths()`（LoadPoint.swift:211-225）
专门解析 `Include config.local`，`declaredSlots` 的 ssh snippet 也写死
`Include config.local`，`SSHPage` 用 `text.contains("config.local")` 判断。
**dotfiles 先改，macview 的 ssh 检测会直接失效。**

所以顺序必须是：

1. macview 先支持 glob（`sshIncludePaths` 认 `Include ~/.ssh/conf.d/*`）
2. dotfiles 再切（`prompt-once` 改写 glob）
3. 两边都处理老机器的迁移

**在那之前，保持现状**：`Include ~/.ssh/config.local`。

下面记下已完成的可行性验证，实施时直接用。

**现在**（公开仓库点名了私有文件）：

```
Include ~/.ssh/config.local          # prompt-once.zsh 第 158 行
```

**目标**：

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

`scripts/common/private-state.zsh` 只做一件事：检查**五个**槽位 → 输出 / 写入状态。
它**不装东西、不改 `$HOME`**（除了 `--write` 时的状态文件本身），
和 `brew-audit.zsh` 是同一类「只读检测器」。

---

## macview 这一侧要怎么用（暂未实施）

1. 读 `~/.config/dotfiles/private-state.json`（文件不存在 → 见第 2 步）
2. 文件**不存在 / 无 `version` / `version` 高于已知** → 显示「还没检测过」或
   「请升级 macview」，**不要**当成「没配私有源」
3. **`source.kind == "none"` 且所有 slot 为 `absent`** → 「还没设置私有源（可选）」
4. **`source.present == false`（但 `kind != none`）** → 「私有源拿不到」，
   并列显示 `source.detail`；此时 slot 都是 `incomplete`，**不要**当 bug 逐条报
5. 按 `slots[].status` 做**四态**渲染（见上表）；`incomplete` 标成 bug
6. `source.kind = cloud` 时走服务的 UI（将来）
7. **不要自己推断** —— 有契约就信契约，没契约就显示「未知」。
   （唯一例外是第 10 条的时间新鲜度：那是契约**要求**你算的，不算推断。）
8. `slots[].id` 与它的 `declaredSlots` 对齐，**直接按 id 关联**，不维护映射表
9. 它现有的 `SlotState`（宿主文件里有没有加载行）**继续保留**，与本契约的
   `status`（落点文件状态）**并排展示**，两者互补不冲突
10. **`checked_at` 是快照时间，不是实时状态。** 这个文件只在 `install.zsh`
    跑的时候刷新 —— 之后用户手动删了某个落点文件、或把私有源挪走了，
    JSON 里的 `status` **仍然是旧的**（还会说 `ok`），直到下次跑安装。

    所以**必须按 `checked_at` 判断新鲜度**，不能把 `status` 当实时真值。
    建议：读取时拿当前时间和 `checked_at` 比，超过一个阈值就把它当
    **参考值**而不是结论，标成「上次检测于 X 之前」；`ok` 这类正面状态
    尤其要标（「现在可能已经不是了」）。

    阈值取多少留给 macview（那是 UI 决策），但**不能不看 `checked_at`**。
    这个字段存在就是为了新鲜度 —— 不看它，它就是个死字段。

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
- [x] `placeholder` 用**源内注释哨兵** `# dotfiles:placeholder`（文件第一行）
      判定，不做值黑名单匹配 —— 见「`placeholder` 的判定」
- [x] `placeholder` 读**源文件**（`<source.path>/<source_rel>`），不读 `target`
- [x] slot 的 `id` / `name` **复用 macview 的 `declaredSlots`**（五个：
      `aliases` / `zshrc-local` / `envconfig-local` / `git-local` / `ssh-local`）
- [x] 私有源路径复用 macview 已有的 `PRIVATE_DIR` 约定（默认 `~/private-dotfiles`）
- [x] SSH 具名 → glob **暂缓**：跨仓库，须 macview 先支持 glob 再切 dotfiles
- [x] `loaded_by` 是**静态约定**（设计上谁读），target 没链接时**照常填**，
      不留 null
- [x] `generated_by` **不带版本号**，就写脚本名，只供排查、不参与逻辑
- [x] 「内容有效」= **`effect` 能取到至少一个非空值**；`ok`/`incomplete` 的
      分界就是它，不另写一套有效性判据
- [x] `source.present == false`（配了源但没拉下来）→ 所有 slot 填
      **`incomplete`** + `source.detail`，**不得**报 `absent`（那会谎报成没配）
- [x] `aliases` 的源内文件名**就叫 `aliases`**（无 `.local`）——
      规则：源内名 = target 的 basename（`ssh-local` 例外，多一层目录）
- [x] `effect` 仅在 `status=ok` 时非 null；其它三态一律 `null`
- [x] 五个槽位的 `source_rel` / `target` / `loaded_by` **在文档里列全**，
      实现照抄不用猜
- [x] **检测对象分流**：`source_rel` / 哨兵读**源**；`effect` 读 **`target`**
      （`ok` = 「落到 `$HOME` 的那份生效了」，源对了但没链过去不算）
- [x] 判定顺序**先看 target 在不在，再取 `effect`**；两条判定不可合并
      （合并会把「没链接」和「链接了但内容空」压成同一个 `incomplete`）
- [x] 新增 `slots[].why`：**仅 `incomplete` 时非 null**，说明是哪一种成因
      （给人看的自由文本，非机读码；未知字段读取方忽略即可）
- [x] `aliases` 的生效判据 = **能从 target 解析出至少一个 `alias`**，
      解析规则与 macview 的 `parseAliases`（`Settings/Inspect.swift:438`）一致
- [x] `present = false`（配了源没拉下来）**当前无法触发** ——
      没有持久记录能区分「配过但没了」和「从没配过」，详见判定表第 0 行的说明。
      要做需要扩展（记住 `source.remote`），现在不做

### 尚未决定

（暂无。实现中若发现新的分歧点，追加到此处再定。）


---

## 参考

这份契约的设计依据来自 `macview` 的调研文档
（`macview/notes/public-base-private-overlay-research.md`），关键几条：

- **§7.1** 公开仓库不点名私有文件 → 用 glob（→ 本文「设计原则 1」、SSH 改造）
- **§7.2** 验证效果而非文件存在 →（→ 本文 `effect` 字段）
- **§7.3** 两级报告：未安装 vs 装了但不全 →（→ 本文 `absent` vs `incomplete`）
- **§3** 业界普遍没有 overlay 验证器，`greened` 的 stale-link 报告是例外 → 这正是 macview 的机会
