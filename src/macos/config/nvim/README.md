# Neovim / AstroNvim

基于 [AstroNvim](https://github.com/AstroNvim/AstroNvim) v5 的配置，链接到
`~/.config/nvim`。**不要**按 AstroNvim 官方模板 README 那样「从模板新建仓库」——
这就是本仓库的配置，直接改这里。

## 怎么用

`install.zsh` 会把这个目录链接到 `~/.config/nvim`。首次启动 `nvim` 时，
[lazy.nvim](https://github.com/folke/lazy.nvim) 会自动克隆它自己与所有插件。

手动操作：

- `:Lazy` —— 插件面板（同步 / 更新 / 查看状态）
- `:Lazy sync` —— 按 `lazy-lock.json` 安装并锁定版本
- `:Mason` —— 语言服务器 / 格式化器 / 调试器面板
- `:checkhealth` —— 排查环境问题

## 这个配置装了什么

| 文件 | 作用 |
|---|---|
| `lua/lazy_setup.lua` | lazy.nvim 引导 + AstroNvim 选项（leader 为空格） |
| `lua/community.lua` | astrocommunity 语言包与功能包（见下） |
| `lua/plugins/astrocore.lua` | vim 选项、mappings、autocmds |
| `lua/plugins/astroui.lua` | 主题（`catppuccin`）、图标 |
| `lua/plugins/astrolsp.lua` | LSP：codelens、格式保存、按键 |
| `lua/plugins/mason.lua` | 自动装 lua-language-server / stylua / debugpy / tree-sitter-cli |
| `lua/plugins/none-ls.lua` | 额外格式化 / 诊断源（当前为空，按需加） |
| `lua/plugins/treesitter.lua` | 语法高亮（已装 lua / vim 解析器） |
| `lua/plugins/user.lua` | 你自己的插件定制（当前空骨架） |
| `lazy-lock.json` | 插件版本锁 —— 保证换机器装出同一套 |

**语言支持**（由 `community.lua` 的 astrocommunity pack 提供）：
Lua、Rust、Python、Go、TypeScript（all-in-one）。

**其它**：catppuccin 主题（在 `community.lua` 导入，`astroui.lua` 的
`colorscheme` 指的就是它）、Copilot、opencode.nvim、
img-clip、dropbar、hop。

## 加东西改哪里

- 加插件 / 改插件选项 → `lua/plugins/user.lua`（或按主题新建 `lua/plugins/<名字>.lua`）
- 加语言支持 → `lua/community.lua` 里加 `{ import = "astrocommunity.pack.xxx" }`
- 加语言服务器 / 格式化器 → `lua/plugins/mason.lua` 的 `ensure_installed`
- 改按键 / vim 选项 → `lua/plugins/astrocore.lua`

改完插件版本会写进 `lazy-lock.json`，**记得提交它** —— 否则换机器装到的版本会漂移。

## 排错

```sh
nvim --headless "+Lazy! sync" +qa     # 命令行同步插件
nvim +checkhealth                     # 健康检查
rm -rf ~/.local/share/nvim/lazy       # 插件装坏了就删掉重来（会重新克隆）
```
