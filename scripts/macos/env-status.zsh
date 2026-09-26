#!/usr/bin/env zsh
#
# 环境状态：回答「dotfiles 声明了哪些环境变量、PATH 由谁组装、每一条带什么条件」。
# 契约见 macview-contract.md 第 2.11 节（本文建时新增）。
#
# ## 它做什么
#
# 读仓库里的环境相关文件，抽出**声明**（`export` / `path+=` / `typeset -U path`），
# 输出一个 JSON 到 stdout。数据源是三个文件：
#
#   · src/macos/config/zsh/zshenv     —— PATH 的唯一归属 + 核心变量
#   · src/macos/config/env/envconfig  —— TERM 兜底
#   · src/macos/config/env/exports    —— 公共导出变量（~/.exports）
#
# ## 它不做什么（最要紧的一条）
#
# ⚠️ **它不报「实际生效值」，只报「声明」。** 这是本次刻意定的边界
# （用户 2026-09-26 拍板）。
#
# 理由：`zshenv` 里全是**条件**——14 处 `[[ -d … ]] &&`、7 个 `if`、brew 探测
# 门。声明值和实际值**根本不是一回事**：
#
#   · `[[ -d "$HOME/.bin" ]] && path+=("$HOME/.bin")`
#     —— 声明里有这一条，但本机 `~/.bin` 不存在，所以它**没进 PATH**。
#
# 要报「实际值」只有一条可靠的路：起一个真 zsh（`zsh -l -c 'print $PATH'`）。
# 但那会**执行 .zshrc**（oh-my-zsh + 一串插件）——慢，而且等于这个只读检测器
# 去**跑用户的配置**。本仓库所有 `*-status.zsh` 的共同纪律是「只读文本、不执行」，
# 这里不能破例。
#
# 所以产出里每一条都带 `condition` 字段，**原样记下声明时的守卫**：
#   · 无守卫（无条件加）        → `condition = null`
#   · 同行 `[[ -d X ]] && …`    → `condition = "[[ -d X ]]"`（原文）
#   · 在 `if …; then` 块里的     → `condition = "<if 的那行条件>"`（原文）
#
# 界面照实说「dotfiles 声明：X 存在时才加」，**不画那个 `✓ 已生效`**
# —— 我们没查过实际值，画勾就是撒谎（契约 §二「没能查 ≠ 没有」的同一条纪律）。
#
# ## 决议 2：PATH 按「段」报，每段带来源与条件
#
# PATH 的组装逻辑散在 zshenv 的多个位置（`_pre` 前置、条件追加、brew 段补 bin）。
# 本脚本按**出现顺序**逐条抽出「往 PATH 里加什么」，每条带：
#   · `value`     —— 加进去的字面量（`$HOME/.bin` 这种**不展开**，同 shell-map）
#   · `order`     —— `prepend`（前置，`path=(X $path)` 那种）/ `append`（追加）
#   · `condition` —— 守卫原文（见上）
#   · `owner`     —— 哪一段加的（`user-paths` / `language-tools` / `brew`）
#
# **不展开 `$HOME` / `$HOMEBREW_PREFIX`** —— 展开会给界面一个可能不存在的
# 绝对路径，反而更误导（同 shell-map §2.10 的决定）。
#
# ## 决议 3：变量报「声明值」，原样，不 eval
#
# `export EDITOR=nvim` → 报 `name=EDITOR`, `value="nvim"`。
# 值原样抄（去掉两端引号），**不展开 `$` 变量、不跑命令替换**。
# 值里若含 `$(…)` 或 `$VAR`，`dynamic=true` 标出来 —— 界面说「这是运行时算的」，
# 而不是把它硬当成字面量。
#
# ## 决议 4：抠不出任何东西 → 报错退出
#
# 同 link-status / alias-status 的纪律：某个源文件不在，或一条都没抽到，
# **报错退出、不给空数组**。空数组会被界面显示成「环境变量是空的」——
# 而真相可能是解析器坏了。
#
# ## 解析器的边界（说清楚，免得以为它无所不能）
#
# 这是**行级文本解析，不是 shell 求值**。认得：
#   · `export NAME=value` / `export NAME="value"` / `export NAME='value'`
#   · `export PATH`（只导出，不改 —— 忽略）
#   · `typeset -U path`（去重声明 —— 记一条 `path_dedup: true` 的事实）
#   · `path=($_pre $path)` 前置（`_pre` 里攒的目录）/ `path+=("$X")` 追加
#   · `_pre+=("$X")` —— zshenv 用它攒要**前置**的目录，归 `prepend` /
#     `user-paths`（不认它就会漏报 `~/.bin` / `~/.local/bin`）
#   · 同行 `[[ … ]] && <语句>` / `[[ … ]] || <语句>` 的守卫
#   · 缩进的 `if …; then` … `elif` … `else` … `fi`（一层，够本仓库用）
#   · 行尾注释（**引号外**的 `#`）
#
# 它**不**认得（遇到就**跳过那行、不猜、不报错**）：
#   · 多行数组 / 多行语句
#   · 嵌套 `if`（只跟一层）
#   · 变量拼接出的完整路径（`$A/$B` 原样留着，不拼）
#   · `eval` / `source` 出来的东西（那是别的文件的事）
# 跳过比猜错好 —— 猜错会给界面一个假的值。
# （**静默跳过**是有意的：这是只读查询脚本，界面上「少一条」比「错一条」轻。
#  唯一会报错退出的情况是「一个源文件不在」或「一条都没抽到」—— 见决议 4。）
#
# 用法：
#   zsh scripts/macos/env-status.zsh --json

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/env-status.zsh --json

  --json    把环境声明（变量 + PATH 段）打到 stdout（只读，不落盘）

契约见仓库根目录的 macview-contract.md。
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --json) MODE="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "必须指定 --json。" >&2
  usage >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "env-status 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── JSON 工具（照抄 link-status / shell-map，理由见那里）──────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_str_or_null() {
  if [[ -z "${1:-}" ]]; then printf 'null'; else printf '"%s"' "$(json_escape "$1")"; fi
}

# ── 源文件清单 ──────────────────────────────────────────────────────────
#
# 顺序 = 界面显示的组顺序。`rel` 是仓库内相对路径（给 macview 显示）。
#
# ⚠️ 只有这三个。**不递归** source 出来的文件（同 shell-map §2.10 的边界）：
# envconfig 里会 source `~/.envconfig.local`（私有源，内容不在仓库），那一层
# 属于私有源报告的职责，不在这里跟。
ENV_FILES=(
  "src/macos/config/zsh/zshenv"
  "src/macos/config/env/envconfig"
  "src/macos/config/env/exports"
)

# ── 抽「变量声明」和「PATH 段」的解析器 ─────────────────────────────────
#
# 一个文件走一遍，产出三类行（字段用 \x1f 分隔），由调用方收集：
#   · `var␟名␟值␟条件␟dynamic␟源文件␟行号`
#   · `path␟值␟order␟条件␟owner␟源文件␟行号`
#   · `dedup␟(空)␟源文件␟行号`（`typeset -U path`）
#
# （文本里写「\x1f」是因为字段里可能有 TAB / 空格，而 \x1f 几乎不可能出现。）
#
# ⚠️ 用 `$(extract_file …)` 调用时它在**子 shell** 里跑 —— 所以这个函数
# **不维护任何计数器**，行号、条数都由调用方从产出行里数（alias-status 踩过
# 这个坑：子 shell 里改全局，外面看不到）。
#
# ⚠️ 所有 `local` 在循环**外**声明。zsh 的坑：在会跑两遍以上的循环里写
# `local x` 而 x 已有值时，会把 `x=值` 打到 stdout，污染 JSON。

# 去掉一行的尾部空白 + 行尾注释（引号外的 `#`；本仓库注释都在行尾且不在引号里）。
strip_line() {
  local line="$1"
  local in_s=0 in_d=0 i ch out="" len=${#line}
  # 逐字符扫，遇到引号外的 `#` 就截断 —— 比 `%%#*` 稳（值里可能真有 `#`，
  # 如 `export FOO="a#b"`）。
  for (( i = 1; i <= len; i++ )); do
    ch="${line[$i]}"
    if (( in_s )); then
      [[ "$ch" == "'" ]] && in_s=0
    elif (( in_d )); then
      [[ "$ch" == '"' ]] && in_d=0
    else
      case "$ch" in
        "'") in_s=1 ;;
        '"') in_d=1 ;;
        '#') break ;;
      esac
    fi
    out+="$ch"
  done
  out="${out%"${out##*[![:space:]]}"}"
  # 也掐掉**前导**空白 —— 缩进行（`  fi`、`  path+=(…)`）要靠这个才能
  # 被后面的 `if`/`fi`/`path` 判断认出来。第一版只掐了尾部，结果缩进的
  # `  fi` 匹配不上 `fi`，if 计数器永远不减，块内的条件污染到块外。
  out="${out#"${out%%[![:space:]]*}"}"
  printf '%s' "$out"
}

# 从一行里掰出「守卫」和「语句本体」。
# 输入：一行（已 strip）。
# 输出（全局）：GUARD（守卫原文，无则空）、BODY（语句本体）。
#
# 认两种写法（本仓库就这两种）：
#   · 同行 `[[ -d "$X" ]] && path+=(...)`  → GUARD='[[ -d "$X" ]]'，BODY='path+=(...)'
#   · 纯语句（守卫在上面的 `if …; then` 块里 —— 由调用方的 in_if 状态补）
GUARD=""; BODY=""

split_guard() {
  local line="$1"
  GUARD=""; BODY="$line"

  # 找 `]] && ` / `]] || ` —— 取它之前为守卫，之后为语句。
  # `&&` 和 `||` 都切：本仓库两种都有
  #   · `[[ -d X ]] && path+=(X)`     ← 存在才加
  #   · `[[ ":$PATH:" == *X* ]] || path+=(X)` ← 不在 PATH 里才加
  # 两种都是「这条声明带守卫」，守卫原文照记。
  # 只在行**含** `[[` 且含 `&&`/`||` 时才切，避免误切值里的符号。
  if [[ "$line" == *'[['* ]] && { [[ "$line" == *'&&'* ]] || [[ "$line" == *'||'* ]]; }; then
    local pre="" op=""
    if [[ "$line" == *'&&'* ]]; then
      # 取 `&&` 与 `||` 里**更靠前**的那个当分界（本仓库同一行极少混用）。
      pre="${line%%&\&*}"
      op="&&"
      if [[ "$line" == *'||'* ]]; then
        local pre2="${line%%||*}"
        (( ${#pre2} < ${#pre} )) && { pre="$pre2"; op="||"; }
      fi
    else
      pre="${line%%||*}"
      op="||"
    fi
    pre="${pre%"${pre##*[![:space:]]}"}"
    # 守卫必须形如 `[[ … ]]`；否则不是我们认的写法，不切。
    if [[ "$pre" == '[['* && "$pre" == *']]' ]]; then
      GUARD="$pre"
      # ⚠️ 不用 `${line:offset}` 算偏移 —— zsh 的算术切片/引号嵌套很容易差一位
      # （第一版就差了，切出 `& path+=…`）。直接用**文本前缀剥离**：
      # 从原行里砍掉守卫，再砍掉后面的 `&&`/`||`。
      BODY="${line#"$pre"}"
      BODY="${BODY#"${BODY%%[![:space:]]*}"}"   # 掐前导空白
      BODY="${BODY#"$op"}"
      BODY="${BODY#"${BODY%%[![:space:]]*}"}"   # 再掐一次
    fi
  fi
}

# 解析一条 `path=`/`path+=` 语句。
# 输入：BODY（如 `path=($_pre $path)` 或 `path+=("$HOME/go/bin")`）。
# 输出（全局）：PATH_VALUES（数组，可能多个）、PATH_ORDER、PATH_OK
#   PATH_ORDER：`prepend`（`path=(X $path)`）/ `append`（`path+=(…)`）
#
# 只抓**同一行内**写完的数组；跨行的（`path+=( \n … \n )`）跳过，不猜。
PATH_VALUES=(); PATH_ORDER=""; PATH_OK=0

parse_path_stmt() {
  local body="$1"
  PATH_VALUES=(); PATH_ORDER=""; PATH_OK=0

  # 值列表：括号里的内容。
  [[ "$body" == *'('* && "$body" == *')'* ]] || return 1
  local inner="${body#*\(}"
  inner="${inner%\)*}"
  inner="${inner%"${inner##*[![:space:]]}"}"
  inner="${inner#"${inner%%[![:space:]]*}"}"
  [[ -n "$inner" ]] || return 1

  # 判断 append / prepend：
  #   `path=(… $path)`  ← 末尾有 `$path` → prepend
  #   `path+=(…)`       ← 语句是 `path+=(` → append
  if [[ "$body" == 'path='* ]]; then
    # 无 `+`。看末尾是不是 `$path`。
    if [[ "$inner" == *'$path' ]]; then
      PATH_ORDER="prepend"
    else
      # `path=(X)` 整体替换 —— 本仓库没有这种写法，跳过更安全。
      return 1
    fi
  elif [[ "$body" == 'path+='* ]]; then
    PATH_ORDER="append"
  else
    return 1
  fi

  # 掰出每个 `$X` 或字面量。去掉 `$path` 自身（它不是新加的一段）。
  local -a toks=()
  tok_split "$inner"
  local t
  for t in "${TOKENS[@]}"; do
    [[ "$t" == '$path' ]] && continue          # 原 PATH 本身，不是新段
    [[ "$t" == '$_pre' ]] && continue          # 变量容器（下面单独处理 _pre）
    toks+=("$t")
  done
  # ⚠️ `_pre=()` 那套（先把 `~/.bin` 攒进 `_pre`，最后 `path=($_pre $path)`）：
  # 这种情况下 `path=(…)` 里是 `$_pre`，真正的内容在**上面几行的 `_pre+=(…)`**。
  # 本脚本**不为它开特例** —— 那些 `_pre+=(…)` 行按它们自己的 `path` 语义
  # 是另一个变量，我们抓不到，会漏。这是**已知边界**（见文件头「不认得」）。
  # 好在 `_pre` 段加的是 `~/.bin` / `~/.local/bin`，界面上少报这两条比**错报**
  # 强；真正要紧的 brew / 语言工具段都是直白的 `path+=(…)`。

  (( ${#toks[@]} )) || return 1
  PATH_VALUES=("${toks[@]}")
  PATH_OK=1
  return 0
}

# 把 `$HOME/go/bin` 这种拆成一个一个 token（数组元素）。
# 输出（全局数组）：TOKENS
TOKENS=()

tok_split() {
  local s="$1"
  TOKENS=()
  # 本仓库的数组元素有：`"$HOME/go/bin"` / `$HOME/.bin` / `$_pre` / `$path` / 裸字面量。
  # 按空白切，再去掉两端的引号。
  local -a parts=(${(z)s})
  local p
  for p in "${parts[@]}"; do
    p="${p#\"}"; p="${p%\"}"
    p="${p#\'}"; p="${p%\'}"
    [[ -n "$p" ]] && TOKENS+=("$p")
  done
}

# 抽一个文件。产出以 `\n` 连接的「记录行」到 stdout。
# 用法：extract_file <abs_path> <rel_path> <owner>
#
# `owner` 是 PATH 段的归属标签（给界面分组用）：
#   · zshenv   → 按位置细分成 user-paths / language-tools / brew
#   · 其它文件 → 文件名
extract_file() {
  local abs="$1" rel="$2" owner_hint="$3"

  if [[ ! -f "$abs" ]]; then
    echo "Error: 找不到 $rel（$abs）—— 仓库结构变了吗？" >&2
    return 1
  fi

  local lineno=0
  local t guard body
  local in_if=0
  local if_cond=""

  # ⚠️ 所有 local 在循环外一次声明（防 zsh 打印）。
  local name value dynamic
  local pv porder
  local owner

  while IFS= read -r raw; do
    (( lineno++ ))
    t="$(strip_line "$raw")"
    [[ -n "$t" ]] || continue

    # ── 跟踪 if 块（一层，够本仓库用）──────────────────────────────
    #
    # ⚠️ 不能用 `*'if '*` 判断 —— `elif ` 里也含子串 `if `（`l-i-f-空格`），
    # 会把 `elif` 误当成 `if` 开来开去，计数器错乱，导致块外的语句全被
    # 盖上块内的条件（第一版就这么错的：MANPAGER 背上了 brew 的 if）。
    # 所以**按词首**判断：`if` / `elif` / `else` / `fi` 必须是这一行的开头词。
    local first="${t%%[[:space:]]*}"
    case "$first" in
      if)
        (( in_if++ ))
        # `if <cond>; then` → 记下 <cond>。去掉开头的 if、结尾的 then / `;`。
        if_cond="${t#if }"
        if_cond="${if_cond%then*}"
        if_cond="${if_cond%;*}"
        if_cond="${if_cond%"${if_cond##*[![:space:]]}"}"
        # 收尾的 `then` 若同一行，也要从条件里去掉（`…; then` 已由上面处理；
        # `… then` 无分号时兜底）。
        if_cond="${if_cond%then}"
        if_cond="${if_cond%"${if_cond##*[![:space:]]}"}"
        ;;
      elif)
        # elif 只是同一层 if 的另一个分支 —— **不**再 +1。
        if_cond="${t#elif }"
        if_cond="${if_cond%then*}"
        if_cond="${if_cond%;*}"
        if_cond="${if_cond%then}"
        if_cond="${if_cond%"${if_cond##*[![:space:]]}"}"
        ;;
      else)
        # else 分支没有自己的条件 —— 用「if 的反面」表示不了，就留空，
        # 界面显示为「否则」那条（guard 为空 = 无条件，语义上正好）。
        if_cond=""
        ;;
      fi)
        (( in_if > 0 )) && (( in_if-- ))
        [[ $in_if -eq 0 ]] && if_cond=""
        ;;
    esac

    # ── 拆守卫 / 本体 ──────────────────────────────────────────────
    split_guard "$t"
    guard="$GUARD"; body="$BODY"

    # 块内的纯语句没有同行守卫 —— 用 if 的条件补上（这就是「声明时的守卫」）。
    if [[ -z "$guard" ]] && (( in_if > 0 )) && [[ -n "$if_cond" ]]; then
      guard="$if_cond"
    fi

    # ── typeset -U path（去重声明）─────────────────────────────────
    if [[ "$body" == *'typeset'*'path'* ]]; then
      printf 'dedup\x1f%s\x1f%s\x1f%d\n' "$(json_escape "$guard")" "$rel" "$lineno"
      continue
    fi

    # ── export ────────────────────────────────────────────────────
    if [[ "$body" == 'export '* ]]; then
      local rest="${body#export }"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      # `export PATH` / `export MANPATH`（只导出、无值）→ 系统既有变量，
      # 不是我们「声明」的，跳过（否则会把 PATH 本身当变量报出来）。
      if [[ "$rest" == *'='* ]]; then
        name="${rest%%=*}"
        value="${rest#*=}"
        name="${name%"${name##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        # 去两端引号（只去一层）。
        if [[ "${value[1]}" == '"' && "${value[-1]}" == '"' && ${#value} -ge 2 ]]; then
          value="${value[2,-2]}"
        elif [[ "${value[1]}" == "'" && "${value[-1]}" == "'" && ${#value} -ge 2 ]]; then
          value="${value[2,-2]}"
        fi
        # 值里含 `$`（变量/命令替换）→ dynamic，界面说「运行时算的」。
        dynamic=0
        [[ "$value" == *'$'* || "$value" == *'`'* ]] && dynamic=1
        if [[ -n "$name" ]]; then
          printf 'var\x1f%s\x1f%s\x1f%s\x1f%d\x1f%s\x1f%d\n' \
            "$(json_escape "$name")" "$(json_escape "$value")" \
            "$(json_escape "$guard")" "$dynamic" "$rel" "$lineno"
        fi
      fi
      continue
    fi

    # ── path= / path+= ────────────────────────────────────────────
    if [[ "$body" == 'path='* || "$body" == 'path+='* ]]; then
      # `path=($_pre $path)` 只是把上面攒的 `_pre` 刷进 PATH —— `_pre` 里的
      # 每一条已经由**上面**的 `_pre+=(…)` 分支报过了，这里跳过（不重复报）。
      # （`_pre+=(…)` 在 zshenv 里出现在这一行之前，所以那个分支已经跑过。）
      if [[ "$body" == 'path=('*'$_pre'* ]]; then
        continue
      fi
      if parse_path_stmt "$body"; then
        # owner 细分：zshenv 里按位置分（用户路径 / 语言工具 / brew）。
        owner="$owner_hint"
        if [[ "$rel" == *'zshenv' ]]; then
          if [[ "$body" == *'HOMEBREW'* ]]; then
            owner="brew"
          elif [[ -z "$guard" ]]; then
            owner="user-paths"
          else
            owner="language-tools"
          fi
        fi
        for pv in "${PATH_VALUES[@]}"; do
          printf 'path\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%d\n' \
            "$(json_escape "$pv")" "$PATH_ORDER" "$(json_escape "$guard")" \
            "$owner" "$rel" "$lineno"
        done
      fi
      continue
    fi

    # ── _pre+=(…) ─────────────────────────────────────────────────
    #
    # zshenv 用 `_pre` 攒好要**前置**的目录，最后 `path=($_pre $path)` 一次刷进去
    # （这样自定义路径排在系统路径前面，不被同名命令遮住 —— 见 zshenv 的注释）。
    # 所以 `_pre+=(…)` 的语义是 **prepend**，owner 归 `user-paths`。
    # 不认它就会漏报 `~/.bin` / `~/.local/bin` —— 那两条恰恰是用户最该知道
    # 「有没有生效」的（本机这俩目录都不存在 → 其实没进 PATH）。
    if [[ "$body" == '_pre+='* ]]; then
      if parse_path_stmt "${body/#_pre+=/path+=}"; then
        for pv in "${PATH_VALUES[@]}"; do
          printf 'path\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%d\n' \
            "$(json_escape "$pv")" "prepend" "$(json_escape "$guard")" \
            "user-paths" "$rel" "$lineno"
        done
      fi
      continue
    fi
  done <"$abs"
}

render_json() {
  local now
  now="$(date +%s)"

  # ⚠️ 所有 local 在循环外一次声明（防 zsh 在循环里打印 local）。
  local spec rel abs owner_hint
  local -a dedups=()

  local -a v_name=() v_value=() v_cond=() v_dyn=() v_rel=() v_line=()
  local -a p_value=() p_order=() p_cond=() p_owner=() p_rel=() p_line=()

  local raw rec kind
  local -a f=()
  for spec in "${ENV_FILES[@]}"; do
    rel="$spec"
    abs="$ROOT_DIR/$rel"
    # owner 提示：zshenv 自己细分，其它文件用文件名。
    owner_hint="${rel##*/}"

    if [[ ! -f "$abs" ]]; then
      echo "Error: 找不到源文件 $rel（$abs）—— 仓库结构变了吗？" >&2
      return 1
    fi

    raw="$(extract_file "$abs" "$rel" "$owner_hint")" || return 1

    # 记录之间以换行分隔、字段之间以 \x1f（unit separator）分隔。
    # 用 \x1f 而不是 TAB，是因为字段里可能有 TAB / 空格。
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      # 拆分记录字段：用 IFS=$'\x1f' + read -A。
      # （不能用 `${(s:\x1f:)…}` —— zsh 的 (s:) 旗标把 `\x1f` 当字面量，
      #  不认转义，切不出来。第一版踩过。）
      # IFS 作为 read 的**前缀赋值**，不污染外层 IFS。
      IFS=$'\x1f' read -r -A f <<< "$rec"
      kind="${f[1]}"
      case "$kind" in
        var)
          # var / 名 / 值 / 条件 / dynamic / rel / 行号
          v_name+=("${f[2]}"); v_value+=("${f[3]}"); v_cond+=("${f[4]}")
          v_dyn+=("${f[5]}"); v_rel+=("${f[6]}"); v_line+=("${f[7]}")
          ;;
        path)
          # path / 值 / order / 条件 / owner / rel / 行号
          p_value+=("${f[2]}"); p_order+=("${f[3]}"); p_cond+=("${f[4]}")
          p_owner+=("${f[5]}"); p_rel+=("${f[6]}"); p_line+=("${f[7]}")
          ;;
        dedup)
          dedups+=("${f[3]}")
          ;;
      esac
    done <<<"$raw"
  done

  # 一条都没抽到 = 解析器坏了，不给空（同 link-status / alias-status）。
  if (( ${#v_name[@]} == 0 && ${#p_value[@]} == 0 )); then
    echo "Error: 一条环境声明都没抽到 —— 解析器需要跟着改了。" >&2
    return 1
  fi

  # ── 拼 JSON ─────────────────────────────────────────────────────────
  local i
  out="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"env-status.zsh\","$'\n'

  # ⚠️ 一个**总的诚实声明**：这些是「声明」，不是「实际值」。
  # 放在 JSON 里（不只写注释），因为 macview 要能读到它并显示出来。
  out+="  \"kind\": \"declared\","$'\n'
  out+="  \"note\": \"以下都是仓库里**声明**要设的环境，不是本机实际生效值；dotfiles 没有查实际值的脚本。\","$'\n'

  out+="  \"files\": ["
  for (( i = 1; i <= ${#ENV_FILES[@]}; i++ )); do
    out+=" \"$(json_escape "${ENV_FILES[$i]}")\""
    (( i < ${#ENV_FILES[@]} )) && out+=","
  done
  out+="],"$'\n'

  # 具名变量。
  out+="  \"variables\": ["
  if (( ${#v_name[@]} == 0 )); then
    out+="]"
  else
    out+=$'\n'
    for (( i = 1; i <= ${#v_name[@]}; i++ )); do
      out+="    { \"name\": \"${v_name[$i]}\", \"value\": \"${v_value[$i]}\","
      out+=" \"condition\": $(json_str_or_null "${v_cond[$i]}"),"
      out+=" \"dynamic\": $( (( v_dyn[$i] )) && printf 'true' || printf 'false' ),"
      out+=" \"file\": \"$(json_escape "${v_rel[$i]}")\", \"line\": ${v_line[$i]} }"
      (( i < ${#v_name[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ]"
  fi
  out+=","$'\n'

  # PATH 段。
  out+="  \"path_segments\": ["
  if (( ${#p_value[@]} == 0 )); then
    out+="]"
  else
    out+=$'\n'
    for (( i = 1; i <= ${#p_value[@]}; i++ )); do
      out+="    { \"value\": \"${p_value[$i]}\", \"order\": \"${p_order[$i]}\","
      out+=" \"condition\": $(json_str_or_null "${p_cond[$i]}"),"
      out+=" \"owner\": \"${p_owner[$i]}\","
      out+=" \"file\": \"$(json_escape "${p_rel[$i]}")\", \"line\": ${p_line[$i]} }"
      (( i < ${#p_value[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ]"
  fi
  out+=","$'\n'

  # PATH 的去重事实（`typeset -U path`）。给界面一句「PATH 会自动去重」。
  out+="  \"path_dedup\": $( (( ${#dedups[@]} > 0 )) && printf 'true' || printf 'false' ),"$'\n'

  out+="  \"counts\": { \"variables\": ${#v_name[@]}, \"path_segments\": ${#p_value[@]} }"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  local json
  json="$(render_json)" || return 1

  # 发出前自验一遍合法性（照 link-status / shell-map）。
  if command -v python3 >/dev/null 2>&1; then
    if ! printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      echo "内部错误：产出的 JSON 不合法（这是个 bug，请报告）。" >&2
      return 1
    fi
  fi

  printf '%s\n' "$json"
  return 0
}

main "$@"
