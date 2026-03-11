# Claude CLI + Corporate Proxy (macOS)

Unofficial wrapper that runs [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) through a corporate **HTTP CONNECT** proxy on macOS, with the password stored securely in **Keychain**.

> ⚠️ This is an independent community tool, not affiliated with or endorsed by Anthropic.  
> You need your own Claude subscription or API access.

---

## Features

- Proxy applied automatically on every `proxied-claude` run
- Password stored in **macOS Keychain** — never written to disk in plaintext
- `localhost` is **not** proxied (WebStorm / IDE bridge keeps working)
- `claude-proxy` utility for easy host / user / password management

---

## Requirements

- macOS (uses `security` CLI for Keychain access)
- [Homebrew](https://brew.sh)
- Claude CLI (installed automatically if missing)

---

## Quick install

```bash
chmod +x ./install.sh
./install.sh
```

The script will:
1. Install Claude CLI via Homebrew if not present
2. Ask for proxy host (`IP:PORT`), username, and Keychain service name
3. Save the password to Keychain (interactive prompt)
4. Create `/usr/local/bin/proxied-claude` — the wrapper
5. Create `/usr/local/bin/claude-proxy` — the control utility

---

## Manual install

### 1. Install Claude CLI

```bash
brew install claude
claude --version
```

### 2. Create config directory

```bash
mkdir -p ~/.config/proxied-claude
```

Config file: `~/.config/proxied-claude/proxy.conf`

### 3. Create wrapper: `proxied-claude`

```bash
sudo nano /usr/local/bin/proxied-claude
```

```bash
#!/bin/bash
set -euo pipefail

CLAUDE_BIN="/opt/homebrew/bin/claude"
CONF="$HOME/.config/proxied-claude/proxy.conf"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -x "$CLAUDE_BIN" ]] || die "Claude binary not found: $CLAUDE_BIN"
[[ -f "$CONF" ]] || die "Proxy config not found: $CONF (run: claude-proxy set-all IP:PORT USER)"

# shellcheck disable=SC1090
source "$CONF"

: "${CLAUDE_PROXY_HOST:?Missing CLAUDE_PROXY_HOST}"
: "${CLAUDE_PROXY_USER:?Missing CLAUDE_PROXY_USER}"
: "${CLAUDE_PROXY_KEYCHAIN_SERVICE:=claude-proxy}"

PASS="$(security find-generic-password -a "$CLAUDE_PROXY_USER" -s "$CLAUDE_PROXY_KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
[[ -n "$PASS" ]] || die "Proxy password not found in Keychain (service=$CLAUDE_PROXY_KEYCHAIN_SERVICE, account=$CLAUDE_PROXY_USER)"

PROXY="http://${CLAUDE_PROXY_USER}:${PASS}@${CLAUDE_PROXY_HOST}"

export HTTPS_PROXY="$PROXY"
export HTTP_PROXY="$PROXY"
# Do not proxy localhost — keeps the IDE ↔ Claude bridge working
export NO_PROXY="localhost,127.0.0.1,::1,::ffff:127.0.0.1"
export no_proxy="$NO_PROXY"

exec "$CLAUDE_BIN" "$@"
```

```bash
sudo chmod +x /usr/local/bin/proxied-claude
```

### 4. Create control utility: `claude-proxy`

```bash
sudo nano /usr/local/bin/claude-proxy
```

```bash
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
  claude-proxy update
  claude-proxy uninstall
EOC
    exit 1
    ;;
esac
```

```bash
sudo chmod +x /usr/local/bin/claude-proxy
```

### 5. Save password to Keychain

```bash
# Replace YOUR_USER with your proxy username
security add-generic-password -a YOUR_USER -s claude-proxy -U -w
```

---

## WebStorm / JetBrains IDE integration

### 1. Install the plugin

**Settings → Plugins → Marketplace** → search for **Claude Code [Beta]** → Install → Restart IDE.

### 2. Configure the Claude command

**Settings → Tools → Claude Code [Beta]** → Claude command:

```
/usr/local/bin/proxied-claude
```

Restart the IDE.

---

## Usage

### Manage proxy settings

```bash
# Update to latest version
claude-proxy update

# Uninstall
claude-proxy uninstall

# Show current config
claude-proxy status

# Set host + user + password in one go
claude-proxy set-all 10.0.0.1:3128 john

# Change only host
claude-proxy set-host 10.0.0.1:3128

# Change only user
claude-proxy set-user john

# Update password (prompts securely)
claude-proxy set-password
```

### Run Claude through the proxy

```bash
proxied-claude --version
proxied-claude
```

> Tip: `claude-proxy` manages config + Keychain; `proxied-claude` runs Claude with `HTTP_PROXY`/`HTTPS_PROXY` set.

---

## How it works

```
proxied-claude
  └─ reads ~/.config/proxied-claude/proxy.conf
  └─ fetches password from macOS Keychain
  └─ sets HTTP_PROXY / HTTPS_PROXY
  └─ exec → claude (original binary)
```

`localhost` is always excluded from proxying via `NO_PROXY`, so the IDE ↔ Claude bridge is unaffected.

---

## Uninstall

```bash
claude-proxy uninstall
```

---

## Limitations

- macOS only (Keychain dependency)
- HTTP CONNECT proxies only — SOCKS is not supported by Claude CLI
- `CLAUDE_BIN` path is fixed at install time — if Claude is reinstalled to a different path, update it in `/usr/local/bin/proxied-claude`
- Proxy password is visible in `ps aux` via `HTTPS_PROXY` while Claude is running — acceptable on a personal Mac, but be aware on shared machines

---

## License

MIT
