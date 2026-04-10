# Shared IDE Dir (remove active_dir) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `active_dir` symlink mechanism with a shared `~/.config/proxied-claude/ide/` directory so profile switching works without IDE restart.

**Architecture:** Plugin Config directory is changed from `active_dir` (symlink) to `~/.config/proxied-claude` (real path). All profile `ide/` subdirectories become symlinks to `~/.config/proxied-claude/ide/`. The plugin caches the physical path once and always writes lock files to the shared dir — every profile's CLI finds them via its `ide/` symlink.

**Tech Stack:** bash, bats (bats-core)

**Spec:** `docs/superpowers/specs/2026-04-10-shared-ide-dir-design.md`

---

## File Map

| File | Change |
|------|--------|
| `proxied-claude.bats` | Remove 5 active_dir tests + setup variable + helper line; add 5 new tests |
| `claude-proxy` | Remove ACTIVE_DIR var + write_active ln + _sync-active-dir cmd; add ide/ logic in ensure_default_profile + profile create; update text in print_help + status + uninstall |
| `proxied-claude` | Remove ACTIVE_DIR var + active_dir block; add ide/ safety net; update header comment |
| `install.sh` | Replace `_sync-active-dir` call with migration loop; add `mkdir -p ide`; update IDE hint |
| `CLAUDE.md` | Remove active_dir from architecture, gotchas, component list |
| `CHANGELOG.md` | Replace active_dir entry with shared ide/ entry |
| `README.md` | Update flow diagram + IDE integration section |
| `TODO.md` | Mark #26 done; remove active_dir mention from #7 |

---

## Task 1: Clean up test suite — remove active_dir tests

**Files:**
- Modify: `proxied-claude.bats`

- [ ] **Step 1: Remove `ACTIVE_DIR` from test setup**

In `setup()` (around line 30), delete this line:
```bash
export ACTIVE_DIR="$CONF_DIR/active_dir"
```

- [ ] **Step 2: Remove `ln -sfn` from `write_active` helper**

In `_define_helpers()`, the `write_active` function (around line 65–69) becomes:
```bash
  write_active() {
    local tmp; tmp="$(mktemp "${ACTIVE_FILE}.XXXXXX")"
    echo "$1" > "$tmp"; mv "$tmp" "$ACTIVE_FILE"
  }
```
Delete the line: `ln -sfn "$(profile_claude_dir "$1")" "$ACTIVE_DIR"`

- [ ] **Step 3: Delete 4 `write_active: active_dir *` tests**

Delete these four tests in full (lines ~453–484):
```
@test "write_active: creates active_dir symlink" { … }
@test "write_active: active_dir points to correct claude dir" { … }
@test "write_active: active_dir updates when profile switches" { … }
@test "write_active: active_dir differs per profile" { … }
```

- [ ] **Step 4: Delete `profile use: active_dir updated after use` test**

Delete this test in full (lines ~1471–1478):
```
@test "profile use: active_dir updated after use" { … }
```

- [ ] **Step 5: Run full test suite to confirm no regression**

```bash
cd /Users/r0mm4k/Developer/My/proxied-claude
bats proxied-claude.bats
```
Expected: all remaining tests pass. Count of passing tests is 5 fewer than before.

- [ ] **Step 6: Commit**

```bash
git add proxied-claude.bats
git commit -m "test: remove active_dir tests (behaviour being deleted)"
```

---

## Task 2: Add failing tests for new behaviour

**Files:**
- Modify: `proxied-claude.bats`

- [ ] **Step 1: Add `profile create: ide/ is a symlink pointing to shared dir`**

Add after the `write_active` block of tests (after the last deleted test gap, before the `read_conf` section):
```bash
# ═══════════════════════════════════════════════════════════════════════════════
# ide/ shared symlink
# ═══════════════════════════════════════════════════════════════════════════════

@test "ide/: symlink created when dir does not exist" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir"
  # mirrors profile create logic
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ -L "$claude_dir/ide" ]
  [ "$(readlink "$claude_dir/ide")" = "$CONF_DIR/ide" ]
}

@test "ide/: real dir replaced by symlink (N-branch migration)" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir/ide"
  touch "$claude_dir/ide/59993.lock"   # stale lock file
  # mirrors profile create / install.sh migration logic
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ -L "$claude_dir/ide" ]
  [ "$(readlink "$claude_dir/ide")" = "$CONF_DIR/ide" ]
  [ ! -f "$claude_dir/ide/59993.lock" ]   # stale file gone
}

@test "ide/: existing symlink not touched" {
  mkdir -p "$CONF_DIR/ide"
  local claude_dir="$TEST_DIR/claude-work"
  mkdir -p "$claude_dir"
  ln -s "$CONF_DIR/ide" "$claude_dir/ide"
  local before; before="$(readlink "$claude_dir/ide")"
  # apply logic again — should be a no-op
  [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }
  [ "$(readlink "$claude_dir/ide")" = "$before" ]
}
```

- [ ] **Step 2: Add architecture tests**

Find the `architecture:` test block (around line 1408). Replace:
```bash
@test "architecture: _sync-active-dir not in print_help" {
  run grep "_sync-active-dir" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
  [[ "$output" != *"print_help"* ]]
}
```
With:
```bash
@test "architecture: _sync-active-dir removed" {
  run grep "_sync-active-dir" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
  [ "$status" -ne 0 ]
}

@test "architecture: wrapper has no active_dir" {
  local count
  count="$(grep -c "active_dir\|ACTIVE_DIR" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null || echo 0)"
  [ "$count" -eq 0 ]
}

@test "architecture: wrapper creates ide/ symlink if missing" {
  local count
  count="$(grep -c 'CLAUDE_DIR/ide' "$(dirname "$BATS_TEST_FILENAME")/proxied-claude" 2>/dev/null || echo 0)"
  [ "$count" -ge 1 ]
}
```

- [ ] **Step 3: Run new tests to confirm they fail**

```bash
bats proxied-claude.bats --filter "ide/"
bats proxied-claude.bats --filter "architecture: _sync-active-dir removed"
bats proxied-claude.bats --filter "architecture: wrapper has no active_dir"
bats proxied-claude.bats --filter "architecture: wrapper creates ide/"
```
Expected: `ide/` tests PASS (they test pure shell logic with no dependency on `claude-proxy`).
Architecture tests FAIL — `_sync-active-dir` still exists, `active_dir` still in wrapper.

- [ ] **Step 4: Commit**

```bash
git add proxied-claude.bats
git commit -m "test: add failing tests for shared ide/ dir and architecture"
```

---

## Task 3: Implement `claude-proxy` changes

**Files:**
- Modify: `claude-proxy`

- [ ] **Step 1: Remove `ACTIVE_DIR` variable**

Delete line 45:
```bash
ACTIVE_DIR="$CONF_DIR/active_dir"
```

- [ ] **Step 2: Simplify `write_active()`**

Around line 114–120, change from:
```bash
write_active() {
  local tmp; tmp="$(mktemp "${ACTIVE_FILE}.XXXXXX")"
  echo "$1" > "$tmp"
  mv "$tmp" "$ACTIVE_FILE"
  ln -sfn "$(profile_claude_dir "$1")" "$ACTIVE_DIR"
}
```
To:
```bash
write_active() {
  local tmp; tmp="$(mktemp "${ACTIVE_FILE}.XXXXXX")"
  echo "$1" > "$tmp"
  mv "$tmp" "$ACTIVE_FILE"
}
```

- [ ] **Step 3: Remove `_sync-active-dir` command**

Delete lines 1175–1177:
```bash
  _sync-active-dir)
    ln -sfn "$(profile_claude_dir "$(active_profile)")" "$ACTIVE_DIR"
    ;;
```

- [ ] **Step 4: Add `mkdir -p "$CONF_DIR/ide"` in `ensure_default_profile()`**

Around line 392–404, change from:
```bash
ensure_default_profile() {
  ensure_dirs
  if [[ ! -f "$PROFILES_DIR/default.conf" ]]; then
```
To:
```bash
ensure_default_profile() {
  ensure_dirs
  mkdir -p "$CONF_DIR/ide"
  if [[ ! -f "$PROFILES_DIR/default.conf" ]]; then
```

- [ ] **Step 5: Add ide/ symlink in `profile create`**

Around line 531 in `profile create`, change from:
```bash
      mkdir -p "$claude_dir"

      ok "Profile '$name' created"
```
To:
```bash
      mkdir -p "$claude_dir"
      [[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }

      ok "Profile '$name' created"
```

- [ ] **Step 6: Update `print_help()` IDE config dir**

Around line 446, change:
```bash
  Config dir     : ~/.config/proxied-claude/active_dir
```
To:
```bash
  Config dir     : ~/.config/proxied-claude
```

- [ ] **Step 7: Update `status` command IDE config dir**

Around line 1097–1099, change:
```bash
    echo "  ── IDE integration ────────────────────────────"
    echo "  Command    : $WRAPPER_PATH"
    echo "  Config dir : $(display_path "$CONF_DIR/active_dir")"
```
To:
```bash
    echo "  ── IDE integration ────────────────────────────"
    echo "  Command    : $WRAPPER_PATH"
    echo "  Config dir : $(display_path "$CONF_DIR")"
```

- [ ] **Step 8: Update `uninstall` description**

Around line 1141, change:
```bash
    echo "  $CONF_DIR (all profiles, proxy configs, active_profile)"
```
To:
```bash
    echo "  $CONF_DIR (all profiles, proxy configs, active_profile, shared ide/)"
```

- [ ] **Step 9: Run tests**

```bash
bats proxied-claude.bats --filter "architecture: _sync-active-dir removed"
bats proxied-claude.bats
```
Expected: `architecture: _sync-active-dir removed` now PASSES. All other tests pass.

- [ ] **Step 10: Commit**

```bash
git add claude-proxy
git commit -m "feat: remove active_dir, add shared ide/ symlink logic to claude-proxy"
```

---

## Task 4: Implement `proxied-claude` wrapper changes

**Files:**
- Modify: `proxied-claude`

- [ ] **Step 1: Remove `ACTIVE_DIR` variable**

Delete line 17:
```bash
ACTIVE_DIR="$CONF_DIR/active_dir"
```

- [ ] **Step 2: Add ide/ safety net and remove active_dir block**

Around lines 76–85, change from:
```bash
mkdir -p "$CLAUDE_DIR"
export CLAUDE_CONFIG_DIR="$CLAUDE_DIR"

# ── Update active_dir symlink (IDE integration) ──────────────────────────────
# Safety net: sync symlink with global active_profile.
# Skipped when PROXIED_CLAUDE_PROFILE override is active — override sessions
# are ephemeral and must not displace the global active_dir pointer.
if [[ -z "${PROXIED_CLAUDE_PROFILE:-}" ]]; then
  ln -sfn "$CLAUDE_DIR" "$ACTIVE_DIR"
fi
```
To:
```bash
mkdir -p "$CLAUDE_DIR"
export CLAUDE_CONFIG_DIR="$CLAUDE_DIR"

# ── Ensure ide/ symlink exists (IDE lock-file discovery) ─────────────────────
[[ -e "$CLAUDE_DIR/ide" ]] || ln -s "$CONF_DIR/ide" "$CLAUDE_DIR/ide"
```

- [ ] **Step 3: Update header comment**

Around line 36, change:
```bash
  └─ updates active_dir symlink (IDE integration, skipped when override active)
```
To:
```bash
  └─ ensures ide/ symlink exists → ~/.config/proxied-claude/ide/
```

- [ ] **Step 4: Run architecture tests**

```bash
bats proxied-claude.bats --filter "architecture: wrapper has no active_dir"
bats proxied-claude.bats --filter "architecture: wrapper creates ide/"
bats proxied-claude.bats
```
Expected: both architecture tests PASS. All tests pass.

- [ ] **Step 5: Commit**

```bash
git add proxied-claude
git commit -m "feat: remove active_dir from wrapper, add ide/ symlink safety net"
```

---

## Task 5: Update `install.sh`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add `ide/` to config dirs creation (line 62)**

Change:
```bash
mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/proxies"
```
To:
```bash
mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/proxies" "$CONF_DIR/ide"
```

- [ ] **Step 2: Replace `_sync-active-dir` call with migration loop (line 110)**

Change:
```bash
"$CTL_PATH" _sync-active-dir
```
To:
```bash
# Migrate profile ide/ dirs to shared symlinks (idempotent)
shopt -s nullglob
for _pf in "$CONF_DIR/profiles"/*.conf; do
  _pdir="$(grep -m1 "^PROFILE_CLAUDE_DIR=" "$_pf" 2>/dev/null | cut -d'"' -f2)"
  [[ -n "$_pdir" && -d "$_pdir" ]] || continue
  [[ -L "$_pdir/ide" ]] || { rm -rf "$_pdir/ide"; ln -s "$CONF_DIR/ide" "$_pdir/ide"; }
done
shopt -u nullglob
```

- [ ] **Step 3: Update IDE hint (line 178)**

Change:
```bash
echo "  Config dir     : ~/.config/proxied-claude/active_dir"
```
To:
```bash
echo "  Config dir     : ~/.config/proxied-claude"
```

- [ ] **Step 4: Verify install.sh is syntactically valid**

```bash
bash -n /Users/r0mm4k/Developer/My/proxied-claude/install.sh
```
Expected: no output (no syntax errors).

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: replace _sync-active-dir with ide/ migration in install.sh"
```

---

## Task 6: Update documentation

**Files:**
- Modify: `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `TODO.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Change line 8:
```
- `proxied-claude` — thin launcher (~114 lines): resolves profile (env var override or active_profile) → fetches Keychain password → updates `active_dir` symlink → `exec claude`
```
To:
```
- `proxied-claude` — thin launcher (~108 lines): resolves profile (env var override or active_profile) → fetches Keychain password → ensures `ide/` symlink exists → `exec claude`
```

Delete line 14:
```
- `active_dir` — symlink → active profile's Claude dir (IDE Config directory field)
```

Change line 51:
```
- `active_dir` symlink is updated in three places: `write_active()` (profile switch), `_sync-active-dir` (install/upgrade), and safety net in `proxied-claude` (guarded — skipped when `PROXIED_CLAUDE_PROFILE` override is active).
```
To:
```
- `ide/` in each profile dir is a symlink to `~/.config/proxied-claude/ide/` (shared lock-file dir). Created in `profile create`, migrated in `install.sh`, safety-net in `proxied-claude`. Plugin Config directory is `~/.config/proxied-claude` — a real path, never a symlink.
```

Change line 52:
```
- `PROXIED_CLAUDE_PROFILE` env var overrides global `active_profile` per-process only — does not update `active_dir`. `claude-proxy run <n>` is the user-facing shortcut.
```
To:
```
- `PROXIED_CLAUDE_PROFILE` env var overrides global `active_profile` per-process only. `claude-proxy run <n>` is the user-facing shortcut.
```

- [ ] **Step 2: Update `CHANGELOG.md`**

Replace lines 36–38:
```markdown
- **`active_dir` symlink** — `~/.config/proxied-claude/active_dir` always points to the
  active profile's Claude dir; JetBrains/VS Code Config directory field set once and never
  needs updating when switching profiles
```
With:
```markdown
- **Shared `ide/` directory** — `~/.config/proxied-claude/ide/` is the single physical
  location for IDE lock files; each profile's `ide/` is a symlink to it; plugin Config
  directory is `~/.config/proxied-claude` (a real path, never a symlink); profile switching
  requires no IDE restart
```

- [ ] **Step 3: Update `README.md` — flow diagram**

Change line 36:
```
  └─ updates active_dir symlink (IDE integration, skipped when override active)
```
To:
```
  └─ ensures ide/ symlink exists → ~/.config/proxied-claude/ide/
```

- [ ] **Step 4: Update `README.md` — config layout section**

Change lines 216–217:
```
  active_profile              ← name of the currently active profile
  active_dir                  ← symlink → active profile's Claude dir (for IDE)
```
To:
```
  active_profile              ← name of the currently active profile
  ide/                        ← shared IDE lock-file dir (all profiles symlink here)
```

- [ ] **Step 5: Update `README.md` — IDE integration section**

Replace lines 330–337:
```markdown
3. **Settings → Tools → Claude Code [Beta]** → Config directory:
   ```
   ~/.config/proxied-claude/active_dir
   ```

The config dir symlink always points to the active profile's Claude dir — updates automatically when you switch profiles with `claude-proxy use <n>`.

> **Note:** After `claude-proxy use <n>`, restart the IDE for the new profile to take effect. JetBrains resolves the symlink once at plugin startup and caches the real path — changing the symlink is not picked up until restart. This is a known plugin limitation ([anthropics/claude-code#1698](https://github.com/anthropics/claude-code/issues/1698)).
```
With:
```markdown
3. **Settings → Tools → Claude Code [Beta]** → Config directory:
   ```
   ~/.config/proxied-claude
   ```

All profile `ide/` directories are symlinks to `~/.config/proxied-claude/ide/`. The plugin writes lock files to this shared physical location and the CLI finds them regardless of which profile is active — no IDE restart needed when switching profiles with `claude-proxy use <n>`.
```

- [ ] **Step 6: Update `TODO.md`**

Mark TODO #26 as done — change:
```markdown
- [ ] 26. **IDE restart after `claude-proxy use`** — JetBrains resolves the `active_dir` symlink
  once at plugin startup and caches the real path. Changing the symlink via `claude-proxy use`
  is not picked up until IDE restart. Upstream bug: [anthropics/claude-code#1698](https://github.com/anthropics/claude-code/issues/1698).
  Workaround documented in README. Revisit when the bug is fixed upstream.
```
To:
```markdown
- [x] 26. **IDE restart after `claude-proxy use`** — Fixed: replaced `active_dir` symlink with
  shared `~/.config/proxied-claude/ide/` directory. All profiles' `ide/` dirs are symlinks to
  this physical location. Plugin Config directory is `~/.config/proxied-claude` (real path).
  No IDE restart needed after `claude-proxy use`.
```

In TODO #7 (directory-based auto-switch), find and remove the line:
```
  - `active_dir` symlink → correct for single IDE window, profiles switch with `claude-proxy use`
```
And update the "IDE Config directory for multi-window" note to remove `active_dir` reference.

- [ ] **Step 7: Run full test suite one final time**

```bash
cd /Users/r0mm4k/Developer/My/proxied-claude
bats proxied-claude.bats
```
Expected: all tests pass.

- [ ] **Step 8: Commit docs**

```bash
git add CLAUDE.md CHANGELOG.md README.md TODO.md
git commit -m "docs: update all references — active_dir removed, shared ide/ dir"
```

---

## Self-Review

**Spec coverage check:**
- ✅ `proxied-claude`: ACTIVE_DIR removed, ln block removed, safety net added, comment updated — Tasks 4
- ✅ `claude-proxy`: ACTIVE_DIR removed, write_active simplified, _sync-active-dir removed, ensure_default_profile updated, profile create updated, print_help updated, status updated, uninstall updated — Task 3
- ✅ `install.sh`: _sync-active-dir replaced, mkdir ide added, IDE hint updated — Task 5
- ✅ `proxied-claude.bats`: 5 old tests removed, 5 new tests added — Tasks 1–2
- ✅ `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `TODO.md` — Task 6
- ✅ `profile rename`: no changes needed (mv preserves symlinks) — confirmed in spec

**No placeholders found.**

**Type consistency:** No types — shell only. All variable names consistent (`CONF_DIR`, `CLAUDE_DIR`, `claude_dir`) throughout.
