# claude-proxy doctor — Design Spec

**Date:** 2026-04-17
**Status:** Approved

---

## Goal

Add `claude-proxy doctor` — a diagnostic command that audits the full system in one shot. Modelled after `brew doctor`: shows every check with a ✅/❌ symbol, actionable fix commands for failures, exit code signals health.

---

## Command

```bash
claude-proxy doctor
```

No flags. Read-only — never modifies state.

---

## Output Format

Three sections, printed in order. Each section uses fail-fast: within the **Active profile** section, a failed check stops further checks in that chain (no point checking Keychain if proxy conf is missing). The **Other profiles** section checks each profile independently.

### Happy path

```
  ── System ──────────────────────────────────────────
  ✅ proxied-claude   /usr/local/bin/proxied-claude
  ✅ CLAUDE_BIN       /opt/homebrew/bin/claude

  ── Active profile: work ────────────────────────────
  ✅ profile conf     ~/.config/proxied-claude/profiles/work.conf
  ✅ claude dir       ~/.claude-work
  ✅ proxy            corp-lt
  ✅ keychain         corp-lt  password found

  ── Other profiles ──────────────────────────────────
  ✅ default          (no proxy)
  ✅ personal         keychain: home-proxy password found

  All checks passed.
```

### With failures

```
  ── System ──────────────────────────────────────────
  ✅ proxied-claude   /usr/local/bin/proxied-claude
  ❌ CLAUDE_BIN       /opt/homebrew/bin/claude — not found
     Fix: claude-proxy update --force

  ── Active profile: work ────────────────────────────
  ✅ profile conf     ~/.config/proxied-claude/profiles/work.conf
  ✅ claude dir       ~/.claude-work
  ❌ proxy conf       corp-lt — file missing
     Fix: claude-proxy proxy create corp-lt <host:port> <user>
     (skipping keychain check)

  ── Other profiles ──────────────────────────────────
  ✅ default          (no proxy)
  ❌ personal         keychain: home-proxy password not found
     Fix: claude-proxy proxy set-password home-proxy

  2 issues found.
```

---

## Checks

### Section 1 — System

| Check | Pass condition | Fix shown on fail |
|---|---|---|
| `proxied-claude` | `$WRAPPER_PATH` exists and is executable | `bash <(curl -fsSL .../install.sh)` |
| `CLAUDE_BIN` | Read from installed wrapper via `read_conf "$WRAPPER_PATH" CLAUDE_BIN`; value ≠ `__CLAUDE_BIN__`; path exists and is executable; `basename` ≠ `proxied-claude` | `claude-proxy update --force` |

### Section 2 — Active profile (fail-fast chain)

Active profile = `active_profile` file content, fallback `"default"`.

| Check | Pass condition | Fix shown on fail |
|---|---|---|
| profile conf | `$PROFILES_DIR/<name>.conf` exists | `claude-proxy profile create <name>` |
| claude dir | `profile_claude_dir()` path exists on disk | `mkdir -p <dir>` |
| proxy conf | if `PROFILE_PROXY` set: `$PROXIES_DIR/<proxy>.conf` exists | `claude-proxy proxy create <proxy> <host:port> <user>` |
| proxy fields | `PROXY_HOST` and `PROXY_USER` non-empty in conf | `claude-proxy proxy show <proxy>` |
| keychain | `security find-generic-password` returns non-empty password (uses `PROXY_KEYCHAIN_SERVICE` from conf, fallback `keychain_service()`) | `claude-proxy proxy set-password <proxy>` |

If `PROFILE_PROXY` is empty, skip proxy/keychain checks — show `(no proxy)`.

### Section 3 — Other profiles

All profiles in `$PROFILES_DIR/*.conf` excluding the active one. Each checked independently (same chain as Section 2, same fail-fast per profile). Compact output: one line per profile, error + fix on next line if failed.

---

## Exit Code

| Condition | Exit code |
|---|---|
| All checks passed | `0` |
| Any ❌ | `1` |

---

## Implementation

### Location

New function `cmd_doctor()` in `claude-proxy`. Dispatched from the top-level `case` alongside `status`, `check`, etc.

### Helpers reused (no new code needed)

- `read_conf` — reads values from conf files and from `$WRAPPER_PATH`
- `profile_claude_dir()` — resolves claude dir with default fallback
- `keychain_service()` — builds keychain service name
- `display_path()` — `~`-abbreviates paths for output
- `active_profile()` — reads active profile name

### New helper

```bash
_doc_ok()   { printf "  ✅ %-18s %s\n" "$1" "$2"; }
_doc_fail() { printf "  ❌ %-18s %s\n" "$1" "$2"; printf "     Fix: %s\n" "$3"; }
```

### Not checked

- `ide/` symlink — created at runtime by `proxied-claude`, not a failure state
- Proxy connectivity — use `claude-proxy check` for that

---

## Help text

Add to `print_help`:
```
  claude-proxy doctor          → full system health check
```

Add to header comment block.

---

## Tests

All tests via mirrored helper in `proxied-claude.bats` (same pattern as `cmd_update`).

| Test | What it verifies |
|---|---|
| all checks pass → exit 0, "All checks passed" | happy path |
| CLAUDE_BIN = `__CLAUDE_BIN__` → ❌ + fix | not installed properly |
| CLAUDE_BIN path missing → ❌ + fix | stale path |
| CLAUDE_BIN = proxied-claude → ❌ + fix | self-loop |
| profile conf missing → ❌, keychain skipped | fail-fast |
| proxy conf missing → ❌, keychain skipped | fail-fast |
| keychain missing → ❌ + fix | credentials gap |
| other profile with broken proxy → ❌ independent of active | section independence |
| structural: `doctor` in dispatch | architecture |
| structural: `doctor` in help text | architecture |