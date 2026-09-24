#!/usr/bin/env zsh
#
# 落点状态：回答「$HOME 下的配置落点现在什么样」。契约见 macview-contract.md 第 2.2 节。
#
# ## 它做什么
#
# 逐个检查 `link-dotfiles.zsh` 里 `DOTFILE_LINKS` 声明的每一个落点，判断它
# 处于四态中的哪一个，输出一个 JSON 到 stdout。
#
# ## 它不做什么
#
# **不链接、不改任何文件。** 和 private-state.zsh / brew-audit.zsh 是同一类
# 只读检测器。要真的链，调 `install.zsh link`（那是另一件事，另一个进程）。
#
# ## 落点清单从哪来 —— 这是本脚本最要紧的决定
#
# **从 link-dotfiles.zsh 的 `DOTFILE_LINKS` 读，不在这里再抄一份。**
#
# 理由：抄一份 = 两份声明 = 迟早漂移。而漂移的表现是「GUI 显示 19 个落点，
# 实际链了 20 个」这种不报错的错。仓库里已经有唯一一份声明
# （link-dotfiles.zsh:34），只能有一个真相。
#
# ## 怎么读那个数组而不执行整个脚本
#
# link-dotfiles.zsh 末尾有 `main "$@"`，直接 source 会**真的去链**。
# 所以只把 `DOTFILE_LINKS=(...)` 那段抠出来在本进程里 eval。
# 抠法：从 `DOTFILE_LINKS=(` 到第一个单独 `)` 为止。这个写法对「数组用
# 多行括号」这个格式是稳的 —— 而被抠的文件格式由我们自己控制
# （link-dotfiles.zsh 的注释里也写了「改这里就够了」）。
#
# ⚠️ 抠不出来时必须**报错退出**，不能悄悄给出空数组 ——
# 空数组会让 GUI 显示「0 个落点，全都没问题」，那是假消息。
#
# 用法：
#   zsh scripts/macos/link-status.zsh --json    # 打印 JSON 到 stdout

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; cannot determine dotfile locations." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"
LINK_IMPL="$ROOT_DIR/scripts/macos/link-dotfiles.zsh"

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/link-status.zsh --json

  --json    把落点状态打到 stdout（只读，不落盘）

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
  echo "link-status 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── JSON 工具（照抄 private-state.zsh，理由见那里）──────────────────────
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

# $HOME 下的绝对路径（和 private-state.zsh 的 json_home_path 一致）。
# 用绝对路径而不是 `~`：JSON 里 `~` 不会被任何标准工具展开，等于给了一个
# 「看起来能直接用、其实不能」的值。
json_home_path() {
  local rel="$1"
  printf '"%s"' "$(json_escape "$HOME/$rel")"
}

# ── 从 link-dotfiles.zsh 抠出 DOTFILE_LINKS ─────────────────────────────
extract_links() {
  local lines=()
  local line in_block=0

  while IFS= read -r line; do
    if (( in_block )); then
      if [[ "$line" == ')' ]]; then
        in_block=0
        break
      fi
      lines+=("$line")
    elif [[ "$line" == 'DOTFILE_LINKS=(' ]]; then
      in_block=1
    fi
  done <"$LINK_IMPL"

  # 没找到 `DOTFILE_LINKS=(`，说明 link-dotfiles.zsh 的结构变了。
  # 报错，不返回空 —— 空的会被当成「一个落点都没有」的假消息。
  if (( ${#lines[@]} == 0 )); then
    echo "Error: 在 $LINK_IMPL 里找不到 DOTFILE_LINKS 数组；link-status 的抠取方式需要跟着改。" >&2
    return 1
  fi

  printf '%s\n' "${lines[@]}"
}

# ── 四态判定 ────────────────────────────────────────────────────────────
#
#   linked : 是个符号链接，且指向仓库里的源
#   drift  : 是个符号链接，但指向别处（或源已不存在）
#   absent : 目标不存在
#   other  : 目标是个真文件/目录，不是链接 —— 不能碰，也说不上对错
#
# 为什么 other 要独立：它是「用户自己放了个真文件」。GUI 若把它算成 drift，
# 会误导人去「修复」，而真文件一删就没了（不可逆）。
state_of() {
  local dest="$1" src="$2"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest" || true)"
    if [[ "$current" == "$src" ]]; then
      printf 'linked'
    else
      printf 'drift'
    fi
  elif [[ -e "$dest" ]]; then
    printf 'other'
  else
    printf 'absent'
  fi
}

render_json() {
  local now
  now="$(date +%s)"

  local -a entries=()
  # 抠取失败要让它整体失败（set -e 下 `|| return 1` 会向上传）。
  local raw
  raw="$(extract_links)" || return 1
  entries=("${(@f)raw}")

  local -a rows=()
  local entry src_rel dest_rel src dest st row
  local n_linked=0 n_drift=0 n_absent=0 n_other=0

  for entry in "${entries[@]}"; do
    # 抠出来的是源文件里的**字面行**，带着缩进和两侧的单引号：
    #   `  'zsh/zshenv|.zshenv'`
    # 要先还原成 `zsh/zshenv|.zshenv`。
    # 去前导空白用参数展开（`${x%%[![:space:]]*}` 是「第一个非空白之前的部分」），
    # 别用 `${x##[[:space:]]#}` —— `#` 那个「零或更多」要 extendedglob 才对。
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    entry="${entry#\'}"
    entry="${entry%\'}"
    [[ -n "$entry" ]] || continue
    src_rel="${entry%%|*}"
    dest_rel="${entry#*|}"
    src="$ROOT_DIR/src/macos/config/$src_rel"
    dest="$HOME/$dest_rel"
    st="$(state_of "$dest" "$src")"

    case "$st" in
      linked) (( n_linked++ )) ;;
      drift)  (( n_drift++ )) ;;
      absent) (( n_absent++ )) ;;
      other)  (( n_other++ )) ;;
    esac

    # 每一行拼成一个完整字符串再入数组 —— 跨行的数组拼接容易被 zsh 的
    # 解析搞乱（本文件第一版就是这么错的：产出不是合法 JSON）。
    row="    {"
    row+=$'\n'"      \"src\": \"$(json_escape "$src_rel")\","
    row+=$'\n'"      \"dest\": $(json_home_path "$dest_rel"),"
    row+=$'\n'"      \"state\": \"$st\""
    row+=$'\n'"    }"
    rows+=("$row")
  done

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"link-status.zsh\","$'\n'
  out+="  \"targets\": ["$'\n'
  local i
  for (( i = 1; i <= ${#rows[@]}; i++ )); do
    out+="${rows[$i]}"
    (( i < ${#rows[@]} )) && out+=","
    out+=$'\n'
  done
  out+="  ],"$'\n'
  out+="  \"counts\": {"$'\n'
  out+="    \"linked\": $n_linked,"$'\n'
  out+="    \"drift\": $n_drift,"$'\n'
  out+="    \"absent\": $n_absent,"$'\n'
  out+="    \"other\": $n_other"$'\n'
  out+="  }"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  local json
  json="$(render_json)" || return 1

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
