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

# 需要 sudo 的放最后，失败也不影响前面。
prefs=(
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
