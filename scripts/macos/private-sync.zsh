#!/usr/bin/env zsh
#
# 私有配置的同步：在「中转目录」和「本机生效目录」之间搬文件。
#
# ## 为什么要有这个脚本（而不直接用 git）
#
# 私有仓库**不用 git** —— 同步由外部系统提供，这里只定义两端的交接：
#
#   中转目录（CARRIER）  ←→  本机生效目录（LIVE_DIR = ~/private-dotfiles）
#
#   · CARRIER：同步系统放文件的地方（网盘目录、U 盘、你们自己的同步服务
#     落盘的位置）。本脚本**不关心它怎么来的**，只认「里面有没有那几个文件」。
#   · LIVE_DIR：shell 真正读的地方（`~/.aliases` 等符号链接指过来）。
#     **只改这里，shell 才生效。**
#
# 现在用文件夹 copy 模拟：CARRIER 就是你指定的一个目录。以后换成真正的
# 同步服务，只要它能把文件落到一个目录，这个脚本**一个字都不用改** ——
# 交接面就是「一个目录」，不是某个协议。
#
# ## 三个子命令
#
#   status  只看：两边每个文件是「一致 / 不一致 / 只在一边」。**只读。**
#   pull    CARRIER → LIVE：新机器进场 / 别的机器改了东西拿过来。
#   push    LIVE → CARRIER：本机改了东西，交出去给别的机器。
#
# ## 安全规则（和 clone-dotfiles.zsh 同一个血统）
#
# 1. **pull 之前先看 CARRIER 像不像私有源**：5 个已知文件里一个都没有 →
#    拒绝。那很可能是路径指错了，往 LIVE 里倒一堆别的东西没有意义。
# 2. **覆盖之前先备份**：LIVE 里将被覆盖、且内容不一样的文件，先抄一份到
#    `~/.config/dotfiles/private-backup/<时间>/`。**静默覆盖等于丢配置。**
# 3. **只碰已知的 5 个文件**（+ `machine/` 子树，见下）：两边各自的多余文件
#    一律不动 —— 不删除、不复制。同步脚本没有资格决定「这个文件该不该存在」。
# 4. **幂等**：连跑两遍 pull，第二遍是 no-op（「已经一致」），退出 0。
# 5. 不联网、不提权、不读文件内容（只比对 + 复制）。
#
# ## 同步哪几个文件
#
# 和 private-state.zsh 的槽位表是**同一份名单**（`source_rel` 那一列）：
# `aliases`、`zshrc.local`、`envconfig.local`、`gitconfig.local`、
# `ssh/config.local`，外加 `machine/` 子树（按机器分的文件，见下）。
#
# ⚠️ `gitconfig.local` 例外：没有私有仓库时，prompt-once 直接写
# `~/.gitconfig.local`（真实文件，不是符号链接）。push 会把它收进 CARRIER，
# pull 会覆盖写回去 —— 两边都是你自己的数据，last-write-wins + 备份。
# 身份（name/email）多机器一般是一样的，同步它是对的；不一样就别同步它，
# 从 CARRIER 里删掉那个文件（规则 3：没有的文件不动）。
#
# ## machine/ 子树
#
# 机器特有的东西（比如只在工作电脑有的代理）不要塞进共享文件 ——
# 放 `machine/$(hostname).env`，在 `envconfig.local` / `zshrc.local` 末尾
# 按 hostname 分流 source。同步时整个 `machine/` 目录跟着走，
# 每台机器只读自己的那一份，互不污染。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LIVE_DIR="${PRIVATE_DIR:-$HOME/private-dotfiles}"
BACKUP_ROOT="$HOME/.config/dotfiles/private-backup"

# 同步的文件名单：与 private-state.zsh 的 SLOTS 表 `source_rel` 列一致。
# ⚠️ 改这里要同步改那边 —— 两处各写各的会漂移（只差一个文件名，
# status 就会永远报「只在一边」）。
SYNC_FILES=(
  'aliases'
  'zshrc.local'
  'envconfig.local'
  'gitconfig.local'
  'ssh/config.local'
)
# 跟着走的子树（整个目录，有就同步，没有就跳过，不报错）。
SYNC_DIRS=(
  'machine'
)

usage() {
  cat <<EOF
Usage: zsh scripts/macos/private-sync.zsh <status|pull|push> [options]

  status              比对 CARRIER 和 LIVE（只读，永远退出 0）
  pull                CARRIER → LIVE（新机器进场 / 拿别的机器的改动）
  push                LIVE → CARRIER（本机改完交出去）

  加 --json 时 status 改出结构化结果（给 macview 读，只读）。
  ⚠️ --json **不要求** --carrier：没配中转目录也是一个**合法状态**
  （界面要显示「没配」，不是报错）。而 pull/push 没 carrier 仍然退出 1。

Options:
  --carrier <目录>    中转目录（默认：\$PRIVATE_SYNC_DIR，必须给其中一个）
  --live <目录>       本机生效目录（默认：\$PRIVATE_DIR 或 ~/private-dotfiles）
  -h, --help          显示这段

退出码：
  0  成功（含「已经一致」、含 status）
  1  失败（CARRIER 不像私有源 / 复制失败 / 参数错）
EOF
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage >&2; exit 1; }
shift || true

CARRIER="${PRIVATE_SYNC_DIR:-}"
AS_JSON=0
while (( $# > 0 )); do
  case "$1" in
    --carrier) CARRIER="${2:-}"; shift 2 ;;
    --live) LIVE_DIR="${2:-}"; shift 2 ;;
    --json) AS_JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# ⚠️ **只有 pull/push 缺 carrier 才算错。** status 不算 ——
# 「没配中转目录」是界面**要显示的一个状态**（`carrier.set = false`），
# 不是错误。缺了就当空字符串处理，下面所有比对自然全是「只在本机」/「都没有」。
# 早先这里无条件 exit 1，那会让 macview 永远读不到「没配」这个状态。
if [[ -z "$CARRIER" && "$cmd" != "status" ]]; then
  echo "Error: 没给中转目录。用 --carrier <目录>，或设 PRIVATE_SYNC_DIR。" >&2
  exit 1
fi

# ── 小工具 ────────────────────────────────────────────────────────────────

# CARRIER 像不像私有源：5 个已知文件至少命中一个。
# 不像 → 极大概率是指错了路径，倒进去没有意义。
carrier_looks_like_private() {
  local f
  for f in "${SYNC_FILES[@]}"; do
    [[ -e "$CARRIER/$f" ]] && return 0
  done
  for f in "${SYNC_DIRS[@]}"; do
    [[ -e "$CARRIER/$f" ]] && return 0
  done
  return 1
}

# 备份 LIVE 里将被覆盖的文件（内容不一样才备，一样就不用）。
backup_live() {
  local rel="$1"
  local src="$LIVE_DIR/$rel"
  [[ -f "$src" ]] || return 0
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local dest="$BACKUP_ROOT/$ts/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -p "$src" "$dest"
  echo "  已备份 $rel → $BACKUP_ROOT/$ts/$rel"
}

# 复制一个文件（建父目录，保 mtime）。
copy_one() {
  local from="$1" to="$2"
  mkdir -p "$(dirname "$to")"
  cp -p "$from" "$to"
}

# 同步 machine/ 这类子树：有就整目录复制（覆盖同名），没有就跳过。
# ⚠️ 不删除目标里多出来的文件 —— 规则 3。
# ⚠️ 先比对，一样就不动手 —— 否则每次 pull 都算"有改动"，幂等就破了。
sync_dir() {
  local from="$1" to="$2" rel="$3"
  if [[ ! -d "$from" ]]; then
    return 1
  fi
  if [[ -d "$to" ]] && diff -rq "$from" "$to" >/dev/null 2>&1; then
    return 1
  fi
  mkdir -p "$to"
  # 用 tar 搬：保权限、保隐藏文件，不跟符号链接跑。
  (cd "$from" && tar cf - .) | (cd "$to" && tar xf -)
  echo "  已同步目录 $rel/"
  return 0
}

# ── status（只读） ────────────────────────────────────────────────────────

do_status() {
  local f a b
  local same=0 diff=0 only_carrier=0 only_live=0
  for f in "${SYNC_FILES[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    if [[ -e "$a" && -e "$b" ]]; then
      if cmp -s "$a" "$b" 2>/dev/null; then
        echo "  = $f（一致）"; (( same++ )) || true
      else
        echo "  ≠ $f（两边不一样）"; (( diff++ )) || true
      fi
    elif [[ -e "$a" ]]; then
      echo "  → $f（只在中转目录，本机没有）"; (( only_carrier++ )) || true
    elif [[ -e "$b" ]]; then
      echo "  ← $f（只在本机，中转目录没有）"; (( only_live++ )) || true
    else
      echo "  · $f（两边都没有）"
    fi
  done
  echo "一致 $same · 不一致 $diff · 只在中转 $only_carrier · 只在本机 $only_live"
}

# ── status --json（给 macview 读，只读）────────────────────────────────────
#
# ## 为什么单独一个出口而不是把纯文本转成 JSON
#
# 因为纯文本那个 `do_status` 里的 `echo` 是**给人看**的（中文、带提示、
# 末尾一行汇总）。让 macview 去解析中文散文，等于把界面和这句措辞焊死 ——
# 改一句「只在中转」就崩。所以**另写一份结构化的**，两件事各说各的，
# 改其中一句不影响另一句。
#
# ## 报什么、为什么不报什么
#
# **只报事实**（每个文件两边各是什么状态），**不判断该不该同步**。
# 「不一致」是事实；「该 pull」是判断 —— 判断归 macview（它知道用户意图），
# 脚本只负责如实说。
#
# ⚠️ **不含任何文件内容。** 这是私密配置；只报存在性和「内容是否相同」，
# 绝不把内容送出去。macview 也只显示状态。
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  print -r -- "$s"
}

json_bool() { (( $1 )) && printf 'true' || printf 'false'; }

# 单个文件的状态：两边都在且相同 → same；都在但不同 → differ；
# 只在中转 → carrier_only；只在本机 → live_only；都不在 → absent_both。
file_state() {
  local a="$1" b="$2"
  if [[ -e "$a" && -e "$b" ]]; then
    if cmp -s "$a" "$b" 2>/dev/null; then print same; else print differ; fi
  elif [[ -e "$a" ]]; then
    print carrier_only
  elif [[ -e "$b" ]]; then
    print live_only
  else
    print absent_both
  fi
}

# 目录（machine/ 这类子树）的状态：只看**有没有**，不比内容 ——
# 目录内容多且这个版本只做「看」，逐文件比对留给以后真正要 pull 的时候。
dir_state() {
  local a="$1" b="$2"
  if [[ -d "$a" && -d "$b" ]]; then print same
  elif [[ -d "$a" ]]; then print carrier_only
  elif [[ -d "$b" ]]; then print live_only
  else print absent_both
  fi
}

do_json() {
  local out f a b st
  out+="{"$'\n'
  out+="  \"version\": 1,"$'\n'
  out+="  \"checked_at\": $(date +%s),"$'\n'
  out+="  \"generated_by\": \"private-sync.zsh\","$'\n'

  # 两端在哪、中转配没配。`carrier_set` 单独给一个布尔 —— 界面要先回答
  # 「根本没配中转目录」和「配了但两边没差异」，那是两种状态。
  out+="  \"carrier\": {"$'\n'
  out+="    \"path\": $( [[ -n "$CARRIER" ]] && printf '"%s"' "$(json_escape "$CARRIER")" || printf 'null' ),"$'\n'
  out+="    \"set\": $(json_bool $( [[ -n "$CARRIER" ]] && echo 1 || echo 0 )),"$'\n'
  out+="    \"exists\": $(json_bool $( [[ -d "$CARRIER" ]] && echo 1 || echo 0 )),"$'\n'
  out+="    \"looks_like_private\": $(json_bool $( carrier_looks_like_private && echo 1 || echo 0 ))"$'\n'
  out+="  },"$'\n'
  out+="  \"live\": {"$'\n'
  out+="    \"path\": \"$(json_escape "$LIVE_DIR")\","$'\n'
  out+="    \"exists\": $(json_bool $( [[ -d "$LIVE_DIR" ]] && echo 1 || echo 0 ))"$'\n'
  out+="  },"$'\n'

  out+="  \"files\": ["$'\n'
  local n=${#SYNC_FILES[@]} i=0
  for f in "${SYNC_FILES[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    st="$(file_state "$a" "$b")"
    # ⚠️ `(( i++ ))` 在 i=0 时**返回非零**（表达式的值是自增前的 0），
    # `set -e` 会当场把整个脚本杀掉 —— 而且是**静默**的（`status --json`
    # 输出空，退出码还可能看着像 0）。踩过。`|| true` 断掉这个语义。
    (( i++ )) || true
    out+="    {"$'\n'
    out+="      \"rel\": \"$(json_escape "$f")\","$'\n'
    out+="      \"state\": \"$st\","$'\n'
    out+="      \"in_carrier\": $(json_bool $( [[ -e "$a" ]] && echo 1 || echo 0 )),"$'\n'
    out+="      \"in_live\": $(json_bool $( [[ -e "$b" ]] && echo 1 || echo 0 )),"$'\n'
    out+="      \"linked\": $(json_bool $( [[ -L "$b" ]] && echo 1 || echo 0 ))"$'\n'
    out+="    }"
    (( i < n )) && out+=","$'\n' || out+=""$'\n'
  done
  out+="  ],"$'\n'

  out+="  \"dirs\": ["$'\n'
  n=${#SYNC_DIRS[@]}; i=0
  for f in "${SYNC_DIRS[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    st="$(dir_state "$a" "$b")"
    (( i++ )) || true   # 同上：i=0 时返回非零，会被 set -e 杀掉
    out+="    {"$'\n'
    out+="      \"rel\": \"$(json_escape "$f")\","$'\n'
    out+="      \"state\": \"$st\""$'\n'
    out+="    }"
    (( i < n )) && out+=","$'\n' || out+=""$'\n'
  done
  out+="  ]"$'\n'
  out+="}"$'\n'

  printf '%s' "$out"
}

# ── pull / push ───────────────────────────────────────────────────────────

# 把 KNOWN 文件从 $1 搬到 $2（backup 语义由调用方定：pull 才备份）。
do_pull() {
  if ! carrier_looks_like_private; then
    echo "Error: $CARRIER 里一个私有文件都没有 —— 路径可能指错了，没动本机。" >&2
    exit 1
  fi
  local f a b changed=0
  for f in "${SYNC_FILES[@]}"; do
    a="$CARRIER/$f"; b="$LIVE_DIR/$f"
    [[ -e "$a" ]] || continue
    if [[ -e "$b" ]] && cmp -s "$a" "$b" 2>/dev/null; then
      continue
    fi
    # LIVE 里有且不一样 → 先备份（规则 2）。
    if [[ -e "$b" ]]; then
      backup_live "$f"
    fi
    copy_one "$a" "$b"
    echo "  已拿过来 $f"
    (( changed++ )) || true
  done
  local d
  for d in "${SYNC_DIRS[@]}"; do
    if [[ -d "$CARRIER/$d" ]]; then
      if sync_dir "$CARRIER/$d" "$LIVE_DIR/$d" "$d"; then
        (( changed++ )) || true
      fi
    fi
  done
  if (( changed == 0 )); then
    echo "已经一致，什么都没做。"
  else
    echo "拿过来 $changed 项。改动即生效（下次开 shell）—— 要确认去 macview 对应页看一眼。"
  fi
}

do_push() {
  local f a b changed=0
  for f in "${SYNC_FILES[@]}"; do
    a="$LIVE_DIR/$f"; b="$CARRIER/$f"
    [[ -e "$a" ]] || continue
    if [[ -e "$b" ]] && cmp -s "$a" "$b" 2>/dev/null; then
      continue
    fi
    # push 不备份 CARRIER 那边 —— CARRIER 是中转，不是真相；
    # 真相在 LIVE（有备份的是 pull 那条路）。中转丢了可以从任一机器重新 push。
    copy_one "$a" "$b"
    echo "  已交出去 $f"
    (( changed++ )) || true
  done
  local d
  for d in "${SYNC_DIRS[@]}"; do
    if [[ -d "$LIVE_DIR/$d" ]]; then
      if sync_dir "$LIVE_DIR/$d" "$CARRIER/$d" "$d"; then
        (( changed++ )) || true
      fi
    fi
  done
  if (( changed == 0 )); then
    echo "已经一致，什么都没做。"
  else
    echo "交出去 $changed 项。记得用你们的同步方式把中转目录送出去。"
  fi
}

case "$cmd" in
  status)
    if (( AS_JSON )); then do_json; else do_status; fi
    ;;
  pull)   do_pull ;;
  push)   do_push ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
