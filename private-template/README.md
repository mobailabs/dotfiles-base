# Private Dotfiles Template (macOS + Ubuntu/Debian + Linuxbrew)

这个目录是“私有 dotfiles 仓库”的模板设计（不包含任何敏感信息），用于配合本公共仓库工作。

目标：
- 跨平台：macOS + Ubuntu/Debian（Linuxbrew，服务器无 GUI）
- 只放私有/机器差异内容：Git 身份、SSH 配置、公司内网变量、额外软件清单等
- 通过 symlink 把私有配置安装到 `$HOME`，并与公共仓库的 overlay 机制对齐：
  - `~/.gitconfig.local`
  - `~/.zshrc.local`
  - `~/.envconfig.local`

默认行为：
- **默认覆盖**：`link-private.zsh` 会删除并替换 `$HOME` 下同名 overlay 目标（`~/.gitconfig.local` / `~/.zshrc.local` / `~/.envconfig.local`）。
- 默认会尝试执行一次 secrets 流程：`scripts/secret-helper.zsh reveal-install`（best-effort）；是否覆盖 `~/.ssh/config` 等路径取决于 `secrets/manifest.yml` 的映射以及是否成功 reveal 出对应明文文件。

---

## 推荐的私有仓库结构

建议在你的私有仓库里采用与公共仓库一致的三层结构：

```text
.
├── install.zsh
├── packages/
│   ├── common/brew-cli.private.txt
│   ├── macos/
│   │   ├── brew-cli.private.txt
│   │   └── brew-cask.private.txt
│   └── linux/brew-cli.private.txt
├── scripts/
│   ├── common/link-private.zsh
│   └── common/brew-private-install.zsh
└── src/
    ├── common/config/
    │   ├── env/envconfig.local
    │   ├── git/gitconfig.local
    │   └── zsh/zshrc.local
    ├── macos/config/
    │   └── zsh/zshrc.local
    └── linux/config/
        └── zsh/zshrc.local
```

其中：
- `src/**/config/**`：只放“私有 overlay 文件”，不要放密钥/明文 token
- `packages/**`：私有软件清单（公司工具、个人偏好），macOS 才有 cask
- `install.zsh`：调用 `brew-private-install` + `link-private`

---

## 创建私有仓库（示例）

```bash
mkdir -p ~/.dotfiles-private
cd ~/.dotfiles-private
# 从公共仓库复制模板作为起点：
#   cp -R ~/.dotfiles/private-template/. ~/.dotfiles-private/
# 然后执行：
#   zsh install.zsh
```

如需跳过 secrets 流程：

```bash
SKIP_SECRETS=1 zsh install.zsh
```

推荐把私有仓库作为独立 git 仓库托管（GitHub private / 自建 git），并确保：
- 不提交任何密钥、token、密码
- 敏感内容使用加密工具（例如 `sops`/`git-secret`/`age`）或放入密码管理器

---

## 与公共仓库如何配合

公共仓库已经会 `include` / `source` 这些 overlay：
- `~/.gitconfig.local`
- `~/.zshrc.local`
- `~/.envconfig.local`

因此私有仓库只要把对应文件链接到 `$HOME` 即可。

可选项：
- `BREW_UPDATE=0`：跳过 `brew update`（更快，但可能遇到过期索引）。

---

## Linux（Ubuntu/Debian）注意事项

- Linuxbrew 默认前缀通常是 `/home/linuxbrew/.linuxbrew`，需要写入权限（常见需要 `sudo`）。
- 建议私有仓库只在 `packages/linux/brew-cli.private.txt` 放“额外”公式，基础必装由公共仓库负责。

---

## Secrets（git-secret）

模板包含一个可选的 secrets 工作流：

- `scripts/secret-helper.zsh`：封装 `git-secret` 的常用操作（check / reveal / hide / install / reveal-install）
- `secrets/manifest.yml`：把解密后的文件名映射到安装目标路径（最小 YAML 子集：`key: "dest"`）
- `.gitignore`：默认忽略 `secrets/*` 明文文件，只允许提交 `secrets/manifest.yml` 和 `secrets/*.secret`

示例：

```bash
zsh scripts/secret-helper.zsh check
zsh scripts/secret-helper.zsh reveal-install
```

安全建议：
- 不建议把 SSH 私钥/长期 token 放进 git（即便加密）；优先使用 ssh-agent + 硬件密钥/系统钥匙串/密码管理器。
- 如果你仍选择加密存放，务必限制仓库访问、启用 2FA、并定期轮转密钥与 token。

---

## bin（自用脚本）

模板包含 `bin/` 目录，建议你把常用脚本放进去并提交到私有仓库。

默认约定：
- 私有仓库路径：`~/.dotfiles-private`
- 脚本路径：`~/.dotfiles-private/bin`

内置命令（都依赖上述固定路径）：
- `dot-install`：安装 public + private
- `dot-install-public`：只安装 public
- `dot-install-private`：只安装 private
- `dot-update`：`git pull --rebase` 两个仓库后重装
- `dot-link`：只重做 symlink
- `dot-status`：查看两个仓库状态
- `dot-secrets`：调用 `scripts/secret-helper.zsh ...`
- `dot-doctor`：环境自检（OS/brew/mise/TERM 等）

如果你的私有仓库不在默认路径，请在 `~/.zshrc.local` 设置：

```bash
export DOTFILES_PRIVATE_ROOT="$HOME/path/to/your-private-repo"
```
