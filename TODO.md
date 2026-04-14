# TODO

Planned improvements for future iterations.

---

## Features

- [ ] 1. **`claude-proxy backup` / `restore`** — export all config to a tarball for machine
  migration. Includes `profiles/`, `proxies/`, `active_profile`. Never includes Keychain
  passwords — user re-enters them via `claude-proxy proxy set-password <n>` after restore.

- [ ] 2. **`claude-proxy doctor`** — diagnose the full system in one command: binaries,
  `__CLAUDE_BIN__` patch, config dir, profile dirs, proxy confs, Keychain entries,
  active profile validity.

- [ ] 3. **Directory-based auto-switch** — `proxied-claude` automatically picks the right
  profile based on a `.proxied-claude-profile` file in the project root (or any parent
  directory, walking up like `git` searches for `.git`). This is the correct solution
  for **parallel multi-window IDE** use: each project declares its profile once, both
  IDE windows work simultaneously without interference.

  **Priority chain in `proxied-claude`:**
  ```
  PROXIED_CLAUDE_PROFILE (env var)  →  1st (explicit per-process override)
  .proxied-claude-profile (file)    →  2nd (declarative per-project)
  active_profile (global)           →  3rd (fallback)
  ```

  **User flow (once per project):**
  ```bash
  cd ~/work/myproject
  claude-proxy profile local set work
  # ✅ Created .proxied-claude-profile → work
  #    JetBrains Config directory: ~/.config/proxied-claude  (shared, set once for all profiles)
  ```
  After that — open any number of projects in parallel, each uses its own profile automatically.
  No per-project IDE configuration needed — `workspaceFolders` in the lock file routes the
  CLI to the correct IDE window.

  **Behaviour:**
  - Project has `.proxied-claude-profile` → uses that profile, does NOT change global
    `active_profile` (ephemeral, same semantics as `PROXIED_CLAUDE_PROFILE`)
  - Project has no `.proxied-claude-profile` → falls back to global `active_profile`
  - Walk up stops at `/` — no match = fallback to global

  **Files to change:**
  - `proxied-claude` — extend resolve_profile block: walk up `$PWD` looking for
    `.proxied-claude-profile`; if found, use it as profile (same ephemeral semantics as
    `PROXIED_CLAUDE_PROFILE` — no global side effects)
  - `claude-proxy` — new subcommand `profile local set <n>` / `local unset` / `local show`:
    creates/removes `.proxied-claude-profile` in `$PWD`, prints reminder that JetBrains
    Config directory is `~/.config/proxied-claude` (shared, already set)
  - `proxied-claude.bats` — tests for walk up logic: found in current dir, found in
    parent, not found → fallback
  - `README.md` — multi-window IDE section with the full flow

  **IDE Config directory for multi-window:**
  Single `~/.config/proxied-claude` Config directory works for all windows simultaneously —
  no per-project `.idea/` configuration needed. Lock files are written to the shared
  `~/.config/proxied-claude/ide/` dir; CLI matches the correct IDE window via
  `workspaceFolders` in the lock file. Each terminal uses its own profile via
  `.proxied-claude-profile`.

  **Open questions:**
  - Should `.proxied-claude-profile` be gitignored by default? (probably yes — it's
    machine-local, like `.env`; `claude-proxy profile local set` could offer to add it)
  - File name: `.proxied-claude-profile` vs `.proxied-claude` — latter is shorter but
    could conflict with a directory name

- [ ] 4. **Failover proxies** — define multiple proxies per profile; `proxied-claude` tries
  them in order if the first is unreachable:
  ```
  PROFILE_PROXIES="corp-lt corp-backup"
  ```

- [ ] 5. **`claude-proxy proxy create --check`** — immediately run `proxy check` after
  creating a proxy to verify it works, without a separate command.

- [ ] 6. **`claude-proxy profile set-description <profile> <text>`** — store a
  human-readable note in the profile conf, shown in `list` and `status`:
  ```
  work     corp-lt   Work Team account  ◀ active
  personal (none)    Personal Pro
  ```

- [ ] 7. **`--json` output** — machine-readable output for `status`, `profile list`,
  `proxy list`. Useful for scripting and IDE integrations.

- [ ] 8. **`claude-proxy proxy check --watch`** — periodic proxy health monitoring,
  re-checking at a given interval until interrupted.

- [ ] 9. **`claude-proxy proxy set-host` / `proxy set-user`** — change host or user of an
  existing proxy without deleting and recreating it (which requires re-entering the password).
  v1 had top-level `set-host` / `set-user`; v2 removed them but never added the equivalent
  under `proxy`:
  ```bash
  claude-proxy proxy set-host corp-lt 10.0.0.2:3128
  claude-proxy proxy set-user corp-lt john.doe
  ```

- [ ] 10. **`copy-settings` — path rewrite for custom `PROFILE_CLAUDE_DIR`** — the sed rewrite
  in `do_copy_settings` only matches `~/.claude` and `~/.claude-<name>` patterns. If a user
  set `PROFILE_CLAUDE_DIR` to a custom path (e.g. `/Volumes/Work/.claude-work`), paths in
  `settings.json` would not be rewritten. Needs passing `src_dir` into sed instead of
  relying on the fixed `~/.claude*` pattern.

- [ ] 11. **`proxy check` — `nc` without curl fallback** — `cmd_proxy check` uses `nc -z -w 5`
  with no fallback. The old `install.sh` check had a curl fallback. On macOS `nc` is always
  present so this is low-risk, but worth revisiting if Linux support (TODO #15) is added.

- [ ] 12. **`profile create --proxy <n>`** — create profile and link a proxy in one command
  instead of two separate steps:
  ```bash
  claude-proxy profile create work --from default --proxy corp-lt
  # instead of:
  # claude-proxy profile create work --from default
  # claude-proxy profile set-proxy work corp-lt
  ```
  Useful in the install wizard too: currently `install.sh` asks about proxy separately after
  profile creation. With this flag the wizard could pass it directly.

- [ ] 13. **`profile create` copy-settings — validate input name** — `claude-proxy:607`
  the user-typed profile name in the interactive copy-settings prompt is checked only via
  `[[ -f "$PROFILES_DIR/${_choice}.conf" ]]`. `validate_name` is not called, so a name with
  special characters gets a silent "not found" warning instead of a clear error. No security
  risk (file only read, never executed), but inconsistent with the rest of the codebase.

- [ ] 14. **`uninstall` — mention `~/.claude.json` in "Will NOT delete" list** — `claude-proxy:1206`
  the message reads `Will NOT delete: ~/.claude  ~/.claude-*` but omits `~/.claude.json`
  (the default profile's auth/config file at `$HOME`). Users manually cleaning up may miss it.

---

## Security

- [ ] 1. **`install.sh` — checksum verification** — the installer downloads binaries via
  `curl --proto '=https' --tlsv1.2` but does not verify content hashes. For a tool that
  stores credentials, a `sha256sum` check against a published `SHA256SUMS` file would
  materially raise the supply-chain security bar. Depends on GitHub Releases release assets.

- [ ] 2. **URL-encode proxy password in proxy URL** — `proxied-claude:102`, `claude-proxy:991`
  construct `http://user:pass@host` without encoding the password. A password containing
  `@`, `:`, or `/` produces a malformed URL that silently breaks connectivity with no error
  message. Fix: add a `url_encode_pass()` helper (~15 lines of pure bash) and apply it to
  the password before interpolation in both files.

---

## CI / DX

- [ ] 1. **Shell completions (zsh / bash)** — tab-complete subcommands, profile names,
  and proxy names.

- [ ] 2. **Split test suite into `tests/`** — move `proxied-claude.bats` into a `tests/`
  directory and split by domain as the suite grows:
  ```
  tests/
  ├── profiles.bats
  ├── proxies.bats
  ├── migration.bats
  ├── lock.bats
  └── copy_settings.bats
  ```
  Update `bats` invocation in README and GitHub Actions accordingly.

---

## Platform

- [ ] 1. **Linux support** — replace macOS `security` CLI with a pluggable Keychain backend:
  `secret-tool` (GNOME Keyring), `pass`, or a permissions-restricted file as fallback.

---

## Done

- [x] **`PROXIED_CLAUDE_PROFILE` env var override** — run with a specific profile without
  changing global `active_profile`. Includes `claude-proxy run <n>` shorthand.

- [x] **`copy-settings --include-projects`** — optional flag to copy `projects/*/memory/`.
  Conflict detection, batch confirmation, non-interactive die on conflicts.

- [x] **`profile create` — existing directory handling** — warns and asks to start fresh
  if `~/.claude-<name>` already exists; N keeps data, Y deletes; non-interactive keeps silently.

- [x] **`claude-proxy update --version <n>`** — pin to a specific tagged release.
  `install.sh` respects `VERSION` env var; `claude-proxy update --version` passes it through.

- [x] **Active profile display in Claude Code statusline** — `_pc_info()` snippet for
  `hooks/statusline.sh`, documented in README.

- [x] **GitHub Actions CI** — bats tests + shellcheck on push and pull requests.

- [x] **Shellcheck linting in CI** — shellcheck step alongside bats in GitHub Actions.

- [x] **GitHub Releases with version tags** — tagged releases via GitHub Actions on push.

- [x] **`claude-proxy update` — confirmation + version preview** — fetches latest tag via
  GitHub API, shows version comparison, asks confirmation; major bump shows prominent warning.
  Passive `version --check` intentionally skipped — `update` covers the flow and adding
  network calls to `status` would make it unpredictably slow.

- [x] **IDE restart after `claude-proxy use`** — shared `~/.config/proxied-claude/ide/`
  dir; all profiles symlink here. No IDE restart needed when switching profiles.

- [x] **Copy `mcpServers` when creating/copying a profile** — `do_copy_settings()` merges
  `mcpServers` from source `.claude.json`. `python3` is optional — guarded with warn+skip
  if absent. Conflict detection included.
