#!/usr/bin/env zsh
#
# git 身份：回答「这台机器 commit 时用谁的名字、为什么可能 commit 不了」。
# 契约见 macview-contract.md 第 2.9 节。
#
# ## 它做什么
#
# 跑 `git config --list --show-origin`，把和「身份 / 凭据」有关的配置值抽出来，
# 输出一个 JSON 到 stdout。
#
# ## 它不做什么
#
# **不改任何 git 配置、不 commit、不读 token。** 和 link-status.zsh /
# private-state.zsh 是同一类只读检测器。
#
# ## 最要紧的决定：**问 git，不自己解析 gitconfig 文件**
#
# 这是本脚本唯一重要的设计选择，理由有三条：
#
# 1. **gitconfig 的解析不是「读文本」那么简单。** 一个值可能来自
#    系统文件（`/opt/homebrew/etc/gitconfig`）、用户文件（`~/.gitconfig`）、
#    被 `include` 进来的文件（`~/.gitconfig.local`）、环境变量（`GIT_CONFIG_*`）、
#    仓库的 `.git/config`…… **顺序有优先级，后面的覆盖前面的。**
#    自己解析 = 自己复刻一套 git 的配置合并规则 —— 复刻错了，界面就会
#    报一个 git 根本不认的「身份」。
# 2. **问 git 拿到的就是真相。** `git config --list --show-origin` 是 git
#    自己展开完 include、算完优先级之后的结果，还带 `--show-origin` 标出
#    「这个值从哪个文件来」。界面要的正是这个。
# 3. **实测就有一个坑**：本机直接跑 `git config --global user.name` 是**空的**，
#    但 `git config user.name`（不加 --global）是 `cole`。也就是说
#    **「--global」和「实际生效」不是一回事**（--global 会少读一层）。
#    要是脚本自己去解析 `~/.gitconfig`，很可能就掉进这个坑，报出
#    「没配身份」——而真相是配了。所以**用 `--list` 这条最全的读法**，
#    不用 `--global`。
#
# ## 为什么报「值」也报「来自哪个文件」（origin）
#
# 「name 是 cole」之外，还有一个对用户有用的事实：**这个 cole 是从哪读来的**。
# 例如「name 来自 `~/.gitconfig.local`」直接回答了「我的身份配在哪」。
# 而且这正是 git 身份页和私有源段**不重复**的关键 ——
# 私有源段说的是「私有源**仓库**里有没有这一项」，这里说的是
# 「git **实际**从哪个文件读到的」。两个问题，两个答案。
#
# ## 为什么不读 token
#
# 契约 §2.9 和设计稿 §3.3 都定了：**token / 密码一律不读、不显示。**
# `gh` 的 `hosts.yml` 碰都不碰。理由不是抽象的「安全」，是两个具体的：
# ① token 跟这页要回答的问题（「我是谁 / 为什么 commit 不了」）无关；
# ② 读它得另接一套 `gh` 的私有格式，多一份解析就多一份会坏的。
# 凭据 helper 只报「命令是什么」（`!gh auth git-credential`）—— 那本来
# 就写在公开的 gitconfig 里，不是秘密。
#
# 用法：
#   zsh scripts/macos/git-identity.zsh --json

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
Usage: zsh scripts/macos/git-identity.zsh --json

  --json    把 git 身份状态打到 stdout（只读，不落盘）

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
  echo "git-identity 只支持 macOS（当前 $(uname -s)）" >&2
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

json_str_or_null() {
  if [[ -z "${1:-}" ]]; then printf 'null'; else printf '"%s"' "$(json_escape "$1")"; fi
}

# ── 问 git ──────────────────────────────────────────────────────────────
#
# 产出 `--show-origin --list` 的原始行。**这里不做解析** —— 解析在别的函数，
# 这样「git 怎么读」和「我们怎么切」是两件事，分开能各自测。
#
# ⚠️ **不在仓库里跑也没关系**：本机实测在 /tmp 下跑，一样能拿到
# user.name / credential.*（它们是全局配置）。所以不 require 仓库。
#
# ⚠️ git 不在时**报错退出**，不给空结果 —— 空结果会被界面显示成
# 「没配身份」，而真相是「问不出 git」。
git_config_dump() {
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: 找不到 git，问不出身份配置。" >&2
    return 1
  fi
  # `--list --show-origin`：算完优先级 + 展开 include，每行带来源文件。
  # `2>/dev/null` 吞掉「不在仓库里」之类的警告（那些不是错误）。
  git config --list --show-origin 2>/dev/null
  return 0
}

# ── 解析工具 ────────────────────────────────────────────────────────────
#
# 一行长这样（源后面是一个 **tab**，然后 `key=value`）：
#   file:/Users/you/.gitconfig.local<TAB>user.name=cole
#
# `--show-origin` 的源有几种前缀：`file:` / `blob:` / `command line:` /
# 空（环境变量来的会显示成空的源）。这里**统一处理**：找第一个 tab 切两半。

# 从一行里取 `key=value` 部分（tab 之后）。
line_kv() {
  local line="$1"
  printf '%s' "${line#*$'\t'}"
}

# 从一行里取「源」部分（tab 之前），并去掉 `file:` 前缀 → 给人看的路径。
# 不是 file: 的源（blob:/command line:/空）原样返回。
line_origin() {
  local line="$1"
  local src="${line%%$'\t'*}"
  case "$src" in
    file:*) printf '%s' "${src#file:}" ;;
    *) printf '%s' "$src" ;;
  esac
}

# 取一行的 key（`=` 之前）。git 输出里 key 是**小写**的
# （实测 `user.useConfigOnly` 输出成 `user.useconfigonly`）——
# 所以下面的匹配全部用小写。
line_key() {
  local kv="$1"
  printf '%s' "${kv%%=*}"
}

# 取一行的 value（`=` 之后，含空值）。
line_value() {
  local kv="$1"
  if [[ "$kv" == *=* ]]; then printf '%s' "${kv#*=}"; fi
}

render_json() {
  local now
  now="$(date +%s)"

  local dump
  dump="$(git_config_dump)" || return 1

  # ⚠️ 所有 `local` 声明在循环外一次做完 —— zsh 的坑：在**会跑两遍以上的
  # 循环里**写 `local x`，而 `x` 已经有值时，zsh 会把 `x=值` **打印到 stdout**，
  # 直接污染 JSON。（同样的坑在 alias-status.zsh 里记过。）
  local line kv key value origin
  local name="" name_origin=""
  local email="" email_origin=""
  local use_config_only=""
  local -a helper_hosts=()  helper_cmds=()
  local -a include_paths=()

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kv="$(line_kv "$line")"
    [[ "$kv" == *=* ]] || continue
    key="$(line_key "$kv")"
    value="$(line_value "$kv")"
    origin="$(line_origin "$line")"

    case "$key" in
      user.name)
        # 后面出现的覆盖前面 —— git 的优先级就是这样，`--list` 也按
        # 从低到高排，所以**取最后一个**才对。
        name="$value"; name_origin="$origin" ;;
      user.email)
        email="$value"; email_origin="$origin" ;;
      user.useconfigonly)
        # 只认 `true`（值可能是 true/yes/1/on）。取最后一个。
        use_config_only="$value" ;;
      include.path)
        include_paths+=("$value") ;;
      credential.*.helper)
        # key 形如 `credential.https://github.com.helper`。
        # ⚠️ 跳过**空值** —— gitconfig 里每个 host 有两条 helper：
        # 一条空（重置，`helper =`）、一条是命令（`helper = !gh …`）。
        # 那条空的是「先清空继承来的 helper」的写法，不是「用空 helper」。
        [[ -n "$value" ]] || continue
        # 取 host：key 去掉 `credential.` 前缀和 `.helper` 后缀。
        local host="${key#credential.}"
        host="${host%.helper}"
        helper_hosts+=("$host")
        helper_cmds+=("$value") ;;
    esac
  done <<<"$dump"

  # 「身份能不能用」= name 和 email **都**非空。这正是 git commit 的判据：
  # 两者缺一，git 就以「Author identity unknown」拒绝 commit。
  # ⚠️ 这里**不把 useConfigOnly 算进判据** —— 它是「为什么没配就报错」
  # 的机制说明，不是「能不能用」的判据本身（配了 identity 时它照样是 true）。
  local usable=0
  [[ -n "$name" && -n "$email" ]] && usable=1

  # ── 拼 JSON ─────────────────────────────────────────────────────────
  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"git-identity.zsh\","$'\n'
  out+="  \"identity\": {"$'\n'
  out+="    \"name\": $(json_str_or_null "$name"),"$'\n'
  out+="    \"email\": $(json_str_or_null "$email"),"$'\n'
  out+="    \"name_origin\": $(json_str_or_null "$name_origin"),"$'\n'
  out+="    \"email_origin\": $(json_str_or_null "$email_origin"),"$'\n'
  out+="    \"use_config_only\": $( [[ "$use_config_only" == "true" ]] && printf 'true' || printf 'false' ),"$'\n'
  out+="    \"usable\": $( (( usable )) && printf 'true' || printf 'false' )"$'\n'
  out+="  },"$'\n'

  # 凭据 helper 列表（可能为空 —— 那就是没配 host 级的）。
  out+="  \"credential_helpers\": ["
  local i
  if (( ${#helper_hosts[@]} == 0 )); then
    out+="],"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#helper_hosts[@]}; i++ )); do
      out+="    { \"host\": \"$(json_escape "${helper_hosts[$i]}")\", \"helper\": \"$(json_escape "${helper_cmds[$i]}")\" }"
      (( i < ${#helper_hosts[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ],"$'\n'
  fi

  # include 链（gitconfig 里 `[include] path = …` 的路径）。
  out+="  \"include_paths\": ["
  if (( ${#include_paths[@]} == 0 )); then
    out+="]"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#include_paths[@]}; i++ )); do
      out+="    \"$(json_escape "${include_paths[$i]}")\""
      (( i < ${#include_paths[@]} )) && out+=","
      out+=$'\n'
    done
    out+="  ]"$'\n'
  fi

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
