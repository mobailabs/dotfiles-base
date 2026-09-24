#!/usr/bin/env zsh
#
# 仓库自检：把「这个仓库内部是否自洽」变成一条命令。
#
# ## 为什么需要它
#
# 这个仓库里的东西是**交叉引用**的：
#
#   link-dotfiles.zsh 的 DOTFILE_LINKS   ←→  src/macos/config/ 下真的有那个文件？
#   README/shell.md 提到的加载点          ←→  zshrc 里真的有那行 source？
#   prefs.zsh 的顺序表                    ←→  prefs.d/ 下真的有那些文件？
#   private.md 的槽位表                    ←→  private-state.zsh 里真的是那五个？
#   install.zsh 调用的每一个脚本           ←→  scripts/ 下真的存在？
#
# 这些关系**错了不会报错**：改了 A 忘了 B，A 照跑，B 静默失效。
# 以前只能靠人肉眼对，于是「我觉得对」就等于对。
#
# 这个脚本把它们全查一遍。**只读**，不改任何东西，不联网。
#
# 用法：
#   zsh scripts/macos/selfcheck.zsh       # 有问题 exit 1
#
# 它检查的是**仓库内部一致性**，不检查机器状态（那是 brew-audit /
# private-state 的事）。macOS 也不需要 —— 纯文本检查，任何机器都能跑。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 计数
_pass=0
_fail=0
_warn=0

section() {
  echo ""
  echo "── $1"
}

ok()   { _pass=$((_pass + 1)); }
bad()  { _fail=$((_fail + 1)); echo "  ✗ $1"; }
warn() { _warn=$((_warn + 1)); echo "  ! $1"; }

# ── 1. 落点：DOTFILE_LINKS ←→ 源文件 ────────────────────────────────────
#
# 两个方向都查：声明了但源不存在（链接会静默 skip）、源存在但没被链接
# （那个配置永远不生效）。
check_links() {
  section "落点（link-dotfiles.zsh ←→ src/macos/config/）"

  local linkfile="$ROOT_DIR/scripts/macos/link-dotfiles.zsh"
  local cfgroot="$ROOT_DIR/src/macos/config"
  local -a declared=()

  # 从 DOTFILE_LINKS=( ... ) 里抽 `'源|目标'` 行。
  # 只认单引号开头的行 —— 注释和数组声明不会被误抓。
  local line rel
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"     # ltrim
    [[ "$line" == \'* ]] || continue
    line="${line#\'}"
    rel="${line%%|*}"
    [[ -n "$rel" ]] && declared+=("$rel")
  done < "$linkfile"

  (( ${#declared[@]} > 0 )) || { bad "没能从 DOTFILE_LINKS 里解析出任何落点（解析逻辑过期了？）"; return; }

  # 方向一：声明了但源不存在 —— **或源是空目录**。
  #
  # ⚠️ 空目录也算 `-e` 存在，但链接一个空目录 = 那个配置永远不生效
  # （这跟「源缺失」的后果完全一样）。曾实测：加一个空目录落点，
  # 所有检查照样通过。所以这里显式把空目录判为错。
  for rel in "${declared[@]}"; do
    if [[ ! -e "$cfgroot/$rel" ]]; then
      bad "DOTFILE_LINKS 声明了 '$rel'，但 $cfgroot/$rel 不存在"
    elif [[ -d "$cfgroot/$rel" ]] && [[ -z "$(ls -A "$cfgroot/$rel" 2>/dev/null)" ]]; then
      bad "DOTFILE_LINKS 声明了 '$rel'，但 $cfgroot/$rel 是**空目录**（链过去等于该配置永不生效）"
    else
      ok
    fi
  done

  # 方向二：cfgroot 下的一级条目，有没有没被任何落点覆盖的。
  # 只查**一级**（顶层文件/目录）—— 深层子文件属于目录型落点的一部分。
  local entry covered
  for entry in "$cfgroot"/*(N); do
    entry="$(basename "$entry")"
    covered=0
    for rel in "${declared[@]}"; do
      # 落点 'aliases' 覆盖 cfgroot/aliases；
      # 落点 'nvim' 覆盖 cfgroot/nvim（目录）。
      # 落点 'git/gitconfig' 覆盖的是二级，不影响一级覆盖判断。
      [[ "$rel" == "$entry" || "$rel" == "$entry"/* ]] && covered=1
    done
    (( covered )) || bad "$cfgroot/$entry 存在，但 DOTFILE_LINKS 里没有对应落点（这个配置永远不会生效）"
  done

  echo "  落点 ${#declared[@]} 条"
}

# ── 2. 文档引用的脚本 / 文件是否真实存在 ─────────────────────────────────
#
# 只查**明确写成仓库路径**的引用（比如 `scripts/macos/foo.zsh`），
# 不查自然语言里的描述 —— 那样误报太多。
#
# ⚠️ 扫描范围是**仓库里所有 `.md`**（glob 发现），不是写死的三个。
# 写死名单踩过的坑：README/shell/private 之外还有 nvim/README.md 和
# tmux/config/README.md，它们里悬空的路径引用永远不会被发现。
# 凡是「新增一个文档就得记得加进名单」的设计，迟早会漏。
#
# ⚠️ 扩展名白名单必须包含 `.md` —— 文档互相引用（`[x](y.md)`）是最常见
# 的一类引用，漏掉它等于漏掉一整类。同理 `.icns` 之类资源文件也在白名单。
check_doc_refs() {
  section "文档里的仓库路径引用"

  # glob 发现所有 .md（`**` 递归，包含顶层；`(N)` 无匹配时不报错）。
  # ⚠️ 不要再加 `*.md(N)` —— zsh 的 `**/` 已经匹配顶层，重复列出会把
  # 同一个文档数两次（这里曾因此报「8 个文档」而实际只有 5 个）。
  local -a docs=()
  local d
  for d in "$ROOT_DIR"/**/*.md(N); do
    [[ -f "$d" ]] && docs+=("$d")
  done

  (( ${#docs[@]} > 0 )) || { bad "没有找到任何 .md 文档"; return; }

  local doc ref found
  for doc in "${docs[@]}"; do
    # 抓形如 scripts/xxx/yyy.zsh、packages/xxx.txt、src/macos/config/... 的引用。
    # 用 grep -o 把候选抠出来，逐个判存在。
    #
    # ⚠️ 扩展名白名单含 `md` —— 文档间引用（`[a](b.md)`、反引号里的 `x.md`）
    # 也是仓库路径引用，不查就会漏（曾漏掉 `见 [x](nonexistent.md)`）。
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      # 跳过明显是通配/示例的
      [[ "$ref" == *'*'* ]] && continue
      # 跳过花括号展开（`{a,b}`）—— 那是「多个候选」的写法，
      # 单独判存在会误报，且本身就容易过期（合并 common/ 时就发生过）。
      [[ "$ref" == *'{'* ]] && continue
      if [[ -e "$ROOT_DIR/$ref" ]]; then
        ok
      else
        # 用**相对仓库的路径**而不是 basename —— 仓库里有两个 README.md
        # （顶层 / nvim），只写 basename 会指向不明确的文件，等于没说清。
        bad "${doc#"$ROOT_DIR"/} 提到 '$ref'，但仓库里没有"
      fi
    done < <(grep -oE '(scripts|packages|src|prefs\.d)/[A-Za-z0-9_./-]+\.(zsh|sh|txt|toml|conf|lua|md|icns|json|yaml|yml)' "$doc" 2>/dev/null | sort -u)
  done

  echo "  扫描 ${#docs[@]} 个文档"
}

# ── 3. install.zsh 调用的脚本都存在 ─────────────────────────────────────
check_entrypoints() {
  section "install.zsh → 脚本"

  local entry="$ROOT_DIR/install.zsh"
  local ref
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ -f "$ROOT_DIR/$ref" ]]; then
      ok
    else
      bad "install.zsh 调用 '$ref'，但不存在"
    fi
  done < <(grep -oE 'SCRIPT_DIR/[A-Za-z0-9_./-]+\.zsh' "$entry" | sed 's|^SCRIPT_DIR/||' | sort -u)
}

# ── 4. prefs.d：顺序表 ←→ 磁盘 ──────────────────────────────────────────
check_prefs() {
  section "prefs.d/ ←→ prefs.zsh 的顺序表"

  local prefsfile="$ROOT_DIR/scripts/macos/prefs.zsh"
  local prefsdir="$ROOT_DIR/scripts/macos/prefs.d"

  # glob 出来的真实文件
  local -a on_disk=()
  local f
  for f in "$prefsdir"/*.zsh(N); do on_disk+=("$(basename "$f")"); done

  # 顺序表里点名的（PREF_ORDER=( ... ) 里以 .zsh 结尾的裸名）
  local -a ordered=()
  local line name
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == *.zsh ]] || continue
    name="${line%%[[:space:]]*}"
    ordered+=("$name")
  done < <(sed -n '/^PREF_ORDER=(/,/^)/p' "$prefsfile")

  (( ${#on_disk[@]} > 0 )) || { warn "prefs.d/ 下没有 .zsh"; return; }

  for name in "${ordered[@]}"; do
    if (( ${on_disk[(I)$name]} )); then
      ok
    else
      bad "prefs.zsh 顺序表里有 '$name'，但 prefs.d/ 下没有（被删/改名？）"
    fi
  done

  # 磁盘上有、顺序表里没有 —— 不是错（会自动排到末尾跑），但提示一下。
  for f in "${on_disk[@]}"; do
    if (( ! ${ordered[(I)$f]} )); then
      warn "prefs.d/$f 不在 PREF_ORDER 里（会自动排到最后跑；想固定顺序就加上）"
    fi
  done

  echo "  prefs.d/ ${#on_disk[@]} 个文件"
}

# ── 4b. install.zsh 的 usage 说明 ←→ run_base 实际步骤 ───────────────────
#
# `install.zsh help` 是用户唯一能看到的说明。它漏写一步（比如忘了「一次性
# 设置」），用户就不知道会弹一次密码 —— 而这一步恰恰是全自动的关键。
# 两边对不上是纯文本不一致，机器完全能查，不该靠人肉眼。
check_usage_steps() {
  section "install.zsh usage ←→ run_base 实际步骤"

  local entry="$ROOT_DIR/install.zsh"
  [[ -f "$entry" ]] || { bad "install.zsh 不在"; return; }

  # usage 里 base 那一行声明的步骤名（run_step 的 desc 用同名）。
  # 从 `| base   Run setup:` 后面读到行尾，按逗号拆。
  local usage_line
  usage_line="$(sed -n '/| base[[:space:]]*Run setup:/,/^$/p' "$entry" | tr '\n' ' ')"
  [[ -n "$usage_line" ]] || { warn "没能解析 usage 里的 base 说明，跳过"; return; }

  # 逐行抽 run_step "描述" 的 desc
  local -a steps=()
  local step
  while IFS= read -r step; do
    [[ -n "$step" ]] && steps+=("$step")
  done < <(grep -oE 'run_step "[^"]+"' "$entry" | sed 's/run_step "//; s/"$//')

  (( ${#steps[@]} > 0 )) || { bad "没能从 install.zsh 解析出 run_step"; return; }

  # usage 那一行是不是把每个步骤名都提了一遍？
  # 用「关键词」比对（usage 是英文别名，run_step 是中文描述，不能直接全等）——
  # 所以只做**计数**与**逐个关键词**两项弱校验，避免误报。
  echo "  run_base 有 ${#steps[@]} 个 run_step"
  for step in "${steps[@]}"; do
    # 取描述里的「关键词」：去掉括号补充、取第一段。
    local key="${step%%（*}"
    key="${key%% *}"
    [[ -n "$key" ]] || continue
    if [[ "$usage_line" == *"$key"* ]]; then
      ok
    else
      # usage 是英文的，中文描述天然对不上 —— 只对「一次性设置」这种
      # 中文也出现在 usage 里的做硬校验，其余软提示。
      case "$step" in
        *一次性设置*) bad "usage 的 base 说明里没提「一次性设置」这一步（它是最关键的一步：会问密码）" ;;
        *) ok ;;   # 英文/中文别名对应关系无法机判，不误报
      esac
    fi
  done
}

# ── 4c. PATH 归属唯一性 ─────────────────────────────────────────────────
#
# PATH 条目散在多处是「加一处漏一处」的温床，而且不同文件用的方法不同
# （zsh 的 `path+=` 有 typeset -U 去重，bash 手拼 `$PATH:...` 没有）。
# 约定：bash 的 PATH 拼接只允许出现在 .zshenv（唯一归属），
# bash_profile / zshrc 不再各自手拼。
check_path_ownership() {
  section "PATH 归属（.zshenv 唯一）"

  local zshenv="$ROOT_DIR/src/macos/config/zsh/zshenv"
  local zshrc="$ROOT_DIR/src/macos/config/zsh/zshrc"
  local bashp="$ROOT_DIR/src/macos/config/shell/bash_profile"

  [[ -f "$zshenv" ]] || { warn "zshenv 不在，跳过"; return; }

  # zshrc / bash_profile 里不该再有 `export PATH=` 手拼
  local f n
  for f in "$zshrc" "$bashp"; do
    [[ -f "$f" ]] || continue
    n="$(grep -cE 'export PATH=.*\$PATH.*' "$f" 2>/dev/null)"
    if (( n > 0 )); then
      bad "$(basename "$f") 里有 $n 处手拼的 'export PATH=...\$PATH...'（PATH 归属应只在 .zshenv）"
    else
      ok
    fi
  done

  # zshenv 必须真的在管 PATH（否则这个约定是空的）
  grep -q 'export PATH' "$zshenv" && ok || bad ".zshenv 里没有 export PATH —— PATH 归属约定失效"
  grep -q 'typeset -U path' "$zshenv" && ok || warn ".zshenv 没有 'typeset -U path'，PATH 可能累积重复项"
}

# ── 5. private.md 的槽位表 ←→ private-state.zsh ─────────────────────────
check_private_slots() {
  section "private.md 槽位 ←→ private-state.zsh"

  local md="$ROOT_DIR/private.md"
  local impl="$ROOT_DIR/scripts/macos/private-state.zsh"

  [[ -f "$md" ]]   || { warn "private.md 不在，跳过"; return; }
  [[ -f "$impl" ]] || { warn "private-state.zsh 不在，跳过"; return; }

  # 从实现里抽 SLOTS 数组的 id（每行 'id|name|...'）
  local -a impl_ids=()
  local line id
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == \'* ]] || continue
    line="${line#\'}"
    id="${line%%|*}"
    [[ -n "$id" ]] && impl_ids+=("$id")
  done < <(sed -n '/^SLOTS=(/,/^)/p' "$impl")

  # 从 private.md 的 JSON 块里抽 "id": "..."（主格式块）
  local -a doc_ids=()
  while IFS= read -r id; do
    [[ -n "$id" ]] && doc_ids+=("$id")
  done < <(grep -oE '"id": "[a-z-]+"' "$md" | sed 's/.*"id": "//; s/"//' | sort -u)

  (( ${#impl_ids[@]} > 0 )) || { bad "没能从 private-state.zsh 的 SLOTS 里解析出 id"; return; }

  local i
  for i in "${impl_ids[@]}"; do
    if (( ${doc_ids[(I)$i]} )); then
      ok
    else
      bad "private-state.zsh 的槽位 '$i' 不在 private.md 的示例里"
    fi
  done
  for i in "${doc_ids[@]}"; do
    if (( ! ${impl_ids[(I)$i]} )); then
      # doc 里可能还有别的 id（比如 effect 示意块），只警告
      warn "private.md 提到槽位 '$i'，但 private-state.zsh 的 SLOTS 里没有"
    fi
  done

  echo "  实现 ${#impl_ids[@]} 个槽位"
}

# ── 6. 所有 shell 脚本语法 ──────────────────────────────────────────────
check_syntax() {
  section "shell 脚本语法"

  local f n=0
  # ⚠️ 只写 `**/*.zsh(N)` —— zsh 的 `**/` 已包含顶层，再加 `*.zsh(N)`
  # 会把顶层的 install.zsh 数两次（曾报「28 个」而实际只有 27 个）。
  for f in "$ROOT_DIR"/**/*.zsh(N); do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    # prefs.d 里是 bash 脚本，用 bash -n；其余用 zsh -n。
    case "$f" in
      */prefs.d/*) bash -n "$f" 2>/dev/null && ok || bad "bash 语法错误：${f#$ROOT_DIR/}" ;;
      *)           zsh  -n "$f" 2>/dev/null && ok || bad "zsh 语法错误：${f#$ROOT_DIR/}" ;;
    esac
  done
  echo "  检查 $n 个脚本"
}

# ── 7. private-state.zsh 产出的 JSON 合法 ───────────────────────────────
check_private_json() {
  section "private-state.zsh 产出合法 JSON"

  local impl="$ROOT_DIR/scripts/macos/private-state.zsh"
  [[ -f "$impl" ]] || { warn "跳过"; return; }

  if ! command -v python3 >/dev/null 2>&1; then
    warn "没有 python3，跳过 JSON 校验"
    return
  fi

  # --stdout 是只读的，不会落盘。
  local json
  json="$(zsh "$impl" --stdout 2>/dev/null)" || { bad "private-state.zsh --stdout 执行失败"; return; }

  if printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    ok
    # 顺带校验契约必填字段
    local missing
    missing="$(printf '%s' "$json" | python3 -c '
import json,sys
d=json.load(sys.stdin)
req={"version","checked_at","generated_by","source","slots"}
print(",".join(sorted(req-set(d.keys()))))
')"
    [[ -z "$missing" ]] && ok || bad "产出缺少顶层字段：$missing"
  else
    bad "private-state.zsh --stdout 产出的不是合法 JSON"
  fi
}

# ── 8. macview 查询脚本的 JSON 合法（契约见 macview-contract.md 第二节）────
#
# 契约承诺「每个查询脚本的产出都由 selfcheck 校验」。这一节就是兑现它。
# 每个脚本：跑它的 --json（只读）、要求是合法 JSON、要求必填顶层字段都在。
#
# 为什么这条重要：格式漂了若没人管，macview 会「一脸懵」地解析失败 ——
# 而契约第四节写明，「漂移要报错，不要静默」。这里就是那个报错的地方。
check_macview_query_json() {
  section "macview 查询脚本产出合法 JSON"

  if ! command -v python3 >/dev/null 2>&1; then
    warn "没有 python3，跳过 JSON 校验"
    return
  fi

  # `脚本|必填顶层字段（逗号分隔）`
  local -a specs=(
    "preflight.zsh|version,checked_at,generated_by,dotfiles,private,scripts,tools"
    "link-status.zsh|version,checked_at,generated_by,targets,counts"
    "repo-status.zsh|version,checked_at,generated_by,is_git"
    "mise-status.zsh|version,checked_at,generated_by,mise_present,tools"
  )

  local spec name req impl json missing
  for spec in "${specs[@]}"; do
    name="${spec%%|*}"
    req="${spec#*|}"
    impl="$ROOT_DIR/scripts/macos/$name"
    if [[ ! -f "$impl" ]]; then
      bad "$name 不在（契约里承诺了它）"
      continue
    fi

    json="$(zsh "$impl" --json 2>/dev/null)" || { bad "$name --json 执行失败"; continue; }

    if ! printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      bad "$name --json 产出的不是合法 JSON"
      continue
    fi
    ok

    missing="$(REQ="$req" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
req = set(os.environ["REQ"].split(","))
print(",".join(sorted(req - set(d.keys()))))
' <<<"$json")"
    [[ -z "$missing" ]] && ok || bad "$name 产出缺少顶层字段：$missing"
  done

  # brew-audit.zsh 的 --json 模式（给现有脚本加的那个）。
  local audit="$ROOT_DIR/scripts/macos/brew-audit.zsh"
  if [[ -f "$audit" ]]; then
    json="$(zsh "$audit" --json 2>/dev/null)" || true
    if [[ -z "$json" ]]; then
      warn "brew-audit.zsh --json 无输出（可能 brew 不在），跳过"
    elif printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      ok
      missing="$(REQ="version,checked_at,generated_by,declared,installed,missing,duplicate,extra" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
req = set(os.environ["REQ"].split(","))
print(",".join(sorted(req - set(d.keys()))))
' <<<"$json")"
      [[ -z "$missing" ]] && ok || bad "brew-audit.zsh --json 缺少顶层字段：$missing"
    else
      bad "brew-audit.zsh --json 产出的不是合法 JSON"
    fi
  fi
}

# ── 9. shell 脚本里不许有 `local path`（会静默清空 PATH）─────────────────
#
# `path` 是 zsh 的保留变量，和 `PATH` 是同一个数组。在任何函数里写
# `local path`（不带值）都会把 PATH 清空，于是该函数里之后所有
# `command git` / `command brew` 都变成 `command not found` —— 而且**不报错**，
# 只是结果静默变空（真踩过：repo-status.zsh 的 upstream 段变成 null）。
#
# 这条 lint 只查「local ... path ...」这种把 path 当局部变量的写法。
check_no_local_path() {
  section "没有把保留变量 path 当 local 用"

  local f hit
  local -a files=()
  for f in "$ROOT_DIR"/scripts/**/*.zsh(N); do
    [[ -f "$f" ]] && files+=("$f")
  done
  [[ -f "$ROOT_DIR/install.zsh" ]] && files+=("$ROOT_DIR/install.zsh")

  local found=0
  for f in "${files[@]}"; do
    # 匹配 `local path` / `local -a path` / `local x path y` 这类声明里的 path 单词。
    hit="$(grep -nE '^[[:space:]]*local([[:space:]]+-[A-Za-z]+)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]+path([[:space:]]|$)' "$f" 2>/dev/null || true)"
    if [[ -n "$hit" ]]; then
      bad "${f#"$ROOT_DIR"/} 把保留变量 path 声明成了 local（会清空 PATH）：$hit"
      found=1
    fi
  done
  (( found )) || ok
}

# ── 主流程 ──────────────────────────────────────────────────────────────
main() {
  echo "仓库自检（只读，不联网）：$ROOT_DIR"

  check_links
  check_doc_refs
  check_entrypoints
  check_prefs
  check_usage_steps
  check_path_ownership
  check_private_slots
  check_syntax
  check_private_json
  check_macview_query_json
  check_no_local_path

  echo ""
  if (( _fail == 0 )); then
    echo "通过：$_pass 项检查通过$([[ $_warn -gt 0 ]] && echo "，$_warn 条提示")。"
    return 0
  fi
  echo "失败：$_fail 项不通过（$_pass 通过，$_warn 提示）。" >&2
  return 1
}

main "$@"
