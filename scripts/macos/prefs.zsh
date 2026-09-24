#!/usr/bin/env zsh
#
# 应用 macOS 偏好（defaults write）。
#
# 三条设计要点：
#   1. 逐文件执行，**一个失败不中断其余的**。比如 sudo_touchid 要密码，
#      你按了取消，不该让 dock / finder 的偏好也白设。
#   2. 全部幂等 —— defaults write 重复执行结果相同，所以随时可以重跑。
#   3. 结束时报告成功/失败数量，并给出重跑命令。
#
# 注意这里**不用 `set -e`**：那个会让我们刚说的第 1 条失效。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"
PREFS_DIR="$ROOT_DIR/scripts/macos/prefs.d"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS prefs can only be applied on macOS." >&2
  exit 1
fi

if [[ ! -d "$PREFS_DIR" ]]; then
  echo "Prefs directory not found: $PREFS_DIR" >&2
  exit 1
fi

echo "Applying macOS preferences..."

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
if (( ${#stale[@]} > 0 )); then
  echo "  ! 顺序表里的这些文件不在 prefs.d（被删或改名了？）：${(j:、:)stale}" >&2
fi

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
