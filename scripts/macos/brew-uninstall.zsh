#!/usr/bin/env zsh
#
# 卸**一个** homebrew formula 或 cask。
#
# 契约见 macview-contract.md 第 1 节（执行侧命令表）—— 建时新增一行。
#
# ## 它为什么存在
#
# 「能装不能卸」：`brew-packages-install.zsh` 能按清单装，但没有卸载入口。
# 这个脚本补上**动作**那一半（报告那一半早就有了 —— `brew-audit.zsh --json`
# 的 `extra` 就是「装了但清单里没有的」）。
#
# ## 最要紧的认识：**「多出」不等于「该卸」**
#
# macview 会在 Homebrew 页把 `extra` 列出来、每项给一个「卸载」按钮。
# 但那一列里混着三类东西，脚本和界面**都分不出来**：
#
#   1. 别的 formula 的**依赖**（brew 装 A 时顺手装的 B）
#   2. 用户**手动装、想留着**的工具
#   3. 真的不需要了的
#
# 分它们要读依赖图 + 猜用户意图 —— 那是**判断**。所以：
#
#   · **不做「一键清理多出的包」**（那正是框架 §15 禁止的
#     「UI 承诺底层没有的判断能力」）；
#   · **一次只卸一个**，名字**必须显式给** —— 用户点哪个卸哪个，
#     **点这个动作本身就是在做判断**（macview 是控制器，不是判断器）。
#
# ## 它做什么（安全壳，比「套一层 brew uninstall」多）
#
#   1. 补 homebrew 的 PATH（`brew-env.zsh`，同 brew-audit）
#   2. 参数必须**正好一个**包名；0 个或 ≥2 个 → 报错退出（**不猜**）
#   3. 名字以 `-` 开头 → 拒绝（防「把选项当包名」，如 `--force`）
#   4. （可选）`--cask`：明确指定这是 cask —— 见「formula 和 cask 的分别」
#   5. 名字不在「已装的 formula/cask」里 → 报错退出（提前说清，不等 brew 报）
#   6. `brew uninstall [--cask] <名字>` —— **不覆盖 brew 的判断**
#
# ## 它**不做**什么（都是刻意的，不是漏了）
#
#   · **不加 `--zap`** —— 那会删 app 的所有残留（危险）。
#   · **不加 `--ignore-dependencies`** —— 有别的包依赖它时，brew 会拒绝并
#     列出「谁依赖它」。那是 **brew 的判断，不是我们的** —— 脚本**原样转达**，
#     不替用户强行卸掉。
#   · **不跑 `brew autoremove`** —— 那会连带清「没人依赖的包」= 替用户判断
#     「这些也没用了」，越界。要清是用户自己在终端的事。
#
# ## formula 和 cask 的分别（2026-09-27 加 cask）
#
# 之前这一版**明确不做 cask**，理由是「cask 是 GUI app，`brew uninstall
# --cask` 可能删掉用户数据」。查清 Homebrew 文档后，这个担心要**分两半**：
#
#   · **普通 `brew uninstall --cask X`**：只跑 cask **自己声明的 `uninstall`
#     段**（多数是「删 `/Applications/X.app` + 摘符号链接」），**不碰**
#     `~/Library` 的偏好/缓存 —— 和 formula 同量级。
#   · **`brew uninstall --zap --cask X`**：额外跑 `zap` 段，那才删
#     `~/Library` 的偏好/缓存**以及共享资源**（Homebrew 文档原话：
#     「可能删掉应用之间共享的文件」）。
#
# 所以规矩是：**cask 可以卸，但只走普通 uninstall，绝不 `--zap`。**
# 要连偏好一起清，是用户自己在终端跑 `brew uninstall --zap` 的事 ——
# 那是个**判断**（哪些偏好是垃圾），macview 不做。
#
# ### `--cask` 开关：为什么明着要、不猜
#
# 同名包在 formula 和 cask 里都可能存在。**猜**（「formula 里没有就去 cask
# 找」）会把用户想卸的 formula 变成卸一个同名 cask —— 静默的错。所以：
#
#   · 不给 `--cask` → 只认 formula（**保持旧行为**，macview 的 formula
#     按钮照旧）；
#   · 给 `--cask` → 只认 cask。
#
# 界面（macview）从 `extra` 的 `kind` 字段知道该给哪个，**按钮绑死** ——
# 用户不会看到「按了 formula 结果卸了 cask」。
#
# 用法：
#   zsh scripts/macos/brew-uninstall.zsh <formula>
#   zsh scripts/macos/brew-uninstall.zsh --cask <cask>
#   DRY_RUN=1 zsh scripts/macos/brew-uninstall.zsh [--cask] <名字>   # 只看会做什么

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"

log() { echo "[uninstall] $*"; }

usage() {
  cat <<'EOF'
Usage:
  zsh scripts/macos/brew-uninstall.zsh <formula>
  zsh scripts/macos/brew-uninstall.zsh --cask <cask>

  卸载**一个** homebrew formula 或 cask。一次一个，名字必须显式给。

  --cask      卸载的是 cask（GUI app）。不给则当 formula。
              ⚠️ 只跑普通 uninstall，**绝不 --zap**（不删偏好/缓存）。

  DRY_RUN=1   只打印将要做什么，不真的卸。

契约见仓库根目录的 macview-contract.md。
EOF
}

# ── 参数 ────────────────────────────────────────────────────────────────
#
# **是否 cask** 由 `--cask` 明说，其余位置参数**正好一个**。
# 多一个、少一个都报错 —— 见文件头的「一次只卸一个」。
# 这里刻意**不**支持 `--all` / 通配 / 从清单读 —— 那些都是「批量判断」，
# 越界（框架 §15）。
KIND="formula"
POSITIONAL=()
while (( $# > 0 )); do
  case "$1" in
    --cask) KIND="cask"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "不认识的选项：$1" >&2; usage >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if (( ${#POSITIONAL[@]} == 0 )); then
  echo "必须指定一个包名。" >&2
  usage >&2
  exit 2
fi
if (( ${#POSITIONAL[@]} > 1 )); then
  echo "一次只能卸一个 —— 收到 ${#POSITIONAL[@]} 个参数。逐个来。" >&2
  usage >&2
  exit 2
fi

PKG="${POSITIONAL[1]}"

# 名字以 `-` 开头 = 像选项（`--force` / `--zap` 之类）。
# 直接拒绝：绝不让「用户想卸 `X`」变成「brew 按某个选项干别的」。
# ⚠️ 这也**堵死了 `--zap` 的旁路** —— 就算有人把 `--zap` 塞进名字，也拒。
if [[ "$PKG" == -* ]]; then
  echo "包名不能以 '-' 开头（收到 '$PKG'）—— 那看起来是个选项。" >&2
  exit 2
fi

# 名字里带 `/` = 带 tap 的全路径。卸载时 brew 只认包名本身，
# 所以这里取 basename（同 brew-packages-install / brew-audit 的规则）。
PKG_BASE="${PKG##*/}"

DRY_RUN="${DRY_RUN:-0}"

# 仓库只做 macOS（同 brew-audit / brew-packages-install）。
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[uninstall] Unsupported OS: $(uname -s)（这个仓库只做 macOS）" >&2
  exit 2
fi

# ── 找 brew ─────────────────────────────────────────────────────────────
#
# 非交互 shell 的 PATH 里可能没有 homebrew（见 brew-env.zsh 的说明）。
source "$SCRIPT_DIR/brew-env.zsh" || true
if ! command -v brew >/dev/null 2>&1; then
  echo "[uninstall] 找不到 brew，无法卸载。先装 Homebrew。" >&2
  exit 2
fi

# ── 确认它真的装着 ───────────────────────────────────────────────────────
#
# 提前判，给一句人话 —— 而不是把 brew 的原始报错直接甩给用户。
#
# ⚠️ **按 KIND 各查各的**（`--formula` vs `--cask`）—— 两个列表互不包含。
# 若指定 `--cask` 而名字其实是个 formula，也**不自动改判** —— 报错说清
# 让用户重来（见文件头「`--cask` 开关：为什么明着要、不猜」）。
if [[ "$KIND" == "cask" ]]; then
  if ! brew list --cask "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
    if brew list --formula "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
      echo "[uninstall] '$PKG_BASE' 是个 **formula**，但你指定了 --cask。" >&2
      echo "[uninstall] 去掉 --cask 重来（本脚本不猜你想卸哪个）。" >&2
      exit 1
    fi
    echo "[uninstall] '$PKG_BASE' 没装（不在已装 cask 里），不用卸。" >&2
    exit 1
  fi
else
  if ! brew list --formula "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
    if brew list --cask "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
      echo "[uninstall] '$PKG_BASE' 是个 **cask**（GUI app）。" >&2
      echo "[uninstall] 要卸它请加 --cask：zsh scripts/macos/brew-uninstall.zsh --cask $PKG_BASE" >&2
      exit 1
    fi
    echo "[uninstall] '$PKG_BASE' 没装（不在已装 formula 里），不用卸。" >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
  log "would uninstall $KIND: $PKG_BASE"
  exit 0
fi

# ── 卸 ──────────────────────────────────────────────────────────────────
#
# ⚠️ **不覆盖 brew 的判断**：不给 `--force` / `--ignore-dependencies`。
# 有别的包依赖它时，brew 会**拒绝**并列出「谁依赖它」—— 我们照实转达，
# 让用户自己决定（先卸依赖它的、或留着）。这是**brew 的判断，不是我们的**。
#
# ⚠️ **`--cask` 时也绝不加 `--zap`** —— 那才会删 `~/Library` 的偏好/缓存
# 以及共享资源（见文件头「formula 和 cask 的分别」）。
log "uninstalling $KIND: $PKG_BASE"
if [[ "$KIND" == "cask" ]]; then
  if ! brew uninstall --cask "$PKG_BASE" </dev/null; then
    echo "[uninstall] brew 拒绝了。看上面 brew 的原话决定下一步；本脚本不替你做主。" >&2
    echo "[uninstall] 说明：**没有**用 --zap —— 你的偏好/缓存都还在。" >&2
    exit 1
  fi
  log "已卸载 cask：$PKG_BASE"
  echo "[uninstall] 注意：只删了 app 本身。`~/Library` 里的偏好/数据还在 ——" >&2
  echo "[uninstall] 要连那些一起清，是你在终端跑 'brew uninstall --zap $PKG_BASE' 的事" >&2
  echo "[uninstall] （那是判断「哪些偏好是垃圾」,macview 不做）。" >&2
else
  if ! brew uninstall "$PKG_BASE" </dev/null; then
    echo "[uninstall] brew 拒绝了（可能被别的包依赖，或它自己报的别的原因）。" >&2
    echo "[uninstall] 看上面 brew 的原话决定下一步；本脚本不替你做主。" >&2
    exit 1
  fi
  log "已卸载：$PKG_BASE"
fi
