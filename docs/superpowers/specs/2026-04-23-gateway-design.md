# Gateway Support Design

**Date:** 2026-04-23  
**Status:** Approved

## Context

proxied-claude currently supports one auth path: corporate HTTP proxy (network-level routing via `HTTP_PROXY`/`HTTPS_PROXY`). A second auth method has appeared at work: LiteLLM — an LLM gateway that replaces the Anthropic API endpoint. These two are orthogonal: a profile can use both simultaneously (HTTP proxy routes traffic, LiteLLM authorises model access).

The feature is named "gateway" rather than "litellm" to stay provider-agnostic — any future OpenAI-compatible LLM gateway fits the same model.

## Data Model

### New resource: `gateways/<n>.conf`

```ini
CONFIG_VERSION=1
GATEWAY_URL="https://litellm.corp.example.com:4000"
GATEWAY_KEYCHAIN_SERVICE="claude-proxy-gateway:corporate"   # optional override
```

- `GATEWAY_URL` — the base URL passed to Claude Code as `ANTHROPIC_BASE_URL`
- `GATEWAY_KEYCHAIN_SERVICE` — optional Keychain service name override (default: `claude-proxy-gateway:<name>`)
- Token stored in Keychain: `security find-generic-password -a "<name>" -s "<service>" -w`
- No `GATEWAY_USER` field — the gateway name itself is the Keychain account (`-a`)

### Profile conf change

One new optional field in `profiles/<n>.conf`:

```ini
PROFILE_GATEWAY="corporate"
```

Fully backwards-compatible — profiles without `PROFILE_GATEWAY` are unaffected.

## Commands

### New `claude-proxy gateway` group

```bash
claude-proxy gateway create <name> <url>   # create gateways/<n>.conf
claude-proxy gateway list                   # list all gateways
claude-proxy gateway show <name>            # print gateway conf
claude-proxy gateway delete <name>          # delete conf; warn if used by any profile
claude-proxy gateway set-token <name>       # store token in Keychain interactively
```

### New profile subcommands

```bash
claude-proxy profile set-gateway <profile> <gateway>   # link gateway to profile
claude-proxy profile unset-gateway <profile>            # unlink
```

### Example workflow

```bash
claude-proxy gateway create corporate https://litellm.corp.com:4000
claude-proxy gateway set-token corporate     # prompts for token → Keychain
claude-proxy profile set-gateway work corporate
```

### `claude-proxy doctor` additions

- Linked gateway conf exists
- Gateway token is present in Keychain

## Launcher (`proxied-claude`)

Inserted after the proxy block (after line ~133), before `exec "$CLAUDE_BIN"`:

```bash
# ── Apply gateway if linked ──────────────────────────────────────────────────

LINKED_GATEWAY="$(read_conf "$PROFILE_CONF" PROFILE_GATEWAY)"

if [[ -n "$LINKED_GATEWAY" ]]; then
  GATEWAY_CONF="$CONF_DIR/gateways/${LINKED_GATEWAY}.conf"
  [[ -f "$GATEWAY_CONF" ]] || die "Gateway '$LINKED_GATEWAY' (profile '$PROFILE') not found.
  Fix: claude-proxy profile unset-gateway $PROFILE
  Or:  claude-proxy gateway create $LINKED_GATEWAY <url>"

  GATEWAY_URL="$(read_conf "$GATEWAY_CONF" GATEWAY_URL)"
  KEYCHAIN_GW_SVC="$(read_conf "$GATEWAY_CONF" GATEWAY_KEYCHAIN_SERVICE)"

  [[ -n "$GATEWAY_URL" ]] || die "Gateway '$LINKED_GATEWAY' missing GATEWAY_URL."

  KEYCHAIN_GW_SVC="${KEYCHAIN_GW_SVC:-claude-proxy-gateway:${LINKED_GATEWAY}}"
  GATEWAY_TOKEN="$(security find-generic-password -a "$LINKED_GATEWAY" -s "$KEYCHAIN_GW_SVC" -w 2>/dev/null || true)"
  [[ -n "$GATEWAY_TOKEN" ]] || die "Token for gateway '$LINKED_GATEWAY' not in Keychain.
  Fix: claude-proxy gateway set-token $LINKED_GATEWAY"

  export ANTHROPIC_BASE_URL="$GATEWAY_URL"
  export ANTHROPIC_AUTH_TOKEN="$GATEWAY_TOKEN"
fi
```

**Note:** The architecture test checks the exact line count of `proxied-claude` — update the expected count after adding this block.

## Tests (`proxied-claude.bats`)

Three new test groups:

### `gateway` group
- `gateway create` — creates conf with correct fields
- `gateway list` — lists existing gateways
- `gateway show` — prints conf
- `gateway delete` — removes conf; warns when profile still links it
- `gateway set-token` — stores token in Keychain (mocked `security`)

### `profile gateway` group
- `profile set-gateway` — writes `PROFILE_GATEWAY` to profile conf
- `profile unset-gateway` — removes `PROFILE_GATEWAY` from profile conf
- Error when gateway does not exist

### `launcher gateway` group
- Profile with gateway → `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` exported correctly
- Profile with both proxy and gateway → all four env vars exported
- Profile without gateway → vars not set
- Missing gateway conf → launcher exits with clear error
- Missing Keychain token → launcher exits with clear error

## Install & Migration

### `install.sh` changes

**Step 2 — Config directories (line 95):** Add `gateways/` to `mkdir`:
```bash
mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/proxies" "$CONF_DIR/gateways" "$CONF_DIR/ide"
```

**Step 2 — Header comment (line 10):** Update to mention `gateways/`:
```
#   profiles/<n>.conf   proxies/<n>.conf   gateways/<n>.conf   active_profile
```

**New function `validate_gateway_inputs`** — placed alongside `validate_proxy_inputs`:
```bash
# Validate gateway wizard inputs; emits warnings and returns 1 on failure.
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
  printf '%s' "Gateway name (e.g. corp-gw):                    " >&2; read -r _def_gw_name
  printf '%s' "Gateway URL  (e.g. https://litellm.corp.com:4000): " >&2; read -r _def_gw_url

  if validate_gateway_inputs "${_def_gw_name:-}" "${_def_gw_url:-}"; then
    "$CTL_PATH" gateway create "$_def_gw_name" "$_def_gw_url"
    "$CTL_PATH" profile set-gateway default "$_def_gw_name"
    ok "Gateway '$_def_gw_name' linked to 'default'"
    info "Store the token: claude-proxy gateway set-token $_def_gw_name"
  fi
fi
```

**Wizard — additional profile** (after proxy block for `$_profile_name`, before closing `fi`):
```bash
printf '%s' "Add a gateway for '$_profile_name'? [y/N] " >&2; read -r _do_gw
if [[ "${_do_gw:-}" =~ ^[Yy]$ ]]; then
  printf '%s' "Gateway name (e.g. corp-gw):                       " >&2; read -r _gw_name
  printf '%s' "Gateway URL  (e.g. https://litellm.corp.com:4000): " >&2; read -r _gw_url

  if validate_gateway_inputs "${_gw_name:-}" "${_gw_url:-}"; then
    "$CTL_PATH" gateway create "$_gw_name" "$_gw_url"
    "$CTL_PATH" profile set-gateway "$_profile_name" "$_gw_name"
    ok "Gateway '$_gw_name' linked to '$_profile_name'"
    info "Store the token: claude-proxy gateway set-token $_gw_name"
  fi
fi
```

Note: `gateway create` in wizard does NOT call `set-token` — consistent with proxy wizard not calling `set-password`. The `info` line reminds the user what to do next. If a gateway with the same name already exists (e.g. user enters same name for default and additional profile), `gateway create` must handle gracefully (skip creation, still link).

**Quick start hints** — add one line after existing proxy/profile examples:
```
echo "  claude-proxy gateway create corp-gw https://litellm.corp.com:4000"
```

### Migration

No migration needed. `PROFILE_GATEWAY` is a new optional field — existing profile confs without it work unchanged. Existing installs get `gateways/` created automatically on the first `claude-proxy` invocation after upgrade (via `ensure_dirs()` — see `claude-proxy` changes below).

### `claude-proxy` changes for dirs

`ensure_dirs()` (line ~91) — add `GATEWAYS_DIR`:
```bash
GATEWAYS_DIR="$CONF_DIR/gateways"
ensure_dirs() { mkdir -p "$PROFILES_DIR" "$PROXIES_DIR" "$GATEWAYS_DIR"; }
```

## Architecture Constraints

- `read_conf` is used everywhere — no `source`/`eval` (injection risk)
- Token never written to conf files — Keychain only
- `gateway delete` checks all profile confs for `PROFILE_GATEWAY=<name>` before deleting; Keychain entry is **not** deleted automatically (user may have the same token stored for other purposes — they remove it manually if needed)
- `gateway create` is idempotent on name collision: if conf already exists, skip creation but do not error — wizard can safely call it even if user enters the same gateway name for multiple profiles
- `gateways/` directory created in step 2 of install, and in `ensure_dirs()` for upgrades