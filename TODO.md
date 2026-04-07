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

- [ ] 3. **`claude-proxy check [<proxy>]`** — make the proxy name argument optional.
  Currently `claude-proxy check` (no args) works; `claude-proxy check corp-lt` falls
  through to unknown command. Should be a shortcut for `claude-proxy proxy check corp-lt`.

- [ ] 4. **`claude-proxy backup` / `restore`** — export all config to a tarball for machine
  migration. Includes `profiles/`, `proxies/`, `active_profile`. Never includes Keychain
  passwords — user re-enters them via `claude-proxy proxy set-password <n>` after restore.

- [ ] 5. **`claude-proxy doctor`** — diagnose the full system in one command: binaries,
  `__CLAUDE_BIN__` patch, config dir, profile dirs, proxy confs, Keychain entries,
  active profile validity.

- [ ] 6. **`claude-proxy update --version <n>`** — pin to a specific release instead of
  always pulling `main`.

---

## Installation

- [ ] 7. **Install a specific version** — respect `VERSION` env var in `install.sh` and
  download tagged assets instead of always fetching from `main`:
  ```bash
  VERSION=2.0.0 bash <(curl -fsSL .../install.sh)
  ```

---

## CI / DX

- [ ] 8. **GitHub Actions** — auto-run `bats proxied-claude.bats` on push and pull requests.

- [ ] 9. **Shell completions (zsh / bash)** — tab-complete subcommands, profile names,
  and proxy names.

---

## Platform

- [ ] 10. **Linux support** — replace macOS `security` CLI with a pluggable Keychain backend:
  `secret-tool` (GNOME Keyring), `pass`, or a permissions-restricted file as fallback.