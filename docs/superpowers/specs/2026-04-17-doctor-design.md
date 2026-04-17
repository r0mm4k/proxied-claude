# claude-proxy doctor — Design Spec

**Date:** 2026-04-17
**Status:** Approved (rev 2)

---

## Goal

Add `claude-proxy doctor` — a diagnostic command that audits the full system in one shot. Modelled after `brew doctor`: shows every check with a ✅/❌ symbol, actionable fix commands for failures, exit code signals health.

---

## Command

```bash
claude-proxy doctor
```

No flags. Read-only — never modifies state. No lock acquired.

---

## Output Format

Three sections, printed in order.

**Fail-fast** applies within the **Active profile** section only: a failed check stops the chain for that profile (no point checking Keychain if proxy conf is missing). The `(skipping X check)` message is shown only in this section.

**Other profiles** section checks each profile independently with the same fail-fast logic per profile. Output per profile: one line when passing, error line + fix line when failing. No `(skipping ...)` message.

If the active profile is the only profile, the "Other profiles" section is **omitted entirely** (no header).

### Happy path — multiple profiles

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

### Happy path — single profile (no Other profiles section)

```
  ── System ──────────────────────────────────────────
  ✅ proxied-claude   /usr/local/bin/proxied-claude
  ✅ CLAUDE_BIN       /opt/homebrew/bin/claude

  ── Active profile: default ─────────────────────────
  ✅ profile conf     ~/.config/proxied-claude/profiles/default.conf
  ✅ claude dir       ~/.claude
  ✅ (no proxy)

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
  ❌ personal         proxy conf: home-proxy — file missing
     Fix: claude-proxy proxy create home-proxy <host:port> <user>

  2 issues found.
```

---

## Checks

### Section 1 — System

| Check | Pass condition | Fix shown on fail |
|---|---|---|
| `proxied-claude` | `$WRAPPER_PATH` exists, readable (`-r`), and executable (`-x`) | `bash <(curl -fsSL https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh)` |
| `CLAUDE_BIN` | `$WRAPPER_PATH` readable; `read_conf` returns non-empty value ≠ `__CLAUDE_BIN__`; path exists and is executable; `basename` ≠ `proxied-claude` | `claude-proxy update --force` |

**CLAUDE_BIN failure sub-cases** (shown in the ❌ message detail):
- Wrapper not readable: `proxied-claude not readable — check permissions`
- Value is `__CLAUDE_BIN__`: `not patched — installation incomplete`
- Path not found: `<path> — not found`
- Path not executable: `<path> — not executable`
- Self-loop: `<path> — points to proxied-claude itself`

### Section 2 — Active profile (fail-fast chain)

Active profile = `active_profile()` — returns `"default"` if file missing/empty.

| Check | Pass condition | Fix shown on fail |
|---|---|---|
| profile conf | `$PROFILES_DIR/<name>.conf` exists | `claude-proxy profile create <name>` |
| claude dir | `profile_claude_dir()` path exists on disk | `mkdir -p <dir>` |
| proxy linked? | if `PROFILE_PROXY` empty → show `✅ (no proxy)`, stop chain (all good) | — |
| proxy conf | `$PROXIES_DIR/<proxy>.conf` exists | `claude-proxy proxy create <proxy> <host:port> <user>` |
| proxy fields | `PROXY_HOST` and `PROXY_USER` non-empty in conf | `claude-proxy proxy show <proxy>` |
| keychain | `security find-generic-password` returns non-empty password | `claude-proxy proxy set-password <proxy>` |

Keychain lookup: uses `PROXY_KEYCHAIN_SERVICE` from proxy conf, fallback to `keychain_service()` — same pattern as `proxied-claude` line 123.

### Section 3 — Other profiles

All `$PROFILES_DIR/*.conf` excluding the active profile. If none → section omitted entirely.

Each profile runs the same check chain as Section 2 (including proxy fields check) with the same fail-fast per profile. Compact output: one line when passing, error + fix line when failing.

---

## Exit Code

| Condition | Exit code |
|---|---|
| All checks passed | `0` |
| Any ❌ | `1` |

---

## Implementation

### Location

New function `cmd_doctor()` in `claude-proxy`, placed near `cmd_status`. Dispatched from the top-level `case` block. No lock acquired (read-only).

### Output helpers (cmd_doctor-internal only)

```bash
_doc_ok()   { printf "  ✅ %-18s %s\n" "$1" "$2"; }
_doc_fail() { printf "  ❌ %-18s %s\n" "$1" "$2"; printf "     Fix: %s\n" "$3"; ((_doc_issues++)) || true; }
```

`_doc_issues` is a local integer counter incremented by `_doc_fail`. Note: `((_doc_issues++)) || true` — the `|| true` is required because bash treats `((0))` as exit 1 under `set -e`.

At the end of `cmd_doctor`: if `_doc_issues -eq 0` → print `"  All checks passed."`, exit 0; else → print `"  $_doc_issues issue(s) found."`, exit 1.

These helpers are internal to `cmd_doctor` — not for reuse elsewhere.

### set -e safety

Every fallible command inside `cmd_doctor` must be guarded against `set -euo pipefail`:
- File tests (`[[ -f ]]`, `[[ -x ]]`, `[[ -r ]]`) — safe, no exit
- `read_conf` — already uses `|| true` internally, safe
- `security find-generic-password` — **must** use `|| true`: returns exit 1 when entry not found
- `profile_claude_dir()`, `keychain_service()`, `display_path()` — pure bash, safe

### Helpers reused (no new code needed)

- `read_conf` — reads values from conf files and from `$WRAPPER_PATH`
- `profile_claude_dir()` — resolves claude dir with default fallback
- `keychain_service()` — builds keychain service name
- `display_path()` — `~`-abbreviates paths for output
- `active_profile()` — reads active profile name with `"default"` fallback

### Not checked

- `ide/` symlink — created at runtime by `proxied-claude`, not a failure state
- Proxy connectivity — use `claude-proxy check` for that

---

## Documentation Updates

### `print_help` (claude-proxy ~line 524)

Add to Shortcuts section (same format as existing entries):
```
  claude-proxy doctor          → full system health check
```

### Header comment block (claude-proxy ~line 35)

Add to Shortcuts block:
```
#   claude-proxy doctor          → full system health check
```

### README.md Shortcuts section (~line 249)

Add after `claude-proxy status`:
```
claude-proxy doctor                    # full system health check
```

---

## Tests

Tests in `proxied-claude.bats` using a mirrored `cmd_doctor()` helper inside `_define_helpers()`.

### Test fixture: mocking `$WRAPPER_PATH`

`cmd_doctor` reads `$WRAPPER_PATH` to extract `CLAUDE_BIN`. Tests must:
1. Create a temp file: `WRAPPER_PATH="$(mktemp)"`
2. Write content and make executable:
   ```bash
   printf 'CLAUDE_BIN="%s"\n' "/mock/claude" > "$WRAPPER_PATH"
   chmod +x "$WRAPPER_PATH"
   ```
3. Create the mock `CLAUDE_BIN` target as needed: `touch /tmp/mock-claude && chmod +x /tmp/mock-claude`

### Test fixture: mocking `security`

Override as a shell function (same pattern as `curl` mocking in `cmd_update` tests):
```bash
# Password found:
security() { [[ "$*" == *"find-generic-password"* ]] && echo "mock-password" || true; }

# Password not found (exit 1, no output — same as real Keychain miss):
security() { return 1; }
```

### Test matrix

| Test | What it verifies |
|---|---|
| all checks pass → exit 0, "All checks passed" | happy path |
| active profile has no proxy → `(no proxy)` shown, exit 0 | no-proxy path |
| single profile → no "Other profiles" section | empty section omitted |
| CLAUDE_BIN = `__CLAUDE_BIN__` → ❌ + fix | not patched |
| CLAUDE_BIN path missing → ❌ + fix | stale path |
| CLAUDE_BIN = proxied-claude → ❌ + fix | self-loop |
| profile conf missing → ❌, `(skipping keychain check)`, exit 1 | fail-fast active |
| proxy conf missing → ❌, `(skipping keychain check)`, exit 1 | fail-fast active |
| keychain missing → ❌ + fix, exit 1 | credentials gap |
| other profile with broken proxy → ❌ independent of active | section independence |
| structural: `doctor` in dispatch | architecture |
| structural: `doctor` in help text | architecture |