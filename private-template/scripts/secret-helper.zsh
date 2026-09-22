#!/usr/bin/env zsh
# Private secrets helper for dotfiles-private template.
#
# - Uses git-secret to decrypt secrets into ./secrets/
# - Optionally installs decrypted files to target locations using secrets/manifest.yml
#
# Manifest format (very small subset of YAML):
#   # comments allowed
#   filename: "~/.ssh/config"
#   tokens.env: "~/.config/private/tokens.env"
#
# Where "filename" refers to the decrypted file located at:
#   <repo>/secrets/<filename>
#
# Security notes:
# - Do NOT store SSH private keys in git, even encrypted. Prefer Keychain/1Password/YubiKey.
# - This script sets restrictive permissions (0600) on installed files; also sets ~/.ssh to 0700.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$ROOT_DIR/secrets"
MANIFEST_FILE="$SECRETS_DIR/manifest.yml"

# Enable verbose logs by running with: SECRET_HELPER_DEBUG=1 zsh scripts/secret-helper.zsh install
SECRET_HELPER_DEBUG="${SECRET_HELPER_DEBUG:-0}"

log_debug() {
  [[ "$SECRET_HELPER_DEBUG" == "1" ]] || return 0
  echo "[debug] $*" >&2
}

log_info_when_debug() {
  [[ "$SECRET_HELPER_DEBUG" == "1" ]] || return 0
  echo "[info] $*" >&2
}

print_usage() {
  cat <<'EOF'
Usage: zsh scripts/secret-helper.zsh <command> [args]

Commands:
  check
      Check required commands and basic GPG state.

  reveal
      Run `git secret reveal -f` inside the repository.

  install
      Install decrypted files according to secrets/manifest.yml.

  reveal-install
      Reveal secrets, then install them according to manifest.

  add <path> [dest]
      Convenience helper:
        - Copies <path> into secrets/ as a plaintext file (basename by default, or use [dest])
        - Runs `git secret add` for the corresponding plaintext file
      Note: you still need to run `hide` to encrypt.

  hide
      Run `git secret hide -f` inside the repository.

Notes:
- This script expects to be run from within the dotfiles-private repository.
- The manifest parser is intentionally minimal; keep manifest lines in "key: value" form.
- Targets support "~" expansion and environment variables like "$HOME".

Examples:
  zsh scripts/secret-helper.zsh check
  zsh scripts/secret-helper.zsh reveal
  zsh scripts/secret-helper.zsh install
  zsh scripts/secret-helper.zsh reveal-install

EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  local c="$1"
  have_cmd "$c" || die "Missing required command: $c"
}

ensure_repo() {
  [[ -d "$ROOT_DIR/.git" ]] || die "Not a git repository: $ROOT_DIR"
}

expand_path() {
  # Expand ~ and env vars. Keep it simple with eval; inputs are controlled by you (private repo).
  local p="$1"
  # shellcheck disable=SC2296,SC2086
  eval "echo $p"
}

chmod_safely() {
  local mode="$1"
  local path="$2"
  chmod "$mode" "$path" 2>/dev/null || true
}

looks_like_shell_script() {
  local path="$1"

  log_debug "looks_like_shell_script: ENTER path=$path"

  [[ -f "$path" ]] || {
    log_debug "looks_like_shell_script: file not found, returning 1"
    return 1
  }

  # Simple rule: executable iff the first two chars are "#!"
  # (covers sh/bash/zsh/expect/python/ruby/node/etc.)
  # Note: use /bin/dd with absolute path to avoid PATH issues in subshells
  local head
  head="$(LC_ALL=C /bin/dd if="$path" bs=1 count=2 2>/dev/null || true)"

  log_debug "looks_like_shell_script: path=$path head2='${head}' (hex: $(printf '%s' "$head" | xxd -p 2>/dev/null || true))"

  if [[ "$head" == "#!" ]]; then
    log_debug "looks_like_shell_script: MATCH! returning 0 (is script)"
    return 0
  else
    log_debug "looks_like_shell_script: NO MATCH, returning 1 (not script)"
    return 1
  fi
}

ensure_dir_mode() {
  local dir="$1"
  local mode="$2"
  if [[ -d "$dir" ]]; then
    chmod_safely "$mode" "$dir"
  fi
}

cmd_check() {
  ensure_repo
  require_cmd git

  if ! have_cmd git-secret; then
    echo "git-secret: NOT FOUND (install it via brew: git-secret)"
  else
    echo "git-secret: $(command -v git-secret)"
  fi

  if ! have_cmd gpg; then
    echo "gpg: NOT FOUND (install it via brew: gnupg)"
  else
    echo "gpg: $(command -v gpg)"
    if gpg --list-secret-keys >/dev/null 2>&1; then
      echo "gpg: secret keys present"
    else
      echo "gpg: no secret keys found (you may need to import your private key)"
    fi
  fi

  if [[ -f "$MANIFEST_FILE" ]]; then
    echo "manifest: $MANIFEST_FILE"
  else
    echo "manifest: NOT FOUND (optional) - $MANIFEST_FILE"
  fi
}

cmd_reveal() {
  ensure_repo
  require_cmd git
  require_cmd git-secret

  (cd "$ROOT_DIR" && git secret reveal -f)
  echo "Revealed secrets into: $SECRETS_DIR"
}

cmd_hide() {
  ensure_repo
  require_cmd git
  require_cmd git-secret

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    die "manifest.yml not found: $MANIFEST_FILE"
  fi

  echo "Reading files to encrypt from: $MANIFEST_FILE"

  # Read manifest line by line, extract key (filename before colon)
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Extract key before colon (e.g., "config: ~/.ssh/config" → "config")
    if [[ "$line" == *:* ]]; then
      key="${line%%:*}"
      key="$(trim "$key")"
      key="${key//[[:space:]]/}"  # remove spaces
      [[ -n "$key" ]] || continue

      # Check if file exists in secrets/ (as plaintext)
      src_file="$SECRETS_DIR/$key"
      if [[ -f "$src_file" ]]; then
        echo "✅ Adding to git-secret: $key"
        (cd "$ROOT_DIR" && git secret add "secrets/$key") || die "Failed to add $key"
      else
        echo "⚠️  Skipping (file not found): $src_file"
      fi
    fi
  done < "$MANIFEST_FILE"

  # Now hide all added files
  echo "🔒 Encrypting all tracked files..."
  (cd "$ROOT_DIR" && git secret hide) || die "Failed to encrypt secrets"

  echo "🎉 Encrypted secrets tracked by git-secret."
}


trim() {
  local s="$1"
  # Trim leading
  s="${s#"${s%%[![:space:]]*}"}"
  # Trim trailing
  s="${s%"${s##*[![:space:]]}"}"
  echo "$s"
}

strip_quotes() {
  local s="$1"
  # Remove single or double quotes around the whole string if present
  if [[ "$s" == \"*\" && "$s" == *\" ]]; then
    s="${s#\"}"
    s="${s%\"}"
  elif [[ "$s" == \'*\' && "$s" == *\' ]]; then
    s="${s#\'}"
    s="${s%\'}"
  fi
  echo "$s"
}

install_one() {
  local key="$1"
  local dest_raw="$2"

  local src="$SECRETS_DIR/$key"
  [[ -f "$src" ]] || {
    echo "Skip (missing decrypted file): $src"
    return 0
  }

  local dest
  dest="$(strip_quotes "$(trim "$dest_raw")")"
  [[ -n "$dest" ]] || {
    echo "Skip (empty destination) for key: $key"
    return 0
  }

  dest="$(expand_path "$dest")"

  log_debug "install_one: key=$key src=$src dest_raw=$dest_raw -> dest=$dest"

  # Ensure parent dir exists
  mkdir -p "$(dirname "$dest")"

  # Avoid accidentally overwriting symlink targets (e.g. overlay files linked by dotfiles).
  if [[ -L "$dest" ]]; then
    echo "Skip (destination is a symlink): $dest"
    return 0
  fi

  # Special case: ssh config -> ensure ~/.ssh perms
  if [[ "$dest" == "$HOME/.ssh/config" || "$dest" == */.ssh/config ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
  fi

  # Copy file and enforce strict permissions (600) by default
  cp -f "$src" "$dest"

  log_debug "install_one: after cp, verifying head and perms"
  log_debug "install_one: src head=$(LC_ALL=C head -n 1 "$src" 2>/dev/null || true)"
  log_debug "install_one: dest head before chmod=$(LC_ALL=C head -n 1 "$dest" 2>/dev/null || true)"
  log_debug "install_one: dest ls before chmod=$(ls -l "$dest" 2>/dev/null || true)"

  chmod 600 "$dest" 2>/dev/null || die "Failed to set permissions on $dest"
  log_debug "install_one: dest ls after chmod 600=$(ls -l "$dest" 2>/dev/null || true)"

  # If it's a script (shebang), make it executable (keep owner-only perms)
  if looks_like_shell_script "$dest"; then
    log_info_when_debug "marking executable (shebang): $dest"
    log_debug "install_one: making executable: $dest (chmod 700)"
    chmod 700 "$dest" 2>/dev/null || die "Failed to set executable permissions on $dest"
    log_debug "install_one: dest ls after chmod 700=$(ls -l "$dest" 2>/dev/null || true)"
  else
    log_debug "install_one: not executable: $dest"
  fi

  # If it's an SSH key or config, ensure .ssh dir is 700
  if [[ "$dest" == "$HOME/.ssh/"* ]]; then
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
  fi

  echo "Installed: $dest (from $src)"
}


cmd_install() {
  ensure_repo

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "Manifest not found, nothing to install: $MANIFEST_FILE"
    return 0
  fi

  # Minimal "YAML" parser: supports lines like
  #   key: value
  # Ignores blank lines and comments (# ...).
  local line
  while IFS= read -r line; do
    # Drop comments
    line="${line%%#*}"
    line="$(trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == *:* ]] || continue

    local key="${line%%:*}"
    local value="${line#*:}"

    key="$(trim "$key")"
    value="$(trim "$value")"

    # Normalize key (no spaces)
    key="${key//[[:space:]]/}"

    [[ -n "$key" ]] || continue
    [[ -n "$value" ]] || continue

    install_one "$key" "$value"
  done <"$MANIFEST_FILE"
}

cmd_reveal_install() {
  cmd_reveal
  cmd_install
}

cmd_add() {
  ensure_repo
  require_cmd git
  require_cmd git-secret

  local src_path="${1:-}"
  local dest_name="${2:-}"

  [[ -n "$src_path" ]] || die "Usage: add <path> [dest]"
  [[ -f "$src_path" ]] || die "File not found: $src_path"

  mkdir -p "$SECRETS_DIR"

  if [[ -z "$dest_name" ]]; then
    dest_name="$(basename "$src_path")"
  fi

  local dest_path="$SECRETS_DIR/$dest_name"

  # Copy plaintext into repo (this is what git-secret will encrypt on hide)
  cp -f "$src_path" "$dest_path"
  chmod_safely 600 "$dest_path"
  echo "Copied into secrets/: $dest_path"

  # Track plaintext file with git-secret
  (cd "$ROOT_DIR" && git secret add "secrets/$dest_name")
  echo "Added to git-secret: secrets/$dest_name"
  echo "Next: run 'zsh scripts/secret-helper.zsh hide' to encrypt."
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    check)
      cmd_check "$@"
      ;;
    reveal)
      cmd_reveal "$@"
      ;;
    install)
      cmd_install "$@"
      ;;
    reveal-install)
      cmd_reveal_install "$@"
      ;;
    add)
      cmd_add "$@"
      ;;
    hide)
      cmd_hide "$@"
      ;;
    ""|help|-h|--help)
      print_usage
      ;;
    *)
      die "Unknown command: $cmd (run with 'help' for usage)"
      ;;
  esac
}

main "$@"
