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

**Wizard:** Gateway setup is NOT added to the install wizard. HTTP proxy is required for network access in corporate environments (forced setup); gateway is an optional auth method — Claude Code works fine without it. A one-line hint is added to the post-install output alongside existing proxy/profile hints.

**Migration:** No migration needed. `PROFILE_GATEWAY` is a new optional field — existing profile confs without it work unchanged. The only change: `GATEWAYS_DIR` is added to `ensure_dirs()` in `claude-proxy` (line ~91), so the `gateways/` directory is created automatically on the first `claude-proxy` invocation after upgrade.

## Architecture Constraints

- `read_conf` is used everywhere — no `source`/`eval` (injection risk)
- Token never written to conf files — Keychain only
- `gateway delete` checks all profile confs for `PROFILE_GATEWAY=<name>` before deleting; Keychain entry is **not** deleted automatically (user may have the same token stored for other purposes — they remove it manually if needed)
- `gateways/` directory created alongside `proxies/` during install (or lazily on first `gateway create`)