#!/usr/bin/env zsh
#
# 别名状态：回答「这台机器上定义了哪些 shell 别名、各自是什么」。契约见
# macview-contract.md 第 2.8 节（本文建时新增）。
#
# ## 它做什么
#
# 按**文件**列出仓库里声明的别名（名 → 值），输出一个 JSON 到 stdout。
# 数据源是三个文件：
#
#   · src/macos/config/aliases                —— 主 shell 别名（~/.aliases）
#   · src/macos/config/env/envconfig          —— Python 相关别名
#   · src/macos/config/tmux/config/aliases.sh —— tmux 别名
#
# ## 它不做什么
#
# **不执行、不 source 任何文件，不改任何东西。** 和 link-status.zsh /
# private-state.zsh 是同一类只读检测器。这里只是**读文本、抽 alias 行**。
#
# ## 最要紧的三个决定
#
# ### 1. 按文件分组，不解析 `# --- 组名 ---` 注释
#
# `aliases` 里有 `# --- Git ---` 这类注释把别名分了几组。**不按它分。**
# 理由：注释随便改，一改解析就乱，而且是**静默**乱（分组变了没人知道）；
# 而且注释分组本身就不齐（`# Safety checks` 那组只是普通注释、不是 `---` 标题），
# 按它分必然有漏。所以只按**文件**分 —— 三个文件是**加载位置**不同，
# 这是客观事实，不会漂移。（决定见设计稿《功能页细化》§3.1。）
#
# ### 2. 必须抓**缩进的** alias（这是最容易漏的坑）
#
# `aliases` 的第 31 条里有 **5 条是缩进的**——它们在 `if` 分支里：
#
#     if command -v eza &> /dev/null; then
#       alias ls='eza'        ← 缩进！
#       alias ll='eza -l ...'
#       ...
#     else
#       alias ll='ls -lah'    ← 缩进！而且是**第二个 ll**
#     fi
#
# 所以正则**必须允许前导空白**（`^[[:space:]]*alias `）。锚 `^alias ` 会只数出
# 26 条，而真实是 31 —— 那会让 macview 显示少 5 条，且不报错。
#
# ### 3. 报出「条件」和「重名」—— 否则界面会撒谎
#
# 上面那个 `ll` 出现两次（`eza` 版 + 兜底版），值还不一样。**不能只报一个。**
# 每一行都带 `condition` 字段：
#   · 在 `if command -v eza ...` 分支里 → `condition = "eza 存在"`
#   · 在对应的 `else` 分支里           → `condition = "eza 不存在"`
#   · 不在任何分支里（普通别名）        → `condition = null`
#
# 这样界面上会显示两个 `ll` 并注上「仅当 eza 存在 / eza 不存在时的兜底」——
# 而不是显示两个一模一样的名字让人以为文件坏了。
#
# ## 解析器的边界（说清楚，免得以为它无所不能）
#
# 这是**行级文本解析，不是 shell 求值**。它认得：
#   · `alias 名='值'` / `alias 名="值"`（两种引号）
#   · 缩进（`^[[:space:]]*`）
#   · `alias -- 名=值`（`--` 分隔符，用于名字以 `-` 开头，如 `alias -- -='cd -'`）
#   · 行尾注释（`alias tls='tmux ls'   # 说明`）—— 引号**外**的 `#` 才是注释
#   · `if condition; then` … `else` … `fi`（一层，够本仓库用）
#
# 它**不**认得（本仓库现在没有，但要知道）：
#   · 多行 alias（值里带换行）
#   · 嵌套 `if`
#   · 值里带转义引号（`alias x='a'\''b'`）
#   · `unalias`
# 遇到这些，它会**跳过那一行**（不报错、也不猜），并在 stderr 记一条。
# 跳过比猜错好 —— 猜错会给界面一个假的值。
#
# ⚠️ 抠不出任何别名时**报错退出**，不给空数组 —— 空数组会让界面显示
# 「没有别名」，而真相可能是解析器坏了。和 link-status.zsh 同一纪律。
#
# 用法：
#   zsh scripts/macos/alias-status.zsh --json

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
Usage: zsh scripts/macos/alias-status.zsh --json

  --json    把别名清单打到 stdout（只读，不落盘）

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
  echo "alias-status 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── JSON 工具（照抄 link-status.zsh，理由见那里）──────────────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ── 源文件清单（按顺序）─────────────────────────────────────────────────
#
# 顺序 = 界面显示的组顺序。`rel` 是仓库内相对路径（给 macview 显示），
# `abs` 是实际读的路径。
SOURCE_RELS=(
  "src/macos/config/aliases"
  "src/macos/config/env/envconfig"
  "src/macos/config/tmux/config/aliases.sh"
)

# ── 一行 alias 的解析 ────────────────────────────────────────────────────
#
# 输入：一行文本 + 当前 condition（外层 if 分支，可能为空）。
# 输出（全局变量）：AL_NAME / AL_VALUE / AL_COND（空表示无条件）。
# 返回 0 = 认出来了；1 = 这行不是 alias（跳过）。
#
# 用全局变量传值是因为 zsh 里 `$(...)` 会开子 shell，命令替换里改了全局
# 外面看不到 —— 这是本文件最容易写错的地方，所以显式用全局。
AL_NAME=""; AL_VALUE=""; AL_COND=""

parse_alias_line() {
  local line="$1" cond="$2"
  AL_NAME=""; AL_VALUE=""; AL_COND=""

  # 掐掉尾部空白。
  line="${line%"${line##*[![:space:]]}"}"

  # 必须匹配 `<空白>alias ` 。不匹配就当它不存在（注释、空行、代码）。
  [[ "$line" =~ '^[[:space:]]*alias[[:space:]]' ]] || return 1

  # 去掉 `alias` 及其后的空白。
  local rest="${line#*alias}"
  rest="${rest#"${rest%%[![:space:]]*}"}"

  # `alias -- 名=值`：`--` 是分隔符（名字以 `-` 开头时用）。
  if [[ "$rest" == "-- "* ]]; then
    rest="${rest#-- }"
  elif [[ "$rest" == "--" ]]; then
    return 1
  fi

  # 名字：到 `=` 为止。`alias -- -='cd -'` 走到这里名字是 `-`。
  [[ "$rest" == *=* ]] || return 1
  local name="${rest%%=*}"
  name="${name%"${name##*[![:space:]]}"}"   # 掐名字尾部空白
  [[ -n "$name" ]] || return 1

  local value="${rest#*=}"
  value="${value#"${value%%[![:space:]]*}"}"   # 掐值前导空白

  # ── 取值：从引号里扫，扫到闭合引号为止 ────────────────────────────────
  #
  # ⚠️ **不能只判断「最后一个字符是不是引号」。** 因为值后面可能有行尾注释：
  #     alias tls='tmux ls'   # 列出所有会话
  # 那种情况下最后一个字符是注释的最后一个字，不是引号。第一版就是这么错的：
  # tmux 的 11 条里 6 条带行尾注释，全被跳过（只抓到 5 条）。
  #
  # 正确做法：**从开引号往后扫，数到匹配的闭合引号**，后面的全部丢掉
  # （不管是空白还是 `# 注释`）。
  local quote="${value[1]}"
  if [[ "$quote" != "'" && "$quote" != '"' ]]; then
    # 没有引号：本仓库的值**都有引号**，走到这里多半格式变了 —— 跳过、不猜。
    echo "alias-status: 跳过没有引号的 alias：$line" >&2
    return 1
  fi

  local body="${value[2,-1]}"   # 去掉开引号
  local i ch out="" escaped=0 found=0
  for (( i = 1; i <= ${#body}; i++ )); do
    ch="${body[$i]}"
    if (( escaped )); then
      # 反斜杠后的字符**原样保留**（值里可能真有反斜杠，如 tmux 的 `\;`）。
      out+="$ch"; escaped=0; continue
    fi
    if [[ "$ch" == '\' ]]; then
      out+="$ch"; escaped=1; continue
    fi
    if [[ "$ch" == "$quote" ]]; then
      found=1
      break
    fi
    out+="$ch"
  done

  if (( ! found )); then
    # 引号没闭上 —— 这行我们看不懂（多行值？），跳过，不猜。
    echo "alias-status: 跳过引号不闭合的 alias：$line" >&2
    return 1
  fi

  # 闭合引号之后**只允许空白或 `#` 注释**。若还有别的（说明这行是
  # 引号拼接，如 `alias x='a'\''b'`——我们只抓到第一段），**跳过**，
  # 因为「只抓第一段」会给出一个**不完整的值**，那比不给更糟。
  local tail="${value:$(( i + 2 ))}"
  tail="${tail#"${tail%%[![:space:]]*}"}"   # 掐前导空白
  if [[ -n "$tail" && "${tail[1]}" != '#' ]]; then
    echo "alias-status: 跳过引号后还有内容的 alias（可能是引号拼接）：$line" >&2
    return 1
  fi

  AL_NAME="$name"
  AL_VALUE="$out"
  AL_COND="$cond"
  return 0
}

# ── 从一个文件抽别名 ────────────────────────────────────────────────────
#
# 用法：extract_file <abs_path> <rel_path>
# 产出：每行一条 `名<TAB>值<TAB>条件<TAB>源相对路径`（条件空则字段为空）。
#
# ⚠️ 用 `$(extract_file ...)` 调用时它在**子 shell** 里跑 —— 所以这个函数
# **不维护任何计数器**，条数由调用方从产出行里数（见 render_json）。
# （第一版这里用全局 N_ALIASES 累加，被这个坑坑过：子 shell 里改了外面看不到，
# 导致「一条都没抽到」的假报错。）
extract_file() {
  local abs="$1" rel="$2"

  if [[ ! -f "$abs" ]]; then
    # 文件不在 —— 报错退出，不给空组（空组会被显示成「这个文件没别名」）。
    echo "Error: 找不到 $rel（$abs）—— 仓库结构变了吗？" >&2
    return 1
  fi

  local line
  # ⚠️ 同 render_json 的坑：`while` 循环里的 `local` 只声明一次（在外面）。
  local t cond
  local in_if=0 branch=0
  local if_cond=""   # 记住 `if` 的条件文字，供 else 分支复用

  while IFS= read -r line; do
    # 掐掉尾部空白后用整行判断结构（if/else/fi 不缩进也不影响）。
    # ⚠️ 不写 `local`（在循环外声明过了）—— 在循环里 `local` 会打印。
    t="${line%"${line##*[![:space:]]}"}"

    if [[ "$t" =~ '^[[:space:]]*if[[:space:]]+' ]]; then
      in_if=1; branch=1
      # 条件文字：`if command -v eza &> /dev/null; then` → `eza`
      # 只认 `command -v <名>` 这一种（本仓库只用这一种）。认不出就把
      # 整个条件原样留着（界面显示原文也比显示一个猜出来的强）。
      if [[ "$t" =~ 'command -v[[:space:]]+([^[:space:];&]+)' ]]; then
        if_cond="${match[1]}"
      else
        if_cond="$t"
      fi
      continue
    fi
    if [[ "$t" =~ '^[[:space:]]*else[[:space:]]*$' ]]; then
      branch=2
      continue
    fi
    if [[ "$t" =~ '^[[:space:]]*fi[[:space:]]*$' ]]; then
      in_if=0; branch=0; if_cond=""
      continue
    fi

    cond=""
    if (( in_if )); then
      if (( branch == 1 )); then
        cond="$if_cond 存在"
      else
        cond="$if_cond 不存在"
      fi
    fi

    if parse_alias_line "$line" "$cond"; then
      printf '%s\t%s\t%s\t%s\n' "$AL_NAME" "$AL_VALUE" "$AL_COND" "$rel"
    fi
  done <"$abs"

  return 0
}

render_json() {
  local now
  now="$(date +%s)"

  # 逐文件抽，全部行收进 rows。
  local -a rows=()
  local rel abs raw
  for rel in "${SOURCE_RELS[@]}"; do
    abs="$ROOT_DIR/$rel"
    raw="$(extract_file "$abs" "$rel")" || return 1
    [[ -n "$raw" ]] && rows+=("${(@f)raw}")
  done

  # 条数从收齐的行里数（不靠函数里的全局 —— 见 extract_file 的说明）。
  local total=${#rows[@]}

  # 一条都没有 = 解析器坏了（真仓库不可能三个文件都没 alias）。
  # 报错，不给空数组 —— 见文件头。
  if (( total == 0 )); then
    echo "Error: 三个源文件里一条 alias 都没抽到 —— 解析方式可能跟不上文件格式了。" >&2
    return 1
  fi

  # 拼 JSON 数组。按源相对路径分组输出（组 = 文件，见文件头决定 1）。
  # 用「组数组」：每个文件一个对象，含 file + aliases。
  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"alias-status.zsh\","$'\n'
  out+="  \"files\": ["$'\n'

  local -a file_blocks=()
  # ⚠️ **所有 `local` 声明必须在这里（循环外）一次性做完。**
  # zsh 的坑：在**会跑两遍以上的循环里**写 `local x`，而 `x` 已经有值时，
  # zsh 会把 `x=值` **打印到 stdout** —— 直接污染 JSON。
  # （第一版就是 `local r` 写在 `for one_rel` 里，第二次迭代时输出
  #  `r=$'...'` 到 stdout，产出的 JSON 前面多了一堆垃圾行。
  #  这个坑不报错、只在循环第二次出现，极难查 —— 所以写死在这里。）
  local one_rel block r i item name value cond itemrow
  local -a items=()

  for one_rel in "${SOURCE_RELS[@]}"; do
    # 每个文件重置，但**不重新 `local`**（见上面的坑）。
    items=()
    for r in "${rows[@]}"; do
      [[ "${r##*$'\t'}" == "$one_rel" ]] || continue
      # r = 名<TAB>值<TAB>条件<TAB>file；切掉最后的 file 字段。
      items+=("${r%$'\t'*}")
    done

    block=""
    block+="    {"$'\n'
    block+="      \"file\": \"$(json_escape "$one_rel")\","$'\n'
    block+="      \"aliases\": ["
    if (( ${#items[@]} == 0 )); then
      block+="]"$'\n'
    else
      block+=$'\n'
      for (( i = 1; i <= ${#items[@]}; i++ )); do
        item="${items[$i]}"
        name="${item%%$'\t'*}"
        value="${item#*$'\t'}"
        cond="${value#*$'\t'}"
        value="${value%%$'\t'*}"
        itemrow="        {"
        itemrow+=$'\n'"          \"name\": \"$(json_escape "$name")\","
        itemrow+=$'\n'"          \"value\": \"$(json_escape "$value")\","
        itemrow+=$'\n'"          \"condition\": "
        if [[ -n "$cond" ]]; then
          itemrow+="\"$(json_escape "$cond")\""
        else
          itemrow+="null"
        fi
        itemrow+=$'\n'"        }"
        block+="$itemrow"
        (( i < ${#items[@]} )) && block+=","
        block+=$'\n'
      done
      block+="      ]"$'\n'
    fi
    block+="    }"
    file_blocks+=("$block")
  done

  for (( i = 1; i <= ${#file_blocks[@]}; i++ )); do
    out+="${file_blocks[$i]}"
    (( i < ${#file_blocks[@]} )) && out+=","
    out+=$'\n'
  done
  out+="  ],"$'\n'
  out+="  \"count\": $total"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  local json
  json="$(render_json)" || return 1

  # 自己先验一遍合法性 —— 产出的不是合法 JSON 是 bug，要在**发出前**发现
  # （照 link-status.zsh）。
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
