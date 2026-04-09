# TODO

Planned improvements for future iterations.

---

## Features

- [x] 1. **`PROXIED_CLAUDE_PROFILE` env var override** — run with a specific profile without
  changing global `active_profile`. Useful for multiple terminals or aliases:
  ```bash
  PROXIED_CLAUDE_PROFILE=work proxied-claude
  alias claude-work="PROXIED_CLAUDE_PROFILE=work proxied-claude"
  # or via: claude-proxy run work
  ```

- [x] 2. **`copy-settings --include-projects`** — optional flag to also copy the `projects/`
  directory (per-repo Claude data). Skipped by default — only useful if both profiles
  work on the same repositories:
  ```bash
  claude-proxy profile copy-settings work --from default --include-projects
  ```
  Additional UX improvements needed:
  - When destination has existing data, show a summary of conflicting files/dirs
    and ask for batch confirmation instead of per-file `warn` (especially important
    with `--include-projects` where `projects/` may have dozens of subdirs);
    non-interactive with conflicts → `die` (consistent with `proxy delete`, `uninstall`)
  - In interactive `profile create`, also ask "Copy projects too? [y/N]" when
    `--include-projects` becomes available

- [x] 3. **`profile create` — existing directory handling** — if `~/.claude-<name>` already
  exists and is non-empty (e.g. after deleting and recreating a profile), warn the user
  and ask whether to start fresh:
  ```
  ⚠  Directory ~/.claude-work already exists and contains data.
     Your previous session data and settings are preserved.

     Start fresh and delete existing data? [y/N]
  ```
  - **N (default)**: use existing dir, replace "you need to log in" note with
    `"If your session expired, log in again when you first use this profile"`
  - **Y**: `rm -rf ~/.claude-work && mkdir`, show normal login note
  - Non-interactive (`-t 0` false): silently use existing dir + `warn` (no prompt)

- [ ] 4. **`claude-proxy backup` / `restore`** — export all config to a tarball for machine
  migration. Includes `profiles/`, `proxies/`, `active_profile`. Never includes Keychain
  passwords — user re-enters them via `claude-proxy proxy set-password <n>` after restore.

- [ ] 5. **`claude-proxy doctor`** — diagnose the full system in one command: binaries,
  `__CLAUDE_BIN__` patch, config dir, profile dirs, proxy confs, Keychain entries,
  active profile validity.

- [ ] 6. **`claude-proxy update --version <n>`** — pin to a specific release instead of
  always pulling `main`. Two-part change:
  - `install.sh`: respect `VERSION` env var to set `REPO_RAW` to a tagged ref instead of `main`
  - `claude-proxy update --version <n>`: pass `VERSION=<n>` when invoking `install.sh`
  ```bash
  claude-proxy update --version 2.1.0
  # or via install.sh directly:
  VERSION=2.1.0 bash <(curl -fsSL .../install.sh)
  ```
  Depends on: #22 (GitHub Releases).

- [ ] 7. **Directory-based auto-switch** — `proxied-claude` automatically picks the right
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
  #    JetBrains Config directory: ~/.claude-work
  ```
  Then in JetBrains: Config directory = `~/.claude-work` (Store in project → saved in `.idea/`).
  After that — open any number of projects in parallel, each uses its own profile automatically.

  **Behaviour:**
  - Project has `.proxied-claude-profile` → uses that profile, does NOT update `active_dir`
    (ephemeral, same as `PROXIED_CLAUDE_PROFILE` — no global side effects)
  - Project has no `.proxied-claude-profile` → falls back to global `active_profile`
  - Walk up stops at `/` — no match = fallback to global

  **Files to change:**
  - `proxied-claude` — extend resolve_profile block: walk up `$PWD` looking for
    `.proxied-claude-profile`; if found, use it as profile (same guard for `active_dir`
    safety net as `PROXIED_CLAUDE_PROFILE`)
  - `claude-proxy` — new subcommand `profile local set <n>` / `local unset` / `local show`:
    creates/removes `.proxied-claude-profile` in `$PWD`, prints IDE Config directory path
  - `proxied-claude.bats` — tests for walk up logic: found in current dir, found in
    parent, not found → fallback, symlink not updated when local profile active
  - `README.md` — multi-window IDE section with the full flow

  **IDE Config directory for multi-window (no code change needed today):**
  - `active_dir` symlink → correct for single IDE window, profiles switch with `claude-proxy use`
  - Direct path `~/.claude-work` per-project in `.idea/` → correct for parallel multi-window;
    each project configured once via `claude-proxy profile local set`

  **Open questions:**
  - Should `.proxied-claude-profile` be gitignored by default? (probably yes — it's
    machine-local, like `.env`; `claude-proxy profile local set` could offer to add it)
  - File name: `.proxied-claude-profile` vs `.proxied-claude` — latter is shorter but
    could conflict with a directory name

- [ ] 8. **Failover proxies** — define multiple proxies per profile; `proxied-claude` tries
  them in order if the first is unreachable:
  ```
  PROFILE_PROXIES="corp-lt corp-backup"
  ```

- [ ] 9. **`claude-proxy proxy create --check`** — immediately run `proxy check` after
  creating a proxy to verify it works, without a separate command.

- [ ] 10. **`claude-proxy profile set-description <profile> <text>`** — store a
  human-readable note in the profile conf, shown in `list` and `status`:
  ```
  work     corp-lt   Work Team account  ◀ active
  personal (none)    Personal Pro
  ```

- [ ] 11. **`--json` output** — machine-readable output for `status`, `profile list`,
  `proxy list`. Useful for scripting and IDE integrations.

- [x] 12. **Active profile display in Claude Code statusline** — `_pc_info()` shell
  helper reads `active_profile` + `profiles/<n>.conf` directly (no subprocess).
  Outputs `profile (proxy)` (or just `profile`, or nothing). Ships as an optional
  snippet in README under "Claude Code statusline integration".

- [ ] 13. **`claude-proxy proxy check --watch`** — periodic proxy health monitoring,
  re-checking at a given interval until interrupted.

- [ ] 14. **`claude-proxy proxy set-host` / `proxy set-user`** — change host or user of an
  existing proxy without deleting and recreating it (which requires re-entering the password).
  v1 had top-level `set-host` / `set-user`; v2 removed them but never added the equivalent
  under `proxy`:
  ```bash
  claude-proxy proxy set-host corp-lt 10.0.0.2:3128
  claude-proxy proxy set-user corp-lt john.doe
  ```

- [ ] 15. **`copy-settings` — path rewrite for custom `PROFILE_CLAUDE_DIR`** — the sed rewrite
  in `do_copy_settings` only matches `~/.claude` and `~/.claude-<name>` patterns. If a user
  set `PROFILE_CLAUDE_DIR` to a custom path (e.g. `/Volumes/Work/.claude-work`), paths in
  `settings.json` would not be rewritten. Needs passing `src_dir` into sed instead of
  relying on the fixed `~/.claude*` pattern.

- [ ] 16. **`proxy check` — `nc` without curl fallback** — `cmd_proxy check` uses `nc -z -w 5`
  with no fallback. The old `install.sh` check had a curl fallback. On macOS `nc` is always
  present so this is low-risk, but worth revisiting if Linux support (TODO #23) is added.

- [ ] 24. **`profile create --proxy <n>`** — create profile and link a proxy in one command
  instead of two separate steps:
  ```bash
  claude-proxy profile create work --from default --proxy corp-lt
  # instead of:
  # claude-proxy profile create work --from default
  # claude-proxy profile set-proxy work corp-lt
  ```
  Useful in the install wizard too: currently `install.sh` asks about proxy separately after
  profile creation. With this flag the wizard could pass it directly.

- [ ] 25. **`claude-proxy update` — confirmation + version preview** — currently updates
  silently without showing what version is being installed or asking for confirmation.
  Improvements:
  - Before downloading: fetch and display the new version number, ask `Upgrade to vX.Y.Z? [y/N]`
  - For major version bumps (e.g. v1 → v2): show a prominent warning with a link to
    release notes / migration guide before asking; user can abort and read first
  - `claude-proxy version --check` (or hint in `claude-proxy status`): compare installed
    version against latest on GitHub and show a hint if an update is available — without
    blocking or auto-fetching on every run (only on explicit `version` / `status` call)
  - Depends on: #22 (GitHub Releases, where version info and release notes are published)

---

## Security

- [ ] 17. **`install.sh` — checksum verification** — the installer downloads binaries via
  `curl --proto '=https' --tlsv1.2` but does not verify content hashes. For a tool that
  stores credentials, a `sha256sum` check against a published `SHA256SUMS` file would
  materially raise the supply-chain security bar. Depends on: #22 (GitHub Releases, where
  checksums can be published as release assets).

---

## CI / DX

- [ ] 18. **GitHub Actions** — auto-run `bats proxied-claude.bats` on push and pull requests.

- [ ] 19. **Shell completions (zsh / bash)** — tab-complete subcommands, profile names,
  and proxy names.

- [ ] 20. **Split test suite into `tests/`** — move `proxied-claude.bats` into a `tests/`
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

- [ ] 21. **Shellcheck linting in CI** — add a shellcheck step to GitHub Actions alongside
  the bats tests. Catches common shell pitfalls (quoting, word splitting, deprecated syntax)
  across `proxied-claude`, `claude-proxy`, and `install.sh`.

- [ ] 22. **GitHub Releases with version tags** — publish tagged releases (`v2.0.0`, `v2.1.0`)
  so the `update` command can pin to a specific version (TODO #6) and users can audit what
  they're installing.

---

## Platform

- [ ] 23. **Linux support** — replace macOS `security` CLI with a pluggable Keychain backend:
  `secret-tool` (GNOME Keyring), `pass`, or a permissions-restricted file as fallback.
