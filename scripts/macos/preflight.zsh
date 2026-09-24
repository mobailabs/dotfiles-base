#!/usr/bin/env zsh
#
# 前提检查：回答「这台机器能不能开工」。契约见 macview-contract.md 第 2.1 节。
#
# ## 它做什么
#
# 只读地检查：仓库在不在、私有仓库在不在、要调的脚本逐个在不在、
# 命令行工具 / Homebrew / git 在不在。输出一个 JSON 到 stdout。
#
# ## 它不做什么
#
# **不装东西、不改任何文件、不发网络请求。** 和 private-state.zsh 是同一类
# 只读检测器。网络探测尤其重要：日常「看」的时候一次网络请求都不该发
# （旧实现那 5 秒 `curl` 是纯开销，见 macview-contract.md 第五节）。
#
# ## 为什么「脚本在不在」要单列
#
# 它会**变**。你在本仓库重命名一个脚本，macview 不知道（结构写死在它那边）——
# 不在前提里检查，表现就是「点了按钮，什么都没发生」。查了就能报出来。
#
# ## 三态，不是两态
#
# state 除了 present / absent，还有 unknown。理由（照 private.md 的精神）：
# 「问不出来」（超时、权限不够）被说成「不在」，会让人去装一个可能已经装好的
# 东西 —— 和「说成在」一样是假消息，只是方向相反。
#
# 用法：
#   zsh scripts/macos/preflight.zsh --json    # 打印 JSON 到 stdout

set -uo pipefail

# $HOME 是所有落点的基准。没它的话下面 `$HOME/...` 要么崩在参数展开，
# 要么产出 `/xxx` 这种**看起来合法、其实全错**的路径 —— 静默给 macview
# 一份假状态，比直接失败更糟。（private-state.zsh 就是这么防的。）
if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; cannot determine dotfile locations." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/preflight.zsh --json

  --json    把前提检查结果打到 stdout（只读，不落盘）

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

# 这个仓库只做 macOS。不假装能跑别的平台（和 private-state.zsh 态度一致）。
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "preflight 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── macview 要调的脚本（结构写死，见契约第四节）─────────────────────────
#
# ⚠️ 这份清单必须和 macview 的 `DotfilesLayout` 保持一致。改一处要改两处。
#    它是「结构写死」那份描述的仓库侧副本。
SCRIPTS=(
  'install.zsh|install.zsh'
  'scripts/macos/brew-install.zsh|brew-install.zsh'
  'scripts/macos/link-dotfiles.zsh|link-dotfiles.zsh'
  'scripts/macos/prefs.zsh|prefs.zsh'
  'scripts/macos/mise-setup.zsh|mise-setup.zsh'
  'scripts/macos/brew-audit.zsh|brew-audit.zsh'
  'scripts/macos/private-state.zsh|private-state.zsh'
)

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

# 一个字符串值，或 null。
json_str_or_null() {
  if [[ -z "${1:-}" ]]; then printf 'null'; else printf '"%s"' "$(json_escape "$1")"; fi
}

# ── 三态探测 ────────────────────────────────────────────────────────────
#
# 返回 present / absent / unknown。
#   present: 路径存在且可读
#   absent : 明确不存在（ENOENT）
#   unknown: 存在但读不了（EACCES 之类）—— 不能说成 absent
probe_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    if [[ -r "$p" ]]; then
      printf 'present'
    else
      printf 'unknown'
    fi
  else
    printf 'absent'
  fi
}

# 命令在不在 PATH 里（macview 侧会先 enhPath，这里只管当前 PATH）。
probe_command() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'present'
  else
    printf 'absent'
  fi
}

render_json() {
  local now
  now="$(date +%s)"

  local dotfiles_state private_state
  dotfiles_state="$(probe_path "$ROOT_DIR")"
  private_state="$(probe_path "$HOME/private-dotfiles")"

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"preflight.zsh\","$'\n'
  out+="  \"dotfiles\": {"$'\n'
  out+="    \"state\": \"$dotfiles_state\","$'\n'
  out+="    \"path\": $(json_str_or_null "$ROOT_DIR")"$'\n'
  out+="  },"$'\n'
  out+="  \"private\": {"$'\n'
  out+="    \"state\": \"$private_state\","$'\n'
  out+="    \"path\": $(json_str_or_null "$HOME/private-dotfiles")"$'\n'
  out+="  },"$'\n'
  out+="  \"scripts\": ["$'\n'

  local i spec name rel state
  local n=${#SCRIPTS[@]}
  for (( i = 1; i <= n; i++ )); do
    spec="${SCRIPTS[$i]}"
    rel="${spec%%|*}"
    name="${spec#*|}"
    state="$(probe_path "$ROOT_DIR/$rel")"
    out+="    {"$'\n'
    out+="      \"name\": \"$(json_escape "$name")\","$'\n'
    out+="      \"path\": \"$(json_escape "$rel")\","$'\n'
    out+="      \"state\": \"$state\""$'\n'
    out+="    }"
    (( i < n )) && out+=","
    out+=$'\n'
  done

  out+="  ],"$'\n'
  out+="  \"tools\": {"$'\n'
  out+="    \"git\": \"$(probe_command git)\","$'\n'
  out+="    \"homebrew\": \"$(probe_command brew)\""$'\n'
  out+="  }"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  local json
  json="$(render_json)"

  # JSON 合法性自检（照 private-state.zsh：产出时就自己发现，别让 GUI 一脸懵）。
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
