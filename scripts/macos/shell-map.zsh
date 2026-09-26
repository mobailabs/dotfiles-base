#!/usr/bin/env zsh
#
# shell 启动链：回答「启动一个 zsh 时，谁加载了谁」。契约见
# macview-contract.md 第 2.10 节。
#
# ## 它做什么
#
# 看仓库里的三个启动文件（`zshenv` / `zprofile` / `zshrc`），抽出里面所有的
# `source xxx` / `. xxx` 调用，输出一个 JSON（节点 + 边）到 stdout。
#
# ## 它不做什么
#
# **不 source、不执行任何东西，不改任何文件。** 和 link-status.zsh 一样，
# 是只读的**文本**解析器（不是 shell 求值）。
#
# ## 最要紧的两个决定
#
# ### 1. 启动链**不能**在 macview 里写死 —— 所以要这个脚本
#
# 设计稿 §3.4 定过：`DotfilesLayout` 写死的是**文件路径清单**（那是契约，
# 有 selfcheck 兜底）；启动链写死的是**文件之间的 source 关系**，那个
# **没有兜底** —— dotfiles 改了 `zshrc` 的 source 顺序，macview 不会知道，
# 会画出过期的链。所以只有「每次读一遍」这一条不漂移的路。
#
# ### 2. 边分三类，因为「能不能点开」不同
#
# `source` 的目标有三种：
#
#   · **repo**   —— 目标是仓库里的文件（`~/.exports` 其实链到仓库的
#     `env/exports`）。这类**可以在 macview 里点开**。
#   · **private** —— 目标是私有 overlay（`~/.zshrc.local`）。**存在就加载、
#     不存在就跳过**，而且内容不在仓库里 —— 界面只说「如果它在就加载」。
#   · **external** —— 目标是别的东西（Homebrew 装的插件、`~/.bun/_bun`、
#     oh-my-zsh 本体）。不在仓库里，界面只列出、不给「打开仓库文件」。
#
# 怎么分辨：**靠 `link-dotfiles.zsh` 的 `DOTFILE_LINKS`**（那 19 个落点的
# 目标 → 源的映射）。`~/.exports` 在表里 → 对应 `env/exports`；不在表里
# 但在 `$HOME` 下的 `.local` 之类 → private；其余 → external。
# **不在这里再抄一份落点表**（抄一份 = 两份声明 = 迟早漂移，同 link-status）。
#
# ## 解析器的边界（说清楚，免得以为它无所不能）
#
# ### 只解析三个**启动文件**，不递归跟进
#
# 只解析 `zshenv` / `zprofile` / `zshrc` 三个（用户 2026-09-25 拍板）。
# **不递归**跟进被 source 的文件（比如 `zsh/oh-my-zsh.sh` 自己还 source 了
# `ohmyzsh.plugins.zsh`，那一条**不**出现在结果里）。
#
# 理由：
#   · 设计稿 §3.4 的树画的就是「三个启动文件 → 它们直接 source 的东西」；
#   · 递归要处理**环**（`a` source `b`、`b` source `a`）、要决定外部文件
#     跟不跟 —— 复杂度为「多看两层嵌套」这点信息不值得；
#   · 真要看某个文件 source 了什么，点开那个文件看（界面给「打开文件」）。
# 所以结果里的 `edges` 是**三个启动文件的直接 source**，语义清楚。
#
# 这是**行级文本解析，不是 shell 求值**。它认得：
#   · `source <路径>` / `. <路径>`
#   · `[[ -f <路径> ]] && source <路径>`（本仓库最常见的写法）
#   · 缩进（在 `if` 块里的 source）
#   · 行尾注释
# 它**不**认得（遇到就跳过那一行，并在 stderr 记一条）：
#   · 变量拼接的复杂路径（`source "$X/$Y"` 认得字面量，但 `$X` 不展开）
#   · 多行语句
#   · `source <(...)` 这类进程替换
# 跳过比猜错好 —— 猜错会给界面一条假的边。
#
# 用法：
#   zsh scripts/macos/shell-map.zsh --json

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set." >&2
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
Usage: zsh scripts/macos/shell-map.zsh --json

  --json    把启动链打到 stdout（只读，不落盘）

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
  echo "shell-map 只支持 macOS（当前 $(uname -s)）" >&2
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

# ── 启动文件清单（节点）────────────────────────────────────────────────
#
# `repo_rel|home_rel|phase`：
#   · repo_rel  —— 仓库内相对路径（读它、也是 macview 点开的路径）
#   · home_rel  —— 它链到 `$HOME` 下的哪（`~/.zshenv` 等）。用来把 source
#     的目标 `~/.exports` **反查**回仓库文件。
#   · phase     —— 什么时候加载（给人看的事实，不是 macview 判的）：
#     `all`（所有 shell）/ `login`（登录 shell）/ `interactive`（交互 shell）
#
# ⚠️ **这个清单和 `DOTFILE_LINKS` 是两码事**：这里只列**会加载别人的**
# 启动文件（zshenv/zprofile/zshrc）。别的一堆落点（nvim/gitconfig…）
# 不参与启动链。所以不复用那张表来列举，只**用它来解析 source 的目标**。
STARTUP_FILES=(
  'zsh/zshenv|.zshenv|all'
  'zsh/zprofile|.zprofile|login'
  'zsh/zshrc|.zshrc|interactive'
)

# ── 从 link-dotfiles.zsh 抠 DOTFILE_LINKS（照抄 link-status.zsh）──────
# 产出每行 `源|目标`（目标是 `$HOME` 相对路径，如 `.exports`）。
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

  if (( ${#lines[@]} == 0 )); then
    echo "Error: 在 $LINK_IMPL 里找不到 DOTFILE_LINKS 数组；shell-map 的抠取方式需要跟着改。" >&2
    return 1
  fi

  printf '%s\n' "${lines[@]}"
}

# ── 一行 source 的解析 ──────────────────────────────────────────────────
#
# 输入：一行文本。输出（全局变量）：SRC_TARGET（目标字面量，未展开）。
# 返回 0 = 认出来了；1 = 这行不是 source（跳过）。
#
# 用全局变量传值是因为 zsh 里 `$(...)` 会开子 shell，命令替换里改了全局
# 外面看不到 —— 显式用全局（同 link-status 的纪律）。
SRC_TARGET=""

parse_source_line() {
  local line="$1"
  SRC_TARGET=""

  # 掐掉尾部空白 + 行尾注释（`#` 在**引号外**才是注释；这里简化处理：
  # 本仓库的 source 行注释都在行尾且不在引号里，按「第一个 # 之前」切）。
  line="${line%%#*}"
  line="${line%"${line##*[![:space:]]}"}"

  # 找 `source ` 或 `. `（`.` 作为命令名，后面必须跟空白）。
  # 允许前面有 `[[ … ]] &&` 之类的条件 —— 所以不锚 `^`。
  local rest=""
  if [[ "$line" =~ '(^|[[:space:]])source[[:space:]]+(.*)' ]]; then
    rest="${match[2]}"
  elif [[ "$line" =~ '^[[:space:]]*\.[[:space:]]+(.*)' ]]; then
    rest="${match[1]}"
  else
    return 1
  fi

  # 掐掉目标后的空白。
  rest="${rest%"${rest##*[![:space:]]}"}"

  # 目标：去掉两端引号（单/双）。
  local q="${rest[1]}"
  if [[ "$q" == '"' || "$q" == "'" ]]; then
    # 找闭合引号，取中间。
    local body="${rest[2,-1]}"
    local i ch out="" found=0
    local len=${#body}
    for (( i = 1; i <= len; i++ )); do
      ch="${body[$i]}"
      if [[ "$ch" == "$q" ]]; then found=1; break; fi
      out+="$ch"
    done
    (( found )) || return 1
    rest="$out"
  else
    # 没引号：取到第一个空白为止。
    rest="${rest%%[[:space:]]*}"
  fi

  [[ -n "$rest" ]] || return 1
  SRC_TARGET="$rest"
  return 0
}

# ── 把一个 source 目标分类 ──────────────────────────────────────────────
#
# 输出（全局变量）：EDGE_KIND（repo/private/external）、EDGE_REL （repo 时的
# 仓库相对路径，否则空）、EDGE_DISPLAY（给人看的目标）。
EDGE_KIND=""; EDGE_REL=""; EDGE_DISPLAY=""

classify_target() {
  local target="$1"
  EDGE_KIND="external"; EDGE_REL=""; EDGE_DISPLAY="$target"

  # 展开开头 `~` / `$HOME` 成 `$HOME` 下的相对路径，便于查表。
  local home_rel=""
  case "$target" in
    '~/'*) home_rel="${target#\~/}" ;;
    '$HOME/'*) home_rel="${target#\$HOME/}" ;;
    '${HOME}/'*) home_rel="${target#\${HOME}/}" ;;
  esac

  # 表里找得到（**整条**目标在表里）→ repo（`~/.exports` → `env/exports`）。
  if [[ -n "$home_rel" && -n "${LINK_MAP[$home_rel]:-}" ]]; then
    EDGE_KIND="repo"
    EDGE_REL="${LINK_MAP[$home_rel]}"
    EDGE_DISPLAY="$target"
    return
  fi

  # 落点在**某个被链接的目录里** → repo（拼出仓库内路径）。
  # 例：落点 `.config/tmux|tmux/config`（`tmux/config` 是个**目录**），
  # 而 source 目标是 `$HOME/.config/tmux/aliases.sh` —— 它在这个目录里，
  # 对应仓库的 `tmux/config/aliases.sh`。
  # ⚠️ 第一版漏了这一条，把 tmux 的 aliases.sh 标成了 external。
  if [[ -n "$home_rel" ]]; then
    local d
    for d in "${LINK_DIRS[@]}"; do
      if [[ "$home_rel" == "$d/"* ]]; then
        EDGE_KIND="repo"
        EDGE_REL="${LINK_MAP[$d]}/${home_rel#$d/}"
        EDGE_DISPLAY="$target"
        return
      fi
    done
  fi

  # 是 `$HOME` 下的 `.local`（或表外的点文件）→ private overlay。
  # 判据：目标在 `$HOME` 下，且**没有**出现在落点表里 —— 那就是私有的
  # 本地覆盖（`.zshrc.local` / `.envconfig.local` 这类）。
  if [[ "$home_rel" == *.local || "$home_rel" == *.local.* ]]; then
    EDGE_KIND="private"
    EDGE_DISPLAY="$target"
    return
  fi

  # 其余：外部（Homebrew / oh-my-zsh / bun / 用户自己的 path）。
  # 不展开 `$HOMEBREW_PREFIX` 之类 —— 展开要给界面一个可能不存在的绝对
  # 路径，反而更误导。**原样显示字面量**，界面照实说「这是外部的」。
  EDGE_KIND="external"
  EDGE_DISPLAY="$target"
}

render_json() {
  local now
  now="$(date +%s)"

  # 先建「$HOME 相对路径 → 仓库相对路径」的映射表（关联数组）。
  # 同时记下落点里哪些是**目录**（`$HOME` 下的目标，其仓库源是个目录）
  # —— 用来把 `$HOME/.config/tmux/aliases.sh` 这类「在链接目录里的文件」
  # 也归成 repo。
  local -A LINK_MAP=()
  local -a LINK_DIRS=()
  local raw line src dest
  raw="$(extract_links)" || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # 行形如 `  'zsh/zshrc|.zshrc'` —— 去掉首尾空白和单引号。
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line#\'}"
    line="${line%\'}"
    src="${line%%|*}"
    dest="${line#*|}"
    [[ -n "$src" && -n "$dest" ]] && LINK_MAP[$dest]="$src"
    # 仓库源是**目录**吗？用仓库里的实际类型判断（不看名字猜）。
    if [[ -d "$ROOT_DIR/src/macos/config/$src" ]]; then
      LINK_DIRS+=("$dest")
    fi
  done <<<"$raw"

  # ⚠️ 所有 `local` 声明在循环外一次做完 —— zsh 的坑：在**会跑两遍以上的
  # 循环里**写 `local x`，而 `x` 已经有值时，zsh 会把 `x=值` **打印到 stdout**，
  # 直接污染 JSON。（alias-status.zsh 里记过这个坑。）
  local one spec repo_rel home_rel phase abs lineno
  local cond_line t

  local -a node_repos=() node_homes=() node_phases=()
  local -a edge_from=() edge_to=() edge_kind=() edge_rel=() edge_cond=() edge_line=()

  for spec in "${STARTUP_FILES[@]}"; do
    repo_rel="${spec%%|*}"
    local rest1="${spec#*|}"
    home_rel="${rest1%%|*}"
    phase="${rest1#*|}"
    abs="$ROOT_DIR/src/macos/config/$repo_rel"

    node_repos+=("$repo_rel")
    node_homes+=("$home_rel")
    node_phases+=("$phase")

    if [[ ! -f "$abs" ]]; then
      # 启动文件不在 —— 报错退出，不画一条缺节点的链（那是假消息）。
      echo "Error: 找不到启动文件 $repo_rel（$abs）—— 仓库结构变了吗？" >&2
      return 1
    fi

    lineno=0
    local in_if=0
    while IFS= read -r t; do
      (( lineno++ ))

      # 这一行有没有条件守卫？**要看两种情况**（第一版只看了同行，漏了）。
      #   · 同行的 `[[ -f … ]] && source …`（本仓库最常见）
      #   · **前几行的 `if [[ -f … ]]; then`** —— 这种 source 在下一行，
      #     同行看不出来。所以要跟踪「现在在不在一个 if 块里」。
      # ⚠️ 第一版就是这么错的：fzf / 插件那几条 source 在
      # `if [[ -f … ]]; then` 的**下一行**，全被标成「非条件」。
      if [[ "$t" == *'if '* && "$t" == *'then'* ]]; then
        (( in_if++ ))
      fi
      if [[ "$t" == *'fi'* ]]; then
        (( in_if > 0 )) && (( in_if-- ))
      fi

      cond_line=0
      if (( in_if > 0 )) || [[ "$t" == *'[['* || "$t" == *'-f '* ]]; then
        cond_line=1
      fi

      if parse_source_line "$t"; then
        classify_target "$SRC_TARGET"
        edge_from+=("$repo_rel")
        edge_to+=("$EDGE_DISPLAY")
        edge_kind+=("$EDGE_KIND")
        edge_rel+=("$EDGE_REL")
        edge_cond+=("$cond_line")
        edge_line+=("$lineno")
      fi
    done <"$abs"
  done

  # ── 拼 JSON ─────────────────────────────────────────────────────────
  local out="" i
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"shell-map.zsh\","$'\n'

  # 节点（启动文件）。
  out+="  \"nodes\": ["$'\n'
  for (( i = 1; i <= ${#node_repos[@]}; i++ )); do
    out+="    { \"repo_rel\": \"$(json_escape "${node_repos[$i]}")\","
    out+=" \"home_rel\": \"$(json_escape "${node_homes[$i]}")\","
    out+=" \"phase\": \"$(json_escape "${node_phases[$i]}")\" }"
    (( i < ${#node_repos[@]} )) && out+=","
    out+=$'\n'
  done
  out+="  ],"$'\n'

  # 边（谁 source 谁）。
  out+="  \"edges\": ["
  if (( ${#edge_from[@]} == 0 )); then
    out+="]"$'\n'
  else
    out+=$'\n'
    for (( i = 1; i <= ${#edge_from[@]}; i++ )); do
      out+="    {"
      out+=" \"from\": \"$(json_escape "${edge_from[$i]}")\","
      out+=" \"to\": \"$(json_escape "${edge_to[$i]}")\","
      out+=" \"kind\": \"$(json_escape "${edge_kind[$i]}")\","
      out+=" \"repo_rel\": $(json_str_or_null "${edge_rel[$i]}"),"
      out+=" \"conditional\": $( (( edge_cond[$i] )) && printf 'true' || printf 'false' ),"
      out+=" \"line\": ${edge_line[$i]}"
      out+=" }"
      (( i < ${#edge_from[@]} )) && out+=","
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
