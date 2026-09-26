#!/usr/bin/env zsh
#
# SSH 状态：回答「我的远程连接身份和配置现在是什么状态」。
# 契约见 macview-contract.md 第 2.12 节。
#
# ## 它报三样
#
# 1. **keys**  —— `~/.ssh` 下的私钥清单：名字 / 类型 / 权限 / 有没有配对公钥。
# 2. **config** —— `~/.ssh/config` 里声明的 Host，及每台的
#    HostName / User / Port / IdentityFile；外加那个加载点（`Include` 行）。
# 3. **agent** —— `ssh-add -l` 报的已加载 key 指纹。
#
# ## ⚠️ 最要紧的边界：**只报「结构」，绝不读密钥内容**
#
# 这条是安全边界，不是性能考虑。具体到三条：
#
# 1. **私钥文件的内容一个字都不读。** 只 `stat` 它的元信息（名字、权限、大小）。
#    这也是为什么**不用 `ssh-keygen -l -f <私钥>`** —— 实测那个命令会
#    **读私钥、从里面算出公钥**。我们要指纹时只从 `.pub` 上取：
#    `ssh-keygen -l -f <公钥>` 只碰公钥文件。
#    没有配对 `.pub` 的私钥 → 只报名字 + 权限，**不报指纹**（宁可少报）。
# 2. **公钥内容也不整条读。** 只从 `.pub` 第一行取**类型**（`ssh-ed25519`）和
#    指纹 —— 那两样是「这个 key 是什么」，不是秘密；公钥正文（第三字段起）
#    是长的 base64，用户不需要在这里看到，界面也不显示它。
# 3. **不碰 `known_hosts` 的内容**，只报它在不在（一个事实位）。
#
# ## 为什么列 host，且这次不违反「不碰私有仓库」
#
# `~/.ssh/config` 是**用户自己的**文件（本机是 git-secret 解密落下来的，
# 来自 private-dotfiles）。旧的 SSH 页曾决定**不列 host** —— 理由是
# 「列出来会给人错觉：这一页在管那些主机」。
#
# 那个顾虑是对的，但**不该由脚本承担** —— 脚本只报事实，界面负责措辞。
# 而且「我配了哪些主机」正是用户来 SSH 页最想知道的（契约 §2.12 的
# questions）。所以这里**只读、只列**：读 Host / HostName / User / Port /
# IdentityFile 这些**配置项**（它们不是秘密，就是配置文件里的字），
# **不验证连通性、不发网络请求、不改那个文件**。
#
# ## 为什么 agent 查不出来 ≠ 没有 key
#
# `ssh-add -l` 在没有 agent / agent 里没 key / agent 没运行时**都是非零退出码**，
# 但含义完全不同：
#   · exit 1 = agent 在，但**里面没有 key**（正常，尤其是刚开机）；
#   · exit 2 = **连不上 agent**（`SSH_AUTH_SOCK` 没设 / agent 没跑）。
# 这两种在界面上是「加载了 0 个」和「问不出 agent」两件事，不能混
# （同契约 §二「没能查 ≠ 没有」）。所以 `agent.state` 分开报。
#
# ## 为什么不报「这台 key 连得上 GitHub 吗」
#
# 那要发网络请求（`ssh -T git@github.com`）。本仓库所有 `*-status.zsh` 都是
# **只读本地文本、不发网络**（契约 §2.1 的精神）。所以不做。
#
# 用法：
#   zsh scripts/macos/ssh-status.zsh --json

set -uo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME is not set." >&2
  exit 1
fi

# 契约版本。改动**不兼容**的格式时才 +1（加字段不算）。
CONTRACT_VERSION=1

# ── 参数 ────────────────────────────────────────────────────────────────
MODE=""

usage() {
  cat <<'EOF'
Usage: zsh scripts/macos/ssh-status.zsh --json

  --json    把 SSH 状态打到 stdout（只读，不碰密钥内容、不发网络）

契约见仓库根目录的 macview-contract.md。
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --json) MODE="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "必须指定 --json。" >&2
  usage >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ssh-status 只支持 macOS（当前 $(uname -s)）" >&2
  exit 2
fi

# ── JSON 工具（照抄 git-identity.zsh，理由见那里）──────────────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_str_or_null() {
  if [[ -z "${1:-}" ]]; then printf 'null'; else printf '"%s"' "$(json_escape "$1")"; fi
}

SSH_DIR="$HOME/.ssh"

# ── 权限：八进制字符串（如 "600"）────────────────────────────────────────
#
# ⚠️ **不读文件内容** —— 只 `stat` 元信息。
# macOS 的 `stat -f '%Lp'` 给八进制权限（Linux 是 `-c '%a'`）。
file_mode() {
  local f="$1"
  [[ -e "$f" ]] || return 1
  local m
  m="$(stat -f '%Lp' "$f" 2>/dev/null)" || return 1
  # 补齐到 3 位：`000` 权限的 stat 输出是 `0`，显示成 `0` 会让人以为是解析坏了。
  printf '%03d' "$m" 2>/dev/null || printf '%s' "$m"
}

# ── keys ────────────────────────────────────────────────────────────────
#
# 私钥的判据：文件名以 `id_` 开头，**且不含 `.pub`**，且不是 `known_hosts*`。
# 为什么用「id_ 开头」而不是「看内容判断是不是私钥」：**看内容就破了
# 不读私钥的纪律**。约定俗成的私钥名就是 `id_<type>`（ssh-keygen 默认），
# 用名字识别是**这个边界下唯一不越线的办法**。代价：用户自己改名的私钥
# （如 `github_key`）不会被列出来 —— 这个代价明说在这里，不藏。
#
# 产物：每行 `name|type|mode|has_pub|fingerprint`（字段缺失留空）。
probe_keys() {
  [[ -d "$SSH_DIR" ]] || return 0

  # ⚠️ 所有 `local` 声明在循环外一次做完 —— zsh 的坑：在**会跑两遍以上的
  # 循环里**写 `local x`，而 `x` 已经有值时，zsh 会把 `x=值` **打印到
  # stdout**，直接污染 JSON。（同样的坑在 alias-status.zsh 里记过。）
  local f name pub typ mode has_pub fp line

  # nullglob：没有匹配时不报错、给空（zsh 默认会原样保留 pattern）。
  setopt local_options nullglob
  for f in "$SSH_DIR"/id_*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.pub ]] && continue

    name="${f:t}"
    pub="${f}.pub"
    mode="$(file_mode "$f" || true)"

    if [[ -f "$pub" ]]; then
      has_pub=1
      # 类型 + 指纹**只从 .pub 取** —— 绝不碰私钥内容。
      # `ssh-keygen -l -f <公钥>` 输出形如：
      #   256 SHA256:xxxx comment (ED25519)
      # 末字段括号里就是类型；`-l` 只读公钥文件。
      line="$(ssh-keygen -l -f "$pub" 2>/dev/null || true)"
      if [[ -n "$line" ]]; then
        # 类型：括号里那个词，转小写后拼成 ssh-<type>（对得上 .pub 第一字段）。
        typ="$(
          printf '%s' "$line" | sed -n 's/.*(\(.*\))$/\1/p' | tr '[:upper:]' '[:lower:]'
        )"
        [[ -n "$typ" ]] && typ="ssh-${typ}"
        # 指纹：第二个字段（`SHA256:…`）。
        fp="$(printf '%s' "$line" | awk '{print $2}')"
      fi
    else
      has_pub=0
      typ=""
      fp=""
    fi

    printf '%s|%s|%s|%s|%s\n' "$name" "$typ" "$mode" "$has_pub" "$fp"
  done
}

# ── config ──────────────────────────────────────────────────────────────
#
# 解析 `~/.ssh/config`。**只读 Host 及其配置项，不验证连通性。**
#
# ssh config 的语法：一个 `Host <pattern…>` 起一个块，块内是其配置项
# （`HostName` / `User` / `Port` / `IdentityFile`…），直到下一个 `Host`。
# 关键字**大小写不敏感**（ssh 自己就是），所以下面用小写比较。
#
# ⚠️ **只取顶层 Host** —— 和 private-state.zsh 的 `probe_ssh_hosts` 一致：
# 含 `*` / `?` 通配的 pattern **跳过**（`Host *` 是「所有主机的默认值」，
# 不是一台具体主机；把它当主机列出来会误导）。
#
# 产物：每行 `name|hostname|user|port|identityfile`。
probe_config_hosts() {
  local cfg="$SSH_DIR/config"
  [[ -f "$cfg" ]] || return 0

  # ⚠️ locals 全在循环外（见 probe_keys 的说明）。
  local raw stripped; local -a parts=()
  local cur_name="" cur_hostname="" cur_user="" cur_port="" cur_identity=""
  local kw val h

  emit_current() {
    [[ -n "$cur_name" ]] || return 0
    printf '%s|%s|%s|%s|%s\n' \
      "$cur_name" "$cur_hostname" "$cur_user" "$cur_port" "$cur_identity"
  }

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    # 去注释（`#` 之后）——但要保留行首注释的判空。
    stripped="${raw%%#*}"
    # ssh config 的分隔符是空白或 `=`（`HostName=foo` 也合法）。
    stripped="${stripped//=/ }"
    parts=(${=stripped})
    (( ${#parts[@]} >= 2 )) || continue

    kw="${parts[1]:l}"   # 关键字转小写
    val="${parts[2]}"

    case "$kw" in
      host)
        # 先把上一个块吐出去，再起新块。
        emit_current
        cur_name=""
        cur_hostname=""
        cur_user=""
        cur_port=""
        cur_identity=""
        # 一个 Host 行可能有多个 pattern（`Host a b c`）——
        # 通配跳过，取第一个非通配的当代表（够用：界面只列「配了哪些主机」）。
        for h in "${parts[@]:1}"; do
          [[ "$h" == *"*"* || "$h" == *"?"* ]] && continue
          cur_name="$h"
          break
        done
        ;;
      hostname) [[ -n "$cur_name" ]] && cur_hostname="$val" ;;
      user) [[ -n "$cur_name" ]] && cur_user="$val" ;;
      port) [[ -n "$cur_name" ]] && cur_port="$val" ;;
      identityfile)
        # 可能多行（多个 IdentityFile）—— 用逗号连起来，界面拆开显示。
        [[ -n "$cur_name" ]] || continue
        if [[ -n "$cur_identity" ]]; then
          cur_identity="${cur_identity},${val}"
        else
          cur_identity="$val"
        fi
        ;;
    esac
  done < "$cfg"

  # 最后一个块。
  emit_current
}

# ── 加载点：`~/.ssh/config` 里有没有 `Include` ─────────────────────────
#
# 这就是旧的 SSH 页唯一能查的那件事（旧 `SSHPage.swift` 的注释写死了）：
# 私有 overlay 要生效，宿主文件里得有 `Include config.local` 那一行。
#
# 产出：`has_config|has_include|include_targets`（targets 逗号分隔）。
probe_load_point() {
  local cfg="$SSH_DIR/config"
  local has_config=0 has_include=0
  local -a targets=()

  if [[ -f "$cfg" ]]; then
    has_config=1
    local raw stripped; local -a parts=()
    local p
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      stripped="${raw%%#*}"
      stripped="${stripped//=/ }"
      parts=(${=stripped})
      (( ${#parts[@]} >= 2 )) || continue
      if [[ "${parts[1]:l}" == "include" ]]; then
        has_include=1
        # Include 可以跟多个路径。
        for p in "${parts[@]:1}"; do
          targets+=("$p")
        done
      fi
    done < "$cfg"
  fi

  local joined=""
  if (( ${#targets[@]} > 0 )); then
    joined="${(j:,:)targets}"
  fi
  printf '%s|%s|%s\n' "$has_config" "$has_include" "$joined"
}

# ── agent ───────────────────────────────────────────────────────────────
#
# `ssh-add -l`：agent 里加载了哪些 key。
#   · exit 0 = 有 key（输出每行一把，含指纹）；
#   · exit 1 = agent 在、但**里面是空的**；
#   · exit 2 = **连不上 agent**（没跑 / SSH_AUTH_SOCK 没设）。
# 三种各自的含义不同，所以 `state` 分开报（见文件头）。
#
# 产物：`state|key1,key2,…`，state ∈ running|empty|unreachable|unknown。
probe_agent() {
  local out rc
  out="$(ssh-add -l 2>&1)"
  rc=$?

  case "$rc" in
    0)
      # 每行形如 `256 SHA256:xxx comment (ED25519)` —— 取指纹（第二字段）。
      local fp
      local -a fps=()
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        fp="$(printf '%s' "$line" | awk '{print $2}')"
        [[ -n "$fp" ]] && fps+=("$fp")
      done <<<"$out"
      printf 'running|%s\n' "${(j:,:)fps}"
      ;;
    1)
      printf 'empty|\n'
      ;;
    2)
      printf 'unreachable|\n'
      ;;
    *)
      printf 'unknown|\n'
      ;;
  esac
}

render_json() {
  local now
  now="$(date +%s)"

  local keys_out hosts_out lp_out agent_out
  keys_out="$(probe_keys)"
  hosts_out="$(probe_config_hosts)"
  lp_out="$(probe_load_point)"
  agent_out="$(probe_agent)"

  # 加载点那行：has_config|has_include|targets
  local lp_has_config lp_has_include lp_targets
  lp_has_config="${lp_out%%|*}"
  lp_out="${lp_out#*|}"
  lp_has_include="${lp_out%%|*}"
  lp_targets="${lp_out#*|}"

  # agent 那行：state|fps
  local ag_state ag_fps
  ag_state="${agent_out%%|*}"
  ag_fps="${agent_out#*|}"

  # ⚠️ locals 声明在循环外（见 probe_keys 的说明）。
  local line f_name f_type f_mode f_haspub f_fp
  local h_name h_host h_user h_port h_idf

  local out=""
  out+="{"$'\n'
  out+="  \"version\": $CONTRACT_VERSION,"$'\n'
  out+="  \"checked_at\": $now,"$'\n'
  out+="  \"generated_by\": \"ssh-status.zsh\","$'\n'

  # ── keys ──
  out+="  \"keys\": ["
  if [[ -z "$keys_out" ]]; then
    out+="],"$'\n'
  else
    out+=$'\n'
    local first=1
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      # name|type|mode|has_pub|fingerprint
      f_name="${line%%|*}"; line="${line#*|}"
      f_type="${line%%|*}"; line="${line#*|}"
      f_mode="${line%%|*}"; line="${line#*|}"
      f_haspub="${line%%|*}"
      f_fp="${line#*|}"
      (( first )) || out+=","$'\n'
      first=0
      out+="    {"
      out+=" \"name\": \"$(json_escape "$f_name")\","
      out+=" \"type\": $(json_str_or_null "$f_type"),"
      out+=" \"mode\": $(json_str_or_null "$f_mode"),"
      out+=" \"has_public\": $( [[ "$f_haspub" == "1" ]] && printf 'true' || printf 'false' ),"
      out+=" \"fingerprint\": $(json_str_or_null "$f_fp") }"
    done <<<"$keys_out"
    out+=$'\n'"  ],"$'\n'
  fi

  # ── config.hosts ──
  out+="  \"hosts\": ["
  if [[ -z "$hosts_out" ]]; then
    out+="],"$'\n'
  else
    out+=$'\n'
    local first=1
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      # name|hostname|user|port|identityfile
      h_name="${line%%|*}"; line="${line#*|}"
      h_host="${line%%|*}"; line="${line#*|}"
      h_user="${line%%|*}"; line="${line#*|}"
      h_port="${line%%|*}"
      h_idf="${line#*|}"
      (( first )) || out+=","$'\n'
      first=0
      out+="    {"
      out+=" \"name\": \"$(json_escape "$h_name")\","
      out+=" \"hostname\": $(json_str_or_null "$h_host"),"
      out+=" \"user\": $(json_str_or_null "$h_user"),"
      out+=" \"port\": $(json_str_or_null "$h_port"),"
      out+=" \"identity_file\": $(json_str_or_null "$h_idf") }"
    done <<<"$hosts_out"
    out+=$'\n'"  ],"$'\n'
  fi

  # ── config.load_point ──
  out+="  \"load_point\": {"$'\n'
  out+="    \"has_config\": $( [[ "$lp_has_config" == "1" ]] && printf 'true' || printf 'false' ),"$'\n'
  out+="    \"has_include\": $( [[ "$lp_has_include" == "1" ]] && printf 'true' || printf 'false' ),"$'\n'
  out+="    \"include_targets\": ["
  if [[ -z "$lp_targets" ]]; then
    out+="]"$'\n'
  else
    out+=$'\n'
    local first=1 t
    local -a tparts=()
    IFS=',' read -r -A tparts <<<"$lp_targets"
    for t in "${tparts[@]}"; do
      [[ -n "$t" ]] || continue
      (( first )) || out+=","$'\n'
      first=0
      out+="      \"$(json_escape "$t")\""
    done
    out+=$'\n'"    ]"$'\n'
  fi
  out+="  },"$'\n'

  # ── agent ──
  out+="  \"agent\": {"$'\n'
  out+="    \"state\": \"$(json_escape "$ag_state")\","$'\n'
  out+="    \"loaded_fingerprints\": ["
  if [[ -z "$ag_fps" ]]; then
    out+="]"$'\n'
  else
    out+=$'\n'
    local first=1 fp
    local -a fparts=()
    IFS=',' read -r -A fparts <<<"$ag_fps"
    for fp in "${fparts[@]}"; do
      [[ -n "$fp" ]] || continue
      (( first )) || out+=","$'\n'
      first=0
      out+="      \"$(json_escape "$fp")\""
    done
    out+=$'\n'"    ]"$'\n'
  fi
  out+="  },"$'\n'

  # ── counts ──
  local n_keys=0 n_hosts=0
  if [[ -n "$keys_out" ]]; then
    n_keys="$(printf '%s\n' "$keys_out" | grep -c . || true)"
  fi
  if [[ -n "$hosts_out" ]]; then
    n_hosts="$(printf '%s\n' "$hosts_out" | grep -c . || true)"
  fi
  out+="  \"counts\": { \"keys\": $n_keys, \"hosts\": $n_hosts }"$'\n'

  out+="}"$'\n'
  printf '%s' "$out"
}

main() {
  local json
  json="$(render_json)" || return 1

  # 自己先验一遍合法性 —— 产出的不是合法 JSON 是 bug，要在**发出前**发现
  # （照 git-identity.zsh）。
  if command -v python3 >/dev/null 2>&1; then
    if ! printf '%s' "$json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      echo "内部错误：产出的 JSON 不合法（这是个 bug，请报告）。" >&2
      return 1
    fi
  fi

  printf '%s\n' "$json"
  return 0
}

main "$@"
