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

os_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    *) echo "macos" ;;
  esac
}

# 与 macview parsePackageList 同规则：去注释、取第一字段。
read_declared() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line pkg
  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg%%[[:space:]]*}"
    [[ -n "$pkg" ]] || continue
    echo "$pkg"
  done <"$file"
}

# 与 macview basename() 同规则：取最后一段。
basename_of() { echo "${1##*/}"; }

main() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found; 无法对账。先装 Homebrew。" >&2
    exit 2
  fi

  local os
  os="$(os_id)"

  # label|kind|path  —— 与 macview 的 packageListFiles 一一对应
  local specs=(
    "公共 / 通用 formulae|formula|$ROOT_DIR/packages/common/brew-cli.txt"
    "公共 / $os formulae|formula|$ROOT_DIR/packages/$os/brew-cli.txt"
    "公共 / macos casks|cask|$ROOT_DIR/packages/macos/brew-cask.txt"
  )

  local installed_formulae installed_casks
  installed_formulae="$(brew list --formula 2>/dev/null | sort -u)"
  installed_casks="$(brew list --cask 2>/dev/null | sort -u)"

  local declared_all=() missing=() duplicated=()
  local spec label kind path
  for spec in "${specs[@]}"; do
    label="${spec%%|*}"
    kind="${${spec#*|}%%|*}"
    path="${spec##*|}"

    local names=()
    [[ -f "$path" ]] || continue
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      names+=("$n")
    done < <(read_declared "$path" | sed 's|.*/||')

    # 清单内重复
    local seen=() n
    for n in "${names[@]}"; do
      if (( ${seen[(I)$n]} )); then
        duplicated+=("$label: $n")
      else
        seen+=("$n")
      fi
    done

    local installed_set
    if [[ "$kind" == "cask" ]]; then
      installed_set="$installed_casks"
    else
      installed_set="$installed_formulae"
    fi

    for n in "${names[@]}"; do
      if (( ${${(f)installed_set}[(I)$n]} )); then
        : # 已装
      else
        missing+=("$label: $n")
      fi
      declared_all+=("$n")
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
  local extras=() inst
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
