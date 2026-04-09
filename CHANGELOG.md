# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - 2026-04-07

### Added
- **Multi-profile support** — manage multiple Claude accounts with isolated config
  directories (`~/.claude-<n>`), each with an optional linked proxy
- **Multi-proxy support** — named, reusable proxy configs stored separately from profiles
- **`default` profile** — automatically created on install, points to `~/.claude`;
  existing v1 users see zero change in behavior
- **`claude-proxy profile`** subcommands:
  - `list` — show all profiles with active marker
  - `create <n> [--from <source>] [--include-projects]` — create profile, optionally copy settings and project memory
  - `delete <n>` — remove profile config (Claude dir kept on disk)
  - `rename <old> <new>` — rename profile and move its Claude dir
  - `use <n>` — switch active profile
  - `show [<n>]` — show any profile's details without switching
  - `set-proxy <profile> <proxy>` — link a proxy to a profile
  - `unset-proxy <profile>` — run profile without proxy
  - `copy-settings <profile> --from <source> [--include-projects]` — copy portable config files between profiles; `--include-projects` also copies `projects/*/memory/` (per-project memory, not history)
- **`claude-proxy proxy`** subcommands:
  - `list` — show all proxies and which profiles use them
  - `create <n> <host:port> <user>` — create proxy, save password to Keychain
  - `delete <n>` — remove proxy config and Keychain entry; auto-unlinks all linked profiles
  - `rename <old> <new>` — rename proxy, migrate Keychain entry, update all linked profiles
  - `set-password <n>` — update password in Keychain
  - `show <n>` — show proxy details (password never shown)
  - `check <n>` — three-level health check: TCP → proxy auth (407 detection) → Anthropic API
- **Shortcuts**: `claude-proxy use`, `status`, `check`, `version`, `help`, `migrate`
- **`claude-proxy status`** — full overview: active profile + all profiles + all proxies
- **`claude-proxy migrate`** — manual v1 → v2 migration command
- **`claude-proxy version` / `--version` / `-v`** — print version
- **`claude-proxy help` / `--help` / `-h`** — show full command reference
- **Auto-migration from v1** — `install.sh` and `claude-proxy migrate`
  detect and migrate `proxy.conf` automatically:
  - Keychain entry renamed `claude-proxy` → `claude-proxy:default` (old entry removed)
s  - `proxy.conf` deleted after successful migration (no longer kept as `.migrated`)
  - `profiles/default.conf` and `proxies/default.conf` created automatically
- **`copy-settings`** copies: `settings.json`, `CLAUDE.md`, `keybindings.json`,
  `policy-limits.json`, `hooks/`, `plugins/` — skips auth, history, cache;
  `--include-projects` additionally copies `projects/*/memory/` (accumulated project context)
- **Batch conflict UX** in `copy-settings`: when destination already has files, shows a
  summary of all conflicts and asks once to confirm; non-interactive with conflicts → `die`
  (replaces per-file warnings)
- **Existing directory handling in `profile create`** — if `~/.claude-<name>` already
  exists with data (e.g. after deleting and recreating a profile), warns the user and
  offers to start fresh `[y/N]`; N (default) keeps existing data with an adjusted login
  note; Y deletes the directory cleanly; non-interactive silently uses existing data + `warn`
- **Concurrency lock** — `mkdir`-based POSIX lock (`~/.config/proxied-claude/.lock`)
  prevents race conditions when two terminals run mutating commands simultaneously;
  read-only commands (`list`, `show`, `status`, `check`) skip locking
- **`require_interactive()`** guard — commands that need `stdin` (password input,
  confirmations) now fail fast with a clear message when piped or run in CI
- **Wrapper checks for unpatched `__CLAUDE_BIN__`** — catches broken installs early
- **Wrapper checks for unmigrated v1 config** — exits with `Run: claude-proxy migrate`
  instead of silently misbehaving
- **Path traversal protection** — profile and proxy names validated to `[a-zA-Z0-9_-]`
- **Atomic `active_profile` writes** — via `mktemp` + `mv`, safe against partial reads
- **`CONFIG_VERSION=1`** in all conf files — foundation for future migrations
- **Friendly error messages** for removed v1 commands (`set-all`, `set-host`, `set-user`)
- **JetBrains and VS Code** integration documented in README
- **Test suite** — `proxied-claude.bats` (107 tests, requires `bats-core`)

### Changed
- **`proxied-claude` is now a thin, fast launcher** (~99 lines) — transparent wrapper,
  all arguments pass directly to Claude Code without interception or self-repair
- **`read_conf()` rewritten from `bash -c "source ..."` to `grep`-based parsing** — eliminates
  a fork+exec per call, prevents code injection from malformed `.conf` files
  (e.g. `PROXY_HOST="$(whoami)"` now returns the literal string instead of executing)
- **`install.sh` delegates to `claude-proxy`** — profile creation wizard and migration
  now call the installed binary, reducing installer from ~400 to 183 lines
- **`claude-proxy status`** expanded from single proxy view to full system overview
- **Help text defined once** via `print_help()` — was duplicated across multiple commands
- **Unknown command now prints error** — `claude-proxy unknown` exits 1 with a message
  instead of silently printing help (explicit `help`/`--help`/empty still print help)
- **`curl` uses `--proto '=https' --tlsv1.2`** in `update` and `install.sh`
- **`sudo rm -f`** in uninstall (was `sudo rm`)
- **`profile delete`** hints how to remove data — shows `rm -rf <dir>` in output
- **`profile rename`** always moves the Claude dir when path changes

### Removed
- `claude-proxy set-all` (v1) — replaced by `claude-proxy proxy create`
- `claude-proxy set-host` (v1) — replaced by `claude-proxy proxy create`
- `claude-proxy set-user` (v1) — replaced by `claude-proxy proxy create`

  > v1 users: these commands now print a friendly migration hint instead of a
  > cryptic error. Run `claude-proxy migrate` or `claude-proxy update` to
  > migrate your config automatically.

### Security
- **Conf files are no longer sourced as bash** — grep-based parsing eliminates
  the entire class of injection attacks via malformed config values
- **Profile and proxy names validated** against `^[a-zA-Z0-9_-]+$` — prevents path traversal
- **HTTPS-only downloads** — `curl --proto '=https' --tlsv1.2` prevents protocol downgrade
- **Interactive guard** — prevents `security` CLI from hanging on non-interactive stdin
- **Keychain migration during rename** — old entry deleted after new one is confirmed written

---

## [1.1.0] - 2026-03-12

### Added
- `claude-proxy check` — verifies proxy connectivity in two steps:
  TCP reachability and Anthropic API reachability (`/v1/models`) through the proxy
- Fallback TCP reachability check via `curl` when `nc` (netcat) is not available

### Fixed
- `claude-proxy check` now validates that the proxy host is in `IP:PORT` format before
  attempting a TCP connection — previously a missing port caused a cryptic `nc` error

### Documentation
- Limitations: noted that proxy password is briefly visible in `ps aux` during
  `claude-proxy check` (passed to `curl` via `--proxy`)

---

## [1.0.0] - 2026-03-11

### Added
- `install.sh` — automated setup: installs wrapper and control utility
- `proxied-claude` — wrapper that runs Claude CLI with `HTTP_PROXY`/`HTTPS_PROXY` set
- `claude-proxy` — control utility to manage proxy host, user, and password
  - `status` — show current config
  - `set-host` — change proxy host
  - `set-user` — change proxy user
  - `set-password` — update password in Keychain
  - `set-all` — set host + user + password in one go
  - `update` — update to latest version from GitHub (preserves existing config and Keychain password)
  - `uninstall` — remove all installed files and Keychain entry
- Password stored securely in **macOS Keychain** — never written to disk in plaintext
- `localhost` excluded from proxying via `NO_PROXY` (WebStorm / IDE bridge support)
- Re-running `install.sh` detects existing config and offers to keep current settings
