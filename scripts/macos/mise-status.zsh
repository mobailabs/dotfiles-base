#!/usr/bin/env zsh
#
# 开发环境状态：回答「mise 声明的工具装了没有」。契约见 macview-contract.md 第 2.5 节。
#
# ## 它做什么
#
# 只读地对比两件事：
#   · `src/macos/config/mise/config.toml` 里声明了什么（[tools] 段）
#   · `mise ls --json` 说这台机器装了什么
# 输出一个 JSON 到 stdout。
#
# ## 它不做什么
#
# **不装、不 `mise install`、不改任何文件、不发网络请求。**
# `mise ls` 是本地查询，不联网（联网的是 `mise install` / `mise use`）。
#
# ## 为什么要写 `--json` 而不是解析 `mise ls` 的表格
#
# mise 的 `ls` 默认输出是**给人看的表格**，列宽/颜色会变。`--json` 是它给的
# 稳定结构，直接用，不自己解析表格 —— 那又会变成「复刻别人的文本格式」，
# 正是这个仓库要避免的。
#
# ## 时间：这个查询可能慢
#
# `mise ls` 在某些环境下要起 shell、加载 config，可能要几百毫秒到几秒。
# 契约里写了它「懒查 + 可缓存」—— 那是 **macview 侧**的责任（它决定什么时候调），
# 本脚本只负责「调了就快答，答不出就如实说」。
#
# 用法：
#   zsh scripts/macos/mise-status.zsh --json    # 打印 JSON 到 stdout

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; cannot determine dotfile locations." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"
MISE_CONFIG="$ROOT_DIR/src/macos/config/mise/config.toml"

CONTRACT_VERSION=1

MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/mise-status.zsh --json

  --json    把 mise 状态打到 stdout（只读，不落盘、不联网）

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
  echo "mise-status 只支持 macOS（当前 $(uname -s)）" >&2
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

# ── 解析 config.toml 的 [tools] 段 ──────────────────────────────────────
#
# 只认这种极简格式（本仓库的 config.toml 就是这么写的）：
#   [tools]
#   node = "25"
# 早退条件：遇到下一个 `[` 开头的段就停。
#
# ⚠️ 这不是通用 TOML 解析器，是「读我们自己那份文件」的专用解析。
# 若哪天 config.toml 变复杂（多行值、行内注释），这里要跟着改 ——
# 所以 selfcheck 里有一条「mise 工具数」的交叉检查会盯着它。
read_declared_tools() {
  [[ -f "$MISE_CONFIG" ]] || return 0
  local in_tools=0 line name ver
  while IFS= read -r line; do
    # 去掉行尾注释（` # ...`）。值里不含 # 的前提下够用。
    line="${line%%#*}"
    if [[ "$line" == '[tools]' ]]; then in_tools=1; continue; fi
    if (( in_tools )) && [[ "$line" == '['* ]]; then in_tools=0; continue; fi
    (( in_tools )) || continue
    # `name = "version"`
    if [[ "$line" == *=* ]]; then
      name="${line%%=*}"
      ver="${line#*=}"
      name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
      ver="${ver#"${ver%%[![:space:]]*}"}"; ver="${ver%"${ver##*[![:space:]]}"}"
      ver="${ver#\"}"; ver="${ver%\"}"
      [[ -n "$name" ]] && printf '%s|%s\n' "$name" "$ver"
    fi
  done <"$MISE_CONFIG"
}

# ── 读 mise 装了什么 ────────────────────────────────────────────────────
#
# `mise ls --json` 的输出形状（mise 2025.x）是：
#   { "node": [ { "version": "25.1.0", "installed": true, ... } ], ... }
# 用 python3 抽成 `name|version` 行。没有 python3 就落 unknown —— 不猜。
read_installed_tools() {
  command -v mise >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  local raw
  raw="$(mise ls --json 2>/dev/null)" || return 1
  [[ -n "$raw" ]] || return 1

  printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
for name, entries in d.items():
    if not isinstance(entries, list):
        continue
    for e in entries:
        if isinstance(e, dict) and e.get("installed"):
            print(name + "|" + str(e.get("version") or ""))
' 2>/dev/null
}

render_json() {
  local now
  now="$(date +%s)"

  local mise_present="false"
  command -v mise >/dev/null 2>&1 && mise_present="true"

  # `mise_ok` 三态：true / false / null（null = 有 mise 但问不出结果）。
  local mise_ok="null"
  local -A installed_map=()
  if [[ "$mise_present" == "true" ]]; then
    local installed_raw
    if installed_raw="$(read_installed_tools)"; then
      mise_ok="true"
      # ⚠️ 这个临时变量名**不能**和后面 rows 循环里的变量重名 —— zsh 对
      # **已存在**的变量再 `local` 一次会把它打印到 stdout（`iver=1.98.1`），
      # 污染 JSON 而且是静默的。brew-audit.zsh:86 记着同一个坑。
      # 这里用 `inst_line` / `inst_name` / `inst_ver` 区分开。
      local inst_line inst_name inst_ver
      while IFS= read -r inst_line; do
        [[ -n "$inst_line" ]] || continue
        inst_name="${inst_line%%|*}"
        inst_ver="${inst_line#*|}"
        installed_map[$inst_name]="$inst_ver"
      done <<<"$installed_raw"
    else
      mise_ok="false"
    fi
  fi

  local -a rows=()
  local dline dname dver st iver row
  while IFS= read -r dline; do
    [[ -n "$dline" ]] || continue
    dname="${dline%%|*}"
    dver="${dline#*|}"

    if [[ "$mise_present" != "true" ]]; then
      st="unknown"          # 没 mise：说不上「装了没」
      iver=""
    elif [[ "$mise_ok" != "true" ]]; then
      st="unknown"          # 有 mise 但问不出来：也不能说 absent
      iver=""
    elif [[ -n "${installed_map[$dname]:-}" ]]; then
      # 装了。声明是「大版本」（如 `25`），装的是具体版本（如 `25.1.0`）——
      # 大版本对得上就算 ok，不对就 drift。（字符串前缀比对，够用且保守。）
      iver="${installed_map[$dname]}"
      if [[ "$iver" == "$dver"* ]]; then
        st="ok"
      else
        st="drift"
      fi
    else
      st="absent"
      iver=""
    fi

    row="    {"
    row+=$'\n'"      \"name\": \"$(json_escape "$dname")\","
    row+=$'\n'"      \"declared\": \"$(json_escape "$dver")\","
    row+=$'\n'"      \"installed\": $(json_str_or_null "$iver"),"
    row+=$'\n'"      \"state\": \"$st\""
    row+=$'\n'"    }"
    rows+=("$row")
  done < <(read_declared_tools)

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"mise-status.zsh\","$'\n'
  out+="  \"mise_present\": $mise_present,"$'\n'
  out+="  \"mise_ok\": $mise_ok,"$'\n'
  out+="  \"tools\": ["$'\n'
  local i
  for (( i = 1; i <= ${#rows[@]}; i++ )); do
    out+="${rows[$i]}"
    (( i < ${#rows[@]} )) && out+=","
    out+=$'\n'
  done
  out+="  ]"$'\n'
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
