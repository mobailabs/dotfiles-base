#!/usr/bin/env zsh
#
# 卸**一个** homebrew formula。
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
#   2. 参数必须**正好一个** formula 名；0 个或 ≥2 个 → 报错退出（**不猜**）
#   3. 名字以 `-` 开头 → 拒绝（防「把选项当包名」，如 `--force`）
#   4. 名字不在「已装 formula」里 → 报错退出（提前说清，不等 brew 报）
#   5. `brew uninstall <名字>` —— **不覆盖 brew 的判断**
#
# ## 它**不做**什么（都是刻意的，不是漏了）
#
#   · **不加 `--zap`** —— 那会删 app 的所有残留（危险）。
#   · **不加 `--ignore-dependencies`** —— 有别的包依赖它时，brew 会拒绝并
#     列出「谁依赖它」。那是 **brew 的判断，不是我们的** —— 脚本**原样转达**，
#     不替用户强行卸掉。
#   · **不跑 `brew autoremove`** —— 那会连带清「没人依赖的包」= 替用户判断
#     「这些也没用了」，越界。要清是用户自己在终端的事。
#   · **不碰 cask** —— 见 §「只做 formula」。
#
# ## 只做 formula，不碰 cask
#
# cask 是 **GUI app**：`brew uninstall --cask` 可能删掉 app 的用户数据 /
# 配置。后果比 formula 重得多，而且 brew 不怎么拦。所以这一版**明确不做**
# cask 卸载 —— 要做要单独想清楚数据怎么办。
# （`brew-audit.zsh` 的 `extra` 也只算 formula，同一个理由。）
#
# 用法：
#   zsh scripts/macos/brew-uninstall.zsh <formula>
#   DRY_RUN=1 zsh scripts/macos/brew-uninstall.zsh <formula>   # 只看会做什么

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"

log() { echo "[uninstall] $*"; }

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/brew-uninstall.zsh <formula>

  卸载**一个** homebrew formula。一次一个，名字必须显式给。

  DRY_RUN=1   只打印将要做什么，不真的卸。

契约见仓库根目录的 macview-contract.md。
EOF
}

# ── 参数 ────────────────────────────────────────────────────────────────
#
# **正好一个**位置参数。多一个、少一个都报错 —— 见文件头的「一次只卸一个」。
# 这里刻意**不**支持 `--all` / 通配 / 从清单读 —— 那些都是「批量判断」，
# 越界（框架 §15）。
if (( $# == 0 )); then
  echo "必须指定一个 formula 名。" >&2
  usage >&2
  exit 2
fi
if (( $# > 1 )); then
  echo "一次只能卸一个 —— 收到 $# 个参数。逐个来。" >&2
  usage >&2
  exit 2
fi

PKG="$1"

# 名字以 `-` 开头 = 像选项（`--force` / `--cask` 之类）。
# 直接拒绝：绝不让「用户想卸 `X`」变成「brew 按某个选项干别的」。
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
# ⚠️ **只查 formula**：`brew list --formula` 不含 cask。这是**刻意的** ——
# 本脚本只做 formula（见文件头）。所以一个 cask 名会走到下面「没装」的分支 ——
# 报错里说清「只做 formula」，免得用户以为是自己拼错了。
if ! brew list --formula "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
  if brew list --cask "$PKG_BASE" >/dev/null 2>&1 </dev/null; then
    echo "[uninstall] '$PKG_BASE' 是个 **cask**（GUI app），本脚本只卸 formula。" >&2
    echo "[uninstall] cask 卸载要单独做（数据风险，见脚本头）—— 这一版不做。" >&2
    exit 1
  fi
  echo "[uninstall] '$PKG_BASE' 没装（不在已装 formula 里），不用卸。" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  log "would uninstall formula: $PKG_BASE"
  exit 0
fi

# ── 卸 ──────────────────────────────────────────────────────────────────
#
# ⚠️ **不覆盖 brew 的判断**：不给 `--force` / `--ignore-dependencies`。
# 有别的包依赖它时，brew 会**拒绝**并列出「谁依赖它」—— 我们照实转达，
# 让用户自己决定（先卸依赖它的、或留着）。这是**brew 的判断，不是我们的**。
log "uninstalling formula: $PKG_BASE"
if ! brew uninstall "$PKG_BASE" </dev/null; then
  echo "[uninstall] brew 拒绝了（可能被别的包依赖，或它自己报的别的原因）。" >&2
  echo "[uninstall] 看上面 brew 的原话决定下一步；本脚本不替你做主。" >&2
  exit 1
fi

log "已卸载：$PKG_BASE"
