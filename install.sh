#!/usr/bin/env bash
set -euo pipefail

# ─── proxied-claude installer ─────────────────────────────────────────────────
# Installs:
#   /usr/local/bin/proxied-claude   — wrapper (runs Claude with active profile)
#   /usr/local/bin/claude-proxy     — control utility (profiles + proxies)
#
# Config: ~/.config/proxied-claude/
#   profiles/<n>.conf   proxies/<n>.conf   active_profile
#
# Upgrade (preserves all config and migrates v1 automatically):
#   claude-proxy update
#   — or —
#   PROXIED_CLAUDE_UPGRADE=1 bash install.sh
# ─────────────────────────────────────────────────────────────────────────────

VERSION="2.0.0"
WRAPPER_PATH="/usr/local/bin/proxied-claude"
CTL_PATH="/usr/local/bin/claude-proxy"
CONF_DIR="$HOME/.config/proxied-claude"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/r0mm4k/proxied-claude/main}"
IS_UPGRADE="${PROXIED_CLAUDE_UPGRADE:-0}"

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "── $* ──"; }
ok()   { echo "✅ $*"; }
info() { echo "   $*"; }
warn() { echo "⚠️  $*"; }

# Validate name (only safe chars)
validate_name() {
  local name="$1"
  [[ -n "$name" && "$name" =~ ^[a-zA-Z0-9_-]+$ ]]
}

if [[ "$IS_UPGRADE" == "1" ]]; then
  echo "== proxied-claude upgrade v$VERSION =="
else
  echo "== proxied-claude installer v$VERSION =="
fi

# ── 1. Claude binary ────────────────────────────────────────────────────────

step "Claude CLI"

if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
else
  echo "Claude not found — installing via Homebrew..."
  command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install: https://brew.sh"
  brew install claude
  CLAUDE_BIN="$(command -v claude)"
fi
# Prefer canonical Homebrew path on Apple Silicon
[[ -x "/opt/homebrew/bin/claude" ]] && CLAUDE_BIN="/opt/homebrew/bin/claude"
echo "Claude binary: $CLAUDE_BIN"

# ── 2. Config directories ──────────────────────────────────────────────────

step "Config directories"
mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/proxies"
ok "$CONF_DIR"

# ── 3. Download and install binaries ───────────────────────────────────────

step "Installing proxied-claude (sudo required)"

TMP_WRAPPER="$(mktemp)"
TMP_CTL="$(mktemp)"
trap 'rm -f "$TMP_WRAPPER" "$TMP_CTL"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 "${REPO_RAW}/proxied-claude" -o "$TMP_WRAPPER"
sed "s@CLAUDE_BIN=\"__CLAUDE_BIN__\"@CLAUDE_BIN=\"${CLAUDE_BIN}\"@" "$TMP_WRAPPER" > "${TMP_WRAPPER}.patched"
mv "${TMP_WRAPPER}.patched" "$TMP_WRAPPER"
sudo cp "$TMP_WRAPPER" "$WRAPPER_PATH"
sudo chmod +x "$WRAPPER_PATH"
ok "$WRAPPER_PATH"

step "Installing claude-proxy (sudo required)"
curl -fsSL --proto '=https' --tlsv1.2 "${REPO_RAW}/claude-proxy" -o "$TMP_CTL"
sudo cp "$TMP_CTL" "$CTL_PATH"
sudo chmod +x "$CTL_PATH"
ok "$CTL_PATH"

# ── 4. Migrate v1 config if present ────────────────────────────────────────
# Delegation: claude-proxy is now installed, use it as single source of truth.

LEGACY_CONF="$CONF_DIR/proxy.conf"
if [[ -f "$LEGACY_CONF" ]]; then
  step "Migrating v1 config"
  "$CTL_PATH" migrate
fi

# ── 5. Ensure default profile exists (fresh install) ──────────────────────

if [[ ! -f "$CONF_DIR/profiles/default.conf" ]]; then
  cat > "$CONF_DIR/profiles/default.conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="$HOME/.claude"
PROFILE_PROXY=""
EOF
  ok "Created default profile → $HOME/.claude"
fi
if [[ ! -f "$CONF_DIR/active_profile" || ! -s "$CONF_DIR/active_profile" ]]; then
  _tmp="$(mktemp "$CONF_DIR/active_profile.XXXXXX")"
  echo "default" > "$_tmp"
  mv "$_tmp" "$CONF_DIR/active_profile"
fi
"$CTL_PATH" _sync-active-dir

# ── 6. First-run wizard (skipped on upgrade) ─────────────────────────────

if [[ "$IS_UPGRADE" == "1" ]]; then
  echo ""
  ok "Upgrade complete. All your profiles and proxies are unchanged."
  echo ""
  echo "Version : $VERSION"
  echo "Help    : claude-proxy help"
  exit 0
fi

step "Initial setup (optional — press Enter to skip)"
echo "   Tip: you can skip this entirely — the 'default' profile (~/.claude) is ready to use."
echo ""

read -r -p "Create an additional profile now? [y/N] " _do_profile
if [[ "${_do_profile:-}" =~ ^[Yy]$ ]]; then
  read -r -p "Profile name (e.g. work, personal): " _profile_name

  if ! validate_name "${_profile_name:-}"; then
    warn "Invalid name '${_profile_name:-}' — only letters, digits, - and _ allowed. Skipping."
    _profile_name=""
  fi

  if [[ -n "$_profile_name" && "$_profile_name" != "default" ]]; then
    # Delegate to claude-proxy — it handles settings copy interactively
    "$CTL_PATH" profile create "$_profile_name"

    read -r -p "Add a proxy for '$_profile_name'? [y/N] " _do_proxy
    if [[ "${_do_proxy:-}" =~ ^[Yy]$ ]]; then
      read -r -p "Proxy name (e.g. corp-lt): " _proxy_name
      read -r -p "Proxy host (IP:PORT):      " _proxy_host
      read -r -p "Proxy user:                " _proxy_user

      _valid=true
      validate_name "${_proxy_name:-}" || { warn "Invalid proxy name — skipping"; _valid=false; }
      [[ "${_proxy_host:-}" =~ ^[^:]+:[0-9]+$ ]] || \
        { warn "Invalid host format (need hostname:PORT) — skipping"; _valid=false; }
      [[ -n "${_proxy_user:-}" ]] || { warn "User cannot be empty — skipping"; _valid=false; }

      if [[ "$_valid" == "true" ]]; then
        "$CTL_PATH" proxy create "$_proxy_name" "$_proxy_host" "$_proxy_user"
        "$CTL_PATH" profile set-proxy "$_profile_name" "$_proxy_name"
        ok "Proxy '$_proxy_name' linked to '$_profile_name'"
      fi
    fi
  fi
fi

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
ok "Installation complete! v$VERSION"
echo ""
echo "Run 'hash -r' or open a new terminal if commands aren't found yet."
echo ""
echo "Quick start:"
echo "  claude-proxy profile list"
echo "  claude-proxy proxy create corp-lt 10.0.0.1:3128 john"
echo "  claude-proxy profile create work --from default"
echo "  claude-proxy profile set-proxy work corp-lt"
echo "  claude-proxy use work"
echo "  proxied-claude"
echo ""
echo "JetBrains — Settings → Tools → Claude Code [Beta]:"
echo "  Claude command : $WRAPPER_PATH"
echo "  Config dir     : ~/.config/proxied-claude/active_dir"
echo ""
echo "VS Code — settings.json:"
echo "  \"claude.claudePath\": \"$WRAPPER_PATH\""
echo ""
echo "Full help: claude-proxy help"
