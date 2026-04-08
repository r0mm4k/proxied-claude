# TODO

Planned improvements for future iterations.

---

## Features

- [ ] 1. **`PROXIED_CLAUDE_PROFILE` env var override** — run with a specific profile without
  changing global `active_profile`. Useful for multiple terminals or aliases:
  ```bash
  PROXIED_CLAUDE_PROFILE=work proxied-claude
  alias claude-work="PROXIED_CLAUDE_PROFILE=work proxied-claude"
  ```

- [ ] 2. **`copy-settings --include-projects`** — optional flag to also copy the `projects/`
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

- [ ] 3. **`profile create` — existing directory handling** — if `~/.claude-<name>` already
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

- [ ] 4. **`claude-proxy check [<proxy>]`** — make the proxy name argument optional.
  Currently `claude-proxy check` (no args) works; `claude-proxy check corp-lt` falls
  through to unknown command. Should be a shortcut for `claude-proxy proxy check corp-lt`.

- [ ] 5. **`claude-proxy backup` / `restore`** — export all config to a tarball for machine
  migration. Includes `profiles/`, `proxies/`, `active_profile`. Never includes Keychain
  passwords — user re-enters them via `claude-proxy proxy set-password <n>` after restore.

- [ ] 6. **`claude-proxy doctor`** — diagnose the full system in one command: binaries,
  `__CLAUDE_BIN__` patch, config dir, profile dirs, proxy confs, Keychain entries,
  active profile validity.

- [ ] 7. **`claude-proxy update --version <n>`** — pin to a specific release instead of
  always pulling `main`. Two-part change:
  - `install.sh`: respect `VERSION` env var to set `REPO_RAW` to a tagged ref instead of `main`
  - `claude-proxy update --version <n>`: pass `VERSION=<n>` when invoking `install.sh`
  ```bash
  claude-proxy update --version 2.1.0
  # or via install.sh directly:
  VERSION=2.1.0 bash <(curl -fsSL .../install.sh)
  ```

- [ ] 8. **Directory-based auto-switch** — automatically use the right profile based on
  current directory. A `.proxied-claude-profile` file in a repo root (or per-dir mapping
  in conf) overrides `active_profile` for that session. Works like `git config --local`:
  ```bash
  echo "work" > ~/work/myproject/.proxied-claude-profile
  # proxied-claude in that dir picks up 'work' profile automatically
  ```

- [ ] 9. **Failover proxies** — define multiple proxies per profile; `proxied-claude` tries
  them in order if the first is unreachable:
  ```
  PROFILE_PROXIES="corp-lt corp-backup"
  ```

- [ ] 10. **`claude-proxy proxy create --check`** — immediately run `proxy check` after
  creating a proxy to verify it works, without a separate command.

- [ ] 11. **`claude-proxy profile set-description <profile> <text>`** — store a
  human-readable note in the profile conf, shown in `list` and `status`:
  ```
  work     corp-lt   Work Team account  ◀ active
  personal (none)    Personal Pro
  ```

- [ ] 12. **`--json` output** — machine-readable output for `status`, `profile list`,
  `proxy list`. Useful for scripting and IDE integrations.

- [ ] 13. **Shell prompt integration** — show active profile in `$PS1`, similar to
  git branch display. Ships as an optional snippet in README.

- [ ] 14. **`claude-proxy proxy check --watch`** — periodic proxy health monitoring,
  re-checking at a given interval until interrupted.

---

## CI / DX

- [ ] 15. **GitHub Actions** — auto-run `bats proxied-claude.bats` on push and pull requests.

- [ ] 16. **Shell completions (zsh / bash)** — tab-complete subcommands, profile names,
  and proxy names.

---

## Platform

- [ ] 17. **Linux support** — replace macOS `security` CLI with a pluggable Keychain backend:
  `secret-tool` (GNOME Keyring), `pass`, or a permissions-restricted file as fallback.
