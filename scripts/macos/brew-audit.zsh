#!/usr/bin/env zsh
#
# 对账：packages/*.txt 里声明的包，这台机器实际装了没有。
#
# 「清单说该有、这台没有」是最常见的静默失效 —— 这个脚本专门报它。
#
# ## 输出分三类
#
#   - 缺失：声明了、这台没装        → 该跑 install.zsh
#   - 重复：清单内部或跨清单出现两次 → 清理，否则计数会和逐清单相加对不上
#   - 多出：这台有、清单里没有      → 要不要加进清单，你决定
#
# ## 两种输出：给人看的文本 / 给 macview 看的 JSON
#
#   默认            人读文本（就是下面那三段）
#   `--json`        结构化 JSON 到 stdout，契约见 macview-contract.md 第 2.3 节
#
# **两模式共用同一份「算出来的结果」** —— 不是各算一遍。判据只有一处，
# 不会出现「文本说缺 3 个、JSON 说缺 2 个」这种两个真相。
#
# ## 解析规则
#
# 与 scripts/macos/brew-packages-install.zsh 保持同一套：
#   `#` 之后是注释 / 去掉前导空白后取第一个字段 / 取 basename 去比。
# 两处任何一处改了规则，另一边必须同步 —— 否则装的和报的会对不上。
#
# 只覆盖公共仓库的 2 份清单（macos cli + macos cask）。
#
# 用法：
#   zsh scripts/macos/brew-audit.zsh           # 人读文本
#   zsh scripts/macos/brew-audit.zsh --json    # JSON

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONTRACT_VERSION=1

MODE="text"

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/brew-audit.zsh [--json]

  默认      人读文本报告
  --json    结构化 JSON 到 stdout（给 macview 用，只读）

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

# 这个仓库只做 macOS。不假装能跑别的平台 —— 和 check.zsh 的态度一致。
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "brew-audit 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# 非交互 shell 的 PATH 里可能没有 homebrew（见 brew-env.zsh 的说明）。
# 先补齐，否则会对着一台装好 brew 的机器报「brew not found」。
source "$SCRIPT_DIR/brew-env.zsh" || true

# ── JSON 工具（和别的只读检测器同一套）────────────────────────────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# 与 macview parsePackageList 同规则：去注释、取第一个**非空**字段。
#
# ⚠️ 不能写成 `${pkg%%[[:space:]]*}` —— 那会让前导空白的行（`  zsh`）
# 得到空串而漏掉。Swift 的 `split(whereSeparator:)` 会丢弃空子串，
# 所以它认得 `  zsh` 里的 `zsh`。这里先 ltrim 再取第一段，行为才一致。
read_declared() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line pkg
  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"   # 去掉前导空白
    pkg="${pkg%%[[:space:]]*}"              # 取第一个字段
    [[ -n "$pkg" ]] || continue
    echo "$pkg"
  done <"$file"
}

# 取最后一段（`user/tap/formula` → `formula`）。
# 串到流水线里用；命名保留 basename 的说法，和 macview 的 basename() 对应。
basename_of() { echo "${1##*/}"; }

# ── 算出结果（文本和 JSON 共用）─────────────────────────────────────────
#
# 全部结果经全局数组返回，避免在 stdout 里混进别的东西（JSON 模式尤其怕这个）。
#
# 全局：
#   _missing      元素形如 `label\tname`
#   _duplicated   元素形如 `label\tname`
#   _extras       元素形如 `name`
#   _declared_cli / _declared_cask   计数
#   _installed_cli / _installed_cask 计数
compute_audit() {
  # label|kind|path —— 与 macview 的 packageListFiles 对应。
  #
  # ⚠️ 只覆盖**公共仓库**的这 2 份。用户自己另装的包不在这里查 ——
  # 本脚本只对账「仓库声明的」vs「本机装的」，不猜用户额外加了什么。
  #
  # 以前是 3 条（common formulae / macos formulae / casks）—— 前两份已合并
  # 成 packages/macos/brew-cli.txt（仓库只做 macOS）。
  local specs=(
    "公共 / formulae|formula|$ROOT_DIR/packages/macos/brew-cli.txt"
    "公共 / casks|cask|$ROOT_DIR/packages/macos/brew-cask.txt"
  )

  local installed_formulae installed_casks
  installed_formulae="$(brew list --formula 2>/dev/null | sort -u)"
  installed_casks="$(brew list --cask 2>/dev/null | sort -u)"

  _installed_cli=$(( $(printf '%s\n' "$installed_formulae" | grep -c .) ))
  _installed_cask=$(( $(printf '%s\n' "$installed_casks" | grep -c .) ))

  # 所有 local 在**循环外声明一次**，而且**不要**和别处的变量重名。
  #
  # ⚠️ 不要在会多次执行的循环体里写 `local x` —— zsh 在重新声明一个
  # 已存在的变量时会把它打印到 stdout（`name=pkgB`），污染审计输出。
  # 这是本文件踩过的真坑，不是理论风险。
  #
  # ⚠️ 并且**绝不要**用 `path` 当变量名 —— `path` 是 zsh 的保留变量，和
  # `PATH` 是同一个数组。`local path`（不带值）会把 PATH 清空，之后所有
  # `command brew` 都变成 `command not found`，而**不报错**。
  # 所以这里叫 `list_path`。（selfcheck 的 check_no_local_path 会拦这个。）
  local -a names=() seen=()
  local spec label kind list_path name installed_set dup_key

  _missing=()
  _duplicated=()
  _extras=()
  _declared_cli=0
  _declared_cask=0

  for spec in "${specs[@]}"; do
    label="${spec%%|*}"
    kind="${${spec#*|}%%|*}"
    list_path="${spec##*|}"

    names=()
    seen=()
    [[ -f "$list_path" ]] || continue
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      names+=("$(basename_of "$name")")
    done < <(read_declared "$list_path")

    if [[ "$kind" == "cask" ]]; then
      _declared_cask=${#names[@]}
    else
      _declared_cli=${#names[@]}
    fi

    # 清单内重复。
    # 与 macview 的 duplicates() 一致：同一个重复名**只报一次**
    # （`!dups.contains(n)`）。逐次出现地报会和 macview 的计数对不上。
    for name in "${names[@]}"; do
      if (( ${seen[(I)$name]} )); then
        dup_key="$label: $name"
        (( ${_duplicated[(I)$dup_key]} )) || _duplicated+=("$dup_key")
      else
        seen+=("$name")
      fi
    done

    if [[ "$kind" == "cask" ]]; then
      installed_set="$installed_casks"
    else
      installed_set="$installed_formulae"
    fi

    for name in "${names[@]}"; do
      if (( ${${(f)installed_set}[(I)$name]} )); then
        : # 已装
      else
        _missing+=("$label: $name")
      fi
    done
  done

  # 「多出」：这台装了、清单里没有。
  #
  # ⚠️ **formula 和 cask 都算**（2026-09-27 改）。
  #
  # 以前只算 formula，理由是「cask 太多系统自带/手动装的」。但那让 cask
  # 在 macview 里**完全看不见** —— 用户装了个 cask、清单里没有，界面不显示、
  # 也就无从卸载。现在两边都列，**照实列、不画勾**（和 formula 一个规矩：
  # 「多出」不等于「该卸」，见 brew-uninstall.zsh 的文件头）。
  #
  # ⚠️ `declared_all` 里存的是**名字**、**不含 kind** —— formula 和 cask
  # 理论上可能同名。所以判定要**分 kind 各查各的**，不能用一个大集合
  # （那会把「和某个 cask 同名的 formula」误判成「已声明」）。
  local -a declared_cli_names=() declared_cask_names=()
  local spec2 kind2 list_path2 n2
  for spec2 in "${specs[@]}"; do
    kind2="${${spec2#*|}%%|*}"
    list_path2="${spec2##*|}"
    [[ -f "$list_path2" ]] || continue
    while IFS= read -r n2; do
      [[ -n "$n2" ]] || continue
      if [[ "$kind2" == "cask" ]]; then
        declared_cask_names+=("$(basename_of "$n2")")
      else
        declared_cli_names+=("$(basename_of "$n2")")
      fi
    done < <(read_declared "$list_path2")
  done

  # `_extras` 元素形如 `kind\tname` —— JSON 要分 kind（界面靠它决定怎么卸）。
  local inst
  while IFS= read -r inst; do
    [[ -n "$inst" ]] || continue
    if (( ! ${declared_cli_names[(I)$inst]} )); then
      _extras+=("formula"$'\t'"$inst")
    fi
  done <<<"$installed_formulae"

  while IFS= read -r inst; do
    [[ -n "$inst" ]] || continue
    if (( ! ${declared_cask_names[(I)$inst]} )); then
      _extras+=("cask"$'\t'"$inst")
    fi
  done <<<"$installed_casks"
}

# ── 文本输出（原来的样子，保留）────────────────────────────────────────
render_text() {
  # ⚠️ `item` 在下面「多出」那段用到。**在函数开头声明一次** ——
  # 在会跑多遍的循环体里 `local` 已有值的变量，zsh 会把 `x=值` 打到 stdout
  # （本文件 compute_audit 那段记着这个真坑）。`ex_kind` / `ex_name` 同理。
  local item ex_kind ex_name

  echo "== 清单里声明、但没装 =="
  if (( ${#_missing[@]} == 0 )); then
    echo "  （无）"
  else
    printf '  %s\n' "${_missing[@]}"
  fi

  echo
  echo "== 清单内部/跨清单重复 =="
  if (( ${#_duplicated[@]} == 0 )); then
    echo "  （无）"
  else
    printf '  %s\n' "${_duplicated[@]}"
  fi

  echo
  echo "== 这台装了、清单里没有（formula + cask，仅供参考，不一定要卸）=="
  if (( ${#_extras[@]} == 0 )); then
    echo "  （无）"
  else
    # `_extras` 元素是 `kind\tname` —— 文本模式给 cask 加个后缀，
    # 一眼能区分（cask 卸载的后果和 formula 不同，见 brew-uninstall.zsh）。
    for item in "${_extras[@]}"; do
      ex_kind="${item%%$'\t'*}"
      ex_name="${item#*$'\t'}"
      if [[ "$ex_kind" == "cask" ]]; then
        printf '  %s  (cask)\n' "$ex_name"
      else
        printf '  %s\n' "$ex_name"
      fi
    done
  fi

  echo
  if (( ${#_missing[@]} > 0 )); then
    echo "有 ${#_missing[@]} 个包缺失 → zsh install.zsh"
    return 1
  fi
  echo "对齐。"
  return 0
}

# ── JSON 输出（给 macview）──────────────────────────────────────────────
#
# `missing` / `duplicated` / `extra` 每项拆成 kind + name：
#   `公共 / formulae: jq` → { "label": "公共 / formulae", "kind": "formula", "name": "jq" }
# label 里带「formulae/casks」—— 从 label 无法可靠反推 kind（中文标签会改），
# 所以 kind 在 compute_audit 时就要留住。这里按清单顺序重建：先 formulae 后 casks。
render_json() {
  local now
  now="$(date +%s)"

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"brew-audit.zsh\","$'\n'
  out+="  \"declared\": { \"cli\": $_declared_cli, \"cask\": $_declared_cask },"$'\n'
  out+="  \"installed\": { \"cli\": $_installed_cli, \"cask\": $_installed_cask },"$'\n'

  local item label name kind rows first

  # ── missing ──
  rows=""
  first=1
  for item in "${_missing[@]}"; do
    label="${item%%: *}"
    name="${item#*: }"
    kind="formula"
    [[ "$label" == *cask* ]] && kind="cask"
    (( first )) || rows+=","$'\n'
    first=0
    rows+="    { \"label\": \"$(json_escape "$label")\", \"kind\": \"$kind\", \"name\": \"$(json_escape "$name")\" }"
  done
  out+="  \"missing\": ["$'\n'
  out+="$rows"$'\n'
  out+="  ],"$'\n'

  # ── duplicate ──
  rows=""
  first=1
  for item in "${_duplicated[@]}"; do
    label="${item%%: *}"
    name="${item#*: }"
    kind="formula"
    [[ "$label" == *cask* ]] && kind="cask"
    (( first )) || rows+=","$'\n'
    first=0
    rows+="    { \"label\": \"$(json_escape "$label")\", \"kind\": \"$kind\", \"name\": \"$(json_escape "$name")\" }"
  done
  out+="  \"duplicate\": ["$'\n'
  out+="$rows"$'\n'
  out+="  ],"$'\n'

  # ── extra（formula + cask）──
  # `_extras` 元素是 `kind\tname`。kind 直接写进 JSON —— 界面靠它决定
  # 「按 formula 卸」还是「按 cask 卸」（两条卸载路径的警告措辞不同）。
  rows=""
  first=1
  for item in "${_extras[@]}"; do
    kind="${item%%$'\t'*}"
    name="${item#*$'\t'}"
    (( first )) || rows+=","$'\n'
    first=0
    rows+="    { \"kind\": \"$kind\", \"name\": \"$(json_escape "$name")\" }"
  done
  out+="  \"extra\": ["$'\n'
  out+="$rows"$'\n'
  out+="  ]"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found; 无法对账。先装 Homebrew。" >&2
    exit 2
  fi

  compute_audit

  if [[ "$MODE" == "json" ]]; then
    local json
    json="$(render_json)"
    if command -v python3 >/dev/null 2>&1; then
      if ! printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        echo "内部错误：产出的 JSON 不合法（这是个 bug，请报告）。" >&2
        exit 1
      fi
    fi
    printf '%s\n' "$json"
    # 退出码语义和文本模式一致：有缺失就 1。
    (( ${#_missing[@]} > 0 )) && exit 1
    exit 0
  fi

  render_text
}

main "$@"
