#!/usr/bin/env zsh
#
# 一次性设置里唯一需要人工的部分：**sudo 预授权**。
#
# 其余「脚本猜不出来」的私人信息（git 身份、ssh 加载点）**不归公开仓库管** ——
# 公开仓库只提供通用配置；个人 / 机器专属的配置由用户自己（或 macview）维护。
#
# ## 为什么预授权一次
#
# 一次 `sudo -v` 会把凭据缓存几分钟，之后同一环境里的 sudo 不必再输。
# 这能省掉大部分重复输入 —— 但**不是保证**：缓存会过期（默认 5 分钟），
# 后台 keep-alive 也未必刷得动。所以需要 sudo 的步骤各自就近确认（见 install.zsh）。
#
# ## 非交互场景
#
# stdin 不是 tty（CI / 远程 pipe），或传了 --yes：这里**不**主动拿授权 ——
# 需要 root 的步骤会自己用 `sudo_authorize` 就地弹框
# （终端提示 或 macview 原生密码框），不会静默跳过。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# 统一的 sudo 调用方式（终端 / macview 两种环境都认）。定义 SUDO / sudo_check /
# sudo_authorize —— 本文件里**不写裸 sudo**，理由见那个文件。
source "$ROOT_DIR/scripts/macos/sudo-env.zsh"

# ── 参数 ────────────────────────────────────────────────────────────────
ASSUME_YES=0
while (( $# > 0 )); do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    *) shift ;;
  esac
done

# 有没有可交互的终端
interactive=1
[[ -t 0 ]] || interactive=0
(( ASSUME_YES )) && interactive=0

# ── sudo 预授权 ────────────────────────────────────────────────────────
# 一次 `sudo -v` 会把凭据缓存几分钟，之后同一环境里的 sudo 不必再输。
# 这能省掉大部分重复输入 —— 但**不是保证**：缓存会过期（默认 5 分钟），
# 后台 keep-alive 也未必刷得动。所以需要 sudo 的步骤各自就近确认（见 install.zsh）。
#
# ⚠️ 用 `sudo-env.zsh` 的 `sudo_check` / `sudo_authorize`，**不写裸
# sudo** —— 这样在 macview 那种「无 tty + SUDO_ASKPASS」的环境里也能弹框
# 拿到授权（见那个文件的说明）。
preauth_sudo() {
  if ! sudo_check; then
    if (( interactive )); then
      echo ""
      echo "管理员权限（用于 Touch ID for sudo、装 Homebrew、少数 cask）"
      echo "  这里先授权一次。install.zsh 会在后台尽力保持，"
      echo "  但**不保证一直有效** —— 若后面某个步骤再问一次密码，输一下即可"
      echo "  （它一定会等你输入，不会悄悄卡住）。"
      echo "  不输直接回车 = 这一步没授权；需要 sudo 的步骤会就地再问一次。"
      if sudo_authorize 2>/dev/null; then
        echo "  已授权。"
      else
        echo "  ! 未授权；需要 sudo 的步骤会就地再问一次（不会静默跳过）。"
      fi
    else
      # 非交互（`--yes` / 无 tty）。这里**不**主动去拿授权 ——
      # 因为下面每一步需要 root 时都会**自己**用 `sudo_authorize`
      # （brew-bootstrap、sudo_touchid），而且那些步骤能就近判断
      # 「用户是不是真的要走这一步」。在这里预授权等于替它们决定了。
      #
      # ⚠️ 措辞不能写成「会跳过需要 sudo 的步骤」—— 那是**假的**：
      # 各步骤会就地弹框（终端提示 或 macview 的原生密码框），不会跳过。
      echo "  非交互：需要 sudo 的步骤会就地再问一次（不会跳过）。"
    fi
  else
    echo "  sudo 已预授权。"
  fi
}

# ── 主流程 ─────────────────────────────────────────────────────────────
main() {
  echo ""
  echo ">>> 一次性设置（权限；之后基本不再询问）"
  preauth_sudo
}

main "$@"
