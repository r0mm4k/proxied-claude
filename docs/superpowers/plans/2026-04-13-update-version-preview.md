# Update Version Preview & --version Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `claude-proxy update` fetch the latest tagged release from GitHub API, show a version preview with confirmation, warn on major version bumps, and support `--version <tag>` to pin to a specific release.

**Architecture:** Extract inline `update)` block into `cmd_update()` function (mirrors existing pattern of `do_copy_settings`, `cmd_proxy_create`, etc.). `cmd_update` fetches `/releases/latest` via curl, compares with installed `VERSION`, shows preview, prompts confirmation, then passes `VERSION=<tag>` to `install.sh`. `require_interactive` is called early to fail fast in CI/pipes.

**Tech Stack:** bash, curl, python3 (JSON parsing — already used in project), bats-core

---

## Files

| Action | Path | What changes |
|--------|------|-------------|
| Modify | `claude-proxy` | Extract `cmd_update()`, add `--version` flag, GitHub API fetch, version comparison, preview, confirmation, pass VERSION to install.sh; update help text |
| Modify | `proxied-claude.bats` | Add tests for cmd_update (arg parsing, version comparison, major version warning, non-interactive guard) |
| Modify | `CONTRIBUTING.md` | Note `update --version <tag>` in release section |

---

## Context

**Key variables in `claude-proxy`:**
- `VERSION="2.0.0"` — installed version (without `v` prefix), line 39
- `cmd` dispatched at line 1099: `cmd="${1:-}"; shift || true`
- Inside `update)` block: `$1` is already the first arg after "update" (shift happened)

**Pattern for extracting functions (follow existing code):**
```bash
cmd_update() {
  local _target_version=""
  ...
}
# In dispatch:
update) cmd_update "$@" ;;
```

**python3 JSON parsing (already used in project for mcpServers):**
```bash
python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])"
```

**Test helper pattern (from proxied-claude.bats `_define_helpers`):**
```bash
# Mock curl in test scope:
curl() { echo '{"tag_name":"v2.1.0"}'; }
# Mock require_interactive to no-op:
require_interactive() { :; }
```

---

## Task 1: Extract cmd_update + require_interactive guard

**Files:**
- Modify: `claude-proxy` (inline `update)` block → `cmd_update()` function)
- Modify: `proxied-claude.bats` (add tests)

This task makes `update` require interactive stdin and accept `--version <tag>`. No GitHub API call yet.

- [ ] **Step 1: Write failing tests**

Add at the end of `proxied-claude.bats`, before the final closing line (after the last `@test`):

```bash
# ── update command ────────────────────────────────────────────────────────────

@test "update: --version missing arg dies with usage" {
  _define_helpers
  require_interactive() { :; }
  run cmd_update --version
  assert_failure
  assert_output --partial "Usage: claude-proxy update --version"
}

@test "update: non-interactive without --version dies" {
  _define_helpers
  run cmd_update < /dev/null
  assert_failure
  assert_output --partial "requires interactive"
}

@test "update: --version with unknown flag dies" {
  _define_helpers
  require_interactive() { :; }
  run cmd_update --unknown
  assert_failure
  assert_output --partial "Unknown option"
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
bats proxied-claude.bats --filter "update:" 2>&1
```

Expected: 3 failures — `cmd_update: command not found` or similar.

- [ ] **Step 3: Extract cmd_update function**

In `claude-proxy`, find the current `update)` block (around line 1187):

```bash
  update)
    echo "Updating proxied-claude from GitHub..."
    echo "Your profiles, proxies and settings are preserved."
    echo ""
    _TMP="$(mktemp)"
    trap 'rm -f "$_TMP"' EXIT
    curl -fsSL --proto '=https' --tlsv1.2 \
      "https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh" \
      -o "$_TMP"
    PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
    ;;
```

Replace with a call to the new function (dispatch only):

```bash
  update) cmd_update "$@" ;;
```

Add `cmd_update()` as a new function BEFORE the main `case "$cmd"` block (around line 1099), following the same placement as other `cmd_*` functions. Insert after the last function definition and before the `ensure_default_profile` call:

```bash
cmd_update() {
  local _target_version=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ -n "${2:-}" ]] || die "Usage: claude-proxy update --version <tag> (e.g. v2.1.0)"
        _target_version="$2"; shift 2 ;;
      *)
        die "Unknown option: $1
  Usage: claude-proxy update [--version <tag>]" ;;
    esac
  done

  require_interactive

  _TMP="$(mktemp)"
  trap 'rm -f "$_TMP"' EXIT
  curl -fsSL --proto '=https' --tlsv1.2 \
    "https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh" \
    -o "$_TMP"
  echo "Updating proxied-claude from GitHub..."
  echo "Your profiles, proxies and settings are preserved."
  echo ""
  PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
}
```

- [ ] **Step 4: Run tests — verify pass**

```bash
bats proxied-claude.bats --filter "update:" 2>&1
```

Expected: 3 passing.

- [ ] **Step 5: Run full suite — verify no regressions**

```bash
bats proxied-claude.bats 2>&1 | tail -3
```

Expected: all passing, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "refactor: extract cmd_update(), add --version arg parsing and require_interactive guard"
```

---

## Task 2: GitHub API fetch + version comparison

**Files:**
- Modify: `claude-proxy` (add GitHub API fetch inside `cmd_update`)
- Modify: `proxied-claude.bats` (add version comparison tests)

- [ ] **Step 1: Write failing tests**

Add to `proxied-claude.bats` (after the Task 1 tests):

```bash
@test "update: already up to date exits early" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() { echo '{"tag_name":"v2.0.0"}'; }
  run cmd_update
  assert_success
  assert_output --partial "Already up to date"
}

@test "update: GitHub API failure falls back with warning" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() { return 1; }
  # Should not die — should warn and proceed with main
  run bash -c '
    _define_helpers 2>/dev/null || true
    VERSION="2.0.0"
    require_interactive() { :; }
    curl() { return 1; }
    # Stub out the install part so test does not try to run install.sh
    _do_install() { echo "INSTALL_CALLED"; }
    source /dev/stdin <<'"'"'EOF'"'"'
      cmd_update_fetch() {
        curl -fsSL "https://api.github.com/repos/r0mm4k/proxied-claude/releases/latest" \
          2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['"'"'tag_name'"'"'])" 2>/dev/null || true
      }
EOF
    result="$(cmd_update_fetch)"
    [[ -z "$result" ]] && echo "FALLBACK_OK"
  '
  assert_output --partial "FALLBACK_OK"
}
```

Actually the fetch fallback test is complex to isolate. Replace with a simpler structural test:

```bash
@test "update: already up to date exits 0 with message" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    # First curl call is GitHub API; second would be install.sh — we never reach it
    echo '{"tag_name":"v2.0.0"}'
  }
  run cmd_update
  assert_success
  assert_output --partial "Already up to date: v2.0.0"
}

@test "update: fetches new version tag from GitHub API" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  _install_calls=0
  curl() {
    if [[ "$*" == *api.github.com* ]]; then
      echo '{"tag_name":"v2.1.0"}'
    else
      echo "INSTALL_SH_DOWNLOADED"
    fi
  }
  bash() { echo "BASH_CALLED: VERSION=$VERSION"; }
  run cmd_update
  assert_output --partial "v2.0.0"
  assert_output --partial "v2.1.0"
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
bats proxied-claude.bats --filter "update:" 2>&1
```

Expected: new tests fail (cmd_update doesn't fetch GitHub API yet).

- [ ] **Step 3: Add GitHub API fetch and version comparison to cmd_update**

Update `cmd_update()` in `claude-proxy` to:

```bash
cmd_update() {
  local _target_version=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ -n "${2:-}" ]] || die "Usage: claude-proxy update --version <tag> (e.g. v2.1.0)"
        _target_version="$2"; shift 2 ;;
      *)
        die "Unknown option: $1
  Usage: claude-proxy update [--version <tag>]" ;;
    esac
  done

  require_interactive

  # Fetch latest release from GitHub if no version pinned
  if [[ -z "$_target_version" ]]; then
    local _fetched
    _fetched="$(curl -fsSL --proto '=https' --tlsv1.2 \
      "https://api.github.com/repos/r0mm4k/proxied-claude/releases/latest" \
      2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null \
      || true)"
    if [[ -n "$_fetched" ]]; then
      _target_version="$_fetched"
    else
      warn "Could not fetch latest version from GitHub. Installing from main branch."
    fi
  fi

  # Version comparison — skip if we could not fetch
  local _installed="v$VERSION"
  if [[ -n "$_target_version" && "$_installed" == "$_target_version" ]]; then
    echo "Already up to date: $_installed"
    return 0
  fi

  _TMP="$(mktemp)"
  trap 'rm -f "$_TMP"' EXIT
  curl -fsSL --proto '=https' --tlsv1.2 \
    "https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh" \
    -o "$_TMP"
  echo "Your profiles, proxies and settings are preserved."
  echo ""
  if [[ -n "$_target_version" ]]; then
    VERSION="$_target_version" PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
  else
    PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
  fi
}
```

- [ ] **Step 4: Run tests**

```bash
bats proxied-claude.bats --filter "update:" 2>&1
```

Expected: all update tests passing.

- [ ] **Step 5: Run full suite**

```bash
bats proxied-claude.bats 2>&1 | tail -3
```

Expected: all passing, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: update fetches latest release from GitHub API, detects already-up-to-date"
```

---

## Task 3: Version preview, major version warning, confirmation prompt

**Files:**
- Modify: `claude-proxy` (add preview + prompt between version comparison and install)
- Modify: `proxied-claude.bats` (add preview and major version warning tests)

- [ ] **Step 1: Write failing tests**

Add to `proxied-claude.bats`:

```bash
@test "update: shows installed and latest in preview (structural)" {
  grep -q "Installed\s*:" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
  grep -q "Latest\s*:" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
}

@test "update: major version warning present in source (structural)" {
  grep -q "Major version upgrade" "$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
}

@test "update: aborts when user answers N" {
  _define_helpers
  VERSION="2.0.0"
  # Extract cmd_update and run in subshell with mocked deps and piped 'n'
  run bash -c '
    CLAUDE_PROXY="$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
    source <(sed -n "/^cmd_update()/,/^}$/p" "$CLAUDE_PROXY")
    require_interactive() { :; }
    curl() { [[ "$*" == *api.github.com* ]] && echo '"'"'{"tag_name":"v2.1.0"}'"'"' || true; }
    bash() { echo "INSTALL_CALLED"; }
    VERSION="2.0.0"
    printf "n\n" | cmd_update
  ' "$(dirname "$BATS_TEST_FILENAME")"
  refute_output --partial "INSTALL_CALLED"
  assert_output --partial "Aborted"
}

@test "update: proceeds when user answers Y" {
  _define_helpers
  run bash -c '
    CLAUDE_PROXY="$(dirname "$BATS_TEST_FILENAME")/claude-proxy"
    source <(sed -n "/^cmd_update()/,/^}$/p" "$CLAUDE_PROXY")
    require_interactive() { :; }
    curl() { [[ "$*" == *api.github.com* ]] && echo '"'"'{"tag_name":"v2.1.0"}'"'"' || true; }
    bash() { echo "INSTALL_CALLED"; }
    VERSION="2.0.0"
    printf "y\n" | cmd_update
  ' "$(dirname "$BATS_TEST_FILENAME")"
  assert_output --partial "INSTALL_CALLED"
}
```

- [ ] **Step 2: Run to verify structural tests currently fail**

```bash
bats proxied-claude.bats --filter "update:" 2>&1 | grep -E "ok|not ok"
```

Expected: the new tests fail (preview/warning strings not in source yet).

- [ ] **Step 3: Add preview, warning, and confirmation to cmd_update**

Replace the section in `cmd_update()` between version comparison and install with:

```bash
  # Version preview and confirmation
  echo ""
  if [[ -n "$_target_version" ]]; then
    echo "  Installed : $_installed"
    echo "  Latest    : $_target_version"
    echo ""

    # Major version bump warning
    local _inst_major _new_major
    _inst_major="${VERSION%%.*}"
    _new_major="${_target_version#v}"; _new_major="${_new_major%%.*}"
    if [[ "$_new_major" -gt "$_inst_major" ]]; then
      warn "Major version upgrade ($_installed → $_target_version)."
      echo "   Review release notes before upgrading:"
      echo "   https://github.com/r0mm4k/proxied-claude/releases/tag/${_target_version}"
      echo ""
    fi

    read -r -p "Upgrade to $_target_version? [y/N] " _confirm
  else
    read -r -p "Upgrade to latest (main branch)? [y/N] " _confirm
  fi
  [[ "${_confirm:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }

  echo ""
  echo "Your profiles, proxies and settings are preserved."
  echo ""
```

The full `cmd_update()` now looks like:

```bash
cmd_update() {
  local _target_version=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ -n "${2:-}" ]] || die "Usage: claude-proxy update --version <tag> (e.g. v2.1.0)"
        _target_version="$2"; shift 2 ;;
      *)
        die "Unknown option: $1
  Usage: claude-proxy update [--version <tag>]" ;;
    esac
  done

  require_interactive

  # Fetch latest release from GitHub if no version pinned
  if [[ -z "$_target_version" ]]; then
    local _fetched
    _fetched="$(curl -fsSL --proto '=https' --tlsv1.2 \
      "https://api.github.com/repos/r0mm4k/proxied-claude/releases/latest" \
      2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null \
      || true)"
    if [[ -n "$_fetched" ]]; then
      _target_version="$_fetched"
    else
      warn "Could not fetch latest version from GitHub. Installing from main branch."
    fi
  fi

  # Already up to date?
  local _installed="v$VERSION"
  if [[ -n "$_target_version" && "$_installed" == "$_target_version" ]]; then
    echo "Already up to date: $_installed"
    return 0
  fi

  # Version preview
  echo ""
  if [[ -n "$_target_version" ]]; then
    echo "  Installed : $_installed"
    echo "  Latest    : $_target_version"
    echo ""

    # Major version bump warning
    local _inst_major _new_major
    _inst_major="${VERSION%%.*}"
    _new_major="${_target_version#v}"; _new_major="${_new_major%%.*}"
    if [[ "$_new_major" -gt "$_inst_major" ]]; then
      warn "Major version upgrade ($_installed → $_target_version)."
      echo "   Review release notes before upgrading:"
      echo "   https://github.com/r0mm4k/proxied-claude/releases/tag/${_target_version}"
      echo ""
    fi

    read -r -p "Upgrade to $_target_version? [y/N] " _confirm
  else
    read -r -p "Upgrade to latest (main branch)? [y/N] " _confirm
  fi
  [[ "${_confirm:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }

  # Install
  echo ""
  echo "Your profiles, proxies and settings are preserved."
  echo ""
  local _TMP
  _TMP="$(mktemp)"
  trap 'rm -f "$_TMP"' EXIT
  curl -fsSL --proto '=https' --tlsv1.2 \
    "https://raw.githubusercontent.com/r0mm4k/proxied-claude/main/install.sh" \
    -o "$_TMP"
  if [[ -n "$_target_version" ]]; then
    VERSION="$_target_version" PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
  else
    PROXIED_CLAUDE_UPGRADE=1 bash "$_TMP"
  fi
}
```

- [ ] **Step 4: Run tests**

```bash
bats proxied-claude.bats --filter "update:" 2>&1
```

Expected: all update tests passing.

- [ ] **Step 5: Run full suite**

```bash
bats proxied-claude.bats 2>&1 | tail -3
```

Expected: all passing, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: update shows version preview, major version warning, and asks confirmation"
```

---

## Task 4: Update help text and CONTRIBUTING.md

**Files:**
- Modify: `claude-proxy` (help text for `update`)
- Modify: `CONTRIBUTING.md` (note `--version` flag in release section)

- [ ] **Step 1: Update help text in claude-proxy**

Find in `print_help()` (around line 488):
```bash
  claude-proxy update         → update to latest from GitHub
```

Replace with:
```bash
  claude-proxy update [--version <tag>]  → update to latest release from GitHub
                                            (fetches latest tag, shows preview, asks confirmation)
  claude-proxy update --version v2.0.0  → install a specific release
```

Also update the Shortcuts section (around line 488):
```bash
  claude-proxy update         → update to latest from GitHub
```
Replace with:
```bash
  claude-proxy update         → update to latest release (with preview and confirmation)
```

- [ ] **Step 2: Update CONTRIBUTING.md**

In the Release Process section, the user describes `claude-proxy update` to users. Add a note after the release steps:

Find:
```markdown
GitHub Actions picks up the tag and creates the GitHub Release with generated release notes.
```

Add after:
```markdown

Users can then upgrade with:
```bash
claude-proxy update                    # installs latest release (with preview)
claude-proxy update --version v2.1.0   # pin to a specific release
```
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck claude-proxy
```

Expected: no output.

- [ ] **Step 4: Run full test suite**

```bash
bats proxied-claude.bats 2>&1 | tail -3
```

Expected: all passing, 0 failures.

- [ ] **Step 5: Commit and push**

```bash
git add claude-proxy CONTRIBUTING.md
git commit -m "docs: update help text and CONTRIBUTING for update --version flag"
git push origin main
```