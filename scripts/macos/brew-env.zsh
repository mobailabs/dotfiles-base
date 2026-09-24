#!/usr/bin/env zsh
#
# 把 Homebrew 环境拉进**当前**进程。被 `source`，不是被执行。
#
# ## 为什么需要它
#
# `install.zsh` 是非交互 shell，PATH 是 launchd 的最小值
# （`/usr/bin:/bin:/usr/sbin:/sbin`）。它用**子进程**方式调用每一步，
# 而子进程里 `eval "$(brew shellenv)"` 设的 PATH **不会回传**给父进程。
#
# 结果：brew-install 明明成功了，但后面的 mise-setup / tmux-plugins
# 在父进程的 PATH 里看不到 homebrew 装的东西 ——
#   - mise-setup    → `command -v mise` 失败 → exit 1 → set -e 中止整个流程
#   - tmux-plugins  → `command -v tmux` 失败 → 静默 skip（TPM 永远装不上）
#
# 所以在 brew-install 之后、依赖 brew 安装物的步骤之前，
# 用本文件把 brew 环境补进当前进程。
#
# ## 用法
#
#     source "$ROOT_DIR/scripts/macos/brew-env.zsh"
#
# `set -u` 下也安全；找不到 brew 就静默返回非零（调用方自己决定怎么办）。

# 已经能用了就补齐并返回。
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
  return 0
fi

# 按实际安装路径找（Apple Silicon / Intel）。
for _brew_env_prefix in /opt/homebrew /usr/local; do
  if [[ -x "$_brew_env_prefix/bin/brew" ]]; then
    eval "$("$_brew_env_prefix/bin/brew" shellenv)"
    unset _brew_env_prefix
    return 0
  fi
done
unset _brew_env_prefix

# brew 之外再兜底 mise 的常见落点（官方安装器不走 brew）。
[[ -d "$HOME/.local/bin" ]] && path+=("$HOME/.local/bin")
[[ -d "$HOME/.local/share/mise/shims" ]] && path+=("$HOME/.local/share/mise/shims")
export PATH 2>/dev/null || true

return 1
