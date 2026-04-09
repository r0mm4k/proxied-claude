# profile create — existing directory handling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `profile create <name>` finds `~/.claude-<name>` already contains data, warn the user and offer to start fresh (interactive) or silently use as-is (non-interactive).

**Architecture:** Add a small `dir_has_data()` predicate near Core helpers, move `mkdir -p` out of the lock block, and add branch logic inline in the `create)` case. Mirror the predicate in bats tests.

**Tech Stack:** bash, bats-core

---

## File Map

| File | Change |
|------|--------|
| `claude-proxy` | Add `dir_has_data()` after `ensure_dirs`; modify `create)` case (lines ~468–484) |
| `proxied-claude.bats` | Mirror `dir_has_data()` in `_define_helpers()`; add 4 tests after `profile create` group |

---

### Task 1: Add `dir_has_data()` predicate and failing tests

**Files:**
- Modify: `proxied-claude.bats` — add mirror + 4 tests
- Modify: `claude-proxy` — add predicate (tests will fail until it's there, but predicate is trivial so we add both together)

- [ ] **Step 1: Add mirror of `dir_has_data` to `_define_helpers()` in `proxied-claude.bats`**

Open `proxied-claude.bats`. Find `_define_helpers()` (line ~41). Add after `ensure_dirs`:

```bash
  dir_has_data() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -mindepth 1 -maxdepth 1 -not -name ".DS_Store" \
         -print -quit 2>/dev/null | grep -q .
  }
```

- [ ] **Step 2: Add 4 tests after the `profile create` group (after line ~1348)**

Find the block ending with `@test "profile create: claude dir follows convention"`. Add immediately after:

```bash
# ═══════════════════════════════════════════════════════════════════════════════
# dir_has_data
# ═══════════════════════════════════════════════════════════════════════════════

@test "dir_has_data: non-empty dir returns true" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/settings.json"
  run dir_has_data "$dir"
  [ "$status" -eq 0 ]
}

@test "dir_has_data: dir with only .DS_Store returns false" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  touch "$dir/.DS_Store"
  run dir_has_data "$dir"
  [ "$status" -eq 1 ]
}

@test "dir_has_data: empty dir returns false" {
  local dir="$TEST_DIR/claude-work"
  mkdir -p "$dir"
  run dir_has_data "$dir"
  [ "$status" -eq 1 ]
}

@test "dir_has_data: nonexistent dir returns false" {
  run dir_has_data "$TEST_DIR/does-not-exist"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 3: Run tests — expect 4 failures (function not yet in source)**

```bash
bats proxied-claude.bats --filter "dir_has_data"
```

Expected: 4 tests, all FAIL with something like `dir_has_data: command not found`.

- [ ] **Step 4: Add `dir_has_data()` to `claude-proxy`**

Open `claude-proxy`. Find line 73 (`ensure_dirs() { ... }`). Add immediately after:

```bash
# Returns 0 if dir exists and has data (excluding .DS_Store), 1 otherwise.
dir_has_data() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  find "$dir" -mindepth 1 -maxdepth 1 -not -name ".DS_Store" \
       -print -quit 2>/dev/null | grep -q .
}
```

- [ ] **Step 5: Run tests — expect 4 passing**

```bash
bats proxied-claude.bats --filter "dir_has_data"
```

Expected: 4 tests, all PASS.

- [ ] **Step 6: Run full suite — no regressions**

```bash
bats proxied-claude.bats
```

Expected: all previously passing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: add dir_has_data() predicate with tests"
```

---

### Task 2: Modify `create)` case — move mkdir out of lock, add branch logic

**Files:**
- Modify: `claude-proxy` — `create)` case, lines ~468–484

- [ ] **Step 1: Replace the lock block + mkdir in `create)` case**

Find this block (around line 468):

```bash
      # Lock → create conf + dir → release (short hold)
      lock_acquire
      local conf="$PROFILES_DIR/${name}.conf"
      [[ ! -f "$conf" ]] || die "Profile '$name' already exists."

      local claude_dir="$HOME/.claude-${name}"
      cat > "$conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${claude_dir}"
PROFILE_PROXY=""
EOF
      mkdir -p "$claude_dir"
      lock_release

      ok "Profile '$name' created"
      info "Claude dir : $claude_dir"
      info "Note: you need to log in to Claude the first time you use this profile"
```

Replace with:

```bash
      # Lock → create conf → release (short hold); dir handled below
      lock_acquire
      local conf="$PROFILES_DIR/${name}.conf"
      [[ ! -f "$conf" ]] || die "Profile '$name' already exists."

      local claude_dir="$HOME/.claude-${name}"
      cat > "$conf" <<EOF
CONFIG_VERSION=1
PROFILE_CLAUDE_DIR="${claude_dir}"
PROFILE_PROXY=""
EOF
      lock_release

      local _login_note="Note: you need to log in to Claude the first time you use this profile"

      if dir_has_data "$claude_dir"; then
        if [[ -t 0 ]]; then
          echo ""
          warn "Directory $claude_dir already exists and contains data."
          echo "  Your previous session data and settings are preserved."
          echo ""
          read -r -p "  Start fresh and delete existing data? [y/N] " _fresh
          if [[ "${_fresh:-}" =~ ^[Yy]$ ]]; then
            rm -rf "$claude_dir"
          else
            _login_note="Note: If your session expired, log in again when you first use this profile"
          fi
        else
          warn "Directory $claude_dir already exists and contains data — using as-is"
          _login_note="Note: If your session expired, log in again when you first use this profile"
        fi
      fi
      mkdir -p "$claude_dir"

      ok "Profile '$name' created"
      info "Claude dir : $claude_dir"
      info "$_login_note"
```

- [ ] **Step 2: Run full test suite — no regressions**

```bash
bats proxied-claude.bats
```

Expected: all tests pass.

- [ ] **Step 3: Manual smoke test — non-interactive path**

```bash
# Setup: create a fake claude dir with data
mkdir -p /tmp/test-claude-work
touch /tmp/test-claude-work/settings.json

# Temporarily point HOME to /tmp so profile dir resolves there
# (or just verify the warn appears when running non-interactively via pipe)
echo "" | PROFILES_DIR=/tmp/test-profiles PROXIES_DIR=/tmp/test-proxies \
  ACTIVE_FILE=/tmp/test-active LOCK_DIR=/tmp/test-lock \
  bash -c 'source ./claude-proxy 2>/dev/null; true'
```

Actually — full manual test requires running `claude-proxy profile create` against a real `~/.config`. Do this manually:

```bash
# 1. Create a profile, then delete its conf but leave the dir with data
claude-proxy profile create smoketest
echo "test" > ~/.claude-smoketest/testfile.txt
# Remove conf to simulate "deleted and recreating"
rm ~/.config/proxied-claude/profiles/smoketest.conf

# 2. Recreate — should show warn and prompt (interactive)
claude-proxy profile create smoketest
# Expected output includes:
# ⚠️  Directory ~/.claude-smoketest already exists and contains data.
#    Your previous session data and settings are preserved.
#    Start fresh and delete existing data? [y/N]

# 3. Cleanup
claude-proxy profile delete smoketest
rm -rf ~/.claude-smoketest
```

- [ ] **Step 4: Commit**

```bash
git add claude-proxy
git commit -m "feat: warn and prompt when profile create finds existing dir with data"
```

---

### Task 3: Mark TODO item done

**Files:**
- Modify: `TODO.md`

- [ ] **Step 1: Mark item 3 as done in `TODO.md`**

Find the line:
```
- [ ] 3. **`profile create` — existing directory handling**
```

Change to:
```
- [x] 3. **`profile create` — existing directory handling**
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: mark profile create existing-dir handling as done"
```
