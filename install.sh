#!/usr/bin/env bash
set -euo pipefail

# ====== Settings you may want to change ======
CLAUDE_BIN_DEFAULT="/opt/homebrew/bin/claude"
CONF_DIR="$HOME/.config/proxied-claude"
CONF_FILE="$CONF_DIR/proxy.conf"
WRAPPER_PATH="/usr/local/bin/proxied-claude"
CTL_PATH="/usr/local/bin/claude-proxy"
KEYCHAIN_SERVICE_DEFAULT="claude-proxy"
# ============================================

die()  { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
step() { echo; echo "── $* ──"; }

echo "== Claude Proxy Setup =="

# ── 1. Ensure claude binary exists ──────────────────────────────────────────
step "Checking Claude CLI"
if have claude; then
  CLAUDE_BIN="$(command -v claude)"
else
  echo "Claude not found — installing via Homebrew..."
  have brew || die "Homebrew not found. Install it first: https://brew.sh"
  brew install claude
  CLAUDE_BIN="$(command -v claude)"
fi

# Prefer the canonical Homebrew path on Apple Silicon
if [[ -x "$CLAUDE_BIN_DEFAULT" ]]; then
  CLAUDE_BIN="$CLAUDE_BIN_DEFAULT"
fi
echo "Claude binary: $CLAUDE_BIN"

# ── 2. Gather proxy settings ─────────────────────────────────────────────────
step "Proxy configuration"

SKIP_PASSWORD=false

if [[ -f "$CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  echo "Existing config found:"
  echo "  Host: ${CLAUDE_PROXY_HOST}"
  echo "  User: ${CLAUDE_PROXY_USER}"
  read -r -p "Keep current settings? [Y/n] " keep
  if [[ ! "${keep:-}" =~ ^[Nn]$ ]]; then
    PROXY_HOST="$CLAUDE_PROXY_HOST"
    PROXY_USER="$CLAUDE_PROXY_USER"
    KEYCHAIN_SERVICE="${CLAUDE_PROXY_KEYCHAIN_SERVICE:-$KEYCHAIN_SERVICE_DEFAULT}"
    SKIP_PASSWORD=true
    echo "OK: keeping current settings"
  fi
fi

if [[ "$SKIP_PASSWORD" == "false" ]]; then
  read -r -p "Proxy host (IP:PORT): " PROXY_HOST
  [[ -n "${PROXY_HOST}" ]] || die "Proxy host is required."

  read -r -p "Proxy user: " PROXY_USER
  [[ -n "${PROXY_USER}" ]] || die "Proxy user is required."

  read -r -p "Keychain service name [${KEYCHAIN_SERVICE_DEFAULT}]: " KEYCHAIN_SERVICE
  KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE:-$KEYCHAIN_SERVICE_DEFAULT}"
fi

# ── 3. Write config file ─────────────────────────────────────────────────────
step "Writing config"
mkdir -p "$CONF_DIR"
if [[ "$SKIP_PASSWORD" == "false" ]]; then
  cat > "$CONF_FILE" <<EOF
CLAUDE_PROXY_HOST="${PROXY_HOST}"
CLAUDE_PROXY_USER="${PROXY_USER}"
CLAUDE_PROXY_KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE}"
EOF
  echo "Config: $CONF_FILE"
else
  echo "Skipping — keeping existing config"
fi

# ── 4. Create wrapper: proxied-claude ────────────────────────────────────────
step "Installing wrapper (sudo required)"
sudo mkdir -p "$(dirname "$WRAPPER_PATH")"
sudo tee "$WRAPPER_PATH" >/dev/null <<EOF
#!/bin/bash
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN}"
CONF="\$HOME/.config/proxied-claude/proxy.conf"

die() { echo "ERROR: \$*" >&2; exit 1; }

[[ -x "\$CLAUDE_BIN" ]] || die "Claude binary not found: \$CLAUDE_BIN"
[[ -f "\$CONF" ]] || die "Proxy config not found: \$CONF (run: claude-proxy set-all IP:PORT USER)"

# shellcheck disable=SC1090
source "\$CONF"

: "\${CLAUDE_PROXY_HOST:?Missing CLAUDE_PROXY_HOST}"
: "\${CLAUDE_PROXY_USER:?Missing CLAUDE_PROXY_USER}"
: "\${CLAUDE_PROXY_KEYCHAIN_SERVICE:=claude-proxy}"

PASS="\$(security find-generic-password -a "\$CLAUDE_PROXY_USER" -s "\$CLAUDE_PROXY_KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
[[ -n "\$PASS" ]] || die "Proxy password not found in Keychain (service=\$CLAUDE_PROXY_KEYCHAIN_SERVICE, account=\$CLAUDE_PROXY_USER)"

PROXY="http://\${CLAUDE_PROXY_USER}:\${PASS}@\${CLAUDE_PROXY_HOST}"

export HTTPS_PROXY="\$PROXY"
export HTTP_PROXY="\$PROXY"
# Do not proxy localhost — keeps the IDE ↔ Claude bridge working
export NO_PROXY="localhost,127.0.0.1,::1,::ffff:127.0.0.1"
export no_proxy="\$NO_PROXY"

exec "\$CLAUDE_BIN" "\$@"
EOF
sudo chmod +x "$WRAPPER_PATH"
echo "OK: $WRAPPER_PATH"

# ── 5. Create control utility: claude-proxy ──────────────────────────────────
step "Installing control utility (sudo required)"
sudo tee "$CTL_PATH" >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

CONF="$HOME/.config/proxied-claude/proxy.conf"
DIR="$(dirname "$CONF")"

die() { echo "ERROR: $*" >&2; exit 1; }

ensure_conf() {
  mkdir -p "$DIR"
  if [[ ! -f "$CONF" ]]; then
    cat > "$CONF" <<'EOC'
CLAUDE_PROXY_HOST=""
CLAUDE_PROXY_USER=""
CLAUDE_PROXY_KEYCHAIN_SERVICE="claude-proxy"
EOC
  fi
}

load_conf() {
  # shellcheck disable=SC1090
  source "$CONF"
  : "${CLAUDE_PROXY_KEYCHAIN_SERVICE:=claude-proxy}"
}

write_conf() {
  cat > "$CONF" <<EOC
CLAUDE_PROXY_HOST="${CLAUDE_PROXY_HOST}"
CLAUDE_PROXY_USER="${CLAUDE_PROXY_USER}"
CLAUDE_PROXY_KEYCHAIN_SERVICE="${CLAUDE_PROXY_KEYCHAIN_SERVICE}"
EOC
}

cmd="${1:-}"
shift || true

case "$cmd" in
  status)
    ensure_conf
    cat "$CONF"
    ;;

  set-host)
    [[ $# -eq 1 ]] || die "Usage: claude-proxy set-host IP:PORT"
    ensure_conf; load_conf
    CLAUDE_PROXY_HOST="$1"; write_conf
    echo "OK: host → $CLAUDE_PROXY_HOST"
    ;;

  set-user)
    [[ $# -eq 1 ]] || die "Usage: claude-proxy set-user USER"
    ensure_conf; load_conf
    CLAUDE_PROXY_USER="$1"; write_conf
    echo "OK: user → $CLAUDE_PROXY_USER"
    ;;

  set-password)
    ensure_conf; load_conf
    [[ -n "${CLAUDE_PROXY_USER:-}" ]] || die "Set user first: claude-proxy set-user USER"
    security add-generic-password -a "$CLAUDE_PROXY_USER" -s "$CLAUDE_PROXY_KEYCHAIN_SERVICE" -U -w
    echo "OK: password updated in Keychain"
    ;;

  set-all)
    [[ $# -eq 2 ]] || die "Usage: claude-proxy set-all IP:PORT USER"
    ensure_conf; load_conf
    CLAUDE_PROXY_HOST="$1"; CLAUDE_PROXY_USER="$2"; write_conf
    security add-generic-password -a "$CLAUDE_PROXY_USER" -s "$CLAUDE_PROXY_KEYCHAIN_SERVICE" -U -w
    echo "OK: host/user updated, password saved in Keychain"
    ;;

  check)
    ensure_conf; load_conf

    [[ -n "${CLAUDE_PROXY_HOST:-}" ]] || die "Proxy host not set (run: claude-proxy set-host IP:PORT)"
    [[ -n "${CLAUDE_PROXY_USER:-}" ]] || die "Proxy user not set (run: claude-proxy set-user USER)"

    PASS="$(security find-generic-password \
      -a "$CLAUDE_PROXY_USER" \
      -s "$CLAUDE_PROXY_KEYCHAIN_SERVICE" \
      -w 2>/dev/null || true)"
    [[ -n "$PASS" ]] || die "Proxy password not found in Keychain"

    TARGET="https://api.anthropic.com"
    PROXY_URL="http://${CLAUDE_PROXY_USER}:${PASS}@${CLAUDE_PROXY_HOST}"

    echo "Checking proxy: ${CLAUDE_PROXY_HOST}"
    echo "User:           ${CLAUDE_PROXY_USER}"
    echo "Target:         ${TARGET}"
    echo

    # ── 1. TCP reachability ────────────────────────────────────────────────
    PROXY_IP="${CLAUDE_PROXY_HOST%%:*}"
    PROXY_PORT="${CLAUDE_PROXY_HOST##*:}"
    [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || die "Invalid proxy host format, expected IP:PORT (got: $CLAUDE_PROXY_HOST)"

    printf "  %-35s" "TCP connect to proxy..."
    _tcp_ok=false
    if command -v nc >/dev/null 2>&1; then
      nc -z -w 5 "$PROXY_IP" "$PROXY_PORT" 2>/dev/null && _tcp_ok=true || true
    elif curl -s --max-time 5 -o /dev/null \
        "http://$PROXY_IP:$PROXY_PORT" 2>/dev/null; then
      _tcp_ok=true
    fi
    if [[ "$_tcp_ok" == "true" ]]; then
      echo "✅  OK"
    else
      echo "❌  FAILED (host unreachable or port closed)"
      exit 1
    fi

    # ── 2. Anthropic API reachability ─────────────────────────────────────
    printf "  %-35s" "Anthropic API reachability..."
    API_CODE="$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time 15 \
      --proxy "$PROXY_URL" \
      --proxytunnel \
      "${TARGET}/v1/models" \
      -H "x-api-key: invalid-check" \
      -H "anthropic-version: 2023-06-01" 2>/dev/null || true)"

    case "$API_CODE" in
      200|401|403)
        echo "✅  OK (HTTP $API_CODE — API is reachable)"
        ;;
      000)
        echo "❌  FAILED — no response / timeout"
        exit 1
        ;;
      *)
        echo "⚠️   HTTP $API_CODE — unexpected, but proxy tunnel works"
        ;;
    esac

    echo
    echo "✅  Proxy is working correctly."
    ;;

  uninstall)
    ensure_conf; load_conf
    echo "This will remove proxied-claude, claude-proxy, config, and Keychain password."
    read -r -p "Are you sure? [y/N] " confirm
    [[ "${confirm:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

    WRAPPER_PATH="/usr/local/bin/proxied-claude"
    CTL_PATH="/usr/local/bin/claude-proxy"
    CONF_DIR="$HOME/.config/proxied-claude"

    if [[ -f "$WRAPPER_PATH" ]]; then
      sudo rm "$WRAPPER_PATH" && echo "OK: removed $WRAPPER_PATH"
    else
      echo "SKIP: $WRAPPER_PATH not found"
    fi

    if [[ -f "$CTL_PATH" ]]; then
      sudo rm "$CTL_PATH" && echo "OK: removed $CTL_PATH"
    else
      echo "SKIP: $CTL_PATH not found"
    fi

    KEYCHAIN_USER="${CLAUDE_PROXY_USER:-}"
    KEYCHAIN_SERVICE="${CLAUDE_PROXY_KEYCHAIN_SERVICE:-claude-proxy}"
    if [[ -n "$KEYCHAIN_USER" ]]; then
      if security delete-generic-password \
          -a "$KEYCHAIN_USER" \
          -s "$KEYCHAIN_SERVICE" 2>/dev/null; then
        echo "OK: removed Keychain entry (service=$KEYCHAIN_SERVICE, account=$KEYCHAIN_USER)"
      else
        echo "SKIP: Keychain entry not found"
      fi
    else
      echo "SKIP: no user in config, skipping Keychain cleanup"
    fi

    if [[ -d "$CONF_DIR" ]]; then
      rm -rf "$CONF_DIR" && echo "OK: removed $CONF_DIR"
    else
      echo "SKIP: $CONF_DIR not found"
    fi

    echo
    echo "✅  Done! proxied-claude has been uninstalled."
    ;;

  update)
    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT
    curl -fsSL https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh -o "$TMP"
    bash "$TMP"
    ;;

  *)
    cat <<EOC
Usage:
  claude-proxy status
  claude-proxy set-host  IP:PORT
  claude-proxy set-user  USER
  claude-proxy set-password
  claude-proxy set-all   IP:PORT USER
  claude-proxy check
  claude-proxy update
  claude-proxy uninstall
EOC
    exit 1
    ;;
esac
EOF
sudo chmod +x "$CTL_PATH"
echo "OK: $CTL_PATH"

# ── 6. Save password to Keychain ─────────────────────────────────────────────
step "Saving password to Keychain"
if [[ "$SKIP_PASSWORD" == "true" ]]; then
  echo "Skipping — keeping existing Keychain entry"
else
  security add-generic-password -a "$PROXY_USER" -s "$KEYCHAIN_SERVICE" -U -w
  echo "OK: password stored"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo "✅  Done!"
echo
echo "Test:"
echo "  $WRAPPER_PATH --version"
echo
echo "Manage proxy:"
echo "  claude-proxy status"
echo "  claude-proxy set-all IP:PORT USER"
