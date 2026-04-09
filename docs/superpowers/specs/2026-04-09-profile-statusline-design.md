# Design: Active Profile Display in Claude Code Statusline

**Date:** 2026-04-09
**Scope:** Task 13 (statusline only — zsh PS1 excluded)

---

## Problem

When running Claude Code via `proxied-claude`, there is no quick visual indicator of which
profile (and proxy) is currently active. The user must run `claude-proxy profile list` or
`claude-proxy status` to check.

---

## Solution

Add a snippet to the Claude Code `statusline.sh` hook that prepends the active profile
and proxy to the status line:

```
personal › nigeria | ctx:30% | ▲13 ▼5 | $1.22 | 5h:15% ~4h 7d:65% ~2d
```

The snippet ships as documentation in README — zero new binaries, zero installer changes.

---

## Architecture

**Approach:** Inline shell function in `statusline.sh` (no subprocess to `claude-proxy`).

Reads two files directly:
- `~/.config/proxied-claude/active_profile` — profile name
- `~/.config/proxied-claude/profiles/<name>.conf` — `PROFILE_PROXY` value

Uses `grep` + `tr` (POSIX), matching the `read_conf` pattern already used in
`proxied-claude` and `claude-proxy`. No external dependencies, no new files installed.

---

## Implementation

### `_pc_info()` function

```bash
CYAN=$'\033[36m'

_pc_info() {
  local conf="${HOME}/.config/proxied-claude"
  [[ -f "${conf}/active_profile" ]] || return 0
  local profile; profile=$(tr -d '[:space:]' < "${conf}/active_profile")
  [[ -n "$profile" ]] || return 0
  local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
  proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
  [[ -n "$proxy" ]] && printf '%s' "${CYAN}${profile}${R} ${DIM}›${R} ${proxy}" \
                    || printf '%s' "${CYAN}${profile}${R}"
}

PC_INFO=$(_pc_info)
[[ -n "$PC_INFO" ]] && PREFIX="${PC_INFO} ${DIM}|${R} " || PREFIX=""
```

`CYAN` is declared once alongside existing color variables (GREEN, YELLOW, RED, DIM, R).

### Output position

`PREFIX` is prepended to the existing final `printf`:

```bash
printf '%s' "${PREFIX}ctx:$(color_pct "$CTX")${CTX}%${R} ..."
```

### Degradation

| State | Output |
|---|---|
| proxied-claude not installed (`~/.config/proxied-claude/` absent) | nothing — statusline unchanged |
| proxied-claude installed but `active_profile` missing or empty | nothing |
| profile has no proxy | `personal` |
| profile has proxy | `personal › nigeria` |

---

## Changes

| File | Change |
|---|---|
| `README.md` | New section "Claude Code statusline integration" with snippet |
| `~/.claude-personal/hooks/statusline.sh` | User applies snippet manually |
| `TODO.md` | Task 13 updated: statusline only, zsh PS1 excluded |

No changes to `claude-proxy`, `proxied-claude`, or `install.sh`.

---

## Out of scope

- zsh `$PS1` / agnoster segment — excluded, statusline is sufficient
- `claude-proxy profile current` subcommand — not needed, file reads are sufficient
- Automatic patching of `statusline.sh` by installer — snippet is opt-in documentation
