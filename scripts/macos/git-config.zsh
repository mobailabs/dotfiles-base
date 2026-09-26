#!/usr/bin/env zsh
#
# git 配置：回答「这台 Mac 的 git 全局配置现在是什么样」。
# 契约见 macview-contract.md 第 2.13 节（本文建时新增）。
#
# ## 它做什么
#
# 跑 `git config --list --show-origin`，把**生效的** git 配置整理成几块：
#
#   · sources  —— 有哪些文件在贡献配置（git 实际读的）
#   · aliases  —— `alias.*`（git 别名）
#   · settings —— 一组**值得一眼看**的键的值（core.editor / autocrlf / …）
#   · includes —— `include.path` 链
#   · all      —— **全部**生效配置项（key / value / 来源文件）
#
# ## 它不做什么（三条，和 git-identity.zsh 同一套纪律）
#
# 1. **不改任何 git 配置、不 commit、不发网络。** 是只读检测器。
# 2. **不读 token / 密码。** 凭据 helper 只报命令（那本来就写在公开的
#    gitconfig 里，不是秘密）。`gh` 的 `hosts.yml` 碰都不碰。
#    —— 凭据的字段由 §2.9 `git-identity.zsh` 负责；本脚本**不重复报它**，
#    只报 `credential.*.helper` 之外的普通配置。
# 3. **不判好坏。** `core.autocrlf = input` 是一个**事实**，不是「对 / 错」。
#    「这个值对不对」是界面（用户）的事，脚本只报值 + 来源。
#
# ## 最要紧的决定：**问 git，不自己解析 gitconfig**
#
# 和 §2.9 同一条理由：gitconfig 的值可能来自**系统文件** / **用户文件** /
# `include` 进来的文件 / 环境变量 / 仓库配置，**有优先级、要合并**。
# 自己解析 = 自己复刻一套 git 的合并规则 —— 复刻错了界面就报一个 git 不认的值。
# `git config --list --show-origin` 是 git 自己算完优先级、展开完 include
# 之后的结果，还带 `--show-origin` 标出「这个值从哪个文件来」。
#
# ## 为什么不报「哪些键是 dotfiles 声明 vs 用户自己加的」
#
# 那要把「仓库里的 gitconfig」和「本机生效的 gitconfig」对账 —— 而本机生效的
# 里有 `~/.gitconfig.local`（用户的私有 overlay）和环境变量来的，两者混在一起。
# 对账会给出一个「哪些是 dotfiles 管的」的结论，那是**判断**，不是**事实**。
# 本脚本**只报事实**（值 + 从哪个文件来），把「哪个文件是仓库的」留给界面
# 按路径去说 —— 界面能一眼看出 `~/.gitconfig` 是仓库链过去的（软链）。
#
# ## `all` 里重复的 key 怎么办
#
# `git config --list` 会把**同一个 key 出现多次**都列出来（不同来源、后被覆盖的
# 也在）。本脚本**全报**（`all` 保留每条 + 各自来源），因为「git 最终用哪个」
# 已经由 `settings` 取**最后一个**体现了 —— `all` 是给人核对来源用的。
#
# 用法：
#   zsh scripts/macos/git-config.zsh --json

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set." >&2
  exit 1
fi

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/git-config.zsh --json

  --json    把 git 全局配置状态打到 stdout（只读，不落盘）

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
  echo "git-config 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── JSON 工具（照抄 link-status / git-identity，理由见那里）──────────────
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

# ── 值得一眼看的键（**写死的「关键设置」清单，不是全集**）──────────────
#
# 这些是「大多数开发者会在意、且能一眼看出是不是自己想要的」的键。
# **不是全集** —— 全集在 `all` 里。清单短、有顺序，供界面第二层显示。
#
# ⚠️ 为什么写死：`git config --list` 不告诉我们「哪个键重要」——那是个**选择**，
# 只能由人定。写死在这里，改一处即可。
NOTABLE_KEYS=(
  core.editor
  core.autocrlf
  core.excludesfile
  core.attributesfile
  core.ignorecase
  core.filemode
  init.defaultbranch
  pull.rebase
  rebase.autosquash
  commit.gpgsign
  push.default
  push.autosetupremote
  merge.conflictstyle
  diff.colorMoved
  log.date
  credential.helper
)

# ── 问 git ──────────────────────────────────────────────────────────────
#
# ⚠️ **从一个中立的目录跑（`/`），不在仓库里跑。**
#
# `git config --list` 会**把当前仓库的 `.git/config` 也算进来**。如果 macview
# 恰好在某个仓库目录里起这个脚本，`all` 里就会混进那个仓库的本地配置
# （`.git/config`）—— 而这一页要的是**全局** git 环境，不是「某个仓库」的。
# 仓库自己的配置属于那个仓库（dotfiles 仓库的归 Dotfiles 页，框架 §11）。
# 所以固定 `cd /` 跑，只拿 system + global + include 这三层。
#
# ⚠️ git 不在时**报错退出**，不给空结果 —— 空结果会被界面显示成
# 「没配任何配置」，而真相是「问不出 git」。
git_config_dump() {
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: 找不到 git，问不出配置。" >&2
    return 1
  fi
  # 在子 shell 里 `cd /` —— 不改本脚本的工作目录。
  ( cd / && git config --list --show-origin 2>/dev/null )
  return 0
}

# ── 解析工具（照抄 git-identity，理由见那里）────────────────────────────
#
# 一行长这样（源后面是一个 **tab**，然后 `key=value`）：
#   file:/Users/you/.gitconfig.local<TAB>user.name=cole

# 从一行里取 `key=value` 部分（tab 之后）。
line_kv() {
  local line="$1"
  printf '%s' "${line#*$'\t'}"
}

# 从一行里取「源」部分（tab 之前），并去掉 `file:` 前缀 → 给人看的路径。
line_origin() {
  local line="$1"
  local src="${line%%$'\t'*}"
  case "$src" in
    file:*) printf '%s' "${src#file:}" ;;
    *) printf '%s' "$src" ;;
  esac
}

# 取一行的 key（`=` 之前）。git 输出里 key 是**小写**的。
line_key() {
  local kv="$1"
  printf '%s' "${kv%%=*}"
}

# 取一行的 value（`=` 之后，含空值）。
line_value() {
  local kv="$1"
  if [[ "$kv" == *=* ]]; then printf '%s' "${kv#*=}"; fi
}

# 「关键设置」里有没有这个 key（小写比）。有 → 返回 0。
is_notable() {
  local key="$1" n
  for n in "${NOTABLE_KEYS[@]}"; do
    [[ "${(L)n}" == "$key" ]] && return 0
  done
  return 1
}

render_json() {
  local now
  now="$(date +%s)"

  local dump
  dump="$(git_config_dump)" || return 1

  # ⚠️ 所有 `local` 声明在循环外一次做完 —— zsh 的坑：在**会跑两遍以上的
  # 循环里**写 `local x`，而 `x` 已经有值时，zsh 会把 `x=值` **打印到 stdout**，
  # 直接污染 JSON。（同样的坑在 alias-status.zsh / git-identity.zsh 里记过。）
  local line kv key value origin
  local -a all_keys=() all_vals=() all_origins=()
  local -a alias_keys=() alias_vals=()
  local -a notable_keys=() notable_vals=()
  local -a include_paths=()
  local -a seen_sources=()
  local prev_key="" has_value=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kv="$(line_kv "$line")"
    [[ "$kv" == *=* ]] || continue
    key="$(line_key "$kv")"
    value="$(line_value "$kv")"
    origin="$(line_origin "$line")"

    # 全部生效项（**含被后面覆盖的** —— 这一份是给人核对来源用的）。
    all_keys+=("$key")
    all_vals+=("$value")
    all_origins+=("$origin")

    # 记录配置文件的来源（去重）。
    if [[ -n "$origin" ]]; then
      if (( ${seen_sources[(Ie)$origin]} == 0 )); then
        seen_sources+=("$origin")
      fi
    fi

    case "$key" in
      alias.*)
        # 去重：同一个别名被后面的文件覆盖，**取最后一个**（git 的优先级）。
        # 做法：先记全部，下面再倒着取最后一个（见「拼 JSON」前的整理）。
        alias_keys+=("${key#alias.}")
        alias_vals+=("$value") ;;
      include.path)
        include_paths+=("$value") ;;
      credential.*.helper)
        # ⚠️ 跳过**空值** —— gitconfig 里每个 host 有两条 helper：
        # 一条空（重置）、一条是命令。凭据的详细报由 §2.9 负责，
        # 这里只在 `settings` 里体现 `credential.helper`（全局兜底那条）。
        ;; 
      *)
        # 关键设置：同一个 key 取**最后一个**（下面整理）。
        if is_notable "$key"; then
          notable_keys+=("$key")
          notable_vals+=("$value")
        fi ;;
    esac
  done <<<"$dump"

  # 一条都没有 → 报错退出（同 link-status / alias-status 的纪律）。
  if (( ${#all_keys[@]} == 0 )); then
    echo "Error: git 没给出任何配置（可能 git 坏了）。" >&2
    return 1
  fi

  # ── 去重：别名 / 关键设置都**取最后一个** ─────────────────────────────
  #
  # git 的优先级是「后面的覆盖前面的」，`--list` 也按从低到高排，
  # 所以同一个 key 的生效值是**最后一个**（同 git-identity 取 user.name 的做法）。
  local i j found
  local -a uniq_alias_keys=() uniq_alias_vals=()
  for (( i = 1; i <= ${#alias_keys[@]}; i++ )); do
    found=0
    for (( j = 1; j <= ${#uniq_alias_keys[@]}; j++ )); do
      if [[ "${uniq_alias_keys[$j]}" == "${alias_keys[$i]}" ]]; then
        uniq_alias_vals[$j]="${alias_vals[$i]}"  # 后来的覆盖
        found=1
        break
      fi
    done
    if (( found == 0 )); then
      uniq_alias_keys+=("${alias_keys[$i]}")
      uniq_alias_vals+=("${alias_vals[$i]}")
    fi
  done

  local -a uniq_notable_keys=() uniq_notable_vals=()
  for (( i = 1; i <= ${#notable_keys[@]}; i++ )); do
    found=0
    for (( j = 1; j <= ${#uniq_notable_keys[@]}; j++ )); do
      if [[ "${uniq_notable_keys[$j]}" == "${notable_keys[$i]}" ]]; then
        uniq_notable_vals[$j]="${notable_vals[$i]}"
        found=1
        break
      fi
    done
    if (( found == 0 )); then
      uniq_notable_keys+=("${notable_keys[$i]}")
      uniq_notable_vals+=("${notable_vals[$i]}")
    fi
  done

  # ── 拼 JSON ─────────────────────────────────────────────────────────
  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"git-config.zsh\","$'\n'

  # sources：哪些文件在贡献配置。
  out+="  \"sources\": ["
  if (( ${#seen_sources[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#seen_sources[@]}; i++ )); do
      out+="    \"$(json_escape "${seen_sources[$i]}")\""
      (( i < ${#seen_sources[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # includes：include.path 链。
  out+="  \"include_paths\": ["
  if (( ${#include_paths[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#include_paths[@]}; i++ )); do
      out+="    \"$(json_escape "${include_paths[$i]}")\""
      (( i < ${#include_paths[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # settings：关键设置（去重后的生效值）。
  out+="  \"settings\": ["
  if (( ${#uniq_notable_keys[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#uniq_notable_keys[@]}; i++ )); do
      out+="    { \"key\": \"$(json_escape "${uniq_notable_keys[$i]}")\", \"value\": $(json_str_or_null "${uniq_notable_vals[$i]}") }"
      (( i < ${#uniq_notable_keys[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # aliases：git 别名（去重后的生效值）。
  out+="  \"aliases\": ["
  if (( ${#uniq_alias_keys[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#uniq_alias_keys[@]}; i++ )); do
      out+="    { \"name\": \"$(json_escape "${uniq_alias_keys[$i]}")\", \"value\": \"$(json_escape "${uniq_alias_vals[$i]}")\" }"
      (( i < ${#uniq_alias_keys[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # all：全部生效项（含被覆盖的，带各自来源）。
  out+="  \"all\": ["
  if (( ${#all_keys[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#all_keys[@]}; i++ )); do
      out+="    { \"key\": \"$(json_escape "${all_keys[$i]}")\", \"value\": $(json_str_or_null "${all_vals[$i]}"), \"origin\": $(json_str_or_null "${all_origins[$i]}") }"
      (( i < ${#all_keys[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # counts：脚本自报（界面**以自己的数组长度为准**，同 §2.8）。
  out+="  \"counts\": { \"settings\": ${#uniq_notable_keys[@]}, \"aliases\": ${#uniq_alias_keys[@]}, \"all\": ${#all_keys[@]} }"$'\n'

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
