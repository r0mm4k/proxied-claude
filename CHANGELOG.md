# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
  - `update` — update to latest version from GitHub
  - `uninstall` — remove all installed files and Keychain entry
- Password stored securely in **macOS Keychain** — never written to disk in plaintext
- `localhost` excluded from proxying via `NO_PROXY` (WebStorm / IDE bridge support)
