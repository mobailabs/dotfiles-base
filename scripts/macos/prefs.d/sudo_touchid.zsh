#!/usr/bin/env bash
#
# 让 sudo 支持 Touch ID。
#
# ## 为什么写 /etc/pam.d/sudo_local 而不是 /etc/pam.d/sudo
#
# 早期到处流传的做法是往 `/etc/pam.d/sudo` 追加一行 pam_tid.so。这有几个真问题：
#
#   1. **改的是系统文件**。写坏了（少个空格、拼错模块名）sudo 可能直接不再
#      接受任何认证 —— 管理员权限被锁死，只能进恢复模式修。
#   2. **系统升级会重置** `/etc/pam.d/sudo`，你的行会消失，且不报错。
#   3. 没有备份，多次运行还容易写出重复行。
#
# macOS 12+ 的 sudo 文件第一行就是 `auth include sudo_local`（Apple 特意留的
# 自定义入口）。往 `/etc/pam.d/sudo_local` 写即可生效，而且：
#
#   - 不碰系统文件 → 出错删掉这个文件就完全恢复，零风险
#   - 系统升级不会重置它 → 更持久
#   - 天然幂等
#
# 本脚本优先用 sudo_local；只有在系统的 sudo 文件**没有** include sudo_local
# 时（很老的 macOS），才退回改 /etc/pam.d/sudo —— 且先备份。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 统一的 sudo 调用方式：终端环境 = 裸 sudo（弹终端提示）；
# macview 环境 = sudo -A（弹原生密码框）。见 sudo-env.zsh。
# ⚠️ 这里**不能**写裸 sudo —— 无 tty 时它会报「a terminal is required」。
source "$SCRIPT_DIR/../sudo-env.zsh"

echo "  sudo Touch ID"

SUDO_PAM="/etc/pam.d/sudo"
LOCAL_PAM="/etc/pam.d/sudo_local"
TID_LINE="auth       sufficient     pam_tid.so"

# 已经生效过就跳过（幂等）—— 两条路径都检查。
already=0
if [[ -f "$LOCAL_PAM" ]] && grep -q "pam_tid.so" "$LOCAL_PAM" 2>/dev/null; then
  already=1
fi
if [[ -f "$SUDO_PAM" ]] && grep -q "pam_tid.so" "$SUDO_PAM" 2>/dev/null; then
  already=1
fi

if (( already )); then
  echo "Touch ID for sudo already configured."
  exit 0
fi

# ── 首选：sudo_local（Apple 官方的自定义入口）────────────────────────────
if [[ -f "$SUDO_PAM" ]] && grep -q "include[[:space:]]*sudo_local" "$SUDO_PAM" 2>/dev/null; then
  echo "Enabling Touch ID for sudo via $LOCAL_PAM (requires admin password)..."
  # 用 mktemp + install 保证原子性与权限，不半途留下坏文件。
  tmp="$(mktemp)"
  printf '%s\n' "$TID_LINE" > "$tmp"
  "${SUDO[@]}" install -m 644 -o root -g wheel "$tmp" "$LOCAL_PAM"
  rm -f "$tmp"
  echo "Done. 撤销方法：sudo rm $LOCAL_PAM"
  exit 0
fi

# ── 退回：老系统没有 sudo_local，只能改 sudo 本身，先备份 ────────────────
if [[ -f "$SUDO_PAM" ]]; then
  echo "No sudo_local include found；回退为直接修改 ${SUDO_PAM}（先备份）。"
  backup="${SUDO_PAM}.dotsu-backup.$(date +%Y%m%d-%H%M%S)"
  "${SUDO[@]}" cp -p "$SUDO_PAM" "$backup"
  echo "  原文件已备份到：$backup"
  "${SUDO[@]}" sh -c "printf '%s\n' '$TID_LINE' >> '$SUDO_PAM'"
  echo "Done. 出问题可用备份还原：sudo cp $backup $SUDO_PAM"
else
  echo "! 找不到 ${SUDO_PAM}，跳过（系统结构异常）。" >&2
  exit 0
fi
