# Design: `profile create` — existing directory handling

**Date:** 2026-04-09
**Status:** Approved

## Problem

`profile create <name>` runs `mkdir -p ~/.claude-<name>` unconditionally. If the directory already exists with data from a previous profile lifecycle (e.g. user deleted and recreated a profile), the data is silently reused. The user has no chance to start fresh or even know data was preserved.

## Scope

Single command: `claude-proxy profile create <name>`. No other commands affected.

---

## Design

### 1. New predicate: `dir_has_data()`

Added near other core helpers in `claude-proxy`:

```bash
# Returns 0 if dir exists and contains data (excluding .DS_Store), 1 otherwise
dir_has_data() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  find "$dir" -mindepth 1 -maxdepth 1 -not -name ".DS_Store" \
       -print -quit 2>/dev/null | grep -q .
}
```

**Why `find` over nullglob+glob:** `*` glob without `dotglob` misses hidden files like `.credentials.json`. `find` with `-not -name ".DS_Store"` is the simplest correct approach.

**Why exclude `.DS_Store`:** macOS creates it automatically; it carries no user data and should not trigger the prompt.

### 2. Lock block change

`mkdir -p "$claude_dir"` is moved out of the lock block. The lock only needs to cover conf creation (short hold, as the existing comment states). Directory creation does not need the lock — the profile name is already "claimed" by the conf file.

**Before:**
```bash
lock_acquire
  check conf → create conf → mkdir -p
lock_release
```

**After:**
```bash
lock_acquire
  check conf → create conf
lock_release
# dir check + mkdir/rm-rf here
```

### 3. Existing-dir logic (inline in `create)` case)

After the lock is released:

```bash
local _login_note="Note: you need to log in to Claude the first time you use this profile"

if dir_has_data "$claude_dir"; then
  if [[ -t 0 ]]; then
    # Interactive: prompt user
    echo ""
    warn "Directory $claude_dir already exists and contains data."
    echo "  Your previous session data and settings are preserved."
    echo ""
    read -r -p "  Start fresh and delete existing data? [y/N] " _fresh
    if [[ "${_fresh:-}" =~ ^[Yy]$ ]]; then
      rm -rf "$claude_dir"
      # _login_note stays as "you need to log in"
    else
      _login_note="Note: If your session expired, log in again when you first use this profile"
    fi
  else
    # Non-interactive: silently use existing dir + warn
    warn "Directory $claude_dir already exists and contains data — using as-is"
    _login_note="Note: If your session expired, log in again when you first use this profile"
  fi
fi
mkdir -p "$claude_dir"

ok "Profile '$name' created"
info "Claude dir : $claude_dir"
info "$_login_note"
```

**`_login_note` as variable** avoids duplicating `ok`/`info` calls across branches.

**`mkdir -p` always runs** — after `rm -rf` (Y path) or as no-op for existing dir (N/non-interactive), or as normal creation when dir doesn't exist.

### 4. Behavior matrix

| Condition | Interactive | Result |
|-----------|-------------|--------|
| Dir doesn't exist | any | `mkdir -p`, normal login note |
| Dir exists, empty | any | `mkdir -p` (no-op), normal login note |
| Dir has data | non-interactive | `warn`, use as-is, "session expired" note |
| Dir has data | interactive, N (default) | use as-is, "session expired" note |
| Dir has data | interactive, Y | `rm -rf` + `mkdir`, normal login note |

---

## Testing

Mirrored helper `dir_has_data()` added to `_define_helpers()` in `proxied-claude.bats` — exact copy of the source function.

Four test cases:

| Test | Input | Expected |
|------|-------|----------|
| `dir_has_data: non-empty dir returns true` | dir with `settings.json` | status 0 |
| `dir_has_data: dir with only .DS_Store returns false` | dir with `.DS_Store` only | status 1 |
| `dir_has_data: empty dir returns false` | empty dir | status 1 |
| `dir_has_data: nonexistent dir returns false` | no dir | status 1 |

The interactive Y/N prompt is not tested in bats (no TTY). Non-interactive behavior is covered by `dir_has_data` tests.

---

## Files changed

- `claude-proxy` — add `dir_has_data()`, modify `create)` case
- `proxied-claude.bats` — mirror `dir_has_data()`, add 4 tests