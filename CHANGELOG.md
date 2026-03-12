# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-03-12

### Added
- `claude-proxy check` — verifies proxy connectivity in three steps:
  TCP reachability, proxy auth + CONNECT tunnel, Anthropic API reachability (`/v1/models`)
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
