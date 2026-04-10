# Design: Shared IDE lock-file directory (remove `active_dir`)

**Date:** 2026-04-10  
**Status:** Approved  
**Closes:** TODO #26

---

## Problem

The JetBrains plugin resolves the `Config directory` path to a physical path **once at startup**
and caches it. `active_dir` is a symlink that changes on `claude-proxy use`, but the plugin never
re-reads it — the cached physical path stays until IDE restart. Result: after switching profiles
the CLI looks for lock files in the new profile's `ide/` directory, which is empty, so it never
finds the IDE.

## Solution

Replace the `active_dir` symlink mechanism with a **shared physical `ide/` directory**:

```
~/.config/proxied-claude/ide/   ← single physical location for all lock files

~/.claude/ide          → ~/.config/proxied-claude/ide/   (symlink)
~/.claude-personal/ide → ~/.config/proxied-claude/ide/   (symlink)
~/.claude-work/ide     → ~/.config/proxied-claude/ide/   (symlink)
any new profile/ide    → ~/.config/proxied-claude/ide/   (symlink)
```

**Plugin Config directory** is changed from `~/.config/proxied-claude/active_dir` to
`~/.config/proxied-claude`. This is a real directory — no symlink resolution issue.
After **one IDE restart** the plugin caches the physical path `~/.config/proxied-claude/ide/`
and writes all lock files there. Every profile's `ide/` symlink points to the same place,
so the CLI always finds the lock file regardless of active profile.

## Architecture

**Lock file flow after the change:**

```
Plugin startup:
  Config dir = ~/.config/proxied-claude  (real path, cached once, never changes)
  Plugin writes: ~/.config/proxied-claude/ide/<port>.lock

Profile switch (claude-proxy use work):
  Writes active_profile = "work"
  Nothing else — no symlink update needed

proxied-claude runs:
  CLAUDE_CONFIG_DIR = ~/.claude-work
  Claude CLI reads: ~/.claude-work/ide/ → symlink → ~/.config/proxied-claude/ide/
  Finds lock file → connects to IDE ✓
```

## Files Changed

### `proxied-claude` (wrapper)
- Remove `ACTIVE_DIR` variable
- Remove `ln -sfn "$CLAUDE_DIR" "$ACTIVE_DIR"` block (3 lines + guard)
- Add safety net after `mkdir -p "$CLAUDE_DIR"`:
  `[[ -e "$CLAUDE_DIR/ide" ]] || ln -s "$CONF_DIR/ide" "$CLAUDE_DIR/ide"`
  Covers the default profile when `~/.claude/` is created lazily on first run,
  and any other profile where `ide/` symlink is missing for any reason.
- Update header comment: remove mention of `active_dir` symlink update

### `claude-proxy`
- Remove `ACTIVE_DIR` variable (line 45)
- `write_active()`: remove `ln -sfn "$(profile_claude_dir "$1")" "$ACTIVE_DIR"` line
- Remove `_sync-active-dir` hidden command (lines 1175–1177)
- `ensure_default_profile()`: add `mkdir -p "$CONF_DIR/ide"` to guarantee shared dir exists
- `profile create`: after `mkdir -p "$claude_dir"`, add idempotent symlink creation:
  `[[ -L "$claude_dir/ide" ]] || { rm -rf "$claude_dir/ide"; ln -s "$CONF_DIR/ide" "$claude_dir/ide"; }`
  Handles all branches: Y (fresh dir) → creates symlink; N (existing dir with real `ide/`) →
  migrates to symlink; already a symlink → no-op.
- `profile rename`: no changes needed — `mv "$old_dir" "$new_dir"` carries the symlink as-is;
  absolute target `~/.config/proxied-claude/ide/` stays valid after the move
- `print_help()`: change `Config dir: ~/.config/proxied-claude/active_dir` → `~/.config/proxied-claude`
- `status` command: same change on the `Config dir` output line
- `uninstall` command: remove `active_dir` from description text

### `install.sh`
- Update IDE hint: `Config dir: ~/.config/proxied-claude`
- Remove: call to `_sync-active-dir` command (command is deleted)
- Add: `mkdir -p "$CONF_DIR/ide"` to create shared dir
- Add idempotent migration helper for each profile dir (including `~/.claude`):
  `[[ -L "$dir/ide" ]] || { rm -rf "$dir/ide"; ln -s "$CONF_DIR/ide" "$dir/ide"; }`
  Lock files are ephemeral (contain stale PIDs/authTokens after restart) — no need to
  preserve contents, just replace real dir with symlink.

### `proxied-claude.bats`
- Remove `export ACTIVE_DIR=...` from test setup
- Remove `ln -sfn` line from `write_active` helper inside tests
- Delete 4 tests: `write_active: active_dir *` (they test removed behaviour)
- Delete 1 test: `profile use: active_dir updated after use`
- Add test: `profile create: ide/ is a symlink pointing to shared dir`
- Add test: `profile create: ide/ symlink survives existing-dir N-branch` (real `ide/` dir exists,
  user keeps it — verify `ide/` becomes a symlink after create)
- Add test: `proxied-claude: creates ide/ symlink if missing` (safety net in wrapper)

### `CLAUDE.md`
- Remove `active_dir` from component list
- Remove `active_dir` from "Key design decisions" section
- Update `proxied-claude` description: remove `updates active_dir symlink`
- Remove `_sync-active-dir` mention

### `CHANGELOG.md`
- Remove entry: `active_dir symlink`
- Add entry: `Shared ide/ directory — all profile ide/ dirs are symlinks to ~/.config/proxied-claude/ide/; plugin Config directory is now ~/.config/proxied-claude`

### `README.md`
- Flow diagram: replace `updates active_dir symlink (IDE integration...)` with `sets CLAUDE_CONFIG_DIR → profile dir`
- IDE setup section (step 3): change `Config directory: ~/.config/proxied-claude/active_dir` → `~/.config/proxied-claude`

### `TODO.md`
- Mark #26 as `[x]` (fixed by this change)
- Remove `active_dir symlink →` reference in TODO #7 description

## Migration

**Fresh install (no prior Claude):** `install.sh` creates `~/.config/proxied-claude/ide/`.
No profile dirs exist yet, nothing to migrate.

**v1 → v2 upgrade:** `install.sh` checks `~/.claude/ide/` — if it is a real directory,
moves contents to `~/.config/proxied-claude/ide/` and replaces it with a symlink.

**New profiles (post-install):** `profile create` always creates `ide/` as a symlink.
No manual steps needed.

**Local dev (us):** Fix manually — the install.sh migration handles it on next reinstall,
or run the symlink commands by hand.

## User Action Required (one-time)

After updating:
1. In JetBrains: **Settings → Tools → Claude Code [Beta]**
2. Change `Config directory` from `~/.config/proxied-claude/active_dir` → `~/.config/proxied-claude`
3. Restart the IDE once

After that: `claude-proxy use <profile>` works without any IDE restart.

## Compatibility

- `PROXIED_CLAUDE_PROFILE` per-session override: unaffected
- `claude-proxy run <n>`: unaffected
- TODO #7 (directory-based auto-switch): compatible — each project profile's `ide/` also
  points to the shared dir; multiple IDE windows write separate lock files (different ports)
  to the same shared dir; CLI matches by `workspaceFolders` in the lock file
- Proxy logic: completely unaffected
