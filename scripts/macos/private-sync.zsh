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
while (( $# > 0 )); do
  case "$1" in
    --carrier) CARRIER="${2:-}"; shift 2 ;;
    --live) LIVE_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$CARRIER" ]]; then
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
  status) do_status ;;
  pull)   do_pull ;;
  push)   do_push ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
