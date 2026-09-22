#!/usr/bin/env zsh
#
# 对账：packages/*.txt 里声明的包，这台机器实际装了没有。
#
# 存在的理由和 macview 一样 —— 「清单说该有、这台没有」是最常见的静默失效。
# macview 是图形版（它自己读同样的文件），这里是命令行版。
#
# ## 输出分三类
#
#   - 缺失：声明了、这台没装        → 该跑 install.zsh
#   - 多出：这台有、清单里没有      → 要不要「采纳」进清单，你决定
#   - 重复：清单内部或跨清单出现两次 → 清理，否则 macview 的计数会和逐清单相加对不上
#
# ## 和 macview 的一致性
#
# 解析规则完全照抄 macview 的 parsePackageList：
#   `#` 之后是注释 / 取第一个空白字段 / 取 basename 去比。
# 两边任何一处改了规则，这里必须同步 —— 否则同一个仓库会给出两个答案。
#
# 用法：
#   zsh scripts/common/brew-audit.zsh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 这个仓库只做 macOS。不假装能跑别的平台 —— 和 check.zsh 的态度一致。
os_id() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "brew-audit 只支持 macOS（当前 $(uname -s)）" >&2
    exit 2
  fi
  echo "macos"
}

# 与 macview parsePackageList 同规则：去注释、取第一个**非空**字段。
#
# ⚠️ 不能写成 `${pkg%%[[:space:]]*}` —— 那会让前导空白的行（`  zsh`）
# 得到空串而漏掉。Swift 的 `split(whereSeparator:)` 会丢弃空子串，
# 所以它认得 `  zsh` 里的 `zsh`。这里先 ltrim 再取第一段，行为才一致。
read_declared() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line pkg
  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"   # 去掉前导空白
    pkg="${pkg%%[[:space:]]*}"              # 取第一个字段
    [[ -n "$pkg" ]] || continue
    echo "$pkg"
  done <"$file"
}

# 去重后取最后一段（`daipeihust/tap/im-select` → `im-select`）。
# 串到流水线里用；命名保留 basename 的说法，和 macview 的 basename() 对应。
basename_of() { echo "${1##*/}"; }

main() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found; 无法对账。先装 Homebrew。" >&2
    exit 2
  fi

  local os
  os="$(os_id)"

  # label|kind|path —— 与 macview 的 packageListFiles 对应。
  #
  # ⚠️ 只覆盖**公共仓库**的 3 份。macview 还会读私有仓库的
  # `packages/*.private.txt`（它知道私有仓库在哪，本脚本不知道）。
  # 所以两边在「私有仓库已克隆」时结果会不同 —— 这是已知差异，不是 bug。
  local specs=(
    "公共 / 通用 formulae|formula|$ROOT_DIR/packages/common/brew-cli.txt"
    "公共 / macos formulae|formula|$ROOT_DIR/packages/macos/brew-cli.txt"
    "公共 / macos casks|cask|$ROOT_DIR/packages/macos/brew-cask.txt"
  )

  local installed_formulae installed_casks
  installed_formulae="$(brew list --formula 2>/dev/null | sort -u)"
  installed_casks="$(brew list --cask 2>/dev/null | sort -u)"

  # 所有 local 在**循环外声明一次**。
  #
  # ⚠️ 不要在会多次执行的循环体里写 `local x` —— zsh 在重新声明一个
  # 已存在的变量时会把它打印到 stdout（`name=pkgB`），污染审计输出。
  # 这是本文件踩过的真坑，不是理论风险。
  local -a declared_all=() missing=() duplicated=() extras=() names=() seen=()
  local spec label kind path name installed_set inst dup_key

  for spec in "${specs[@]}"; do
    label="${spec%%|*}"
    kind="${${spec#*|}%%|*}"
    path="${spec##*|}"

    names=()
    seen=()
    [[ -f "$path" ]] || continue
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      names+=("$(basename_of "$name")")
    done < <(read_declared "$path")

    # 清单内重复。
    # 与 macview 的 duplicates() 一致：同一个重复名**只报一次**
    # （`!dups.contains(n)`）。逐次出现地报会和 macview 的计数对不上。
    for name in "${names[@]}"; do
      if (( ${seen[(I)$name]} )); then
        dup_key="$label: $name"
        (( ${duplicated[(I)$dup_key]} )) || duplicated+=("$dup_key")
      else
        seen+=("$name")
      fi
    done

    if [[ "$kind" == "cask" ]]; then
      installed_set="$installed_casks"
    else
      installed_set="$installed_formulae"
    fi

    for name in "${names[@]}"; do
      if (( ${${(f)installed_set}[(I)$name]} )); then
        : # 已装
      else
        missing+=("$label: $name")
      fi
      declared_all+=("$name")
    done
  done

  echo "== 清单里声明、但没装 =="
  if (( ${#missing[@]} == 0 )); then
    echo "  （无）"
  else
    printf '  %s\n' "${missing[@]}"
  fi

  echo
  echo "== 清单内部/跨清单重复 =="
  if (( ${#duplicated[@]} == 0 )); then
    echo "  （无）"
  else
    printf '  %s\n' "${duplicated[@]}"
  fi

  # 「多出」：这台装了、清单里没有。只对 formula 做（cask 太多系统自带/手动装的）。
  echo
  echo "== 这台装了、清单里没有（formula，仅供参考，不一定要加）=="
  while IFS= read -r inst; do
    [[ -n "$inst" ]] || continue
    if (( ! ${declared_all[(I)$inst]} )); then
      extras+=("$inst")
    fi
  done <<<"$installed_formulae"
  if (( ${#extras[@]} == 0 )); then
    echo "  （无）"
  else
    printf '  %s\n' "${extras[@]}"
  fi

  echo
  if (( ${#missing[@]} > 0 )); then
    echo "有 ${#missing[@]} 个包缺失 → zsh install.zsh"
    exit 1
  fi
  echo "对齐。"
}

main "$@"
