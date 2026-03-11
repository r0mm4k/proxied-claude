#!/usr/bin/env bash
set -euo pipefail

WRAPPER_PATH="/usr/local/bin/proxied-claude"
CTL_PATH="/usr/local/bin/claude-proxy"
CONF_DIR="$HOME/.config/proxied-claude"
CONF_FILE="$CONF_DIR/proxy.conf"

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "── $* ──"; }

echo "== Claude Proxy Uninstall =="

# ── 1. Remove wrapper and control utility ────────────────────────────────────
step "Removing binaries (sudo required)"
sudo rm -f "$WRAPPER_PATH" && echo "OK: removed $WRAPPER_PATH" || echo "SKIP: $WRAPPER_PATH not found"
sudo rm -f "$CTL_PATH"     && echo "OK: removed $CTL_PATH"     || echo "SKIP: $CTL_PATH not found"

# ── 2. Remove password from Keychain ─────────────────────────────────────────
step "Removing Keychain password"
if [[ -f "$CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  KEYCHAIN_SERVICE="${CLAUDE_PROXY_KEYCHAIN_SERVICE:-claude-proxy}"
  KEYCHAIN_USER="${CLAUDE_PROXY_USER:-}"

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
else
  echo "SKIP: config not found, skipping Keychain cleanup"
fi

# ── 3. Remove config directory ───────────────────────────────────────────────
step "Removing config"
if [[ -d "$CONF_DIR" ]]; then
  rm -rf "$CONF_DIR"
  echo "OK: removed $CONF_DIR"
else
  echo "SKIP: $CONF_DIR not found"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo "✅  Done! proxied-claude has been uninstalled."
