#!/usr/bin/env zsh
#
# 一次性收集「脚本无法自动猜到」的信息，之后流程基本不用再交互。
#
# ## 为什么需要这个
#
# 前面的步骤已经能做到无人值守，但有三件事脚本**必须**向人要：
#
#   1. git 身份（name/email）—— 猜不出来。gitconfig 里 `useConfigOnly = true`
#      会禁用自动探测，没有它一次 commit 都提交不了。而用户名/邮箱是私密的，
#      不该进公共仓库。
#   2. Touch ID for sudo —— 要写 /etc/pam.d/sudo，需要管理员权限。
#   3. （可选）某些 cask 安装时也会弹密码。
#
# 集中在这里问一次，比装到一半突然卡住好得多 —— 这是「全自动」的关键：
# **把能前置的交互都前置**。但「之后零交互」不是保证：sudo 缓存会过期，
# 需要权限的步骤若过期会就地再问一次（会等你输入，不会卡住）。
#
# ## 非交互场景
#
# 如果 stdin 不是 tty（CI / 远程 pipe），或者传了 --yes，就完全跳过提问，
# 用以下来源按优先级取值：
#   git 身份:  --name/--email 参数 > 环境变量 > 已有的全局 git 配置
#   都取不到 → 保留现状（不建 .gitconfig.local），只提示，不阻断。
#
# 这样 `curl ... | zsh` 也能跑，只是身份需要事后补。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0:A}")/../.." && pwd)"

# ── 参数 ────────────────────────────────────────────────────────────────
# 允许 `zsh install.zsh --name X --email Y` 这种零交互用法。
GIT_NAME=""
GIT_EMAIL=""
ASSUME_YES=0

while (( $# > 0 )); do
  case "$1" in
    --name|--email)
      # 缺值要明确报错 —— 否则 `shift 2` 会打出 `shift count must be <= $#`
      # 这种内部错误，还静默继续。install.zsh 已挡一层，这里再挡一层，
      # 因为 prompt-once 也支持被单独调用。
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        echo "Option $1 requires a value." >&2
        exit 1
      fi
      case "$1" in
        --name)  GIT_NAME="$2" ;;
        --email) GIT_EMAIL="$2" ;;
      esac
      shift 2
      ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    *) shift ;;
  esac
done

# 环境变量兜底（GIT_AUTHOR_* 是 git 认的标准名）
GIT_NAME="${GIT_NAME:-${GIT_AUTHOR_NAME:-}}"
GIT_EMAIL="${GIT_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"
# 都没有就读已有的全局配置（比如老机器上已经设过）
GIT_NAME="${GIT_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"

# 有没有可交互的终端
interactive=1
[[ -t 0 ]] || interactive=0
(( ASSUME_YES )) && interactive=0

# ── 1. git 身份 ────────────────────────────────────────────────────────
setup_git_identity() {
  # 用 git 自己解析，而不是 grep 文本 —— 避免把别的段、其它键误判成身份。
  # 必须 **name 和 email 都在** 才算完整：只有 email 的话 git 一样提交不了。
  local cfg="$HOME/.gitconfig.local"
  local have_name have_email
  have_name="$(git config --file "$cfg" --get user.name  2>/dev/null || true)"
  have_email="$(git config --file "$cfg" --get user.email 2>/dev/null || true)"

  if [[ -n "$have_name" && -n "$have_email" ]]; then
    echo "  git 身份已存在（$have_name <$have_email>），跳过。"
    return 0
  fi

  # 到这里说明身份不完整（或没有）。
  #
  # 把「文件里已有的部分」先并进 GIT_NAME/GIT_EMAIL —— 否则会出现这个 bug：
  # 文件有 email、只缺 name，用户传了 --name，但 --email 为空 → 误判成
  # 「还是要 email」而放弃，明明文件里就有。已实测。
  [[ -n "$have_name" && -z "$GIT_NAME" ]] && GIT_NAME="$have_name"
  [[ -n "$have_email" && -z "$GIT_EMAIL" ]] && GIT_EMAIL="$have_email"

  if (( interactive )); then
    echo ""
    echo "git 提交身份（写进 ~/.gitconfig.local，不进仓库）"
    echo "  留空则跳过 —— 但之后一次 commit 都提交不了，需要自己补。"
    if [[ -z "$GIT_NAME" ]]; then
      printf "  名字: "
      read -r GIT_NAME || GIT_NAME=""
    fi
    if [[ -z "$GIT_EMAIL" ]]; then
      printf "  邮箱: "
      read -r GIT_EMAIL || GIT_EMAIL=""
    fi
  fi

  # 合并后仍不完整：不动文件，只提示到底缺哪一项。
  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    # ⚠️ 缺的**可能不止一项**，所以要用数组收集、全列出来。
    # 旧写法是「猜一项」：`missing="name"` 然后一个条件翻成 email ——
    # 两个都缺时只会说「缺 name」，而 email 同样没配却不提。
    # 用户看到「缺 name」补了名字再来一次，才发现还缺 email —— 多跑一趟。
    local -a missing=()
    [[ -z "$GIT_NAME" ]]  && missing+=("name")
    [[ -z "$GIT_EMAIL" ]] && missing+=("email")

    if [[ -n "$have_name" || -n "$have_email" || -n "$GIT_NAME" || -n "$GIT_EMAIL" ]]; then
      echo "  ! ~/.gitconfig.local 的身份不完整（缺 ${(j:、:)missing}），本次也没提供；保持原样。"
    else
      echo "  ! 没有 git 身份（缺 name、email）；跳过（之后可建 ~/.gitconfig.local 补上）。"
    fi
    return 0
  fi

  # 写入。用 `git config --file` 而不是手拼文本：
  # 它在已有 [user] 段里就地更新，不会把键追加到别的段后面。
  # 只动 user.name / user.email，保留你加过的 gpgsign 等设置。
  git config --file "$cfg" user.name  "$GIT_NAME"
  git config --file "$cfg" user.email "$GIT_EMAIL"
  echo "  已写入 ~/.gitconfig.local（$GIT_NAME <$GIT_EMAIL>）。"
}

# ── 2. sudo 预授权 ─────────────────────────────────────────────────────
# 一次 sudo -v 会把凭据缓存几分钟，之后同一终端里的 sudo 不必再输。
# 这能省掉大部分重复输入 —— 但**不是保证**：缓存会过期，后台 keep-alive
# 也未必刷得动。所以需要 sudo 的步骤各自就近确认（见 install.zsh）。
preauth_sudo() {
  if ! sudo -n true 2>/dev/null; then
    if (( interactive )); then
      echo ""
      echo "管理员权限（用于 Touch ID for sudo、装 Homebrew、少数 cask）"
      echo "  这里先授权一次。install.zsh 会在后台尽力保持，"
      echo "  但**不保证一直有效** —— 若后面某个步骤再问一次密码，输一下即可"
      echo "  （它一定会等你输入，不会悄悄卡住）。"
      echo "  不输直接回车 = 跳过所有需要 sudo 的步骤。"
      if sudo -v 2>/dev/null; then
        echo "  已授权。"
      else
        echo "  ! 未授权；需要 sudo 的步骤会被跳过（不影响其余）。"
      fi
    else
      echo "  非交互且未预授权 sudo；需要 sudo 的步骤会跳过。"
    fi
  else
    echo "  sudo 已预授权。"
  fi
}

# ── 3. ssh 的 Include ──────────────────────────────────────────────────
# ~/.ssh/config 是本机私密文件，不在仓库里 —— 所以链接流程碰不到它。
# 但 `Include ~/.ssh/config.local` 这一行不加，私有 ssh 配置就永远不生效，
# 且不报错。自动加上（幂等），省掉 README 里那条手动步骤。
setup_ssh_include() {
  local ssh_dir="$HOME/.ssh"
  local ssh_config="$ssh_dir/config"
  local line="Include ~/.ssh/config.local"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir" 2>/dev/null || true

  # 已经有（整行完全一致）就跳过。用 -x 全行匹配，避免把
  # `Include ~/.ssh/config.local.bak` 之类误判成已存在。
  if [[ -f "$ssh_config" ]] && grep -qxF "$line" "$ssh_config" 2>/dev/null; then
    echo "  ssh Include 已存在，跳过。"
    return 0
  fi

  # 悬空符号链接 / 不可读：直接放弃，别去动它（否则重定向会打出裸错误，
  # 而且很可能把用户原本指向别处的 config 破坏掉）。
  if [[ -L "$ssh_config" && ! -e "$ssh_config" ]]; then
    echo "  ! ~/.ssh/config 是悬空符号链接，跳过（请自行处理）。" >&2
    return 0
  fi
  if [[ -e "$ssh_config" && ! -r "$ssh_config" ]]; then
    echo "  ! ~/.ssh/config 不可读，跳过。" >&2
    return 0
  fi

  if [[ -f "$ssh_config" ]]; then
    # 插到最上面（Include 必须在其它 Host/config 之前才有效）。
    #
    # ⚠️ 这里是**可能丢配置**的操作，必须稳妥：
    #   1. 先备份原文件 —— 写失败时你的 Host 段不会没。
    #   2. 用 `cat 原文件 到临时文件` 时，若 cat 失败（悬空符号链接 / 权限）
    #      临时文件就只有一行 Include；再 mv 过去就**把原配置覆盖没了**。
    #      所以 cat 之后要校验「读到的行数 == 原文件行数」。
    #   3. 权限用 macOS 支持的 stat -f %Lp 读取后回写
    #      （`chmod --reference` 是 GNU 语法，macOS 的 chmod 不认）。
    local tmp="$ssh_config.dotsu.$$"
    local backup="$ssh_config.dotsu-backup.$(date +%Y%m%d-%H%M%S)"
    local orig_lines new_lines
    orig_lines="$(wc -l < "$ssh_config" | tr -d ' ')"

    if ! { echo "$line"; cat "$ssh_config"; } > "$tmp" 2>/dev/null; then
      echo "  ! 读取 ~/.ssh/config 失败；为安全起见不改动它。" >&2
      rm -f "$tmp"
      return 0
    fi

    new_lines="$(wc -l < "$tmp" | tr -d ' ')"
    # 新文件 = 原文件 + 1 行 Include；对不上说明没读全，放弃。
    if (( new_lines != orig_lines + 1 )); then
      echo "  ! 写入校验失败（原 $orig_lines 行，新 $new_lines 行）；为安全起见不改动。" >&2
      rm -f "$tmp"
      return 0
    fi

    # 保留原权限位（macOS 语法）。读不到就退 600 —— 对 ssh config 是安全的。
    local mode
    mode="$(stat -f '%Lp' "$ssh_config" 2>/dev/null || echo 600)"
    chmod "$mode" "$tmp" 2>/dev/null || chmod 600 "$tmp"

    cp -p "$ssh_config" "$backup" 2>/dev/null || true
    mv "$tmp" "$ssh_config"
    echo "  已把 Include 插到 ~/.ssh/config 顶部（原文件备份：${backup}）。"
  else
    printf '%s\n' "$line" > "$ssh_config"
    chmod 600 "$ssh_config"
    echo "  已创建 ~/.ssh/config 并写入 Include。"
  fi
}

# ── 主流程 ─────────────────────────────────────────────────────────────
main() {
  echo ""
  echo ">>> 一次性设置（身份 / 权限 / ssh；之后基本不再询问）"
  setup_git_identity
  preauth_sudo
  setup_ssh_include
  write_private_state
}

# ── 4. 私有源状态 ──────────────────────────────────────────────────────
# 把「私有源此刻是什么状态」写成契约文件，给 macview 读（契约见 private.md）。
#
# 为什么放在**最后**：前面三步刚改过 ~/.gitconfig.local 和 ~/.ssh/config，
# 现在写出来的才是改动后的真实状态。放在前面会写进旧状态。
#
# 为什么在这里写、而不是单独一步：这个文件的两个调用方之一是 macview，
# 它读的是「上次跑 install 时的状态」。prompt-once 是全流程唯一一次
# 已经问完、可以落地状态的地方（install.zsh 的其余步骤都是纯安装）。
write_private_state() {
  local script="$ROOT_DIR/scripts/macos/private-state.zsh"
  if [[ ! -f "$script" ]]; then
    echo "  ! 找不到 private-state.zsh，跳过私有源状态。" >&2
    return 0
  fi

  # 失败不阻断：状态文件是**辅助**信息，没有它 install 也该成功。
  # （macview 读不到就显示「还没检测过」，不是错误。）
  if zsh "$script" --write --quiet; then
    echo "  私有源状态已记录（给 macview 读；见 private.md）。"
  else
    echo "  ! 私有源状态记录失败（不影响其余步骤）。" >&2
  fi
}

main "$@"
