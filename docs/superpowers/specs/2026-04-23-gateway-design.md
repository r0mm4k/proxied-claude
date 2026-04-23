# Gateway Support Design

**Date:** 2026-04-23
**Status:** Approved (rev 2 — full review pass)

## Context

proxied-claude currently supports one auth path: corporate HTTP proxy (network-level routing via `HTTP_PROXY`/`HTTPS_PROXY`). A second auth method has appeared at work: LiteLLM — an LLM gateway that replaces the Anthropic API endpoint. These two are orthogonal: a profile can use both simultaneously (HTTP proxy routes traffic, LiteLLM authorises model access).

The feature is named "gateway" rather than "litellm" to stay provider-agnostic — any future OpenAI-compatible LLM gateway fits the same model.

---

## Data Model

### New resource: `gateways/<n>.conf`

```ini
CONFIG_VERSION=1
GATEWAY_URL="https://litellm.corp.example.com:4000"
GATEWAY_KEYCHAIN_SERVICE="claude-proxy-gateway:corporate"   # optional override
```

- `GATEWAY_URL` — the base URL passed to Claude Code as `ANTHROPIC_BASE_URL`
- `GATEWAY_KEYCHAIN_SERVICE` — optional override (default: `claude-proxy-gateway:<name>`)
- Token stored in Keychain: `security find-generic-password -a "<name>" -s "<service>" -w`
- No `GATEWAY_USER` field — the gateway name itself is the Keychain account (`-a`)

### Profile conf change

New optional field added to `profiles/<n>.conf`:

```ini
PROFILE_GATEWAY="corporate"
```

Fully backwards-compatible — profiles without `PROFILE_GATEWAY` are unaffected.

### Critical: `write_profile_conf` must gain a 4th param

`write_profile_conf(file, dir, proxy)` is the single source of truth for profile conf. Every write site that doesn't pass gateway will silently **erase** `PROFILE_GATEWAY`. The function must become:

```bash
write_profile_conf() {
  local file="$1" dir="$2" proxy="$3" gateway="${4:-}"
  cat > "$file" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${dir}"
PROFILE_PROXY="${proxy}"
PROFILE_GATEWAY="${gateway}"
EOF
}
```

**All call sites** must be updated to pass the current gateway value. Where modifying an existing profile, read `PROFILE_GATEWAY` first:

| Call site | What to pass as gateway |
|-----------|------------------------|
| `profile create` (new profile) | `""` |
| `profile set-proxy` | `read_conf "$conf" PROFILE_GATEWAY` |
| `profile unset-proxy` | `read_conf "$conf" PROFILE_GATEWAY` |
| `profile rename` | `read_conf "$old_conf" PROFILE_GATEWAY` |
| `unlink_proxy_from_profiles` | `read_conf "$pf" PROFILE_GATEWAY` |
| `ensure_default_profile` / step 5 | `""` |
| `set-gateway` (new) | value being set |
| `unset-gateway` (new) | `""` |

---

## New Helpers in `claude-proxy`

### Variables (alongside existing PROXIES_DIR)

```bash
GATEWAYS_DIR="$CONF_DIR/gateways"
```

### Functions

```bash
# Single source of truth for gateway conf format.
write_gateway_conf() {
  local file="$1" url="$2" svc="$3"
  cat > "$file" <<EOF
CONFIG_VERSION=1
GATEWAY_URL="${url}"
GATEWAY_KEYCHAIN_SERVICE="${svc}"
EOF
}

# Default Keychain service name for a gateway.
gateway_keychain_service() { printf 'claude-proxy-gateway:%s\n' "${1}"; }

require_gateway() {
  [[ -f "$GATEWAYS_DIR/${1}.conf" ]] || \
    die "Gateway '$1' does not exist. Run: claude-proxy gateway list"
}

# Returns space-separated list of profile names using this gateway.
profiles_using_gateway() {
  local gw_name="$1" result=""
  shopt -s nullglob
  for pf in "$PROFILES_DIR"/*.conf; do
    local linked; linked="$(read_conf "$pf" PROFILE_GATEWAY)"
    [[ "$linked" == "$gw_name" ]] && result="${result}$(basename "$pf" .conf) "
  done
  shopt -u nullglob
  printf '%s' "$result"
}

# Unlink gateway from all profiles that reference it.
unlink_gateway_from_profiles() {
  local gw_name="$1"
  shopt -s nullglob
  for pf in "$PROFILES_DIR"/*.conf; do
    local linked; linked="$(read_conf "$pf" PROFILE_GATEWAY)"
    if [[ "$linked" == "$gw_name" ]]; then
      local pdir;  pdir="$(read_conf  "$pf" PROFILE_CLAUDE_DIR)"
      local proxy; proxy="$(read_conf "$pf" PROFILE_PROXY)"
      write_profile_conf "$pf" "$pdir" "$proxy" ""
      info "Unlinked gateway from profile '$(basename "$pf" .conf)'"
    fi
  done
  shopt -u nullglob
}
```

### `ensure_dirs` update

```bash
ensure_dirs() { mkdir -p "$PROFILES_DIR" "$PROXIES_DIR" "$GATEWAYS_DIR"; }
```

---

## Commands

### New `claude-proxy gateway` group

```bash
claude-proxy gateway create <name> <url>   # create gateways/<n>.conf + prompt for token
claude-proxy gateway list                   # list all gateways with usage
claude-proxy gateway show <name>            # print gateway conf + token status
claude-proxy gateway delete <name>          # unlink from profiles, delete Keychain, delete conf
claude-proxy gateway rename <old> <new>     # rename conf + update all linked profiles + migrate Keychain
claude-proxy gateway set-token <name>       # update token in Keychain interactively
```

`gateway create` prompts for the token immediately — consistent with `proxy create` prompting for password. Non-interactive creation is not supported (same as proxy).

`gateway delete` **deletes** the Keychain entry — consistent with `proxy delete`. No orphan tokens left.

`gateway rename` migrates the Keychain entry and updates all linked profiles — consistent with `proxy rename`.

### New profile subcommands

```bash
claude-proxy profile set-gateway <profile> <gateway>   # link gateway to profile
claude-proxy profile unset-gateway <profile>            # unlink
```

### Example workflow

```bash
claude-proxy gateway create corporate https://litellm.corp.com:4000
# ↑ prompts for token interactively → stored in Keychain
claude-proxy profile set-gateway work corporate
```

---

## Updated Outputs (commands that show profile info)

### `profile list`

Add GATEWAY column:

```
  PROFILE               PROXY               GATEWAY              DIR
  -------               -----               -------              ---
  default               corp-lt             (no gateway)         ~/.claude        ◀ active
  work                  corp-lt             corporate            ~/.claude-work
```

### `profile use`

Add gateway line:

```
✅ Switched to profile 'work'
   Claude dir : ~/.claude-work
   Proxy      : corp-lt
   Gateway    : corporate
```

### `profile show`

Add gateway block (mirrors proxy block pattern):

```
  Profile        : work  ◀ active
  Claude dir     : ~/.claude-work
  Proxy          : corp-lt
    Proxy host   : 10.0.0.1:3128
    Proxy user   : john
  Gateway        : corporate
    Gateway URL  : https://litellm.corp.com:4000
    Token in KC  : yes
```

If gateway conf is missing, warn and show fix hint (same pattern as proxy).

### `profile delete`

Warn about gateway if set (mirrors current proxy warning):

```
✅ Profile 'work' deleted
   Claude dir kept on disk: ~/.claude-work
   To also delete data: rm -rf ~/.claude-work
   Proxy 'corp-lt' was linked — it still exists, not deleted
   Gateway 'corporate' was linked — it still exists, not deleted
```

### `cmd_status`

Add gateway to active profile block and profiles table; add "All gateways" section:

```
  ── Active profile ─────────────────────────────
  Profile    : work
  Claude dir : ~/.claude-work
  Proxy      : corp-lt
    Host     : 10.0.0.1:3128
    User     : john
  Gateway    : corporate
    URL      : https://litellm.corp.com:4000

  ── All profiles ───────────────────────────────
  default               (no proxy)         (no gateway)  ◀
  work                  corp-lt            corporate

  ── All proxies ────────────────────────────────
  corp-lt               john@10.0.0.1:3128

  ── All gateways ───────────────────────────────
  corporate             https://litellm.corp.com:4000

  ── IDE integration ────────────────────────────
  Command    : /usr/local/bin/proxied-claude
  Config dir : ~/.config/proxied-claude
```

### `gateway list`

```
  GATEWAY               URL                                       USED BY PROFILES
  -------               ---                                       ----------------
  corporate             https://litellm.corp.com:4000            work
  personal              https://my-gw.example.com:8080           (unused)
```

### `gateway show`

```
  Gateway          : corporate
  URL              : https://litellm.corp.com:4000
  Keychain service : claude-proxy-gateway:corporate
  Token in KC      : yes
```

---

## Updated `uninstall`

Info text and Keychain cleanup must cover gateways:

```
This will remove:
  /usr/local/bin/proxied-claude
  /usr/local/bin/claude-proxy
  ~/.config/proxied-claude  (all profiles, proxy configs, gateway configs, active_profile, shared ide/)
  All Keychain entries for managed proxies and gateways
```

Loop through `gateways/*.conf` and delete Keychain entries — parallel to the existing proxy loop.

---

## Updated `cmd_update` message

```
Your profiles, proxies, gateways and settings are preserved.
```

---

## Updated Header Comment in `claude-proxy`

Add gateway commands to the top-of-file comment block (lines 1-37):

```bash
# Gateway commands:
#   claude-proxy gateway list
#   claude-proxy gateway create <n> <url>
#   claude-proxy gateway delete <n>
#   claude-proxy gateway rename  <old> <new>
#   claude-proxy gateway set-token <n>
#   claude-proxy gateway show  <n>
```

---

## Updated Help Text (`print_help`)

```
Gateway commands:
  claude-proxy gateway list
  claude-proxy gateway create <n> <url>
  claude-proxy gateway delete <n>
  claude-proxy gateway rename  <old> <new>
  claude-proxy gateway set-token <n>
  claude-proxy gateway show  <n>
```

Add to profile commands section:
```
  claude-proxy profile set-gateway   <profile> <gateway>
  claude-proxy profile unset-gateway <profile>
```

---

## Launcher (`proxied-claude`)

Inserted after the proxy block (~line 133), before `exec "$CLAUDE_BIN"`:

```bash
# ── Apply gateway if linked ──────────────────────────────────────────────────

LINKED_GATEWAY="$(read_conf "$PROFILE_CONF" PROFILE_GATEWAY)"

if [[ -n "$LINKED_GATEWAY" ]]; then
  GATEWAY_CONF="$CONF_DIR/gateways/${LINKED_GATEWAY}.conf"
  [[ -f "$GATEWAY_CONF" ]] || die "Gateway '$LINKED_GATEWAY' (profile '$PROFILE') not found.
  Fix: claude-proxy profile unset-gateway $PROFILE
  Or:  claude-proxy gateway create $LINKED_GATEWAY <url>"

  GW_URL="$(read_conf "$GATEWAY_CONF" GATEWAY_URL)"
  GW_KEYCHAIN_SVC="$(read_conf "$GATEWAY_CONF" GATEWAY_KEYCHAIN_SERVICE)"

  [[ -n "$GW_URL" ]] || die "Gateway '$LINKED_GATEWAY' missing GATEWAY_URL."

  GW_KEYCHAIN_SVC="${GW_KEYCHAIN_SVC:-claude-proxy-gateway:${LINKED_GATEWAY}}"
  GW_TOKEN="$(security find-generic-password -a "$LINKED_GATEWAY" -s "$GW_KEYCHAIN_SVC" -w 2>/dev/null || true)"
  [[ -n "$GW_TOKEN" ]] || die "Token for gateway '$LINKED_GATEWAY' not in Keychain.
  Fix: claude-proxy gateway set-token $LINKED_GATEWAY"

  export ANTHROPIC_BASE_URL="$GW_URL"
  export ANTHROPIC_AUTH_TOKEN="$GW_TOKEN"
fi
```

**Note:** Architecture test checks exact line count of `proxied-claude` — update expected count after adding this block (~20 lines).

---

## Tests (`proxied-claude.bats`)

### `gateway` group

- `gateway create` — creates conf with correct fields, prompts for token, stores in Keychain
- `gateway create` duplicate — dies with "already exists"
- `gateway list` — lists gateways with URL and used-by info; empty state message
- `gateway show` — prints all fields + token status
- `gateway delete` — unlinks from all profiles, removes Keychain entry, removes conf
- `gateway delete` used by profile — warns, asks for confirmation
- `gateway rename` — renames conf, migrates Keychain entry, updates all linked profiles
- `gateway rename` to existing name — dies
- `gateway set-token` — updates Keychain entry for existing gateway

### `profile gateway` group

- `profile set-gateway` — writes `PROFILE_GATEWAY` to profile conf; preserves `PROFILE_PROXY`
- `profile unset-gateway` — clears `PROFILE_GATEWAY`; preserves `PROFILE_PROXY`
- `profile set-gateway` to non-existent gateway — dies
- `profile set-proxy` — preserves `PROFILE_GATEWAY` (regression guard)
- `profile unset-proxy` — preserves `PROFILE_GATEWAY` (regression guard)
- `profile rename` — preserves `PROFILE_GATEWAY` in new conf (regression guard)

### `launcher gateway` group

- Profile with gateway — `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` exported correctly
- Profile with both proxy and gateway — all four env vars set
- Profile without gateway — `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` not set
- Missing gateway conf — launcher exits with clear error message
- Missing Keychain token — launcher exits with clear error message

---

## Install & Migration

### `install.sh` changes

**Step 2 — Config directories (line 95):** Add `gateways/`:
```bash
mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/proxies" "$CONF_DIR/gateways" "$CONF_DIR/ide"
```

**Step 2 — Header comment (line 10):**
```
#   profiles/<n>.conf   proxies/<n>.conf   gateways/<n>.conf   active_profile
```

**New function `validate_gateway_inputs`** — placed alongside `validate_proxy_inputs`:
```bash
validate_gateway_inputs() {
  local name="$1" url="$2"
  local _ok=true
  validate_name "${name:-}" || { warn "Invalid gateway name — skipping"; _ok=false; }
  [[ "${url:-}" =~ ^https?:// ]] || \
    { warn "Invalid URL (must start with http:// or https://) — skipping"; _ok=false; }
  [[ "$_ok" == "true" ]]
}
```

**Wizard — default profile** (after proxy block, before `echo ""`):
```bash
printf '%s' "Set up an LLM gateway for the 'default' profile? [y/N] " >&2; read -r _do_default_gw
if [[ "${_do_default_gw:-}" =~ ^[Yy]$ ]]; then
  printf '%s' "Gateway name (e.g. corp-gw):                       " >&2; read -r _def_gw_name
  printf '%s' "Gateway URL  (e.g. https://litellm.corp.com:4000): " >&2; read -r _def_gw_url

  if validate_gateway_inputs "${_def_gw_name:-}" "${_def_gw_url:-}"; then
    "$CTL_PATH" gateway create "$_def_gw_name" "$_def_gw_url"
    # gateway create prompts for token interactively (same as proxy create prompts for password)
    "$CTL_PATH" profile set-gateway default "$_def_gw_name"
    ok "Gateway '$_def_gw_name' linked to 'default'"
  fi
fi
```

**Wizard — additional profile** (after proxy block for `$_profile_name`, before closing `fi`).
Handles the case where the user enters the same gateway name as the default profile — check first:
```bash
printf '%s' "Add a gateway for '$_profile_name'? [y/N] " >&2; read -r _do_gw
if [[ "${_do_gw:-}" =~ ^[Yy]$ ]]; then
  printf '%s' "Gateway name (e.g. corp-gw):                       " >&2; read -r _gw_name
  printf '%s' "Gateway URL  (e.g. https://litellm.corp.com:4000): " >&2; read -r _gw_url

  if validate_gateway_inputs "${_gw_name:-}" "${_gw_url:-}"; then
    # Create only if not already exists (user may reuse a gateway created for default profile)
    if [[ ! -f "$CONF_DIR/gateways/${_gw_name}.conf" ]]; then
      "$CTL_PATH" gateway create "$_gw_name" "$_gw_url"
    else
      info "Gateway '$_gw_name' already exists — reusing"
    fi
    "$CTL_PATH" profile set-gateway "$_profile_name" "$_gw_name"
    ok "Gateway '$_gw_name' linked to '$_profile_name'"
  fi
fi
```

**Quick start hints** — add after existing proxy/profile examples:
```bash
echo "  claude-proxy gateway create corp-gw https://litellm.corp.com:4000"
echo "  claude-proxy profile set-gateway work corp-gw"
```

### Migration

No migration needed. `PROFILE_GATEWAY` is a new optional field — existing profile confs without it read as empty string via `read_conf`, which is treated as "no gateway". `gateways/` is created in `ensure_dirs()` (called on every `claude-proxy` invocation), so it appears automatically on first use after upgrade.

---

## Architecture Constraints

- `read_conf` everywhere — no `source`/`eval`
- Token never written to conf files — Keychain only
- `gateway delete`: unlinks from all profiles AND deletes Keychain entry AND removes conf (consistent with `proxy delete`)
- `gateway rename`: migrates Keychain entry, updates all linked profile confs, renames conf (consistent with `proxy rename`)
- `write_profile_conf` gains 4th param `gateway`; all call sites pass current gateway value — no silent data loss
- `gateway create` is interactive (prompts for token) — consistent with `proxy create`; non-interactive use not supported
- Wizard for additional profile checks `gateways/<n>.conf` existence before calling `gateway create` — safe if user reuses a gateway name