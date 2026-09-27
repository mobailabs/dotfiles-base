#!/usr/bin/env zsh
#
# 应用 macOS 偏好（defaults write）。
#
# 入口：
#
#   zsh scripts/macos/prefs.zsh                应用（逐文件跑 defaults write）
#   zsh scripts/macos/prefs.zsh --no-sudo      应用，但**跳过需要管理员权限的主题**
#   zsh scripts/macos/prefs.zsh --only <主题>  只应用点名的那一个（可重复）
#   zsh scripts/macos/prefs.zsh --list --json  只**列**主题名（只读，不跑）
#
# ── 三条设计要点（应用到系统时）────────────────────────────────────────
#   1. 逐文件执行，**一个失败不中断其余的**。比如 sudo_touchid 要密码，
#      你按了取消，不该让 dock / finder 的偏好也白设。
#   2. 全部幂等 —— defaults write 重复执行结果相同，所以随时可以重跑。
#   3. 结束时报告成功/失败数量，并给出重跑命令。
#
# 注意这里**不用 `set -e`**：那个会让我们刚说的第 1 条失效。
#
# ── `--list --json` 为什么在这里、而不是单开脚本 ────────────────────────
#
# 「有哪些主题」的真相是**两样东西拼出来的**：`PREF_ORDER` 的顺序 + 磁盘上
# glob 到的文件（下面 §顺序 那段）。这个逻辑**只能有一份** —— 单开一个
# `prefs-list.zsh` 就是把「顺序」抄第二遍，两份迟早对不上（而且要人手动同步）。
# 所以 `--list` 复用**同一份** `PREF_ORDER` 和同一个 glob，只是不往下执行。
#
# 它**只读文件名，不读文件内容** —— 不解析 `defaults write` 那些行，所以
# 不违反契约 §2.7（那里禁的是「复刻文本解析」，不是「列目录」）。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"
PREFS_DIR="$ROOT_DIR/scripts/macos/prefs.d"

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE="apply"
JSON=0
# `--no-sudo`：跳过需要管理员权限的主题（见 §提权拆细）。
NO_SUDO=0
# `--only <主题>` 可重复；空 = 全都跑。见 §提权拆细。
ONLY=()

usage() {
  cat <<'EOF'
Usage:
  zsh scripts/macos/prefs.zsh                 应用偏好（会写系统设置）
  zsh scripts/macos/prefs.zsh --no-sudo       应用，但跳过需要管理员权限的主题
  zsh scripts/macos/prefs.zsh --only <主题>   只应用点名的主题（可重复）
  zsh scripts/macos/prefs.zsh --list --json   只列主题名（只读）

  --no-sudo  跳过需要管理员权限的主题（不弹密码，用于「先跑不用密码的那些」）
  --only X   只跑主题 X；可给多次。名字就是 prefs.d 下的文件名
  --list     只列主题，不应用（配合 --json 给 macview）
  --json     把结果打到 stdout（仅配合 --list）
  -h|--help  这段说明

契约见仓库根目录的 macview-contract.md。
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --list) MODE="list"; shift ;;
    --json) JSON=1; shift ;;
    --no-sudo) NO_SUDO=1; shift ;;
    --only)
      [[ -n "${2:-}" ]] || { echo "--only 后面要跟一个主题名。" >&2; exit 2; }
      ONLY+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# `--json` 只在 `--list` 下有意义（应用模式本来就是把过程打到 stdout）。
if (( JSON == 1 )) && [[ "$MODE" != "list" ]]; then
  echo "--json 只能配合 --list 用。" >&2
  usage >&2
  exit 2
fi

# `--no-sudo` 和 `--only` 是两套用法，一起给会让人搞不懂到底跑哪些。
if (( NO_SUDO == 1 )) && (( ${#ONLY[@]} > 0 )); then
  echo "--no-sudo 和 --only 不能一起用（前者是「除需提权的外全跑」，后者是「只跑点名的」）。" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS prefs can only be applied on macOS." >&2
  exit 1
fi

if [[ ! -d "$PREFS_DIR" ]]; then
  echo "Prefs directory not found: $PREFS_DIR" >&2
  exit 1
fi

# ── 顺序 ────────────────────────────────────────────────────────────────
#
# `sudo_touchid.zsh` 要密码，放**最后** —— 它失败时前面的都已经应用过了。
# 其余几个都是 `defaults write`，互相独立，顺序无所谓。
#
# ⚠️ 这里**只列顺序，不列清单**：磁盘上真实有哪些文件由 glob 决定。
# 以前是硬编码数组，后果是「新加一个 prefs.d/foo.zsh 但忘了加进数组」
# → 它**静默不跑**，而且没有任何提示 —— 你配的偏好看起来"生效了"，
# 其实一次都没执行。现在 glob 发现 + 下面的完整性校验把这个坑堵上。
PREF_ORDER=(
  dock.zsh
  finder.zsh
  keyboard.zsh
  trackpad.zsh
  ui_ux.zsh
  app_store.zsh
  textedit.zsh
  security_privacy.zsh
  sudo_touchid.zsh
)

# ── 提权拆细：哪些主题要管理员权限 ──────────────────────────────────────
#
# `sudo_touchid.zsh` 要写 `/etc/pam.d/sudo_local`（root 所有）→ 要管理员权限。
# 其余 8 个只跑 `defaults write`（写当前用户自己的域）→ **不需要**。
#
# ⚠️ **这里是显式声明，不是 grep 文件内容。**契约 §六 明说不去「复刻文本
# 解析」`prefs.d/*.zsh` —— 在这儿 grep `sudo` 同样是复刻解析，且会误判
# （注释里出现 "sudo" 就中招）。「哪个主题要提权」是**人的事实**，只能人写；
# 写在这儿 = 只此一份，改一处。
#
# 用途：`--no-sudo` 跳过它们，让 macview 的「应用系统设置」不再为这 8 个
# 也弹密码框（设计见系统页 §10.3）。
PREF_SUDO=(
  sudo_touchid.zsh
)

# glob 是唯一的「有哪些要跑」的事实来源。
discovered=()
for f in "$PREFS_DIR"/*.zsh(N); do
  discovered+=("$(basename "$f")")
done

# 排在 PREF_ORDER 里的先按顺序跑，其余的（新加的、还没排进顺序）自动排到末尾。
# 这样**新文件一定会跑**，只是顺序在最后 —— 漏加顺序是「慢」，不是「不跑」。
prefs=()
for name in "${PREF_ORDER[@]}"; do
  (( ${discovered[(I)$name]} )) && prefs+=("$name")
done
for name in "${discovered[@]}"; do
  (( ${PREF_ORDER[(I)$name]} )) || prefs+=("$name")
done

# 反过来也要报：PREF_ORDER 里点名了、磁盘上却没有。
# 「顺序里有个文件被删了/改名了」是另一个方向的静默失效。
stale=()
for name in "${PREF_ORDER[@]}"; do
  (( ${discovered[(I)$name]} )) || stale+=("$name")
done

# ── 提权拆细：按 `--no-sudo` / `--only` 收窄要跑的主题 ──────────────────
#
# 只有应用模式需要（`--list` 报的是**全部**主题，不受这俩开关影响 ——
# 「有哪些主题」和「这次跑哪些」是两回事）。
#
# ⚠️ `skipped_sudo` 先定义：`set -u` 下，没走 `--no-sudo` 分支时后面引用
# 它会报 unbound variable。声明在这一层（不在循环里 —— zsh 在循环里再
# `local`/重复赋值已存在变量会把 `x=值` 打到 stdout）。
skipped_sudo=()
if [[ "$MODE" == "apply" ]]; then
  if (( NO_SUDO == 1 )); then
    # 去掉需要管理员权限的。用**新数组**，不改 `prefs` 本身（下面还要用它
    # 报「跳过了哪些」）。
    kept=()
    for name in "${prefs[@]}"; do
      if (( ${PREF_SUDO[(I)$name]} )); then
        skipped_sudo+=("$name")
      else
        kept+=("$name")
      fi
    done
    prefs=("${kept[@]}")
  elif (( ${#ONLY[@]} > 0 )); then
    # 只留点名的。**点名的名字不认识时报警** —— 不静默跑空（那会让人以为
    # 「跑过了、生效了」，其实什么都没跑）。
    requested=()
    unknown=()
    for want in "${ONLY[@]}"; do
      if (( ${prefs[(I)$want]} )); then
        requested+=("$want")
      else
        unknown+=("$want")
      fi
    done
    if (( ${#unknown[@]} > 0 )); then
      echo "  ! 这些主题名在 prefs.d 里没有：${(j:、:)unknown}" >&2
      echo "    可用主题：${(j:、:)prefs}" >&2
      exit 2
    fi
    # 按 `prefs` 的既有顺序跑点名的那些（不按命令行给的先后 —— 顺序只由
    # PREF_ORDER 定，一份）。
    selected=()
    for name in "${prefs[@]}"; do
      (( ${requested[(I)$name]} )) && selected+=("$name")
    done
    prefs=("${selected[@]}")
  fi
fi

# ── `--list`：只报主题名，不跑 ──────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
  json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
  }

  if (( JSON == 0 )); then
    # 人肉看的时候：一行一个，带序号。
    local i=0
    for name in "${prefs[@]}"; do
      i=$((i + 1))
      printf '%2d  %s\n' "$i" "$name"
    done
    exit 0
  fi

  now=$(date +%s)

  # 拼 JSON 数组。⚠️ 所有 `local` 在循环外一次声明 —— zsh 在「会跑两遍以上
  # 的循环里」再 `local` 已有值的变量，会把 `x=值` 打到 stdout，污染 JSON。
  # 而且变量名**要避开脚本里已用过的全局名**（`name` 在上面已做全局循环变量，
  # 这里再 `local name` 会打印 `name=sudo_touchid.zsh` —— 踩过）。
  local out="" theme_rows="" tname in_order needs_sudo first=1
  for tname in "${prefs[@]}"; do
    (( first )) || theme_rows+=","$'\n'
    first=0
    # `in_order` = 这个名字在 PREF_ORDER 里点过名（即顺序是显式的，不是兜底）。
    in_order="false"
    (( ${PREF_ORDER[(I)$tname]} )) && in_order="true"
    # `needs_sudo` = 要用管理员权限（PREF_SUDO 点名了）。macview 靠它决定
    # 「这个主题归哪个按钮」—— **不写死名字**，改主题只改脚本一处。
    needs_sudo="false"
    (( ${PREF_SUDO[(I)$tname]} )) && needs_sudo="true"
    theme_rows+="    { \"name\": \"$(json_escape "$tname")\", \"in_order\": $in_order, \"needs_sudo\": $needs_sudo }"
  done

  local stale_rows="" sfirst=1 sname
  for sname in "${stale[@]}"; do
    (( sfirst )) || stale_rows+=", "
    sfirst=0
    stale_rows+="\"$(json_escape "$sname")\""
  done

  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"prefs.zsh\","$'\n'
  out+="  \"themes\": ["$'\n'
  out+="$theme_rows"$'\n'
  out+="  ],"$'\n'
  # `stale` = 顺序表里点名了、磁盘上没有的（改名/删了）。**这是异常**，
  # 和 `unordered`（新加、还没排顺序，只是顺序靠后）性质不同。
  out+="  \"stale\": [$stale_rows]"$'\n'
  out+="}"

  # 自校验：JSON 必须能被解析。解析不了就**不输出**，免得 macview 收到坏数据。
  if command -v python3 >/dev/null 2>&1; then
    if ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      echo "Error: prefs --list 产出的 JSON 解析不了（脚本有 bug）。" >&2
      exit 1
    fi
  fi

  printf '%s\n' "$out"
  exit 0
fi

# ── 应用 ────────────────────────────────────────────────────────────────

if (( ${#stale[@]} > 0 )); then
  echo "  ! 顺序表里的这些文件不在 prefs.d（被删或改名了？）：${(j:、:)stale}" >&2
fi

# 说清这次跳过了哪些（`--no-sudo`）—— **静默少跑是危险的**：用户以为全
# 应用了，其实 Touch ID 那步没跑。报出来，让他知道还剩什么。
if (( ${#skipped_sudo[@]} > 0 )); then
  echo "跳过需要管理员权限的主题（这次没跑）：${(j:、:)skipped_sudo}"
  echo "  要跑它们：zsh scripts/macos/prefs.zsh --only ${(j: --only :)skipped_sudo}"
  echo
fi

echo "Applying macOS preferences..."

ok=0
failed=()

for name in "${prefs[@]}"; do
  f="$PREFS_DIR/$name"
  [[ -f "$f" ]] || continue
  echo "-> $name"
  rc=0
  if [[ -x "$f" ]]; then
    "$f" || rc=$?
  else
    bash "$f" || rc=$?
  fi
  if (( rc == 0 )); then
    ok=$((ok + 1))
  else
    failed+=("$name")
  fi
done

echo
if (( ${#failed[@]} == 0 )); then
  echo "完成：$ok 个文件全部应用。"
  echo "有些改动需要重启 App 或重新登录才生效。"
else
  echo "完成：$ok 个成功，${#failed[@]} 个失败 -> ${failed[*]}"
  echo "失败的多半需要 sudo（比如 Touch ID for sudo）。可以单独重跑："
  echo "  zsh scripts/macos/prefs.zsh"
  exit 1
fi
