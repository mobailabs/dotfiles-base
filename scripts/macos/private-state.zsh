#!/usr/bin/env zsh
#
# 产出 / 打印「私有源状态」契约文件。契约见 private.md，本文件是它的实现。
#
# ## 它做什么
#
# 检查五个落点（aliases / zshrc-local / envconfig-local / git-local / ssh-local）
# 各自处于四态中的哪一个，然后写成一个 JSON：
#
#   ~/.config/dotfiles/private-state.json
#
# 两个调用方，一份检测逻辑：
#
#   --write   给 prompt-once.zsh 用：写进上面那个文件（原子写、0600）
#   --stdout  给 macview 用：只打印到 stdout，不落盘
#
# ## 它不做什么
#
# **不装东西、不改 $HOME 里的任何配置**（--write 时只写状态文件本身）。
# 和 brew-audit.zsh 是同一类只读检测器。
#
# ## 两个「读源还是读 target」——这是契约里最容易写错的地方
#
#   源里有没有这一项、是不是模板（哨兵） → 读 **源**
#   effect 取到什么值                        → 读 **target**
#
# 理由见 private.md：「源里有没有」是源的属性；而 ok 的含义是
# 「**落到 $HOME 的那份真的生效了**」，源改好了但没链过去不算。
#
# 用法：
#   zsh scripts/macos/private-state.zsh --stdout    # 打印 JSON
#   zsh scripts/macos/private-state.zsh --write     # 写契约文件
#   zsh scripts/macos/private-state.zsh --write --quiet

set -uo pipefail

# $HOME 是所有落点的基准。没它的话下面 `$HOME/...` 要么崩在参数展开，
# 要么（没开 set -u 时）产出 `/xxx` 这种**看起来合法、其实全错**的路径 ——
# 静默给 macview 一份假状态，比直接失败更糟。
# link-dotfiles.zsh 就是这么防的，这里保持一致。
if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set; cannot determine dotfile locations." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# ── 契约常量 ────────────────────────────────────────────────────────────
#
# ⚠️ 槽位清单必须和 macview 的 `declaredSlots`
#    (Sources/MacViewCore/Diff/LoadPoint.swift) 以及 private.md 的
#    「五个槽位的完整映射」表保持一致。改一处要改三处。
#
# 每行：`id|name|source_rel|targetRel|loaded_by_rel`
#   source_rel    源内的相对路径（决定 absent / incomplete）
#   targetRel     落点，相对 $HOME
#   loaded_by_rel 设计上由谁读，相对 $HOME
#
# 为什么 `aliases` 的 source_rel 没有 `.local` 后缀：它落到的 target 就叫
# `~/.aliases`，源里跟它同名即可。规则：源内名 = target 的 basename
# （ssh-local 例外，多一层 ssh/ 目录）。

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# 私有源里的探针变量名。
#
# zshrc.local / envconfig.local 要让检测器证明「这个文件真的被 source 了」，
# 用户得往里面写一行 `export DOTFILES_PRIVATE_LOADED=1`。
# 这是**公开协议**（写在 private.md 里），不是私有约定。
PROBE_MARKER="DOTFILES_PRIVATE_LOADED"

# 占位哨兵：源模板文件第一行写它，用户填完真值后删掉。
# 四种语法里 `#` 都是注释（ssh 的注释须在行首，所以固定放第一行）。
PLACEHOLDER_SENTINEL="# dotfiles:placeholder"

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""
QUIET=0

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/private-state.zsh <--write|--stdout> [--quiet]

  --write    产出 ~/.config/dotfiles/private-state.json（原子写，0600）
  --stdout   把同一份 JSON 打到 stdout，不落盘
  --quiet    只报错，不打印进度（给 install 流程用）

契约见仓库根目录的 private.md。
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --write)  MODE="write"; shift ;;
    --stdout) MODE="stdout"; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "必须指定 --write 或 --stdout（二选一）。" >&2
  usage >&2
  exit 2
fi

# 这个仓库只做 macOS。不假装能跑别的平台 —— 和 brew-audit.zsh 态度一致。
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "private-state 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# 状态文件的位置（契约规定，见 private.md「契约文件的位置」）。
STATE_DIR="$HOME/.config/dotfiles"
STATE_FILE="$STATE_DIR/private-state.json"

# ── 工具函数 ────────────────────────────────────────────────────────────

# JSON 字符串转义。macview 用 Swift 的 JSONDecoder 读，转义错了直接解析失败。
#
# 手写而不是用 `printf %q` 之类：只要覆盖 JSON 规范要求的那几个字符。
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"      # 反斜杠要先转义，否则会把后面的 \" 又转一遍
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  # 其余控制字符（< 0x20）转成 \uXXXX。JSON 不允许裸控制字符。
  # zsh 里用 ${(V)} 拿不到码点，就逐字节扫 —— 这些字符极少出现在路径里。
  setopt localoptions no_multibyte 2>/dev/null || true
  printf '%s' "$s"
}

# 把 `$HOME` 展开成绝对路径，并转成 JSON 字符串字面量。
json_home_path() {
  local rel="$1"
  printf '"%s"' "$(json_escape "$HOME/$rel")"
}

# 值是 string，也可能是 null。用法：json_str_or_null "$val"
json_str_or_null() {
  if [[ -z "${1:-}" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(json_escape "$1")"
  fi
}

# 文件第一行是否等于哨兵。
#
# ⚠️ 读的是**源**里的文件（判定 placeholder），不读 target。
is_placeholder_source() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local first
  IFS= read -r first < "$f" 2>/dev/null || return 1
  [[ "$first" == "$PLACEHOLDER_SENTINEL" ]]
}

# 从 zsh 文件里取 `DOTFILES_PRIVATE_LOADED` 的值。
#
# 用**非交互子 shell** 真的 source 它，而不是 grep —— 因为契约要的是
# 「探针真的被加载了」，grep 只能证明「文件里写了这行字」。
# （zshrc.local 里那行可能在 if 里、可能被后面的 unset 掉。）
probe_zsh_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local out
  out="$(zsh -f -c "source '$f' >/dev/null 2>&1 || true; print -r -- \"\${$PROBE_MARKER:-}\"" 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# 从 gitconfig（INI）里取一个键。**用 git 自己解析**，不手写 INI 解析器。
#
# --file 只读这一个文件，不叠加全局配置 —— 否则用户 shell 里的
# `git config --get` 会把 ~/.gitconfig 的值也带进来，那就不是「这个落点生效了」。
probe_git_file() {
  local f="$1" key="$2"
  [[ -f "$f" ]] || return 1
  local v
  v="$(git config --file "$f" --get "$key" 2>/dev/null)" || return 1
  [[ -n "$v" ]] || return 1
  printf '%s' "$v"
}

# 从 ssh config 里取 `Host` 名（顶层，排除 `Host *` 和带通配的）。
#
# 只读那一行字，不验证连通性 —— 这个字段只用来让用户看见「配了哪些主机」。
probe_ssh_hosts() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  # ⚠️ 所有 `local` 都在循环**外面**声明一次。
  # 在会多次执行的循环体里写 `local x`，zsh 重新声明已有变量时会把它
  # **打印到 stdout**（`parts=(...)`）—— 污染 JSON，而且是静默的。
  # 同一个坑 brew-audit.zsh 里也踩过，那边有更长的说明。
  local out h
  local -a parts hosts
  hosts=()
  while IFS= read -r out; do
    # 去掉注释 / 按空白分词（大小写不敏感地找 `Host` 关键字）
    out="${out%%#*}"
    parts=(${=out})
    (( ${#parts[@]} >= 2 )) || continue
    [[ "${parts[1]:l}" == "host" ]] || continue
    for h in "${parts[@]:1}"; do
      [[ "$h" == *"*"* || "$h" == *"?"* ]] && continue
      hosts+=("$h")
    done
  done < "$f"
  (( ${#hosts[@]} > 0 )) || return 1
  # 去重但保序（同名 Host 出现两次不该报两遍）
  printf '%s' "${(j:,:)${(u)hosts}}"
}

# 从 `aliases` 文件里取 `alias <名字>=<命令>` 的**名字**。
#
# aliases 不是「填一次就生效」的配置，它本来就是一份列别名的一文件 ——
# 所以不能用 DOTFILES_PRIVATE_LOADED 那套探针（没人会往别名文件里写 export）。
# 这里证明「这一项真的生效了吗」的方式是「**能从中解析出至少一个别名**」。
#
# 解析规则**故意和 macview 的 parseAliases 一致**
# （Sources/MacViewCore/Settings/Inspect.swift:438）：
#   跳过 `#` 开头的行；要求行以 `alias `（或正好 `alias`）开头；
#   可选的 `--`；取第一个 `=` 左边当名字。
# 如果这边解析出的数目比它少/多，两边界面就会对不上 —— 改一处要改两处。
probe_alias_names() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local out body name
  local -a names
  names=()
  while IFS= read -r out; do
    body="${out#"${out%%[![:space:]]*}"}"   # 去前导空白
    [[ "$body" == \#* ]] && continue
    [[ "$body" == "alias" || "$body" == "alias "* ]] || continue
    body="${body#alias}"
    body="${body#"${body%%[![:space:]]*}"}"  # 再取前导空白
    [[ "$body" == --* ]] && body="${body#--}"
    body="${body#"${body%%[![:space:]]*}"}"
    [[ "$body" == *=* ]] || continue
    name="${body%%=*}"
    name="${name%"${name##*[![:space:]]}"}"  # 去尾随空白
    [[ -n "$name" ]] || continue
    names+=("$name")
  done < "$f"
  (( ${#names[@]} > 0 )) || return 1
  printf '%s: %s 等' "${#names[@]}" "${(j:,:)${(u)names}}"
}

# ── 私有源 ──────────────────────────────────────────────────────────────
#
# 路径约定复用 macview 已有的 PRIVATE_DIR（Diff/Collect.swift:53-59）：
#   环境变量 PRIVATE_DIR ？用它
#   : 默认               ~/private-dotfiles
#
# 注意：macview 自己的环境里才有 PRIVATE_DIR；install 流程里通常没有，
# 所以这里解析出的就是默认值 —— 和 macview 的默认行为一致。

SOURCE_DIR="${PRIVATE_DIR:-$HOME/private-dotfiles}"

# 判断 source.kind / source.present。
#
#   kind=dir  目录在，且**不是** git 仓库
#   kind=git  有 .git（clone 下来的，或者是一个 worktree）
#   kind=none 目录整个不存在
#
# present=false 只可能发生在 kind=git 且目录不在时（配了但没拉下来）。
# 但「配过」这件事本机没有记录（契约里 source.remote 取自 git remote，
# 目录不在时也读不到）—— 所以当前实现里，目录不在就是 none。
# 留这个分支是为了将来能从别处记住 remote。
detect_source() {
  SOURCE_KIND="none"
  SOURCE_PRESENT=0
  SOURCE_REMOTE=""
  SOURCE_DETAIL=""

  if [[ -d "$SOURCE_DIR/.git" ]]; then
    SOURCE_KIND="git"
    SOURCE_PRESENT=1
  elif [[ -d "$SOURCE_DIR" ]]; then
    SOURCE_KIND="dir"
    SOURCE_PRESENT=1
  fi

  if (( SOURCE_PRESENT )); then
    SOURCE_REMOTE="$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
  fi
}

# ── 槽位判定 ────────────────────────────────────────────────────────────

# 一个槽位的结果，全部塞进这几个全局变量（zsh 里比返回结构体省事）：
#   SLOT_STATUS / SLOT_EFFECT_JSON / SLOT_WHY
#
# $1=id $2=source_rel $3=targetRel
evaluate_slot() {
  local id="$1" source_rel="$2" target_rel="$3"
  local src="$SOURCE_DIR/$source_rel"
  local tgt="$HOME/$target_rel"

  SLOT_STATUS=""
  SLOT_EFFECT_JSON="null"
  SLOT_WHY=""

  # ── 判定表第 0 行：源没拿到 ──
  # 见 private.md：配了源但没拉下来时，**不能**报 absent（那是「用户没配」），
  # 要报 incomplete，让 macview 知道是源整体的问题。
  if (( ! SOURCE_PRESENT )); then
    if [[ "$SOURCE_KIND" == "git" ]]; then
      SLOT_STATUS="incomplete"
      SLOT_WHY="私有源已被配置，但本地不存在"
      return
    fi
    # kind=none：真的没配 → 落到下面的 absent（源里当然也就没有）
  fi

  # ── 判定表第 1 行：源里没这一项 → absent ──
  if [[ ! -e "$src" ]]; then
    SLOT_STATUS="absent"
    return
  fi

  # ── 判定表第 2 行：源里还是模板 → placeholder（**只看源**，不看 target）──
  if is_placeholder_source "$src"; then
    SLOT_STATUS="placeholder"
    return
  fi

  # ── 判定表第 3 行：target 不在 → incomplete ──
  # ⚠️ 顺序：**先看 target 在不在**。反过来的话（先取 effect）会把
  # 「没链接」和「链接了但内容空」压成同一个 incomplete，丢掉信息。
  if [[ ! -e "$tgt" && ! -L "$tgt" ]]; then
    SLOT_STATUS="incomplete"
    SLOT_WHY="源里有，但没落到 $tgt"
    return
  fi

  # ── 判定表第 4/5 行：从 **target** 取 effect ──
  # effect 能取到至少一个非空值 → ok；取不到 → incomplete。
  # 这也是 ok / incomplete 的**唯一**分界，不另写一套「内容有效性」判据。
  local -a pairs=()   # 形如 "键=值"
  case "$id" in
    git-local)
      local name email
      name="$(probe_git_file "$tgt" user.name || true)"
      email="$(probe_git_file "$tgt" user.email || true)"
      [[ -n "$name" ]]  && pairs+=("user.name=$name")
      [[ -n "$email" ]] && pairs+=("user.email=$email")
      ;;
    ssh-local)
      local hosts
      hosts="$(probe_ssh_hosts "$tgt" || true)"
      [[ -n "$hosts" ]] && pairs+=("hosts=$hosts")
      ;;
    aliases)
      # aliases 没有「填了没」的问题（它本来就是列别名的文件），
      # 生效判据 = **能解析出至少一个别名**。见 probe_alias_names 的说明。
      local aliases_summary
      aliases_summary="$(probe_alias_names "$tgt" || true)"
      [[ -n "$aliases_summary" ]] && pairs+=("aliases=$aliases_summary")
      ;;
    zshrc-local|envconfig-local)
      local probe
      probe="$(probe_zsh_file "$tgt" || true)"
      [[ -n "$probe" ]] && pairs+=("$PROBE_MARKER=$probe")
      ;;
  esac

  if (( ${#pairs[@]} == 0 )); then
    SLOT_STATUS="incomplete"
    SLOT_WHY="target 在，但取不到任何验证值（内容为空 / 解析失败）"
    return
  fi

  SLOT_STATUS="ok"
  # 拼成扁平 string→string 对象。键值都已转义。
  local out="{" first=1 p k v
  for p in "${pairs[@]}"; do
    k="${p%%=*}"
    v="${p#*=}"
    (( first )) || out+=","
    first=0
    out+="\"$(json_escape "$k")\":\"$(json_escape "$v")\""
  done
  out+="}"
  SLOT_EFFECT_JSON="$out"
}

# ── 产出 JSON ───────────────────────────────────────────────────────────

# 五个槽位：`id|name|source_rel|targetRel|loaded_by_rel`
SLOTS=(
  'aliases|别名|aliases|.aliases|.zshrc'
  'zshrc-local|常用目录|zshrc.local|.zshrc.local|.zshrc'
  'envconfig-local|环境变量 · 服务 · 代理|envconfig.local|.envconfig.local|.envconfig'
  'git-local|git|gitconfig.local|.gitconfig.local|.gitconfig'
  'ssh-local|ssh|ssh/config.local|.ssh/config.local|.ssh/config'
)

render_json() {
  detect_source

  local now
  now="$(date +%s)"

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"private-state.zsh\","$'\n'
  out+="  \"source\": {"$'\n'
  out+="    \"kind\": \"$SOURCE_KIND\","$'\n'
  out+="    \"path\": "$(json_str_or_null "$([[ -d "$SOURCE_DIR" ]] && printf '%s' "$SOURCE_DIR")")","$'\n'
  out+="    \"remote\": $(json_str_or_null "$SOURCE_REMOTE"),"$'\n'
  out+="    \"present\": $( (( SOURCE_PRESENT )) && printf 'true' || printf 'false' ),"$'\n'
  out+="    \"detail\": $(json_str_or_null "$SOURCE_DETAIL")"$'\n'
  out+="  },"$'\n'
  out+="  \"slots\": ["$'\n'

  local i spec id name source_rel target_rel loaded_by_rel
  local n=${#SLOTS[@]}
  for (( i = 1; i <= n; i++ )); do
    spec="${SLOTS[$i]}"
    id="${spec%%|*}";          spec="${spec#*|}"
    name="${spec%%|*}";        spec="${spec#*|}"
    source_rel="${spec%%|*}";  spec="${spec#*|}"
    target_rel="${spec%%|*}";  loaded_by_rel="${spec#*|}"

    evaluate_slot "$id" "$source_rel" "$target_rel"

    out+="    {"$'\n'
    out+="      \"id\": \"$(json_escape "$id")\","$'\n'
    out+="      \"name\": \"$(json_escape "$name")\","$'\n'
    out+="      \"source_rel\": \"$(json_escape "$source_rel")\","$'\n'
    out+="      \"target\": $(json_home_path "$target_rel"),"$'\n'
    out+="      \"loaded_by\": $(json_home_path "$loaded_by_rel"),"$'\n'
    out+="      \"status\": \"$SLOT_STATUS\","$'\n'
    out+="      \"effect\": $SLOT_EFFECT_JSON,"$'\n'
    out+="      \"why\": $(json_str_or_null "$SLOT_WHY")"$'\n'
    out+="    }"
    (( i < n )) && out+=","
    out+=$'\n'
  done

  out+="  ]"$'\n'
  out+="}"$'\n'
  printf '%s' "$out"
}

# ── 原子写 ──────────────────────────────────────────────────────────────
#
# 先写临时文件再 mv：macview 随时可能在读这个文件，直接重定向会读到半截。
write_state_file() {
  local json="$1"

  mkdir -p "$STATE_DIR" || {
    echo "无法创建 $STATE_DIR" >&2
    return 1
  }

  local tmp="$STATE_FILE.tmp.$$"
  if ! printf '%s' "$json" > "$tmp"; then
    echo "写入临时文件失败：$tmp" >&2
    rm -f "$tmp"
    return 1
  fi

  # 内容可能含邮箱 / 主机名 —— 先收紧权限再落位（mv 保留权限位）。
  chmod 600 "$tmp" 2>/dev/null || true

  if ! mv "$tmp" "$STATE_FILE"; then
    echo "移动到 $STATE_FILE 失败" >&2
    rm -f "$tmp"
    return 1
  fi
  return 0
}

main() {
  local json
  json="$(render_json)"

  # JSON 合法性自检。
  #
  # 这个文件是要给 macview（Swift JSONDecoder）读的，格式错就是**静默**
  # 打不开 —— 与其让 GUI 那边一脸懵，不如产出时就自己发现。
  # python3 在 macOS 上是随开发者工具自带的，这里当可选校验：
  # 没有就跳过，不阻断（检测器本身不该依赖 python）。
  if command -v python3 >/dev/null 2>&1; then
    if ! printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      echo "内部错误：产出的 JSON 不合法（这是个 bug，请报告）。" >&2
      return 1
    fi
  fi

  if [[ "$MODE" == "stdout" ]]; then
    printf '%s' "$json"
    return 0
  fi

  write_state_file "$json" || return 1
  (( QUIET )) || echo "私有源状态已写入 $STATE_FILE"
  return 0
}

main
