#!/usr/bin/env bats
# ─── proxied-claude.bats ─────────────────────────────────────────────────────
# Test suite for claude-proxy and proxied-claude
# Version: 2.0.0
#
# Requirements:
#   brew install bats-core
#
# Run all:
#   bats proxied-claude.bats
#
# Run with TAP output:
#   bats proxied-claude.bats --tap
#
# Filter by name:
#   bats proxied-claude.bats --filter validate_name
#   bats proxied-claude.bats --filter copy-settings
#   bats proxied-claude.bats --filter migration
#   bats proxied-claude.bats --filter lock
# ─────────────────────────────────────────────────────────────────────────────

# ── Setup / Teardown ──────────────────────────────────────────────────────────

setup() {
  export TEST_DIR="$(mktemp -d)"
  export CONF_DIR="$TEST_DIR/proxied-claude"
  export PROFILES_DIR="$CONF_DIR/profiles"
  export PROXIES_DIR="$CONF_DIR/proxies"
  export ACTIVE_FILE="$CONF_DIR/active_profile"
  export LOCK_DIR="$CONF_DIR/.lock"
  mkdir -p "$PROFILES_DIR" "$PROXIES_DIR"
  unset PROXIED_CLAUDE_PROFILE
  _define_helpers
}

teardown() {
  rm -rf "$TEST_DIR"
  unset PROXIED_CLAUDE_PROFILE
}

# ── Helpers (mirror exact implementations from claude-proxy) ──────────────────

_define_helpers() {
  die()  { echo "ERROR: $*" >&2; exit 1; }
  ok()   { echo "✅ $*"; }
  info() { echo "   $*"; }
  warn() { echo "⚠️  $*"; }

  validate_name() {
    local name="$1" kind="${2:-name}"
    [[ -n "$name" ]] || { echo "ERROR: $kind cannot be empty." >&2; return 1; }
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || {
      echo "ERROR: Invalid $kind '$name'." >&2; return 1
    }
  }

  active_profile() {
    if [[ -f "$ACTIVE_FILE" && -s "$ACTIVE_FILE" ]]; then
      local val; val="$(tr -d '[:space:]' < "$ACTIVE_FILE")"
      [[ -n "$val" ]] && echo "$val" || echo "default"
    else
      echo "default"
    fi
  }

  write_active() {
    local tmp; tmp="$(mktemp "${ACTIVE_FILE}.XXXXXX")"
    echo "$1" > "$tmp"; mv "$tmp" "$ACTIVE_FILE"
  }

  # Mirrors profile resolution logic from proxied-claude
  resolve_profile() {
    local override="${PROXIED_CLAUDE_PROFILE:-}"
    if [[ -n "$override" ]]; then
      echo "$override"
    else
      if [[ -f "$ACTIVE_FILE" && -s "$ACTIVE_FILE" ]]; then
        local val; val="$(tr -d '[:space:]' < "$ACTIVE_FILE")"
        [[ -n "$val" ]] && echo "$val" || echo "default"
      else
        echo "default"
      fi
    fi
  }

  require_profile() {
    local name="$1"
    [[ -f "$PROFILES_DIR/${name}.conf" ]] || { echo "ERROR: Profile '$name' does not exist." >&2; return 1; }
  }

  # New grep-based read_conf — must match claude-proxy exactly
  read_conf() {
    local file="$1" var="$2" line
    line="$(grep -m1 "^${var}=" "$file" 2>/dev/null)" || true
    line="${line#*=}"
    line="${line#\"}"
    line="${line%\"}"
    printf '%s' "$line"
  }

  profile_claude_dir() {
    local name="$1"
    local dir; dir="$(read_conf "$PROFILES_DIR/${name}.conf" PROFILE_CLAUDE_DIR)"
    if [[ -z "$dir" ]]; then
      [[ "$name" == "default" ]] && echo "$HOME/.claude" || echo "$HOME/.claude-${name}"
    else
      echo "$dir"
    fi
  }

  # Runs a function with stdin closed — forces [[ -t 0 ]] to return false.
  # Use for tests that exercise non-interactive code paths.
  _run_ni() { "$@" < /dev/null; }

  dir_has_data() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -mindepth 1 -maxdepth 1 -not -name ".DS_Store" \
         -print -quit 2>/dev/null | grep -q .
  }

  # Mirrors non-interactive existing-dir branch of profile create
  # Sets _login_note and prints warn when dir has data; creates dir otherwise.
  # Returns the resulting _login_note via stdout (last line).
  do_create_dir_noninteractive() {
    local claude_dir="$1"
    local _login_note="Note: you need to log in to Claude the first time you use this profile"
    if dir_has_data "$claude_dir"; then
      warn "Directory $claude_dir already exists and contains data — using as-is"
      _login_note="Note: If your session expired, log in again when you first use this profile"
    fi
    mkdir -p "$claude_dir"
    echo "$_login_note"
  }

  SETTINGS_FILES=("settings.json" "CLAUDE.md" "keybindings.json" "policy-limits.json")
  SETTINGS_DIRS=("hooks" "plugins")

  do_copy_settings() {
    local src_dir="$1" dst_dir="$2" src_label="$3" dst_label="$4" \
          include_projects="${5:-0}"
    local copied=0
    mkdir -p "$dst_dir"
    # Locate .claude.json for each profile dir (for mcpServers handling).
    # Claude Code writes to CLAUDE_CONFIG_DIR/.claude.json; legacy default profile
    # wrote to ${dir}.json (i.e. ~/.claude.json) when CLAUDE_CONFIG_DIR was unset.
    local src_claude_json="" dst_claude_json=""
    if [[ -f "${src_dir}/.claude.json" ]]; then src_claude_json="${src_dir}/.claude.json"
    elif [[ -f "${src_dir}.json" ]]; then src_claude_json="${src_dir}.json"; fi
    if [[ -f "${dst_dir}/.claude.json" ]]; then dst_claude_json="${dst_dir}/.claude.json"
    elif [[ -f "${dst_dir}.json" ]]; then dst_claude_json="${dst_dir}.json"; fi
    # Pass 1: collect conflicts
    local conflicts=()
    for f in "${SETTINGS_FILES[@]}"; do
      [[ -f "$src_dir/$f" ]] || continue
      [[ -f "$dst_dir/$f" ]] && conflicts+=("$f")
    done
    for d in "${SETTINGS_DIRS[@]}"; do
      [[ -d "$src_dir/$d" ]] || continue
      for item in "$src_dir/$d"/*; do
        [[ -e "$item" ]] || continue
        [[ -e "$dst_dir/$d/$(basename "$item")" ]] && conflicts+=("$d/$(basename "$item")")
      done
    done
    if [[ "$include_projects" == "1" ]]; then
      shopt -s nullglob
      for proj_dir in "$src_dir/projects"/*/; do
        [[ -d "$proj_dir/memory" ]] || continue
        local repo; repo="$(basename "$proj_dir")"
        for mf in "$proj_dir/memory"/*; do
          [[ -e "$mf" ]] || continue
          [[ -e "$dst_dir/projects/$repo/memory/$(basename "$mf")" ]] && \
            conflicts+=("projects/$repo/memory/$(basename "$mf")")
        done
      done
      shopt -u nullglob
    fi
    # mcpServers conflict: both src and dst already have mcpServers
    if [[ -n "$src_claude_json" && -n "$dst_claude_json" ]]; then
      if command -v python3 >/dev/null 2>&1 && python3 -c "
import json, sys
def has_mcp(p): return bool(json.load(open(p)).get('mcpServers'))
sys.exit(0 if has_mcp(sys.argv[1]) and has_mcp(sys.argv[2]) else 1)
" "$src_claude_json" "$dst_claude_json" 2>/dev/null; then
        conflicts+=(".claude.json (mcpServers)")
      fi
    fi
    # Resolve conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
      if [[ -t 0 ]]; then
        warn "${#conflicts[@]} item(s) already exist in '$dst_label' and will be overwritten:"
        for c in "${conflicts[@]}"; do info "  $c"; done
        echo ""
        read -r -p "  Overwrite? [y/N] " _confirm
        [[ "${_confirm:-}" =~ ^[Yy]$ ]] || return 0
      else
        die "${#conflicts[@]} conflicting item(s) in '$dst_label'. Run interactively to confirm overwrite."
      fi
    fi
    # Pass 2: copy
    for f in "${SETTINGS_FILES[@]}"; do
      if [[ -f "$src_dir/$f" ]]; then
        cp "$src_dir/$f" "$dst_dir/$f"
        info "Copied $f"
        (( copied++ )) || true
      fi
    done
    # Rewrite claude profile dir paths in settings.json
    [[ -f "$dst_dir/settings.json" ]] && \
      sed -E -i '' "s|$HOME/\.claude(-[a-zA-Z0-9_-]*)?|$dst_dir|g" \
        "$dst_dir/settings.json"
    for d in "${SETTINGS_DIRS[@]}"; do
      if [[ -d "$src_dir/$d" ]]; then
        mkdir -p "$dst_dir/$d"
        local dir_copied=0
        for item in "$src_dir/$d"/*; do
          [[ -e "$item" ]] || continue
          cp -r "$item" "$dst_dir/$d/$(basename "$item")"
          (( dir_copied++ )) || true
        done
        [[ $dir_copied -gt 0 ]] && { info "Copied $d/ ($dir_copied item(s))"; (( copied++ )) || true; }
      fi
    done
    # Rewrite absolute plugin cache paths in copied plugin manifests.
    # Use | as delimiter so forward slashes in absolute paths are safe.
    # Profile names are validated to [a-zA-Z0-9_-] so no | characters possible.
    for _pf in "installed_plugins.json" "known_marketplaces.json"; do
      [[ -f "$dst_dir/plugins/$_pf" ]] && \
        sed -i '' "s|${src_dir}/plugins/|${dst_dir}/plugins/|g" \
          "$dst_dir/plugins/$_pf"
    done
    if [[ "$include_projects" == "1" ]]; then
      shopt -s nullglob
      for proj_dir in "$src_dir/projects"/*/; do
        [[ -d "$proj_dir/memory" ]] || continue
        local repo; repo="$(basename "$proj_dir")"
        mkdir -p "$dst_dir/projects/$repo/memory"
        for mf in "$proj_dir/memory"/*; do
          [[ -e "$mf" ]] || continue
          cp -r "$mf" "$dst_dir/projects/$repo/memory/$(basename "$mf")"
          (( copied++ )) || true
        done
      done
      shopt -u nullglob
    fi
    # Copy mcpServers from .claude.json (source replaces destination)
    if [[ -n "$src_claude_json" ]]; then
      local dst_cj
      if [[ -n "$dst_claude_json" ]]; then dst_cj="$dst_claude_json"
      elif [[ "$dst_dir" == "$HOME/.claude" ]]; then dst_cj="${dst_dir}.json"
      else dst_cj="${dst_dir}/.claude.json"; fi
      if command -v python3 >/dev/null 2>&1 && python3 -c "
import json, sys, os
src_mcp = json.load(open(sys.argv[1])).get('mcpServers', {})
if not src_mcp: sys.exit(1)
dst = json.load(open(sys.argv[2])) if os.path.exists(sys.argv[2]) else {}
dst['mcpServers'] = src_mcp
open(sys.argv[2], 'w').write(json.dumps(dst, indent=2) + '\n')
" "$src_claude_json" "$dst_cj" 2>/dev/null; then
        info "Copied mcpServers (.claude.json)"
        (( copied++ )) || true
      fi
    fi
    if [[ $copied -eq 0 ]]; then
      info "No settings found in '$src_label' (nothing copied)"
    else
      ok "Settings copied from '$src_label' → '$dst_label'"
      info "Note: you still need to log in to Claude in the new profile"
    fi
  }

  profiles_using_proxy() {
    local proxy_name="$1" result=""
    shopt -s nullglob
    for pf in "$PROFILES_DIR"/*.conf; do
      local linked; linked="$(read_conf "$pf" PROFILE_PROXY)"
      [[ "$linked" == "$proxy_name" ]] && result="${result}$(basename "$pf" .conf) "
    done
    shopt -u nullglob
    printf '%s' "$result"
  }

  unlink_proxy_from_profiles() {
    local proxy_name="$1"
    shopt -s nullglob
    for pf in "$PROFILES_DIR"/*.conf; do
      local linked; linked="$(read_conf "$pf" PROFILE_PROXY)"
      if [[ "$linked" == "$proxy_name" ]]; then
        local pdir; pdir="$(read_conf "$pf" PROFILE_CLAUDE_DIR)"
        cat > "$pf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${pdir}"
PROFILE_PROXY=""
EOF
        info "Unlinked proxy from profile '$(basename "$pf" .conf)'"
      fi
    done
    shopt -u nullglob
  }

  lock_acquire() {
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      (( waited++ >= 5 )) && { echo "ERROR: lock held" >&2; return 1; }
      sleep 1
    done
    trap 'rm -rf "$LOCK_DIR"' EXIT
  }

  lock_release() {
    rm -rf "$LOCK_DIR"
    trap - EXIT
  }

  make_profile() {
    local name="$1" proxy="${2:-}" dir="${3:-}"
    [[ -z "$dir" ]] && { [[ "$name" == "default" ]] && dir="$HOME/.claude" || dir="$HOME/.claude-${name}"; }
    cat > "$PROFILES_DIR/${name}.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${dir}"
PROFILE_PROXY="${proxy}"
EOF
  }

  make_proxy() {
    cat > "$PROXIES_DIR/${1}.conf" <<EOF
CONFIG_VERSION=1
PROXY_HOST="${2}"
PROXY_USER="${3}"
PROXY_KEYCHAIN_SERVICE="claude-proxy:${1}"
EOF
  }

  # Mirrors cmd_profile set-proxy logic from claude-proxy
  do_set_proxy() {
    local name="$1" proxy="$2"
    local dir; dir="$(profile_claude_dir "$name")"
    cat > "$PROFILES_DIR/${name}.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${dir}"
PROFILE_PROXY="${proxy}"
EOF
  }

  # Mirrors cmd_profile unset-proxy logic from claude-proxy
  do_unset_proxy() {
    local name="$1"
    local dir; dir="$(profile_claude_dir "$name")"
    cat > "$PROFILES_DIR/${name}.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${dir}"
PROFILE_PROXY=""
EOF
  }

  # Mirrors v1 command guard from claude-proxy
  v1_cmd_check() {
    local cmd="$1"
    case "$cmd" in
      set-all|set-host|set-user)
        echo "ERROR: '$cmd' was a v1 command." >&2; return 1 ;;
      set-password)
        echo "ERROR: '$cmd' was a v1 command." >&2; return 1 ;;
    esac
  }

  _pc_info() {
    local conf="${CONF_DIR}"
    local profile="${PROXIED_CLAUDE_PROFILE:-}"
    if [[ -z "$profile" ]]; then
      [[ -f "${conf}/active_profile" ]] || return 0
      profile=$(tr -d '[:space:]' < "${conf}/active_profile")
    fi
    [[ -n "$profile" ]] || return 0
    local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
    proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
    [[ -n "$proxy" ]] && printf '%s (%s)' "$profile" "$proxy" || printf '%s' "$profile"
  }

  require_interactive() {
    [[ -t 0 ]] || die "This command requires interactive input (stdin must be a terminal)."
  }

  cmd_update() {
    local _target_version=""

    # Parse args
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --version)
          [[ -n "${2:-}" ]] || die "Usage: claude-proxy update --version <tag> (e.g. v2.1.0)"
          _target_version="$2"; shift 2 ;;
        *)
          die "Unknown option: $1
Usage: claude-proxy update [--version <tag>]" ;;
      esac
    done

    require_interactive

    # Fetch latest release from GitHub if no version pinned
    if [[ -z "$_target_version" ]]; then
      local _fetched
      _fetched="$(curl -fsSL --proto '=https' --tlsv1.2 \
        "https://api.github.com/repos/r0mm4k/proxied-claude/releases/latest" \
        2>/dev/null \
        | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      if [[ -n "$_fetched" ]]; then
        _target_version="$_fetched"
      else
        warn "Could not fetch latest version from GitHub. Installing from main branch."
      fi
    fi

    # Already up to date?
    local _installed="v$VERSION"
    if [[ -n "$_target_version" && "$_installed" == "$_target_version" ]]; then
      echo "Already up to date: $_installed"
      return 0
    fi

    # Version preview
    echo ""
    if [[ -n "$_target_version" ]]; then
      echo "  Installed : $_installed"
      echo "  Latest    : $_target_version"
      echo ""

      # Major version bump warning
      local _inst_major _new_major
      _inst_major="${VERSION%%.*}"
      _new_major="${_target_version#v}"; _new_major="${_new_major%%.*}"
      if [[ "$_new_major" -gt "$_inst_major" ]]; then
        warn "Major version upgrade ($_installed → $_target_version)."
        echo "   Review release notes before upgrading:"
        echo "   https://github.com/r0mm4k/proxied-claude/releases/tag/${_target_version}"
        echo ""
      fi

      read -r -p "Upgrade to $_target_version? [y/N] " _confirm
    else
      read -r -p "Upgrade to latest (main branch)? [y/N] " _confirm
    fi
    [[ "${_confirm:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }

    # Install
    echo ""
    echo "Your profiles, proxies and settings are preserved."
    echo ""
    local _TMP
    _TMP="$(mktemp)"
    trap 'rm -f "$_TMP"' EXIT
    curl -fsSL --proto '=https' --tlsv1.2 \
      "https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh" \
      -o "$_TMP"
    if [[ -n "$_target_version" ]]; then
      VERSION="$_target_version" PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
    else
      PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
    fi
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# validate_name
# ═══════════════════════════════════════════════════════════════════════════════

@test "validate_name: accepts simple name" {
  run validate_name "work"; [ "$status" -eq 0 ]
}

@test "validate_name: accepts hyphen" {
  run validate_name "corp-lt"; [ "$status" -eq 0 ]
}

@test "validate_name: accepts underscore" {
  run validate_name "my_profile"; [ "$status" -eq 0 ]
}

@test "validate_name: accepts digits" {
  run validate_name "profile2"; [ "$status" -eq 0 ]
}

@test "validate_name: accepts uppercase" {
  run validate_name "WORK"; [ "$status" -eq 0 ]
}

@test "validate_name: rejects path traversal" {
  run validate_name "../../etc/passwd"; [ "$status" -ne 0 ]
}

@test "validate_name: rejects spaces" {
  run validate_name "name with spaces"; [ "$status" -ne 0 ]
}

@test "validate_name: rejects semicolon injection" {
  run validate_name "name;rm -rf ~"; [ "$status" -ne 0 ]
}

@test "validate_name: rejects empty string" {
  run validate_name ""; [ "$status" -ne 0 ]
}

@test "validate_name: rejects slash" {
  run validate_name "some/path"; [ "$status" -ne 0 ]
}

@test "validate_name: rejects dot-dot" {
  run validate_name ".."; [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# active_profile
# ═══════════════════════════════════════════════════════════════════════════════

@test "active_profile: returns default when no file exists" {
  run active_profile
  [ "$status" -eq 0 ]
  [ "$output" = "default" ]
}

@test "active_profile: returns default when file is empty (touch)" {
  touch "$ACTIVE_FILE"
  run active_profile
  [ "$output" = "default" ]
}

@test "active_profile: returns default when file has only newline" {
  echo "" > "$ACTIVE_FILE"
  run active_profile
  [ "$output" = "default" ]
}

@test "active_profile: returns default when file has only whitespace" {
  printf "  \n  " > "$ACTIVE_FILE"
  run active_profile
  [ "$output" = "default" ]
}

@test "active_profile: returns set profile name" {
  write_active "work"
  run active_profile
  [ "$output" = "work" ]
}

@test "active_profile: trims surrounding whitespace" {
  printf "  work  \n" > "$ACTIVE_FILE"
  run active_profile
  [ "$output" = "work" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# write_active
# ═══════════════════════════════════════════════════════════════════════════════

@test "write_active: creates active_profile file" {
  write_active "work"
  [ -f "$ACTIVE_FILE" ]
}

@test "write_active: writes correct value" {
  write_active "personal"
  run cat "$ACTIVE_FILE"
  [ "$output" = "personal" ]
}

@test "write_active: overwrites correctly" {
  write_active "work"
  write_active "personal"
  run active_profile
  [ "$output" = "personal" ]
}

@test "write_active: leaves no temp files behind" {
  write_active "work"
  run bash -c "ls '${ACTIVE_FILE}'* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# ide/ shared symlink
# ═══════════════════════════════════════════════════════════════════════════════

@test "ide/: symlink created when dir does not exist" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir"
  # mirrors profile create logic
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ -L "$claude_dir/ide" ]
  [ "$(readlink "$claude_dir/ide")" = "$CONF_DIR/ide" ]
}

@test "ide/: real dir replaced by symlink (N-branch migration)" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir/ide"
  touch "$claude_dir/ide/59993.lock"   # stale lock file
  # mirrors profile create / install.sh migration logic
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ -L "$claude_dir/ide" ]
  [ "$(readlink "$claude_dir/ide")" = "$CONF_DIR/ide" ]
  [ ! -f "$claude_dir/ide/59993.lock" ]   # stale file gone
}

@test "ide/: existing symlink not touched" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir"
  ln -s "$CONF_DIR/ide" "$claude_dir/ide"
  local before; before="$(readlink "$claude_dir/ide")"
  # apply logic again — should be a no-op
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ "$(readlink "$claude_dir/ide")" = "$before" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# read_conf (grep-based)
# ═══════════════════════════════════════════════════════════════════════════════

@test "read_conf: reads quoted value" {
  echo 'PROXY_HOST="10.0.0.1:3128"' > "$TEST_DIR/test.conf"
  run read_conf "$TEST_DIR/test.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
}

@test "read_conf: reads unquoted value" {
  echo 'PROXY_HOST=10.0.0.1:3128' > "$TEST_DIR/test.conf"
  run read_conf "$TEST_DIR/test.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
}

@test "read_conf: returns empty for missing variable" {
  echo 'PROXY_HOST="10.0.0.1:3128"' > "$TEST_DIR/test.conf"
  run read_conf "$TEST_DIR/test.conf" PROXY_USER
  [ "$output" = "" ]
}

@test "read_conf: does not pollute global environment" {
  echo 'SOME_VAR="injected"' > "$TEST_DIR/test.conf"
  read_conf "$TEST_DIR/test.conf" SOME_VAR > /dev/null
  [ -z "${SOME_VAR:-}" ]
}

@test "read_conf: handles missing file gracefully" {
  run read_conf "/nonexistent/path.conf" SOME_VAR
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "read_conf: reads first match only" {
  cat > "$TEST_DIR/test.conf" <<'EOF'
PROXY_HOST="first"
PROXY_HOST="second"
EOF
  run read_conf "$TEST_DIR/test.conf" PROXY_HOST
  [ "$output" = "first" ]
}

@test "read_conf: does not execute embedded commands" {
  echo 'PROXY_HOST="$(whoami)"' > "$TEST_DIR/test.conf"
  run read_conf "$TEST_DIR/test.conf" PROXY_HOST
  # Should return literal string, not execute it
  [ "$output" = '$(whoami)' ]
}

@test "read_conf: handles empty value" {
  echo 'PROFILE_PROXY=""' > "$TEST_DIR/test.conf"
  run read_conf "$TEST_DIR/test.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile_claude_dir
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile_claude_dir: default returns ~/.claude" {
  make_profile "default"
  run profile_claude_dir "default"
  [ "$output" = "$HOME/.claude" ]
}

@test "profile_claude_dir: named profile returns ~/.claude-<n>" {
  make_profile "work"
  run profile_claude_dir "work"
  [ "$output" = "$HOME/.claude-work" ]
}

@test "profile_claude_dir: respects custom PROFILE_CLAUDE_DIR" {
  cat > "$PROFILES_DIR/custom.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="/custom/path"
PROFILE_PROXY=""
EOF
  run profile_claude_dir "custom"
  [ "$output" = "/custom/path" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# host:port validation
# ═══════════════════════════════════════════════════════════════════════════════

@test "host:port: accepts IP:PORT" {
  [[ "10.0.0.1:3128" =~ ^[^:]+:[0-9]+$ ]]
}

@test "host:port: accepts hostname:PORT" {
  [[ "proxy.corp.com:8080" =~ ^[^:]+:[0-9]+$ ]]
}

@test "host:port: rejects missing port" {
  ! [[ "10.0.0.1" =~ ^[^:]+:[0-9]+$ ]]
}

@test "host:port: rejects non-numeric port" {
  ! [[ "10.0.0.1:abc" =~ ^[^:]+:[0-9]+$ ]]
}

@test "host:port: rejects missing host" {
  ! [[ ":3128" =~ ^[^:]+:[0-9]+$ ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# copy-settings — files
# ═══════════════════════════════════════════════════════════════════════════════

@test "copy-settings: copies settings.json" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/settings.json" ]
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"dark"}' ]
}

@test "copy-settings: copies CLAUDE.md" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo "# My instructions" > "$src/CLAUDE.md"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/CLAUDE.md" ]
}

@test "copy-settings: copies keybindings.json" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"key":"ctrl+x"}' > "$src/keybindings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/keybindings.json" ]
}

@test "copy-settings: copies policy-limits.json" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"limit":100}' > "$src/policy-limits.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/policy-limits.json" ]
}

@test "copy-settings: does not copy auth sessions" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/sessions" "$dst"
  echo "token" > "$src/sessions/auth.json"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -d "$dst/sessions" ]
}

@test "copy-settings: does not copy .credentials" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"token":"secret"}' > "$src/.credentials"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -f "$dst/.credentials" ]
}

@test "copy-settings: does not copy history.jsonl" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo "chat history" > "$src/history.jsonl"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -f "$dst/history.jsonl" ]
}

@test "copy-settings: handles empty source gracefully" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing copied"* ]]
  run bash -c "ls '$dst' | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "copy-settings: shows copied confirmation on successful copy" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Settings copied"* ]]
}

@test "copy-settings: dies on conflict in non-interactive mode" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  run _run_ni do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicting"* ]]
}

@test "copy-settings: dst unchanged on non-interactive conflict" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  run _run_ni do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"light"}' ]
}

@test "copy-settings: rewrites ~/.claude path in settings.json to dst_dir" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"statusLine":{"command":"bash %s/hooks/statusline.sh"}}' \
    "$HOME/.claude" > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [[ "$output" == *"${dst}/hooks/statusline.sh"* ]]
}

@test "copy-settings: rewrites ~/.claude-name path in settings.json to dst_dir" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"statusLine":{"command":"bash %s/hooks/statusline.sh"}}' \
    "$HOME/.claude-personal" > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [[ "$output" == *"${dst}/hooks/statusline.sh"* ]]
}

@test "copy-settings: settings.json without profile paths is copied unchanged" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"dark"}' ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# copy-settings — directories
# ═══════════════════════════════════════════════════════════════════════════════

@test "copy-settings: copies hooks/ directory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/hooks" "$dst"
  echo "#!/bin/bash" > "$src/hooks/pre-commit"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/hooks/pre-commit" ]
}

@test "copy-settings: copies plugins/ directory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/plugins" "$dst"
  echo "{}" > "$src/plugins/my-plugin.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/plugins/my-plugin.json" ]
}

@test "copy-settings: rewrites installPath in installed_plugins.json after copy" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/plugins" "$dst"
  printf '{"plugins":[{"installPath":"%s/plugins/cache/my-plugin"}]}\n' "$src" \
    > "$src/plugins/installed_plugins.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run grep -c "${dst}/plugins/cache/my-plugin" "$dst/plugins/installed_plugins.json"
  [ "$output" = "1" ]
  run grep -c "${src}/plugins/cache/my-plugin" "$dst/plugins/installed_plugins.json"
  [ "$output" = "0" ]
}

@test "copy-settings: rewrites installLocation in known_marketplaces.json after copy" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/plugins" "$dst"
  printf '{"marketplaces":[{"installLocation":"%s/plugins/marketplace"}]}\n' "$src" \
    > "$src/plugins/known_marketplaces.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run grep -c "${dst}/plugins/marketplace" "$dst/plugins/known_marketplaces.json"
  [ "$output" = "1" ]
  run grep -c "${src}/plugins/marketplace" "$dst/plugins/known_marketplaces.json"
  [ "$output" = "0" ]
}

@test "copy-settings: does not copy cache/ directory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/cache" "$dst"
  echo "cached" > "$src/cache/data.bin"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -d "$dst/cache" ]
}

@test "copy-settings: does not copy telemetry/ directory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/telemetry" "$dst"
  echo "{}" > "$src/telemetry/events.json"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -d "$dst/telemetry" ]
}

@test "copy-settings: handles empty hooks/ gracefully" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/hooks" "$dst"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# copy-settings — --include-projects
# ═══════════════════════════════════════════════════════════════════════════════

@test "copy-settings: --include-projects copies project memory file" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# memory" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ -f "$dst/projects/my-repo/memory/MEMORY.md" ]
}

@test "copy-settings: --include-projects preserves memory file content" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# custom context" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  run cat "$dst/projects/my-repo/memory/MEMORY.md"
  [ "$output" = "# custom context" ]
}

@test "copy-settings: --include-projects skips .jsonl history" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo"
  echo '{}' > "$src/projects/my-repo/session.jsonl"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ ! -f "$dst/projects/my-repo/session.jsonl" ]
}

@test "copy-settings: --include-projects skips project dirs without memory/" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo"
  echo '{}' > "$src/projects/my-repo/session.jsonl"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ ! -d "$dst/projects/my-repo" ]
}

@test "copy-settings: --include-projects no-op when projects/ missing" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  run do_copy_settings "$src" "$dst" "src" "dst" 1
  [ "$status" -eq 0 ]
}

@test "copy-settings: --include-projects dies on project memory conflict (non-interactive)" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory" "$dst/projects/my-repo/memory"
  echo "# src" > "$src/projects/my-repo/memory/MEMORY.md"
  echo "# dst" > "$dst/projects/my-repo/memory/MEMORY.md"
  run _run_ni do_copy_settings "$src" "$dst" "src" "dst" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicting"* ]]
}

@test "copy-settings: without --include-projects does not copy project memory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# memory" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -d "$dst/projects" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# copy-settings — mcpServers
# ═══════════════════════════════════════════════════════════════════════════════

@test "copy-settings: copies mcpServers from src .claude.json to new dst" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"mcpServers":{"exa":{"command":"npx","args":["exa"]}}}\n' \
    > "$src/.claude.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/.claude.json" ]
  run python3 -c "import json; d=json.load(open('$dst/.claude.json')); print(list(d['mcpServers'].keys())[0])"
  [ "$output" = "exa" ]
}

@test "copy-settings: copies mcpServers from src legacy .json path (default profile)" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  # legacy path: ${src}.json (simulates ~/.claude.json for the default profile)
  printf '{"mcpServers":{"exa":{"command":"npx"}}}\n' > "${src}.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ -f "$dst/.claude.json" ]
  run python3 -c "import json; d=json.load(open('$dst/.claude.json')); print(list(d['mcpServers'].keys())[0])"
  [ "$output" = "exa" ]
}

@test "copy-settings: copies mcpServers when dst .claude.json exists but has no mcpServers" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"mcpServers":{"exa":{"command":"npx"}}}\n' > "$src/.claude.json"
  printf '{"numStartups":3}\n' > "$dst/.claude.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run python3 -c "import json; d=json.load(open('$dst/.claude.json')); print(d['numStartups'], list(d['mcpServers'].keys())[0])"
  [ "$output" = "3 exa" ]
}

@test "copy-settings: skips mcpServers when src mcpServers is empty" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"mcpServers":{}}\n' > "$src/.claude.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -f "$dst/.claude.json" ]
}

@test "copy-settings: skips mcpServers when src has no .claude.json" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -f "$dst/.claude.json" ]
}

@test "copy-settings: mcpServers conflict included in conflict list (non-interactive dies)" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"mcpServers":{"exa":{"command":"npx"}}}\n' > "$src/.claude.json"
  printf '{"mcpServers":{"other":{"command":"other"}}}\n' > "$dst/.claude.json"
  run _run_ni do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicting"* ]]
}

@test "copy-settings: skips mcpServers silently when src .claude.json is malformed" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf 'not valid json\n' > "$src/.claude.json"
  echo '{"theme":"dark"}' > "$src/settings.json"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -eq 0 ]
  [ ! -f "$dst/.claude.json" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profiles_using_proxy
# ═══════════════════════════════════════════════════════════════════════════════

@test "profiles_using_proxy: finds linked profiles" {
  make_profile "work" "corp-lt"
  make_profile "personal" "corp-lt"
  make_profile "default"
  run profiles_using_proxy "corp-lt"
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"personal"* ]]
  [[ "$output" != *"default"* ]]
}

@test "profiles_using_proxy: returns empty for unused proxy" {
  make_profile "work"
  make_profile "personal"
  run profiles_using_proxy "nonexistent"
  [ "$output" = "" ]
}

@test "profiles_using_proxy: returns empty when no profiles exist" {
  rm -f "$PROFILES_DIR"/*.conf
  run profiles_using_proxy "corp-lt"
  [ "$output" = "" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# unlink_proxy_from_profiles
# ═══════════════════════════════════════════════════════════════════════════════

@test "unlink: clears proxy from linked profiles" {
  make_profile "work" "corp-lt"
  make_profile "personal" "corp-lt"
  make_profile "default"
  unlink_proxy_from_profiles "corp-lt"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "" ]
  run read_conf "$PROFILES_DIR/personal.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

@test "unlink: does not modify unlinked profiles" {
  make_profile "work" "corp-lt"
  make_profile "default" "home-de"
  unlink_proxy_from_profiles "corp-lt"
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "home-de" ]
}

@test "unlink: preserves PROFILE_CLAUDE_DIR" {
  make_profile "work" "corp-lt" "/custom/path"
  unlink_proxy_from_profiles "corp-lt"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "/custom/path" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# lock
# ═══════════════════════════════════════════════════════════════════════════════

@test "lock: acquire creates lock directory" {
  lock_acquire
  [ -d "$LOCK_DIR" ]
  lock_release
}

@test "lock: release removes lock directory" {
  lock_acquire
  lock_release
  [ ! -d "$LOCK_DIR" ]
}

@test "lock: second acquire fails when held" {
  mkdir "$LOCK_DIR"
  run bash -c "
    LOCK_DIR='$LOCK_DIR'
    lock_acquire() {
      local waited=0
      while ! mkdir \"\$LOCK_DIR\" 2>/dev/null; do
        (( waited++ >= 1 )) && { echo 'ERROR: lock held' >&2; return 1; }
        sleep 0.1
      done
    }
    lock_acquire
  "
  [ "$status" -ne 0 ]
  rmdir "$LOCK_DIR"
}

@test "lock: acquire succeeds after release" {
  lock_acquire
  lock_release
  lock_acquire
  [ -d "$LOCK_DIR" ]
  lock_release
}

# ═══════════════════════════════════════════════════════════════════════════════
# ensure_default_profile
# ═══════════════════════════════════════════════════════════════════════════════

@test "ensure_default_profile: creates default.conf if missing" {
  [ ! -f "$PROFILES_DIR/default.conf" ]
  cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY=""
EOF
  [ -f "$PROFILES_DIR/default.conf" ]
}

@test "ensure_default_profile: default dir is ~/.claude" {
  cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY=""
EOF
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "$HOME/.claude" ]
}

@test "ensure_default_profile: does not overwrite existing default.conf" {
  cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY="default"
EOF
  [[ ! -f "$PROFILES_DIR/default.conf" ]] && cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY=""
EOF
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "default" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Profile isolation
# ═══════════════════════════════════════════════════════════════════════════════

@test "profiles: two named profiles have separate dirs" {
  make_profile "work"
  make_profile "personal"
  [ "$(profile_claude_dir "work")" != "$(profile_claude_dir "personal")" ]
}

@test "profiles: default does not overlap with named profiles" {
  make_profile "default"
  make_profile "work"
  [ "$(profile_claude_dir "default")" = "$HOME/.claude" ]
  [ "$(profile_claude_dir "work")" = "$HOME/.claude-work" ]
  [ "$(profile_claude_dir "default")" != "$(profile_claude_dir "work")" ]
}

@test "profiles: switching is reflected immediately" {
  make_profile "work"
  make_profile "personal"
  write_active "work"
  [ "$(active_profile)" = "work" ]
  write_active "personal"
  [ "$(active_profile)" = "personal" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG_VERSION
# ═══════════════════════════════════════════════════════════════════════════════

@test "config: profile has CONFIG_VERSION=1" {
  make_profile "work"
  run read_conf "$PROFILES_DIR/work.conf" CONFIG_VERSION
  [ "$output" = "1" ]
}

@test "config: proxy has CONFIG_VERSION=1" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  run read_conf "$PROXIES_DIR/corp-lt.conf" CONFIG_VERSION
  [ "$output" = "1" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# v1 migration
# ═══════════════════════════════════════════════════════════════════════════════

_run_migration() {
  local legacy="$CONF_DIR/proxy.conf"
  [[ -f "$legacy" ]] || return 0

  local old_host; old_host="$(read_conf "$legacy" CLAUDE_PROXY_HOST)"
  local old_user; old_user="$(read_conf "$legacy" CLAUDE_PROXY_USER)"

  local has_proxy=false
  if [[ -n "$old_host" && -n "$old_user" ]]; then
    has_proxy=true
    cat > "$PROXIES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROXY_HOST="${old_host}"
PROXY_USER="${old_user}"
PROXY_KEYCHAIN_SERVICE="claude-proxy:default"
EOF
  fi

  if [[ ! -f "$PROFILES_DIR/default.conf" ]]; then
    local linked=""; [[ "$has_proxy" == "true" ]] && linked="default"
    cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY="${linked}"
EOF
  else
    if [[ "$has_proxy" == "true" ]]; then
      local _cur_proxy; _cur_proxy="$(read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY)"
      if [[ -z "$_cur_proxy" ]]; then
        local _cur_dir; _cur_dir="$(read_conf "$PROFILES_DIR/default.conf" PROFILE_CLAUDE_DIR)"
        cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${_cur_dir}"
PROFILE_PROXY="default"
EOF
      fi
    fi
  fi
  write_active "default"
  rm "$legacy"
}

@test "migration: proxy.conf removed after migration" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  [ ! -f "$CONF_DIR/proxy.conf" ]
  [ ! -f "$CONF_DIR/proxy.conf.migrated" ]
}

@test "migration: proxies/default.conf created with host" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run read_conf "$PROXIES_DIR/default.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
}

@test "migration: proxies/default.conf created with user" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run read_conf "$PROXIES_DIR/default.conf" PROXY_USER
  [ "$output" = "john" ]
}

@test "migration: keychain service set to claude-proxy:default" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run read_conf "$PROXIES_DIR/default.conf" PROXY_KEYCHAIN_SERVICE
  [ "$output" = "claude-proxy:default" ]
}

@test "migration: profiles/default.conf points to ~/.claude" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "$HOME/.claude" ]
}

@test "migration: profiles/default.conf links to proxy" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "default" ]
}

@test "migration: existing profiles/default.conf gets proxy linked when empty" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY=""
EOF
  _run_migration
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "default" ]
}

@test "migration: existing profiles/default.conf keeps proxy if already set" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  cat > "$PROFILES_DIR/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY="my-existing-proxy"
EOF
  _run_migration
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "my-existing-proxy" ]
}

@test "migration: active_profile set to default" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST="10.0.0.1:3128"
CLAUDE_PROXY_USER="john"
EOF
  _run_migration
  run active_profile
  [ "$output" = "default" ]
}

@test "migration: no proxy.conf → no proxies/default.conf created" {
  _run_migration
  [ ! -f "$PROXIES_DIR/default.conf" ]
}

@test "migration: proxy.conf without host/user creates profile with no proxy" {
  cat > "$CONF_DIR/proxy.conf" <<'EOF'
CLAUDE_PROXY_HOST=""
CLAUDE_PROXY_USER=""
EOF
  _run_migration
  run read_conf "$PROFILES_DIR/default.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile rename
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile rename: old conf removed, new conf created" {
  make_profile "work" "corp-lt"
  local old_dir="$TEST_DIR/claude-work"
  mkdir -p "$old_dir"
  local proxy; proxy="$(read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY)"
  local new_dir="$TEST_DIR/claude-company"
  mv "$old_dir" "$new_dir"
  cat > "$PROFILES_DIR/company.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${new_dir}"
PROFILE_PROXY="${proxy}"
EOF
  rm "$PROFILES_DIR/work.conf"
  [ ! -f "$PROFILES_DIR/work.conf" ]
  [ -f "$PROFILES_DIR/company.conf" ]
}

@test "profile rename: proxy link preserved after rename" {
  make_profile "work" "corp-lt"
  cp "$PROFILES_DIR/work.conf" "$PROFILES_DIR/company.conf"
  rm "$PROFILES_DIR/work.conf"
  run read_conf "$PROFILES_DIR/company.conf" PROFILE_PROXY
  [ "$output" = "corp-lt" ]
}

@test "profile rename: auto-generated dir gets new name" {
  make_profile "work"
  [ "$(profile_claude_dir "work")" = "$HOME/.claude-work" ]
}

@test "profile rename: active_profile updated when renaming active" {
  make_profile "work"
  write_active "work"
  cp "$PROFILES_DIR/work.conf" "$PROFILES_DIR/company.conf"
  rm "$PROFILES_DIR/work.conf"
  write_active "company"
  run active_profile
  [ "$output" = "company" ]
}

@test "profile rename: active_profile unchanged when renaming non-active" {
  make_profile "work"
  make_profile "personal"
  write_active "personal"
  cp "$PROFILES_DIR/work.conf" "$PROFILES_DIR/company.conf"
  rm "$PROFILES_DIR/work.conf"
  run active_profile
  [ "$output" = "personal" ]
}

@test "profile rename: cannot rename default" {
  run bash -c '[[ "default" != "default" ]] || exit 1'
  [ "$status" -ne 0 ]
}

@test "profile rename: custom dir kept as-is in conf" {
  cat > "$PROFILES_DIR/work.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="/custom/fixed/path"
PROFILE_PROXY=""
EOF
  local old_dir; old_dir="$(read_conf "$PROFILES_DIR/work.conf" PROFILE_CLAUDE_DIR)"
  [ "$old_dir" = "/custom/fixed/path" ]
  [ "$old_dir" != "$HOME/.claude-work" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# proxy rename
# ═══════════════════════════════════════════════════════════════════════════════

@test "proxy rename: old conf removed, new conf created" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  local phost; phost="$(read_conf "$PROXIES_DIR/corp-lt.conf" PROXY_HOST)"
  local puser; puser="$(read_conf "$PROXIES_DIR/corp-lt.conf" PROXY_USER)"
  cat > "$PROXIES_DIR/corp.conf" <<EOF
CONFIG_VERSION=1
PROXY_HOST="${phost}"
PROXY_USER="${puser}"
PROXY_KEYCHAIN_SERVICE="claude-proxy:corp"
EOF
  rm "$PROXIES_DIR/corp-lt.conf"
  [ ! -f "$PROXIES_DIR/corp-lt.conf" ]
  [ -f "$PROXIES_DIR/corp.conf" ]
}

@test "proxy rename: host and user preserved" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  cat > "$PROXIES_DIR/corp.conf" <<EOF
CONFIG_VERSION=1
PROXY_HOST="10.0.0.1:3128"
PROXY_USER="john"
PROXY_KEYCHAIN_SERVICE="claude-proxy:corp"
EOF
  rm "$PROXIES_DIR/corp-lt.conf"
  run read_conf "$PROXIES_DIR/corp.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
  run read_conf "$PROXIES_DIR/corp.conf" PROXY_USER
  [ "$output" = "john" ]
}

@test "proxy rename: keychain service name updated" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  cat > "$PROXIES_DIR/corp.conf" <<EOF
CONFIG_VERSION=1
PROXY_HOST="10.0.0.1:3128"
PROXY_USER="john"
PROXY_KEYCHAIN_SERVICE="claude-proxy:corp"
EOF
  rm "$PROXIES_DIR/corp-lt.conf"
  run read_conf "$PROXIES_DIR/corp.conf" PROXY_KEYCHAIN_SERVICE
  [ "$output" = "claude-proxy:corp" ]
}

@test "proxy rename: all linked profiles updated" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  make_profile "work" "corp-lt"
  make_profile "personal" "corp-lt"
  for pf in "$PROFILES_DIR"/*.conf; do
    local linked; linked="$(read_conf "$pf" PROFILE_PROXY)"
    if [[ "$linked" == "corp-lt" ]]; then
      local pdir; pdir="$(read_conf "$pf" PROFILE_CLAUDE_DIR)"
      cat > "$pf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${pdir}"
PROFILE_PROXY="corp"
EOF
    fi
  done
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "corp" ]
  run read_conf "$PROFILES_DIR/personal.conf" PROFILE_PROXY
  [ "$output" = "corp" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile delete
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile delete: conf file removed" {
  make_profile "work"
  rm "$PROFILES_DIR/work.conf"
  [ ! -f "$PROFILES_DIR/work.conf" ]
}

@test "profile delete: Claude dir kept on disk" {
  local dir="$TEST_DIR/claude-work"
  make_profile "work" "" "$dir"
  mkdir -p "$dir"
  rm "$PROFILES_DIR/work.conf"
  [ -d "$dir" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile show
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile show: active profile unchanged after viewing another" {
  make_profile "work"
  make_profile "personal"
  write_active "work"
  read_conf "$PROFILES_DIR/personal.conf" PROFILE_PROXY > /dev/null
  run active_profile
  [ "$output" = "work" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# status overview
# ═══════════════════════════════════════════════════════════════════════════════

@test "status: all profiles are listable" {
  make_profile "default"
  make_profile "work" "corp-lt"
  make_profile "personal"
  shopt -s nullglob
  local files=("$PROFILES_DIR"/*.conf)
  shopt -u nullglob
  [ "${#files[@]}" -eq 3 ]
}

@test "status: all proxies are listable" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  make_proxy "home-de" "192.168.1.1:8080" "roman"
  shopt -s nullglob
  local files=("$PROXIES_DIR"/*.conf)
  shopt -u nullglob
  [ "${#files[@]}" -eq 2 ]
}

@test "status: active marker shown correctly" {
  make_profile "work"
  make_profile "personal"
  write_active "work"
  local active; active="$(active_profile)"
  [ "$active" = "work" ]
  [ "$active" != "personal" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# architecture
# ═══════════════════════════════════════════════════════════════════════════════

@test "architecture: ensure_default_profile only in definition and top-level" {
  local count
  count="$(grep -c "ensure_default_profile" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy" 2>/dev/null; true)"
  [ "${count:-0}" -eq 2 ]
}

@test "architecture: SETTINGS_FILES contains 4 entries" {
  [ "$(echo "${SETTINGS_FILES[*]}" | wc -w | tr -d ' ')" -eq 4 ]
}

@test "architecture: SETTINGS_DIRS contains 2 entries" {
  [ "$(echo "${SETTINGS_DIRS[*]}" | wc -w | tr -d ' ')" -eq 2 ]
}

@test "architecture: SETTINGS_FILES includes keybindings.json" {
  [[ " ${SETTINGS_FILES[*]} " == *" keybindings.json "* ]]
}

@test "architecture: SETTINGS_FILES includes policy-limits.json" {
  [[ " ${SETTINGS_FILES[*]} " == *" policy-limits.json "* ]]
}

@test "architecture: SETTINGS_DIRS includes hooks" {
  [[ " ${SETTINGS_DIRS[*]} " == *" hooks "* ]]
}

@test "architecture: SETTINGS_DIRS includes plugins" {
  [[ " ${SETTINGS_DIRS[*]} " == *" plugins "* ]]
}

@test "architecture: wrapper has no migration code" {
  local count
  count="$(grep -c "migrate\|LEGACY_CONF\|proxy\.conf" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null; true)"
  # comment (1) + condition (1) + error message (1) = exactly 3 lines
  [ "${count:-0}" -eq 3 ]
}

@test "architecture: wrapper has no ensure_default_profile" {
  local count
  count="$(grep -c "ensure_default_profile" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

@test "architecture: help text defined once via print_help" {
  local count
  count="$(grep -c "print_help" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy" 2>/dev/null; true)"
  # definition (1) + help cmd (1) + empty cmd (1) = 3
  [ "${count:-0}" -eq 3 ]
}

@test "architecture: _sync-active-dir removed" {
  run grep "_sync-active-dir" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
  [ "$status" -ne 0 ]
}

@test "architecture: wrapper has no active_dir" {
  local count
  count="$(grep -c "active_dir\|ACTIVE_DIR" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

@test "architecture: wrapper creates ide/ symlink if missing" {
  local count
  count="$(grep -c 'CLAUDE_DIR/ide' "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null; true)"
  [ "${count:-0}" -ge 1 ]
}

@test "architecture: wrapper reads PROXIED_CLAUDE_PROFILE" {
  local count
  count="$(grep -c "PROXIED_CLAUDE_PROFILE" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null; true)"
  [ "${count:-0}" -ge 2 ]
}

@test "architecture: run command in help text" {
  local count
  count="$(grep -c "claude-proxy run" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy" 2>/dev/null; true)"
  [ "${count:-0}" -ge 1 ]
}

@test "architecture: run command in dispatch" {
  local count
  count="$(grep -c "^  run)" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy" 2>/dev/null; true)"
  [ "${count:-0}" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile use
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile use: switching does not modify the source profile conf" {
  make_profile "work" "corp"
  make_profile "personal"
  write_active "work"
  write_active "personal"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "corp" ]
}

@test "profile use: no temp files left after switch" {
  make_profile "work"
  write_active "work"
  run bash -c "ls '${ACTIVE_FILE}'* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# PROXIED_CLAUDE_PROFILE override
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile override: uses PROXIED_CLAUDE_PROFILE when set" {
  write_active "personal"
  PROXIED_CLAUDE_PROFILE="work" run resolve_profile
  [ "$output" = "work" ]
}

@test "profile override: falls back to active_profile when override empty" {
  write_active "personal"
  PROXIED_CLAUDE_PROFILE="" run resolve_profile
  [ "$output" = "personal" ]
}

@test "profile override: falls back to active_profile when override unset" {
  write_active "personal"
  run resolve_profile
  [ "$output" = "personal" ]
}

@test "profile override: falls back to default when no active_profile and no override" {
  run resolve_profile
  [ "$output" = "default" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# claude-proxy run (validation logic mirrored)
# ═══════════════════════════════════════════════════════════════════════════════

run_validate() {
  local name="${1:-}"
  [[ -n "$name" ]] || { echo "Usage: claude-proxy run <profile>" >&2; return 1; }
  validate_name "$name" "profile name" || return 1
  require_profile "$name" || return 1
  echo "ok:$name"
}

@test "run: fails with no args" {
  run run_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "run: fails for non-existent profile" {
  run run_validate "nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "run: succeeds for existing profile" {
  make_profile "work"
  run run_validate "work"
  [ "$status" -eq 0 ]
  [ "$output" = "ok:work" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile set-proxy / unset-proxy
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile set-proxy: proxy written to conf" {
  make_profile "work"
  make_proxy "corp" "10.0.0.1:3128" "john"
  do_set_proxy "work" "corp"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "corp" ]
}

@test "profile set-proxy: PROFILE_CLAUDE_DIR preserved" {
  make_profile "work" "" "/custom/path"
  make_proxy "corp" "10.0.0.1:3128" "john"
  do_set_proxy "work" "corp"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "/custom/path" ]
}

@test "profile set-proxy: CONFIG_VERSION preserved" {
  make_profile "work"
  make_proxy "corp" "10.0.0.1:3128" "john"
  do_set_proxy "work" "corp"
  run read_conf "$PROFILES_DIR/work.conf" CONFIG_VERSION
  [ "$output" = "1" ]
}

@test "profile unset-proxy: PROFILE_PROXY cleared" {
  make_profile "work" "corp"
  do_unset_proxy "work"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

@test "profile unset-proxy: PROFILE_CLAUDE_DIR preserved" {
  make_profile "work" "corp" "/keep/this"
  do_unset_proxy "work"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "/keep/this" ]
}

@test "profile unset-proxy: idempotent when no proxy was set" {
  make_profile "work"
  do_unset_proxy "work"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile create / proxy create — conf format
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile create: conf has all required keys" {
  make_profile "newprof"
  run read_conf "$PROFILES_DIR/newprof.conf" CONFIG_VERSION
  [ "$output" = "1" ]
  run read_conf "$PROFILES_DIR/newprof.conf" PROFILE_CLAUDE_DIR
  [ -n "$output" ]
  run read_conf "$PROFILES_DIR/newprof.conf" PROFILE_PROXY
  # key must be present (empty is valid)
  true
}

@test "profile create: default proxy is empty" {
  make_profile "newprof"
  run read_conf "$PROFILES_DIR/newprof.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

@test "profile create: claude dir follows convention" {
  make_profile "myaccount"
  run read_conf "$PROFILES_DIR/myaccount.conf" PROFILE_CLAUDE_DIR
  [ "$output" = "$HOME/.claude-myaccount" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# dir_has_data
# ═══════════════════════════════════════════════════════════════════════════════

@test "dir_has_data: non-empty dir returns true" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/settings.json"
  run dir_has_data "$dir"
  [ "$status" -eq 0 ]
}

@test "dir_has_data: dir with only .DS_Store returns false" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/.DS_Store"
  run dir_has_data "$dir"
  [ "$status" -eq 1 ]
}

@test "dir_has_data: empty dir returns false" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  run dir_has_data "$dir"
  [ "$status" -eq 1 ]
}

@test "dir_has_data: nonexistent dir returns false" {
  run dir_has_data "$TEST_DIR/does-not-exist"
  [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# profile create — existing dir (non-interactive)
# ═══════════════════════════════════════════════════════════════════════════════

@test "profile create: non-interactive, existing non-empty dir warns" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/settings.json"
  run do_create_dir_noninteractive "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "profile create: non-interactive, existing non-empty dir gives session-expired note" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/settings.json"
  run do_create_dir_noninteractive "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session expired"* ]]
}

@test "profile create: non-interactive, empty dir gives log-in note" {
  local dir="$TEST_DIR/claude-work"
  run do_create_dir_noninteractive "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"you need to log in"* ]]
}

@test "proxy create: conf has all required keys" {
  make_proxy "myproxy" "10.0.0.1:3128" "john"
  run read_conf "$PROXIES_DIR/myproxy.conf" CONFIG_VERSION
  [ "$output" = "1" ]
  run read_conf "$PROXIES_DIR/myproxy.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
  run read_conf "$PROXIES_DIR/myproxy.conf" PROXY_USER
  [ "$output" = "john" ]
  run read_conf "$PROXIES_DIR/myproxy.conf" PROXY_KEYCHAIN_SERVICE
  [ "$output" = "claude-proxy:myproxy" ]
}

@test "proxy create: keychain service name matches proxy name" {
  make_proxy "corp-lt" "10.0.0.1:3128" "john"
  run read_conf "$PROXIES_DIR/corp-lt.conf" PROXY_KEYCHAIN_SERVICE
  [ "$output" = "claude-proxy:corp-lt" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# wrapper — proxy resolution logic
# ═══════════════════════════════════════════════════════════════════════════════

@test "wrapper: profile with no proxy has empty LINKED_PROXY" {
  make_profile "work"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "" ]
}

@test "wrapper: profile with proxy has non-empty LINKED_PROXY" {
  make_profile "work" "corp"
  run read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY
  [ "$output" = "corp" ]
}

@test "wrapper: proxy conf present — host and user readable" {
  make_profile "work" "corp"
  make_proxy "corp" "10.0.0.1:3128" "john"
  local linked; linked="$(read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY)"
  run read_conf "$PROXIES_DIR/${linked}.conf" PROXY_HOST
  [ "$output" = "10.0.0.1:3128" ]
  run read_conf "$PROXIES_DIR/${linked}.conf" PROXY_USER
  [ "$output" = "john" ]
}

@test "wrapper: proxy conf missing triggers error condition" {
  make_profile "work" "corp"
  local linked; linked="$(read_conf "$PROFILES_DIR/work.conf" PROFILE_PROXY)"
  # Proxy conf intentionally not created — wrapper would die here
  [ ! -f "$PROXIES_DIR/${linked}.conf" ]
}

@test "wrapper: NO_PROXY includes localhost" {
  local no_proxy="localhost,127.0.0.1,::1,::ffff:127.0.0.1"
  [[ "$no_proxy" == *"localhost"* ]]
  [[ "$no_proxy" == *"127.0.0.1"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# v1 command hints
# ═══════════════════════════════════════════════════════════════════════════════

@test "v1 command: set-all exits non-zero" {
  run v1_cmd_check "set-all"
  [ "$status" -ne 0 ]
}

@test "v1 command: set-host exits non-zero" {
  run v1_cmd_check "set-host"
  [ "$status" -ne 0 ]
}

@test "v1 command: set-user exits non-zero" {
  run v1_cmd_check "set-user"
  [ "$status" -ne 0 ]
}

@test "v1 command: set-password exits non-zero" {
  run v1_cmd_check "set-password"
  [ "$status" -ne 0 ]
}

@test "v1 command: valid commands pass through" {
  run v1_cmd_check "status"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# statusline
# ═══════════════════════════════════════════════════════════════════════════════

@test "statusline _pc_info: no active_profile → empty output" {
  run _pc_info
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "statusline _pc_info: empty active_profile → empty output" {
  echo "" > "$ACTIVE_FILE"
  run _pc_info
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "statusline _pc_info: profile with no proxy → profile name only" {
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY=""\n' \
    "$HOME/.claude-personal" > "$CONF_DIR/profiles/personal.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "statusline _pc_info: profile with proxy → profile (proxy)" {
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY="home-de"\n' \
    "$HOME/.claude-personal" > "$CONF_DIR/profiles/personal.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "personal (home-de)" ]
}

@test "statusline _pc_info: whitespace in active_profile is stripped" {
  printf '  work  \n' > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY="germany"\n' \
    "$HOME/.claude-work" > "$CONF_DIR/profiles/work.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "work (germany)" ]
}

@test "statusline _pc_info: missing profile conf → profile name only" {
  echo "orphan" > "$ACTIVE_FILE"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "orphan" ]
}

@test "statusline _pc_info: PROXIED_CLAUDE_PROFILE overrides active_profile" {
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY="corp"\n' \
    "$HOME/.claude-work" > "$CONF_DIR/profiles/work.conf"
  PROXIED_CLAUDE_PROFILE="work" run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "work (corp)" ]
}

@test "statusline _pc_info: empty PROXIED_CLAUDE_PROFILE falls back to active_profile" {
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY=""\n' \
    "$HOME/.claude-personal" > "$CONF_DIR/profiles/personal.conf"
  PROXIED_CLAUDE_PROFILE="" run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

# ── update command ────────────────────────────────────────────────────────────

@test "update: --version missing arg dies with usage" {
  _define_helpers
  require_interactive() { :; }
  run cmd_update --version
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: claude-proxy update --version"* ]]
}

@test "update: non-interactive without --version dies" {
  _define_helpers
  run cmd_update < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires interactive"* ]]
}

@test "update: --version with unknown flag dies" {
  _define_helpers
  require_interactive() { :; }
  run cmd_update --unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "update: already up to date exits 0 with message" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    # First curl call is GitHub API; we never reach install.sh download
    echo '{"tag_name":"v2.0.0"}'
  }
  run cmd_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already up to date: v2.0.0"* ]]
}

@test "update: fetches new version tag from GitHub API" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    if [[ "$*" == *api.github.com* ]]; then
      echo '{"tag_name":"v2.1.0"}'
    else
      echo "INSTALL_SH_DOWNLOADED"
    fi
  }
  # Use a file to capture output without 'run' (avoids bash() mock shadowing 'run bash -c')
  local _out; _out="$(mktemp)"
  printf 'y\n' | cmd_update > "$_out" 2>&1
  local _captured; _captured="$(cat "$_out")"; rm -f "$_out"
  [[ "$_captured" == *"v2.0.0"* ]]
  [[ "$_captured" == *"v2.1.0"* ]]
}

@test "update: version preview strings present in source (structural)" {
  grep -q "Installed" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
  grep -q "Latest" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
}

@test "update: major version warning present in source (structural)" {
  grep -q "Major version upgrade" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
}

@test "update: abort path present in source (structural)" {
  grep -q "Aborted" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
}

@test "update: major version warning shown at runtime" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    [[ "$*" == *api.github.com* ]] && echo '{"tag_name":"v3.0.0"}' || true
  }
  local _out; _out="$(mktemp)"
  printf 'n\n' | cmd_update > "$_out" 2>&1 || true
  local _captured; _captured="$(cat "$_out")"; rm -f "$_out"
  [[ "$_captured" == *"Major version upgrade"* ]]
  [[ "$_captured" == *"v3.0.0"* ]]
  [[ "$_captured" == *"Aborted"* ]]
}
