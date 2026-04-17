# proxied-claude — Claude Code with corporate proxy and multiple accounts (macOS)

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) behind a **corporate HTTP proxy** on macOS, with full support for **multiple Claude accounts** (profiles) and **multiple named proxies** — passwords stored securely in **macOS Keychain**.

![macOS only](https://img.shields.io/badge/platform-macOS-lightgrey)
![requires Homebrew](https://img.shields.io/badge/requires-Homebrew-blueviolet)
![Claude Code](https://img.shields.io/badge/Claude-Code-orange)
![License MIT](https://img.shields.io/badge/license-MIT-yellow)
[![Tests](https://img.shields.io/github/actions/workflow/status/r0mm4k/proxied-claude/ci.yml?label=tests)](https://github.com/r0mm4k/proxied-claude/actions/workflows/ci.yml)
![Version](https://img.shields.io/github/v/release/r0mm4k/proxied-claude)

> ⚠️ Independent community tool — not affiliated with or endorsed by Anthropic.
> You need your own Claude subscription.

---

## Who is this for?

Developers who:
- Work behind a **corporate HTTP proxy** and need Claude Code to route through it
- Use **multiple Claude accounts** (e.g. a work Team account and a personal Pro account)
- Want **separate Claude sessions** per account — different history, login, and settings
- Use **JetBrains** or **VS Code** with Claude Code and need one command that always picks the right account and proxy

---

## How it works

```
proxied-claude
  └─ reads PROXIED_CLAUDE_PROFILE env var (per-session override, optional)
  └─ reads ~/.config/proxied-claude/active_profile (fallback)
  └─ loads profiles/<n>.conf       → CLAUDE_CONFIG_DIR, linked proxy name
  └─ loads proxies/<proxy>.conf    → host, user, keychain service name
  └─ fetches password from macOS Keychain (never written to disk)
  └─ exports CLAUDE_CONFIG_DIR (named profiles only) + HTTP_PROXY / HTTPS_PROXY
  └─ ensures ide/ symlink exists → ~/.config/proxied-claude/ide/
  └─ exec → claude (original binary)
```

The wrapper is intentionally thin (~109 lines) — no migration, no self-repair, no overhead. All management is done by `claude-proxy`.

**Default profile:** A profile named `default` is created automatically on install and points to `~/.claude` — the standard Claude Code directory. If you never create additional profiles, everything works exactly as before.

`localhost` is always excluded from proxying (`NO_PROXY`), so the IDE ↔ Claude bridge keeps working.

---

## Requirements

- macOS (uses `security` CLI for Keychain)
- [Homebrew](https://brew.sh)
- Claude Code (auto-installed if missing)
- `python3` — only for `claude-proxy profile copy-settings` (MCP server transfer); pre-installed on most macOS systems

---

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh)
```

Or if you have the repo cloned:

```bash
chmod +x ./install.sh
./install.sh
```

To install from a specific branch or commit (e.g. for local testing):

```bash
REPO_RAW="https://raw.githubusercontent.com/r0mm4k/proxied-claude/main" bash install.sh
```

The installer:
1. Installs Claude Code via `brew install --cask claude-code` if not present
2. Installs `/usr/local/bin/proxied-claude` — the wrapper
3. Installs `/usr/local/bin/claude-proxy` — the control utility
4. **Auto-migrates** any existing v1 config (`proxy.conf`) — your proxy settings and Keychain password are preserved automatically
5. Creates a `default` profile pointing to `~/.claude` (if not already present)
6. Optionally walks you through setting up a proxy for the `default` profile and/or creating additional profiles

> **Just want a proxy on the default profile?** Answer Y to the first wizard question to set one up, then press Enter to skip creating additional profiles.
>
> **Want to skip entirely?** Press Enter twice — the `default` profile points to your existing `~/.claude` and everything works as before.

---

## Upgrading from v1

If you used the previous version of proxied-claude (with `proxy.conf`), just run:

```bash
claude-proxy update
```

Your proxy settings are migrated automatically:
- `proxy.conf` → `profiles/default.conf` + `proxies/default.conf`
- Keychain entry renamed from `claude-proxy` → `claude-proxy:default`
- Old Keychain entry removed
- `proxy.conf` deleted after successful migration

Everything works exactly as before — no action needed.

---

## Quick start

```bash
# 1. Create named proxies
claude-proxy proxy create corp-lt 10.0.0.1:3128 john
claude-proxy proxy create home-de 192.168.1.1:8080 roman

# 2. Create profiles, optionally copying settings from default
claude-proxy profile create work --from default
claude-proxy profile create personal

# 3. Link proxies to profiles
claude-proxy profile set-proxy work     corp-lt
claude-proxy profile set-proxy personal home-de

# 4. Switch active profile
claude-proxy use work

# 5. Run Claude — picks up the active profile automatically
proxied-claude
```

---

## Per-profile setup

`proxied-claude` is a transparent wrapper — every `claude` subcommand works through it and automatically targets the active profile's config directory. This means authentication, MCP servers, and plugins are all per-profile:

```bash
# Active profile
proxied-claude auth login
proxied-claude mcp add my-server npx -y my-mcp-server
proxied-claude plugin install superpowers

# Specific profile (without switching the active one)
PROXIED_CLAUDE_PROFILE=work proxied-claude auth login
PROXIED_CLAUDE_PROFILE=work proxied-claude mcp add my-server npx -y my-mcp-server
PROXIED_CLAUDE_PROFILE=work proxied-claude plugin install superpowers
```

`claude-proxy run` is a shorthand for the same thing:

```bash
claude-proxy run work mcp add my-server npx -y my-mcp-server
claude-proxy run work auth login
```

MCP server config is also portable across profiles via `claude-proxy profile copy-settings` (see the [copy-settings table](#what-gets-copied-with-copy-settings)).

---

## Commands

### Profiles

Each profile is one Claude account with its own isolated config directory and an optional linked proxy. The `default` profile always points to `~/.claude` and cannot be deleted.

```bash
claude-proxy profile list
# Lists all profiles with proxy and directory info

claude-proxy profile create <n> [--from <source>] [--include-projects]
# Creates a new profile → ~/.claude-<n>
# --from <source>: copies settings from <source> profile
# --include-projects: also copies projects/*/memory/ (project context, not history)
# Without --from: interactively asks which profile to copy settings from (and whether to include project memory)
# If ~/.claude-<n> already exists with data: warns and asks whether to start fresh [y/N]
#   N (default): keeps existing data (login note adjusted accordingly)
#   Y: deletes existing data and starts clean
#   Non-interactive: keeps existing data silently + warns

claude-proxy profile delete <n>
# Deletes profile config (cannot delete 'default' or the active profile)
# Claude dir (~/.claude-<n>) is kept on disk

claude-proxy profile rename <old> <new>
# Renames a profile and moves its Claude dir
# Auto-generated dirs are renamed; custom dirs are kept as-is

claude-proxy profile use <n>
# Switches the active profile

claude-proxy profile show [<n>]
# Shows profile details: name, Claude dir, proxy, host, user
# Without argument: shows the active profile

claude-proxy profile set-proxy <profile> <proxy>
# Links a proxy to a profile

claude-proxy profile unset-proxy <profile>
# Removes proxy link — profile runs with a direct connection

claude-proxy profile copy-settings <profile> --from <source> [--include-projects]
# Copies portable config files from <source> to <profile>
# --include-projects: also copies projects/*/memory/ (project context, not history)
# Does NOT copy: auth tokens, chat history, credentials
# If destination has existing files: shows conflict summary and asks once to confirm;
# non-interactive with conflicts → exits with error
```

### Proxies

Named, reusable proxy configurations. Passwords live in macOS Keychain only — never in plain files.

```bash
claude-proxy proxy list
# Lists all proxies with host/user and which profiles use them

claude-proxy proxy create <n> <host:port> <user>
# Creates proxy config + saves password to Keychain

claude-proxy proxy delete <n>
# Deletes proxy config + removes Keychain entry
# Auto-unlinks all profiles that reference the proxy

claude-proxy proxy rename <old> <new>
# Renames proxy, migrates Keychain entry, updates all linked profiles

claude-proxy proxy set-password <n>
# Updates password in Keychain

claude-proxy proxy show <n>
# Shows proxy details (password is never shown)

claude-proxy proxy check <n>
# Tests three levels:
#   1. TCP connect to proxy host
#   2. Proxy authentication (detects HTTP 407)
#   3. Anthropic API reachability via CONNECT tunnel
```

### Shortcuts

```bash
claude-proxy use <n>        # → profile use (changes global active profile)
claude-proxy run <n>        # → launch with profile without changing global active profile
claude-proxy status         # → full overview (active profile + all profiles + all proxies)
claude-proxy check          # → proxy check for the active profile's proxy
claude-proxy version        # print version
claude-proxy migrate        # manually trigger v1 → v2 migration
claude-proxy update                    # re-download latest release from GitHub (preserves all config)
claude-proxy update --version v2.1.0  # pin to a specific release (also works for downgrade)
claude-proxy update --force            # re-bake CLAUDE_BIN (after brew ↔ bootstrap switch)
claude-proxy uninstall      # remove binaries + config (keeps ~/.claude* dirs)
```

---

## Config layout

```
~/.config/proxied-claude/
  active_profile              ← name of the currently active profile
  ide/                        ← shared IDE lock-file dir (all profiles symlink here)
  .lock/                      ← concurrency lock (auto-managed)
  profiles/
    default.conf              ← always exists, points to ~/.claude
    work.conf
    personal.conf
  proxies/
    default.conf              ← migrated from proxy.conf (if existed)
    corp-lt.conf
    home-de.conf

~/.claude/                    ← default profile (standard Claude dir)
~/.claude-work/               ← isolated session for "work"
~/.claude-personal/           ← isolated session for "personal"
```

---

## Examples

### v1 upgrade — nothing to do

```bash
claude-proxy update
# ── Migrating v1 config ──
# ✅  Proxy password migrated → Keychain: claude-proxy:default
# ✅  Old Keychain entry 'claude-proxy' removed
# ✅  Created proxies/default.conf (john@10.0.0.1:3128)
# ✅  Created profiles/default.conf → ~/.claude
# ── Installing proxied-claude ──
# ✅  /usr/local/bin/proxied-claude
# ── Installing claude-proxy ──
# ✅  /usr/local/bin/claude-proxy
# ✅  Upgrade complete.
```

### Work + personal accounts, different proxies

```bash
# Create work profile with settings copied from default
claude-proxy profile create work --from default
claude-proxy profile set-proxy work corp-lt

# Create personal profile (clean, no proxy)
claude-proxy profile create personal

# Switch and run
claude-proxy use work
proxied-claude          # work account, corp-lt proxy

claude-proxy use personal
proxied-claude          # personal account, no proxy
```

### Copy settings to an existing profile

```bash
# Copy only portable settings — no tokens, no history
claude-proxy profile copy-settings personal --from work
```

### Rename a profile or proxy

```bash
# Rename profile (moves ~/.claude-work → ~/.claude-company)
claude-proxy profile rename work company

# Rename proxy (migrates Keychain, updates all linked profiles)
claude-proxy proxy rename corp-lt corp-main
```

### Delete a proxy safely

```bash
claude-proxy proxy delete corp-lt
# ⚠️  Proxy 'corp-lt' is used by profile(s): work
# ⚠️  Those profiles will be unlinked and run without a proxy.
# Delete anyway? [y/N] y
#    Unlinked proxy from profile 'work'
#    Keychain entry removed
# ✅ Proxy 'corp-lt' deleted
```

### Check proxy health

```bash
claude-proxy proxy check corp-lt
#   TCP connect to 10.0.0.1:3128 ...          ✅ OK
#   Proxy authentication ...                   ✅ OK (HTTP 200)
#   Anthropic API via CONNECT tunnel ...      ✅ OK (HTTP 401)
#   ✅ Proxy 'corp-lt' looks good.
```

### Default profile with a proxy

```bash
# The default profile can also use a proxy
claude-proxy profile set-proxy default corp-lt
# Now proxied-claude (without switching profiles) routes through corp-lt
```

---

## IDE integration

### JetBrains (WebStorm, IntelliJ, etc.)

1. **Settings → Plugins → Marketplace** → search **Claude Code [Beta]** → Install → Restart
2. **Settings → Tools → Claude Code [Beta]** → Claude command:
   ```
   /usr/local/bin/proxied-claude
   ```
3. **Settings → Tools → Claude Code [Beta]** → Config directory:
   ```
   /Users/yourname/.config/proxied-claude
   ```
   Use the **full absolute path** — JetBrains does not expand `~`.
   Run `claude-proxy status` to get the exact value ready to copy.

All profile `ide/` directories are symlinks to `~/.config/proxied-claude/ide/`. The plugin writes lock files to this shared physical location and the CLI finds them regardless of which profile is active — no IDE restart needed when switching profiles with `claude-proxy use <n>`.

### VS Code

Add to your `settings.json`:
```json
{
  "claude.claudePath": "/usr/local/bin/proxied-claude"
}
```

---

## Claude Code statusline integration

If you use a custom `statusline.sh` hook, you can prepend the active profile and proxy
to the status line:

```
personal (home-de) | ctx:30% | ▲13 ▼5 | $1.22 | 5h:15% ~4h 7d:65% ~2d
```

Add to your `~/.claude-<profile>/hooks/statusline.sh`, near the top after color declarations:

```bash
CYAN=$'\033[36m'

_pc_info() {
  local conf="${HOME}/.config/proxied-claude"
  local profile="${PROXIED_CLAUDE_PROFILE:-}"
  if [[ -z "$profile" ]]; then
    [[ -f "${conf}/active_profile" ]] || return 0
    profile=$(tr -d '[:space:]' < "${conf}/active_profile")
  fi
  [[ -n "$profile" ]] || return 0
  local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
  proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
  [[ -n "$proxy" ]] && printf '%s' "${CYAN}${profile}${R} ${DIM}(${proxy})${R}" \
                    || printf '%s' "${CYAN}${profile}${R}"
}

PC_INFO=$(_pc_info)
[[ -n "$PC_INFO" ]] && PREFIX="${PC_INFO} ${DIM}|${R} " || PREFIX=""
```

Then prepend `${PREFIX}` to the main `printf` in your script:

```bash
printf '%s' "${PREFIX}ctx:..."
```

If proxied-claude is not installed, or no profile is active, `PREFIX` is empty and the
statusline is unchanged.

[Full statusline.sh example](https://gist.github.com/r0mm4k/1781d46e9b3c83c34253421d828924b5)

---

## What gets copied with `copy-settings`

| Item | Type | Copied | Notes |
|------|------|--------|-------|
| `settings.json` | file | ✅ Yes | UI preferences, themes, enabled plugins |
| `CLAUDE.md` | file | ✅ Yes | Global Claude instructions |
| `keybindings.json` | file | ✅ Yes | Custom keybindings |
| `policy-limits.json` | file | ✅ Yes | Usage policy overrides |
| `hooks/` | dir | ✅ Yes | Custom lifecycle hooks |
| `plugins/` | dir | ✅ Yes | Installed plugins |
| `.claude.json` (mcpServers) | file | ✅ Yes | `mcpServers` key only; other keys are profile-specific |
| `sessions/` | dir | ❌ No | Auth sessions — account-specific |
| `history.jsonl` | file | ❌ No | Chat history — stays in source profile |
| `cache/` | dir | ❌ No | Runtime cache |
| `backups/` | dir | ❌ No | Internal backups |
| `projects/*/memory/` | dir | ⚠️ Optional | Per-project memory — use `--include-projects` |
| `telemetry/` | dir | ❌ No | Telemetry data |

If files already exist in the destination profile, a summary of conflicts is shown and a single confirmation is requested. In non-interactive mode, conflicts cause an error — run interactively to confirm.

---

## Security notes

- Proxy **passwords are stored only in macOS Keychain** — never in `.conf` files.
- Config files are parsed with `grep` — **never sourced as bash**. Values like `$(cmd)` are treated as literal strings.
- `HTTPS_PROXY` (with password) is visible in `ps auxe` **while Claude is running** — acceptable on a personal Mac; be aware on shared machines.
- Profile and proxy **names are validated** — only `[a-zA-Z0-9_-]` allowed, preventing path traversal.
- The `update` command downloads from the release tag (or `main` as fallback) over HTTPS (`--proto '=https' --tlsv1.2`).
- Mutating commands use a **concurrency lock** to prevent race conditions.
- Commands requiring input (passwords, confirmations) **fail fast** when stdin is not a terminal.

---

## Limitations

- **macOS only** — relies on the `security` CLI for Keychain access
- **HTTP CONNECT proxies only** — SOCKS proxies are not supported by Claude Code
- `CLAUDE_BIN` path is baked at install time — if the path becomes stale, proxied-claude auto-detects claude from PATH and warns; run `claude-proxy update --force` to re-bake permanently

---

## License

MIT
