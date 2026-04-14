# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---
## [2.1.5] - 2026-04-14
### Fixed
- Hide login note in copy-settings when user declines overwrite

## [2.1.4] - 2026-04-13
### Fixed
- Replace read -p with printf+read to fix interactive prompts in bash 3.2
- Use sudo install instead of sudo cp to prevent stale fd reads after update

## [2.1.3] - 2026-04-13
### Fixed
- Strip trailing \r from all interactive prompts to fix python3 terminal interference

## [2.1.2] - 2026-04-13
### Fixed
- Remove local from _TMP in cmd_update to prevent unbound variable error on EXIT trap

## [2.1.1] - 2026-04-13
### Fixed
- Prevent python3 from consuming stdin before interactive prompts; add blank lines after prompt answers

## [2.1.0] - 2026-04-13
### Added
- Update fetches latest release from GitHub API, detects already-up-to-date
- Update shows version preview, major version warning, and asks confirmation
- Wizard proxy setup for default profile; fix double login note on profile create --from

### Changed
- Extract cmd_update(), add --version arg parsing and require_interactive guard
- Remove dead branches in cmd_update after _target_version is always set
- Simplify dir_has_data to single process; unify printf in helpers
- Use keychain_service() in uninstall instead of inline hardcode
- Profile rename uses profile_claude_dir() instead of manual fallback
- Cmd_update — remove Reinstall dead branch, redundant guard, simplify version vars
- Extract mcp_has_conflict and mcp_copy_servers helpers from do_copy_settings
- Extract cmd_status, cmd_check, cmd_run from inline case blocks

### Documentation
- Also bump SCRIPT_VERSION in install.sh as part of release process
- Add implementation plan for update version preview and --version flag (#25, #6)
- Update help text and CONTRIBUTING for update --version flag
- Show --version flag in help text; fix: guard major version comparison against non-numeric input
- Remove redundant update example line in header comment
- Remove redundant update example line in print_help
- Update security note — update downloads from release tag, not main
- Add update --version flag to README command reference
- Update CLAUDE.md — claude-proxy line count, remove stale line numbers
- Add REPO_RAW example for installing from branch/main

### Fixed
- Shellcheck --severity=error to skip SC2015 info warnings
- Rename VERSION to SCRIPT_VERSION in install.sh to avoid collision with pinning env var
- Normalize --version tag, downgrade prompt, banner version, sync comments
- Remove main-branch fallback and dead SCRIPT_VERSION

## [2.0.0] - 2026-04-13
### Added
- Replace per-item conflict warn with batch confirm/die in do_copy_settings
- Implement --include-projects (copy projects/*/memory/) in do_copy_settings
- Add --include-projects flag to profile copy-settings
- Add --include-projects to profile create
- Add dir_has_data() predicate with tests
- Warn and prompt when profile create finds existing dir with data
- Allow REPO_RAW env var override in install.sh
- Delete proxy.conf after migration instead of renaming to .migrated
- Always prompt to activate new profile, not only when default is active
- Rewrite claude profile dir paths in settings.json on copy-settings
- Change statusline format from 'profile › proxy' to 'profile (proxy)'
- Add ACTIVE_DIR var and update active_dir symlink in write_active
- Add _sync-active-dir command and call from install
- Add PROXIED_CLAUDE_PROFILE per-session override
- Add claude-proxy run for per-session profile launch
- Remove active_dir, add shared ide/ symlink logic to claude-proxy
- Remove active_dir from wrapper, add ide/ symlink safety net
- Replace _sync-active-dir with ide/ migration in install.sh
- Copy mcpServers from .claude.json in copy-settings (TODO #27)
- Add CI workflow — bats tests and shellcheck
- Add release workflow — auto-create GitHub Release on tag
- Support VERSION env var in install.sh for pinned installs

### Changed
- Remove dead .migrated idempotency code
- Move require_profile mirror into _define_helpers

### Documentation
- Update help text for --include-projects
- Update README, CHANGELOG, TODO for --include-projects
- Add design spec for profile create existing-dir handling
- Add implementation plan for profile create existing-dir handling
- Mark profile create existing-dir handling as done
- Update README, CHANGELOG for profile create existing-dir handling
- Add cleanup instruction for spec/plan files
- Add Fixed section to v2.0.0 changelog for proxy list column width
- Expand task 13 — profile+proxy display for PS1 and statusline
- Add profile statusline display design spec
- Add profile statusline implementation plan
- Add Claude Code statusline integration snippet
- Mark task 13 complete — statusline snippet shipped
- Update changelog — statusline snippet, test count 107→151
- Add copy-settings path rewrite design spec
- Add copy-settings path rewrite implementation plan
- Update changelog — copy-settings path rewrite, test count 151→154
- Update changelog — statusline format profile (proxy)
- Add gist link to statusline integration section
- Simplify gist link in statusline section
- Add IDE integration hints — command + config dir
- Update changelog — active_dir, PROXIED_CLAUDE_PROFILE, run command
- Update README and CLAUDE.md — active_dir, run shortcut, line counts
- Add notes to TODO
- Expand TODO #8 — dir-based auto-switch design and implementation plan
- Fix TODO numbering — sequential 1-23, update cross-references
- Add TODO #24 profile create --proxy, #25 update confirmation
- Expand TODO #25 — major version warning before update
- Add design spec for shared ide/ dir (remove active_dir)
- Revise design spec — fix 5 issues found in review
- Add implementation plan for shared ide/ dir
- Update TODO #7 for shared ide/ architecture — no per-project IDE config needed
- Add IDE restart note and mcpServers row to copy-settings table
- Update all references — active_dir removed, shared ide/ dir
- Update copy-settings table, TODO #27, changelog for CLAUDE_CONFIG_DIR and mcpServers fixes
- Explain TOCTOU early lock_release in proxy create
- Clarify CLAUDE_CONFIG_DIR is not set for default profile
- Add GitHub Releases design spec (#22, #18, #21)
- Add CONTRIBUTING.md to github-releases design scope
- Add GitHub Releases implementation plan
- Regenerate CHANGELOG.md with git-cliff (replaces manual file)
- Add CONTRIBUTING.md — git flow, commit conventions, release process

### Fixed
- Add local _fresh, add non-interactive create dir tests
- Use _run_ni helper to prevent test hang in non-interactive copy-settings tests
- Link proxy to existing default profile during v1 migration
- Suppress keychain dump stdout from security delete-generic-password
- Suppress keychain dump stdout from security add-generic-password -U
- Patch only CLAUDE_BIN assignment in sed, not the guard check
- Widen HOST column in proxy list from 30 to 38 chars
- Display_path backslash, IDE status spacing, _pc_info PROXIED_CLAUDE_PROFILE support
- Simplify install.sh config dir path — hardcode tilde
- Ensure ide/ target dir exists before creating symlink in safety-net
- Output full path in status IDE section; document tilde limitation
- Output full CONF_DIR path in installer wizard IDE section
- Multiple correctness and UX fixes from full code review
- Don't set CLAUDE_CONFIG_DIR for default profile (~/.claude)
- Rewrite plugin cache paths in manifests after copy-settings
- Use correct brew install --cask claude-code command

## [1.0.0] - 2026-03-11
