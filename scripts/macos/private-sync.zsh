#!/usr/bin/env zsh
#
# 私有配置的同步**状态**：比对「中转目录」和「本机生效目录」两边各是什么样。
# **只读** —— 不复制、不备份、不动任何一边（2026-09-29 起动作也移走了，见下）。
#
# ## 为什么要有这个脚本（而不直接用 git）
#
# 私有仓库**不用 git** —— 同步由外部系统提供，这里只定义两端的交接：
#
#   中转目录（CARRIER）  ←→  本机生效目录（LIVE_DIR = ~/private-dotfiles）
#
#   · CARRIER：同步系统放文件的地方（网盘目录、U 盘、你们自己的同步服务
#     落盘的位置）。本脚本**不关心它怎么来的**，只认「里面有没有那几个文件」。
#   · LIVE_DIR：shell 真正读的地方（`~/.aliases` 等符号链接指过来）。
#     **只改这里，shell 才生效。**
#
# 现在用文件夹 copy 模拟：CARRIER 就是你指定的一个目录。以后换成真正的
# 同步服务，只要它能把文件落到一个目录，这个脚本**一个字都不用改** ——
# 交接面就是「一个目录」，不是某个协议。
#
# ## 只有一个子命令
#
#   status  看两边每个文件是「一致 / 不一致 / 只在一边」。**只读。**
#           加 `--json` 时**连文件内容一起列出来**（见下），给 macview 读。
#
# ## 同步动作（拿过来 / 交出去）在哪：**macview**（2026-09-29 用户定）
#
# 原来这里还有 pull / push。用户拍板「**同步功能只在 GUI 上有**」——
# 状态查脚本、动作做进界面（和 git 页同一待遇：那一页也没有辅助脚本，
# add/commit/push 是 macview 自己做的）。所以：
#
#   · 动作已从本脚本删除；语义（方向、覆盖前备份、已知名单、gitconfig
#     进场、幂等、中转目录前置检查）记录在 macview-contract.md
#     「三、编辑侧 · 私有同步动作」，实现在 macview 里；
#   · 本脚本收到 pull / push 参数 → 打一句去处提示、退出 1（不静默）。
#
# ## 要不要列内容（2026-09-28 用户定的：**列，含 token 明文**）
#
# `status --json` 的每个文件带 `content_carrier` / `content_live` ——
# **两边都给**。给两边是必须的：`differ` 时光看一边没法判断哪个对。
#
# **为什么列**：中转目录可能是网盘 / 共享位置。**「把要进去的东西列出来
# 看一眼」本身就是一道安全检查** —— 用户要在东西同步出去之前确认里面
# 有什么、该不该在里面。
#
# **⚠️ 代价（明写，不是反对）**：列出来意味着 token 明文会进 macview 的
# 内存和屏幕。屏保没锁 / 录屏 / 背后有人 = 泄。
# **但这些内容本来就在 `~/private-dotfiles` 里躺着** —— 不列也是同样的风险，
# 只是多了一层「没被打开过」的偶然保护。所以真正的风险不在「列」，
# 在**中转目录是不是共享的**（界面必须说清这一点）。
#
# **上限**：`MAX_LINES` 行 / `MAX_BYTES` 字节，先到先算；被截断时
# `truncated: true`。⚠️ 不封顶的话一个 5 MB 文件能把 JSON 撑爆，macview
# 解析失败 → 显示成「没能查」→ 什么都看不到。
#
# ## status 的纪律
#
# 1. **只读**：只比对、只列，绝不写任何一边（动作归 macview，见上）。
# 2. **只报事实，不报「该不该同步」**：「不一致」是事实；「该拿过来 / 交出去」
#    是判断 —— 判断归界面和用户，脚本不掺。
# 3. **只认已知的 5 个文件**（+ `machine/` 子树，见下）：两边各自的多余文件
#    不进名单 —— 同步没有资格决定「这个文件该不该存在」。
# 4. 不联网、不提权；内容只进本机的 `--json`（给 macview 屏幕上看），
#    脚本不发送任何东西。
#
# 动作侧的对应纪律（中转目录像不像私有源、覆盖前备份、幂等）由 macview
# 执行，写在契约同一节 —— 那边删掉脚本动作时，规则跟着搬了家。
#
# ## status 比对哪几个文件
#
# 和 private-state.zsh 的槽位表是**同一份名单**（`source_rel` 那一列）：
# `aliases`、`zshrc.local`、`envconfig.local`、`gitconfig.local`、
# `ssh/config.local`，外加 `machine/` 子树（按机器分的文件，见下）。
#
# ⚠️ `gitconfig.local` 的落点常是**直写文件**：prompt-once 写
# `~/.gitconfig.local`（不是符号链接），而同步收发的是 LIVE 槽位 ——
# 天生不相连，直写的身份就永远不同步。**接上它们的进场（adopt）已随动作
# 移进 macview**：拿过来/交出去开跑前先把落点搬进 LIVE、落点换成指向它的
# 链（原文件备份，退得回）；两边都有且不一样 → **两边都不动、只报告** ——
# 哪份对是用户的判断，动作不替人决定。status 对没进场的落点**只提示、
# 不搬**（`do_status` 末尾那两行），永远只读。
# 身份（name/email）多机器一般是一样的；不一样就别同步它，
# 从中转目录里删掉那个文件（名单外的文件两边都不动）。
#
# ## machine/ 子树
#
# 机器特有的东西（比如只在工作电脑有的代理）不要塞进共享文件 ——
# 放 `machine/$(hostname).env`，在 `envconfig.local` / `zshrc.local` 末尾
# 按 hostname 分流 source。同步时整个 `machine/` 目录跟着走，
# 每台机器只读自己的那一份，互不污染。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LIVE_DIR="${PRIVATE_DIR:-$HOME/private-dotfiles}"

# 同步的文件名单：与 private-state.zsh 的 SLOTS 表 `source_rel` 列一致。
# ⚠️ 改这里要同步改那边 —— 两处各写各的会漂移（只差一个文件名，
# status 就会永远报「只在一边」）。
SYNC_FILES=(
  'aliases'
  'zshrc.local'
  'envconfig.local'
  'gitconfig.local'
  'ssh/config.local'
)
# 跟着走的子树（整个目录，有就同步，没有就跳过，不报错）。
SYNC_DIRS=(
  'machine'
)

usage() {
  cat <<EOF
Usage: zsh scripts/macos/private-sync.zsh status [options]

  status              比对 CARRIER 和 LIVE（只读，永远退出 0）
                      加 --json 时出结构化结果（含文件内容，给 macview 读）。

  ⚠️ --json **不要求** --carrier：没配中转目录也是一个**合法状态**
  （界面要显示「没配」，不是报错）。
  ⚠️ pull / push 已移进 macview（私有同步页）—— 本脚本只剩 status。

Options:
  --carrier <目录>    中转目录（默认：\$PRIVATE_SYNC_DIR；不给就是「没配」）
  --live <目录>       本机生效目录（默认：\$PRIVATE_DIR 或 ~/private-dotfiles）
  -h, --help          显示这段

退出码：
  0  成功（status 永远 0 —— 「没配」也是要显示的状态，不是失败）
  1  参数错 / 传了 pull 或 push（动作在 macview，脚本不代跑）
EOF
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage >&2; exit 1; }
shift || true

CARRIER="${PRIVATE_SYNC_DIR:-}"
AS_JSON=0
while (( $# > 0 )); do
  case "$1" in
    --carrier) CARRIER="${2:-}"; shift 2 ;;
    --live) LIVE_DIR="${2:-}"; shift 2 ;;
    --json) AS_JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# carrier **永远可空** —— 「没配中转目录」是界面**要显示的一个状态**
# （`carrier.set = false`），不是错误。缺了就当空字符串处理，比对自然
# 全是「只在本机」/「都没有」。（早先这里对 pull/push 无条件 exit 1 ——
# 那两个动作 2026-09-29 移进 macview 了，见文件头。）

# ── 小工具 ────────────────────────────────────────────────────────────────

# CARRIER 像不像私有源：5 个已知文件至少命中一个。
# 不像 → 极大概率是指错了路径，倒进去没有意义。
carrier_looks_like_private() {
  local f
  for f in "${SYNC_FILES[@]}"; do
    [[ -e "$CARRIER/$f" ]] && return 0
  done
  for f in "${SYNC_DIRS[@]}"; do
    [[ -e "$CARRIER/$f" ]] && return 0
  done
  return 1
}


# ── gitconfig.local 进场（已移进 macview）────────────────────────────────
#
# 背景没变：落点 `~/.gitconfig.local` 由 prompt-once **直写**（真实文件），
# 而同步收发的是 LIVE 槽位 —— 两者天生不相连，直写的身份永远不同步。
# 进场 = **只改落点形态**：内容搬进 LIVE（复制并校验）、落点换成指向它的链
# （原文件先备份，退得回）；**两边都有且不一样 → 两边都不动、只报告** ——
# 哪份对是用户的判断，动作不替人决定（结构动作可自动，价值判断不行）。
#
# 2026-09-29 动作移进 macview 时，`adopt_gitconfig` 连同 pull/push 一起
# 搬走了 —— 语义记录在 macview-contract.md「三、编辑侧 · 私有同步动作」，
# 实现在 macview 的同步动作里（搬完之后走通用逻辑，一处特判都不留）。
# status 对没进场的落点**只提示、不搬**（`do_status` 末尾那两行）。

# ── status（只读） ────────────────────────────────────────────────────────

do_status() {
  local f a b
  local same=0 diff=0 only_carrier=0 only_live=0
  for f in "${SYNC_FILES[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    if [[ -e "$a" && -e "$b" ]]; then
      if cmp -s "$a" "$b" 2>/dev/null; then
        echo "  = $f（一致）"; (( same++ )) || true
      else
        echo "  ≠ $f（两边不一样）"; (( diff++ )) || true
      fi
    elif [[ -e "$a" ]]; then
      echo "  → $f（只在中转目录，本机没有）"; (( only_carrier++ )) || true
    elif [[ -e "$b" ]]; then
      echo "  ← $f（只在本机，中转目录没有）"; (( only_live++ )) || true
    else
      echo "  · $f（两边都没有）"
    fi
  done
  echo "一致 $same · 不一致 $diff · 只在中转 $only_carrier · 只在本机 $only_live"
  # gitconfig.local 还没进场时提一句 —— 否则用户在这页看不出
  # 「为什么 git 身份没跟着同步」，只会以为同步坏了。
  # ⚠️ 只提示、不搬：status 永远只读（进场由 macview 的拉/推动作做）。
  if [[ -f "$HOME/.gitconfig.local" && ! -L "$HOME/.gitconfig.local" ]]; then
    if [[ -e "$LIVE_DIR/gitconfig.local" ]] \
       && ! cmp -s "$HOME/.gitconfig.local" "$LIVE_DIR/gitconfig.local" 2>/dev/null; then
      echo "提示: ~/.gitconfig.local 和私有源里的 gitconfig.local 不一样 —— macview 的拿过来/交出去不会替你决定，先自己对齐。"
    else
      echo "提示: ~/.gitconfig.local 还是直写文件 —— 在 macview 私有同步页点「拿过来 / 交出去」会先把它搬进私有源（带备份）并换成链接。"
    fi
  fi
}

# ── status --json（给 macview 读，只读）────────────────────────────────────
#
# ## 为什么单独一个出口而不是把纯文本转成 JSON
#
# 因为纯文本那个 `do_status` 里的 `echo` 是**给人看**的（中文、带提示、
# 末尾一行汇总）。让 macview 去解析中文散文，等于把界面和这句措辞焊死 ——
# 改一句「只在中转」就崩。所以**另写一份结构化的**，两件事各说各的，
# 改其中一句不影响另一句。
#
# ## 报什么、为什么不报什么
#
# **只报事实**（每个文件两边各是什么状态），**不判断该不该同步**。
# 「不一致」是事实；「该拿过来 / 交出去」是判断 —— 判断归 macview 和用户
# （它知道用户意图），脚本只负责如实说。
#
# ⚠️ **含文件内容**（2026-09-28 用户定的，见文件头「要不要列内容」）：
# `content_carrier` / `content_live` 两边都给、含 token 明文 —— 内容只进
# 本机的 macview 屏幕，脚本不发送任何东西。上限见下。
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  print -r -- "$s"
}

json_bool() { (( $1 )) && printf 'true' || printf 'false'; }

# ── 内容：要不要列出来（2026-09-28 用户定的）──
#
# ## 结论：**列全文**（含 token 明文）
#
# 用户明确选了「全文都列」。理由是他自己说的：**中转目录可能是网盘 /
# 共享位置**，所以「把要进去的东西列出来看一眼」本身就是一道**安全检查** ——
# 他要在东西同步出去之前确认里面有什么。
#
# ## ⚠️ 这个决定的代价（明写在这里，不是反对）
#
# 列出来就意味着：**token 明文会出现在 macview 的内存里和屏幕上**。
# 屏保没锁 / 录屏 / 有人从背后看到 = 泄。而这些内容本来躺在
# `~/private-dotfiles` 里，**不列出来也是同样的风险** —— 只是多了一层
# 「没被打开过」的偶然保护。
#
# 真正的风险不在「列」，在**中转目录是不是共享的**。所以界面上必须说清
# 「这些会进中转目录」；而**中转目录该不该是共享的**是用户那边的选择。
#
# ## 上限
#
# 无上限的话，一个 5 MB 的文件会把整个 JSON 撑爆（macview 解析会失败，
# 而失败表现为「没能查」—— 什么都看不到）。所以：**MAX_LINES 行**或
# **MAX_BYTES 字节**，先到先算。被截断时 `truncated: true` —— 界面必须
# 说清「只显示了前 N 行」，否则「看到的」和「实际的」不一致，而用户会
# 以为那就是全部（**这正是最坏的一种骗人**）。

MAX_LINES=400
MAX_BYTES=32768

# 把一个文件的内容变成 JSON 字符串（不存 → null）。
json_content() {
  local f="$1"
  [[ -f "$f" ]] || { printf 'null'; return; }
  local -a lines
  local line bytes=0 count=0
  lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    # ⚠️ 每个算术都**必须**带 `|| true` 或写成 `(( x++ )) || true`。
    # `set -e` 下 `(( expr ))` 的值**决定成败**：
    #   · `(( n++ ))` 在 n=0 时值是 0（自增前的值）→ 非零退出 → 脚本被杀；
    #   · `(( count > MAX ))` 为假时退出码非 0 → 同样被杀。
    # 而且**都是静默的**（输出空、退出码看着像正常）。
    # 本文件里 `(( i++ )) || true` 那处就是踩过之后加的，这里同理。
    (( count++ )) || true
    (( count > MAX_LINES )) && break || true
    (( bytes += ${#line} + 1 )) || true
    (( bytes > MAX_BYTES )) && break || true
    lines+=("$line")
  done < "$f"
  local body
  body="$(printf '%s\n' "${lines[@]}")"
  printf '"%s"' "$(json_escape "$body")"
}

# 这个文件有没有被截断（内容比上限长）。
file_truncated() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  # ⚠️ **不能用 `wc -l < "$path"`（重定向）** —— 踩过两次：
  #   1. `wc -l | tr -d ' '`：管道在 `set -e` 下可能失败，错误漏到 stderr；
  #   2. 解析 wc 的输出时：它给的是「<数字> <文件名>」，直接拿去算术比较
  #      是**非数字**（xtrace 里看得到 `lines=''` 被 `[[ == <-> ]]` 拒掉）
  #      → **明明截断了却报「没截断」**。界面说「没截断」而实际只显示了
  #      前 400 行 —— 那是最坏的骗人：用户以为看到的就是全部。
  #
  # 所以改成**把文件当参数**（`wc -l -- "$path"`），不靠重定向。
  #
  # ⚠️ 判据用 `>=` 而不是 `>`：`wc -l` 数的是**换行符个数**，而读文件时
  # 最后一行没换行符**也会被读到**（`|| [[ -n "$line" ]]` 兜住了）。用 `>`
  # 会在「刚好等于上限」时漏报。多报一次「可能截了」比漏报安全 ——
  # 宁可说多了，不能说少了。
  # ⚠️ **wc 的输出是「<数字> <文件名>」，前面还带空白。** 而拿它直接做算术
  # 比对是**非数字** → 判假 → **明明截断了却报「没截断」**。界面说「没截断」
  # 而实际只显示了前 400 行 —— 那是最坏的骗人：用户以为看到的就是全部。
  #
  # 三步处理（顺序不能换，踩过）：
  #   1. `${out%%[![:space:]]*}` 去掉**前导空白**（不先去掉的话下一步取不到字段）
  #   2. `${out%%[[:space:]]*}` 取到空白为止 = 第一个字段
  #   3. `<->` 确认是纯数字 —— 拿不到数字就**不谎报截断**
  #
  # ⚠️ 不用 `awk`/`tr` 切字段：它们在 `set -e` 下失败会把错误漏到 stderr，
  # 而 `status --json` 的调用方要的是「stderr 干净」。
  local out n
  out="$(wc -l -- "$f" 2>/dev/null)"
  out="${out#"${out%%[![:space:]]*}"}"
  n="${out%%[[:space:]]*}"
  [[ "$n" == <-> ]] || return 1
  (( n >= MAX_LINES )) && return 0 || true
  out="$(wc -c -- "$f" 2>/dev/null)"
  out="${out#"${out%%[![:space:]]*}"}"
  n="${out%%[[:space:]]*}"
  [[ "$n" == <-> ]] || return 1
  (( n >= MAX_BYTES )) && return 0 || true
  return 1
}

# 单个文件的状态：两边都在且相同 → same；都在但不同 → differ；
# 只在中转 → carrier_only；只在本机 → live_only；都不在 → absent_both。
file_state() {
  local a="$1" b="$2"
  if [[ -e "$a" && -e "$b" ]]; then
    if cmp -s "$a" "$b" 2>/dev/null; then print same; else print differ; fi
  elif [[ -e "$a" ]]; then
    print carrier_only
  elif [[ -e "$b" ]]; then
    print live_only
  else
    print absent_both
  fi
}

# 目录（machine/ 这类子树）的状态：只看**有没有**，不比内容 ——
# 目录内容多且这个版本只做「看」，逐文件比对留给以后真正要 pull 的时候。
dir_state() {
  local a="$1" b="$2"
  if [[ -d "$a" && -d "$b" ]]; then print same
  elif [[ -d "$a" ]]; then print carrier_only
  elif [[ -d "$b" ]]; then print live_only
  else print absent_both
  fi
}

do_json() {
  local out f a b st
  out+="{"$'\n'
  out+="  \"version\": 1,"$'\n'
  out+="  \"checked_at\": $(date +%s),"$'\n'
  out+="  \"generated_by\": \"private-sync.zsh\","$'\n'

  # 两端在哪、中转配没配。`carrier_set` 单独给一个布尔 —— 界面要先回答
  # 「根本没配中转目录」和「配了但两边没差异」，那是两种状态。
  out+="  \"carrier\": {"$'\n'
  out+="    \"path\": $( [[ -n "$CARRIER" ]] && printf '"%s"' "$(json_escape "$CARRIER")" || printf 'null' ),"$'\n'
  out+="    \"set\": $(json_bool $( [[ -n "$CARRIER" ]] && echo 1 || echo 0 )),"$'\n'
  out+="    \"exists\": $(json_bool $( [[ -d "$CARRIER" ]] && echo 1 || echo 0 )),"$'\n'
  out+="    \"looks_like_private\": $(json_bool $( carrier_looks_like_private && echo 1 || echo 0 ))"$'\n'
  out+="  },"$'\n'
  out+="  \"live\": {"$'\n'
  out+="    \"path\": \"$(json_escape "$LIVE_DIR")\","$'\n'
  out+="    \"exists\": $(json_bool $( [[ -d "$LIVE_DIR" ]] && echo 1 || echo 0 ))"$'\n'
  out+="  },"$'\n'

  out+="  \"files\": ["$'\n'
  local n=${#SYNC_FILES[@]} i=0
  for f in "${SYNC_FILES[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    st="$(file_state "$a" "$b")"
    # ⚠️ `(( i++ ))` 在 i=0 时**返回非零**（表达式的值是自增前的 0），
    # `set -e` 会当场把整个脚本杀掉 —— 而且是**静默**的（`status --json`
    # 输出空，退出码还可能看着像 0）。踩过。`|| true` 断掉这个语义。
    (( i++ )) || true
    out+="    {"$'\n'
    out+="      \"rel\": \"$(json_escape "$f")\","$'\n'
    out+="      \"state\": \"$st\","$'\n'
    out+="      \"in_carrier\": $(json_bool $( [[ -e "$a" ]] && echo 1 || echo 0 )),"$'\n'
    out+="      \"in_live\": $(json_bool $( [[ -e "$b" ]] && echo 1 || echo 0 )),"$'\n'
    out+="      \"linked\": $(json_bool $( [[ -L "$b" ]] && echo 1 || echo 0 )),"$'\n'
    # ── 内容（⚠️ 见文件头「要不要列内容」那一节）──
    # **两边都给**：`differ` 时用户要能**同时**看到两个版本才判断得出哪个对。
    # 只给一边的话，那一页就回答不了「我该往哪边改」。
    out+="      \"content_carrier\": $(json_content "$a"),"$'\n'
    out+="      \"content_live\": $(json_content "$b"),"$'\n'
    out+="      \"truncated\": $(json_bool $( file_truncated "$a" || file_truncated "$b" && echo 1 || echo 0 ))"$'\n'
    out+="    }"
    (( i < n )) && out+=","$'\n' || out+=""$'\n'
  done
  out+="  ],"$'\n'

  out+="  \"dirs\": ["$'\n'
  n=${#SYNC_DIRS[@]}; i=0
  for f in "${SYNC_DIRS[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    st="$(dir_state "$a" "$b")"
    (( i++ )) || true   # 同上：i=0 时返回非零，会被 set -e 杀掉
    out+="    {"$'\n'
    out+="      \"rel\": \"$(json_escape "$f")\","$'\n'
    out+="      \"state\": \"$st\""$'\n'
    out+="    }"
    (( i < n )) && out+=","$'\n' || out+=""$'\n'
  done
  out+="  ]"$'\n'
  out+="}"$'\n'

  printf '%s' "$out"
}

# ── 入口 ────────────────────────────────────────────────────────────────────
#
# 同步动作（pull/push）2026-09-29 移进 macview —— 行为蓝本曾是本文件的
# do_pull/do_push（覆盖前备份、只碰已知名单、幂等、先进场再比对），
# 现在活在那边，语义记录在 macview-contract.md「三、编辑侧 · 私有同步动作」。
# 这里收到那两个参数**不静默失败**：打一句去处，退出 1。
case "$cmd" in
  status)
    if (( AS_JSON )); then do_json; else do_status; fi
    ;;
  -h|--help)
    usage; exit 0
    ;;
  pull|push)
    echo "pull/push 已移进 macview —— 同步功能只在 GUI 上有（私有同步页的「拿过来 / 交出去」）。" >&2
    exit 1
    ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
