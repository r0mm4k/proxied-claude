# proxied-claude

Shell utility to run Claude Code behind a corporate HTTP proxy with multi-profile and multi-proxy support (macOS only).

## Architecture

Three files, clear separation:
- `proxied-claude` — thin launcher (~135 lines): resolves profile (env var override or active_profile) → fetches Keychain password → ensures `ide/` symlink exists → `exec claude`
- `claude-proxy` — all management logic: profiles, proxies, migration, lock (~1347 lines)
- `install.sh` — download, patch `__CLAUDE_BIN__`, delegate wizard/migration to claude-proxy

Config lives in `~/.config/proxied-claude/`:
- `active_profile` — name of active profile
- `profiles/<n>.conf` — PROFILE_CLAUDE_DIR, PROFILE_PROXY
- `proxies/<n>.conf` — PROXY_HOST, PROXY_USER, PROXY_KEYCHAIN_SERVICE

Passwords are stored in macOS Keychain only — never in conf files.

## Commands

```bash
# Run tests (no side effects on real filesystem)
bats proxied-claude.bats

# Run specific group
bats proxied-claude.bats --filter migration
bats proxied-claude.bats --filter lock
```

## Key Patterns

**read_conf** — grep-based, never sources bash. Used in all three files. Do not replace with `source` or `eval` — injection risk.

**Concurrency lock** — `mkdir`-based POSIX lock at `~/.config/proxied-claude/.lock`. Read-only commands skip it. Always pair `lock_acquire` with `lock_release`.

**Conf format** — always `CONFIG_VERSION=1` + quoted values. Tests mirror helpers from claude-proxy exactly — keep them in sync when changing conf structure.

**`__CLAUDE_BIN__`** — literal placeholder in source `proxied-claude`. Patched by `install.sh` via `sed`. Never hardcode a path.

## Workflow

After completing a brainstorm/plan/implement cycle, delete the generated spec and plan files and their parent directories (`docs/superpowers/`). These are temporary scaffolding — do not commit or keep them in the repo.

## Gotchas

- `proxied-claude` cannot be tested end-to-end (does `exec claude`). Test logic via mirrored helpers in bats.
- `claude-proxy` binary always calls `ensure_default_profile` on startup — do not run it in tests (touches `$HOME/.config`).
- `install.sh` duplicates default-profile creation (step 5, after migration) because on fresh install `claude-proxy migrate` is skipped. This is intentional.
- Architecture tests check exact line counts in source files — update counts if you add matching lines to `proxied-claude` or `claude-proxy`.
- `ide/` in each profile dir is a symlink to `~/.config/proxied-claude/ide/` (shared lock-file dir). Created in `profile create`, migrated in `install.sh`, safety-net in `proxied-claude`. Plugin Config directory is `~/.config/proxied-claude` — a real path, never a symlink.
- `PROXIED_CLAUDE_PROFILE` env var overrides global `active_profile` per-process only. `claude-proxy run <n>` is the user-facing shortcut.