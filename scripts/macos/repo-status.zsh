#!/usr/bin/env zsh
#
# 仓库状态：回答「这个仓库现在的 git 状态」。契约见 macview-contract.md 第 2.6 节。
#
# ## 它做什么
#
# 只读地读 git 状态：在不在仓库里、分支、脏不脏、落后/领先远端多少、
# 改了哪些文件。输出一个 JSON 到 stdout。
#
# ## 它不做什么
#
# **不 fetch、不 pull、不 commit、不改任何文件。**
#
# ⚠️ 特别地：**不跑 `git fetch`** —— 那会发网络请求，还会悄悄改
# `.git/refs/remotes`。契约第五节写死了「日常看的时候一次网络请求都不该发」。
# 所以 `behind` 是**相对于本地已有的远端引用**（`@{upstream}`）算的，
# 可能不是远端此刻的真实状态 —— 这一点在 JSON 里用 `upstream_stale` 说清楚，
# 不装作是最新的。
#
# ## 脏状态包含未跟踪文件吗
#
# 包含。`git status --porcelain` 的 `??` 也算脏 —— 因为「仓库里有没被 git 管的
# 东西」恰恰是用户最需要看到的（它不会被 commit，也永远不会出现在远端）。
#
# 用法：
#   zsh scripts/macos/repo-status.zsh --json    # 打印 JSON 到 stdout

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; cannot determine dotfile locations." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

CONTRACT_VERSION=1

MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/repo-status.zsh --json

  --json    把仓库 git 状态打到 stdout（只读，不落盘、不联网）

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
  echo "repo-status 只支持 macOS（当前 $(uname -s)）" >&2
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

# 只读地跑一条 git 命令。
#
# `-C "$ROOT_DIR"` 而不是 `cd` —— 保证「在哪个目录调用都不影响结果」。
# 失败时返回空串（配合上层：空串表示「问不出来」，不是「没有」）。
git_read() {
  command git -C "$ROOT_DIR" "$@" 2>/dev/null
}

render_json() {
  local now
  now="$(date +%s)"

  # 连 git 都没有 —— 三态里的 unknown（问不出来），不是「没有仓库」。
  if ! command -v git >/dev/null 2>&1; then
    printf '{"version":%d,"checked_at":%s,"generated_by":"repo-status.zsh","is_git":null,"detail":"git 未安装，无法判断"}\n' \
      "$CONTRACT_VERSION" "$now"
    return 0
  fi

  local is_git="false" detail=""
  if git_read rev-parse --is-inside-work-tree >/dev/null; then
    is_git="true"
  else
    # 明确不在 git 工作树里。这是「确定没有」，不是「问不出来」。
    detail="不是 git 工作树"
  fi

  local branch="" dirty="false" ahead="null" behind="null" upstream="" upstream_stale="true"
  local changed_json="[]"

  if [[ "$is_git" == "true" ]]; then
    branch="$(git_read rev-parse --abbrev-ref HEAD)"

    # 脏不脏：有 porcelain 输出就算脏（含未跟踪文件，理由见文件头）。
    local porcelain
    porcelain="$(git_read status --porcelain)"
    [[ -n "$porcelain" ]] && dirty="true"

    # 改了哪些文件（前若干条就够 GUI 展示；文件可能极多，不无限列）。
    if [[ -n "$porcelain" ]]; then
      local -a files=()
      # ⚠️ 这里**绝不能**声明 `local path` —— `path` 是 zsh 的保留变量，
      # 和 `PATH` 是同一个数组。`local path`（不带值）会把 PATH 清空，
      # 于是本函数后续所有 `command git` 都变成 `command not found: git`。
      # 这是本文件踩过的真坑：表现为「上游信息静默变成 null」，不报错。
      local line fs_path
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # porcelain 前两列是状态码，第 4 个字符起是路径。
        # 改名（`R  old -> new`）取箭头右边的新名。
        fs_path="${line[4,-1]}"
        if [[ "$fs_path" == *' -> '* ]]; then
          fs_path="${fs_path##* -> }"
        fi
        # 处理带引号的路径（含空格/特殊字符时 git 会加引号并转义）。
        fs_path="${fs_path#\"}"; fs_path="${fs_path%\"}"
        files+=("$fs_path")
      done <<<"$porcelain"
      # 只报前 50 个 —— GUI 的列表不该被一个 2000 文件的仓库撑爆。
      # 用 `files` 数组的前 50 个拼 JSON。
      local i n=${#files[@]}
      (( n > 50 )) && n=50
      changed_json="["
      for (( i = 1; i <= n; i++ )); do
        changed_json+="\"$(json_escape "${files[$i]}")\""
        (( i < n )) && changed_json+=","
      done
      changed_json+="]"
    fi

    # 上游与领先/落后 —— 只读本地引用，不 fetch（理由见文件头）。
    local upstream_ref
    upstream_ref="$(git_read rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n "$upstream_ref" ]]; then
      upstream="$upstream_ref"
      local counts
      counts="$(git_read rev-list --left-right --count '@{upstream}...HEAD')"
      # 输出形如 `3\t1`（behind\tahead）。解析不出就保持 null。
      if [[ -n "$counts" ]]; then
        local behind_n ahead_n
        behind_n="${counts%%[[:space:]]*}"
        ahead_n="${counts##*[[:space:]]}"
        [[ "$behind_n" == <-> ]] && behind="$behind_n"
        [[ "$ahead_n" == <-> ]] && ahead="$ahead_n"
      fi
      # 本地远端引用多旧了 —— 说明 behind/ahead 是不是「此刻的真相」。
      local ref_mtime head_mtime
      ref_mtime="$(git_read log -1 --format=%ct "$upstream_ref")"
      head_mtime="$(git_read log -1 --format=%ct HEAD)"
      if [[ -n "$ref_mtime" && -n "$head_mtime" ]]; then
        # 上游引用比本地 HEAD 还新 ⇒ 可能刚有人推过 ⇒ 数字可能过期。
        # 简单判据：上游引用的提交时间比 HEAD 新，就标记为「可能不是最新」。
        (( ref_mtime > head_mtime )) && upstream_stale="true" || upstream_stale="false"
      fi
    fi
  fi

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"repo-status.zsh\","$'\n'
  out+="  \"is_git\": $is_git,"$'\n'
  out+="  \"branch\": $(json_str_or_null "$branch"),"$'\n'
  out+="  \"dirty\": $dirty,"$'\n'
  if [[ "$is_git" == "true" ]]; then
    out+="  \"ahead\": $ahead,"$'\n'
    out+="  \"behind\": $behind,"$'\n'
    out+="  \"upstream\": $(json_str_or_null "$upstream"),"$'\n'
    out+="  \"upstream_stale\": $upstream_stale,"$'\n'
    out+="  \"changed_files\": $changed_json"$'\n'
  else
    out+="  \"detail\": $(json_str_or_null "$detail")"$'\n'
  fi
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
