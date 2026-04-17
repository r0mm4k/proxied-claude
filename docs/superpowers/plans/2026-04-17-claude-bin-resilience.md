# CLAUDE_BIN Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make proxied-claude resilient to Claude Code reinstalls (brew ↔ bootstrap) without requiring manual reconfiguration.

**Architecture:** Five changes — (1) runtime fallback in proxied-claude when baked CLAUDE_BIN is stale, (2) remove silent override in install.sh, (3) `--force` flag in claude-proxy update to re-bake CLAUDE_BIN, (4) wizard skip in install.sh when config exists, (5) docs update.

**Tech Stack:** Bash, bats-core tests

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `proxied-claude:25-26` | Modify | Replace hard die with fallback + warning |
| `install.sh:74-84` | Modify | Remove line 83 override, restructure else-branch |
| `install.sh:146-155` | Modify | Skip wizard when config already exists |
| `claude-proxy:1104-1181` | Modify | Add `--force` flag to cmd_update |
| `claude-proxy:35,491-532` | Modify | Update help text and header comment |
| `proxied-claude.bats:399-412` | Modify | Sync test helper cmd_update with `--force` |
| `proxied-claude.bats` (append) | Create tests | New tests for `--force` + structural test for fallback |
| `README.md:476` | Modify | Update CLAUDE_BIN limitation text |

---

### Task 1: proxied-claude — CLAUDE_BIN fallback

**Files:**
- Modify: `proxied-claude:25-26`
- Test: `proxied-claude.bats` (structural)

- [ ] **Step 1: Write structural test for fallback**

Add at the end of the architecture tests section (after line ~1708):

```bash
@test "architecture: wrapper has CLAUDE_BIN fallback via command -v" {
  grep -q "command -v claude" "$(dirname "$BATS_TEST_FILENAME")/proxied-claude"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats proxied-claude.bats --filter "wrapper has CLAUDE_BIN fallback"`
Expected: FAIL — `proxied-claude` doesn't contain `command -v claude` yet.

- [ ] **Step 3: Implement fallback in proxied-claude**

Replace lines 25-26:

```bash
[[ -x "$CLAUDE_BIN" ]] || die "Claude binary not found: $CLAUDE_BIN
  Re-run the installer or reinstall Claude Code."
```

With:

```bash
if [[ ! -x "$CLAUDE_BIN" ]]; then
  _fb="$(command -v claude 2>/dev/null)" || true
  if [[ -n "$_fb" && -x "$_fb" ]]; then
    echo "proxied-claude: WARNING: $CLAUDE_BIN not found, using $_fb" >&2
    echo "proxied-claude: Run 'claude-proxy update --force' to fix permanently." >&2
    CLAUDE_BIN="$_fb"
  else
    die "Claude binary not found: $CLAUDE_BIN
  Reinstall Claude Code, then run: claude-proxy update --force"
  fi
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats proxied-claude.bats --filter "wrapper has CLAUDE_BIN fallback"`
Expected: PASS

- [ ] **Step 5: Run full architecture tests to verify no breakage**

Run: `bats proxied-claude.bats --filter "architecture:"`
Expected: all PASS. Our changes don't add matches for any existing grep patterns (`migrate`, `ensure_default_profile`, `active_dir`, `CLAUDE_DIR/ide`, `PROXIED_CLAUDE_PROFILE`).

- [ ] **Step 6: Commit**

```bash
git add proxied-claude proxied-claude.bats
git commit -m "feat: add CLAUDE_BIN fallback when baked path is stale

proxied-claude now tries 'command -v claude' as fallback before dying.
Shows warning and suggests 'claude-proxy update --force' to fix permanently."
```

---

### Task 2: install.sh — remove silent override

**Files:**
- Modify: `install.sh:74-84`

- [ ] **Step 1: Replace Claude detection logic**

Replace lines 74-84:

```bash
if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
else
  echo "Claude not found — installing via Homebrew..."
  command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install: https://brew.sh"
  brew install --cask claude-code
  CLAUDE_BIN="$(command -v claude)"
fi
# Prefer canonical Homebrew path on Apple Silicon
[[ -x "/opt/homebrew/bin/claude" ]] && CLAUDE_BIN="/opt/homebrew/bin/claude"
echo "Claude binary: $CLAUDE_BIN"
```

With:

```bash
if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
else
  echo "Claude not found — installing via Homebrew..."
  command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install: https://brew.sh"
  brew install --cask claude-code
  # PATH may not include new binary yet — check known locations
  if [[ -x "/opt/homebrew/bin/claude" ]]; then
    CLAUDE_BIN="/opt/homebrew/bin/claude"
  elif [[ -x "/usr/local/bin/claude" ]]; then
    CLAUDE_BIN="/usr/local/bin/claude"
  else
    CLAUDE_BIN="$(command -v claude 2>/dev/null)" \
      || die "Claude not found after brew install. Open a new terminal and retry."
  fi
fi
echo "Claude binary: $CLAUDE_BIN"
```

- [ ] **Step 2: Run full test suite to verify nothing broke**

Run: `bats proxied-claude.bats`
Expected: all PASS. install.sh is not unit-tested, but architecture tests scan source files.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "fix: remove silent CLAUDE_BIN override in install.sh

Line 83 unconditionally preferred /opt/homebrew/bin/claude, overriding
the user's PATH choice (e.g. bootstrap install). Now only falls back
to known paths inside the brew-install branch where PATH may not have
updated yet."
```

---

### Task 3: claude-proxy — `update --force`

**Files:**
- Modify: `claude-proxy:1104-1181` (cmd_update)
- Modify: `claude-proxy:35` (header comment)
- Modify: `claude-proxy:524` (print_help)
- Modify: `claude-proxy:1115` (die Usage text)
- Modify: `proxied-claude.bats:399-412` (test helper cmd_update)
- Test: `proxied-claude.bats` (new tests)

- [ ] **Step 1: Write test — `--force` bypasses already-up-to-date**

Add after the `update: already up to date` test (after line ~2128):

```bash
@test "update: --force bypasses already-up-to-date check" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    if [[ "$*" == *api.github.com* ]]; then
      echo '{"tag_name":"v2.0.0"}'
    else
      echo "INSTALL_SH_DOWNLOADED"
    fi
  }
  local _out; _out="$(mktemp)"
  printf 'y\n' | cmd_update --force > "$_out" 2>&1
  local _captured; _captured="$(cat "$_out")"; rm -f "$_out"
  [[ "$_captured" != *"Already up to date"* ]]
  [[ "$_captured" == *"Reinstall"* ]]
}
```

- [ ] **Step 2: Write test — `--force` with `--version`**

```bash
@test "update: --force with --version works" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  curl() {
    echo "INSTALL_SH_DOWNLOADED"
  }
  local _out; _out="$(mktemp)"
  printf 'y\n' | cmd_update --force --version v2.0.0 > "$_out" 2>&1
  local _captured; _captured="$(cat "$_out")"; rm -f "$_out"
  [[ "$_captured" != *"Already up to date"* ]]
  [[ "$_captured" == *"Reinstall"* ]]
}
```

- [ ] **Step 3: Write test — `--force` alone fetches from API**

```bash
@test "update: --force alone fetches version from API" {
  _define_helpers
  VERSION="2.0.0"
  require_interactive() { :; }
  local _api_called=0
  curl() {
    if [[ "$*" == *api.github.com* ]]; then
      _api_called=1
      echo '{"tag_name":"v2.0.0"}'
    else
      echo "INSTALL_SH_DOWNLOADED"
    fi
  }
  local _out; _out="$(mktemp)"
  printf 'y\n' | cmd_update --force > "$_out" 2>&1
  rm -f "$_out"
  [ "$_api_called" -eq 1 ]
}
```

- [ ] **Step 4: Run new tests to verify they fail**

Run: `bats proxied-claude.bats --filter "update: --force"`
Expected: FAIL — `--force` not recognized yet.

- [ ] **Step 5: Update test helper cmd_update (bats:399-412)**

Replace the arg parsing block (lines 402-412):

```bash
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
```

With:

```bash
    local _force=0

    # Parse args
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --version)
          [[ -n "${2:-}" ]] || die "Usage: claude-proxy update [--force] [--version <tag>]"
          _target_version="$2"; shift 2 ;;
        --force) _force=1; shift ;;
        *)
          die "Unknown option: $1
Usage: claude-proxy update [--force] [--version <tag>]" ;;
      esac
    done
```

- [ ] **Step 6: Update test helper — already-up-to-date check (bats:431)**

Replace lines 431-434:

```bash
    if [[ -n "$_target_version" && "$_installed" == "$_target_version" ]]; then
      echo "Already up to date: $_installed"
      return 0
    fi
```

With:

```bash
    if [[ -n "$_target_version" && "$_installed" == "$_target_version" && "$_force" -eq 0 ]]; then
      echo "Already up to date: $_installed"
      return 0
    fi
```

- [ ] **Step 7: Update test helper — prompt verb (bats:454)**

Replace line 454:

```bash
      read -r -p "Upgrade to $_target_version? [y/N] " _confirm
```

With:

```bash
      if [[ "$_installed" == "$_target_version" ]]; then
        read -r -p "Reinstall $_target_version? [y/N] " _confirm
      else
        read -r -p "Upgrade to $_target_version? [y/N] " _confirm
      fi
```

- [ ] **Step 8: Run new tests to verify they pass**

Run: `bats proxied-claude.bats --filter "update: --force"`
Expected: all 3 PASS.

- [ ] **Step 9: Run existing update tests to verify no breakage**

Run: `bats proxied-claude.bats --filter "update:"`
Expected: all PASS, including the existing `already up to date` test (without `--force` it still returns early).

- [ ] **Step 10: Implement `--force` in real cmd_update (claude-proxy:1104-1167)**

Replace lines 1105-1117 (arg parsing):

```bash
  local _target_version="" _label="Latest"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ -n "${2:-}" ]] || die "Usage: claude-proxy update --version <tag> (e.g. v2.1.0)"
        _target_version="${2#v}"; _target_version="v${_target_version}"; _label="Target"; shift 2 ;;
      *)
        die "Unknown option: $1
Usage: claude-proxy update [--version <tag>]" ;;
    esac
  done
```

With:

```bash
  local _target_version="" _label="Latest" _force=0

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ -n "${2:-}" ]] || die "Usage: claude-proxy update [--force] [--version <tag>]"
        _target_version="${2#v}"; _target_version="v${_target_version}"; _label="Target"; shift 2 ;;
      --force) _force=1; shift ;;
      *)
        die "Unknown option: $1
Usage: claude-proxy update [--force] [--version <tag>]" ;;
    esac
  done
```

- [ ] **Step 11: Update already-up-to-date check (claude-proxy:1137)**

Replace lines 1137-1140:

```bash
  if [[ "$_installed" == "$_target_version" ]]; then
    echo "Already up to date: $_installed"
    return 0
  fi
```

With:

```bash
  if [[ "$_installed" == "$_target_version" && "$_force" -eq 0 ]]; then
    echo "Already up to date: $_installed"
    return 0
  fi
```

- [ ] **Step 12: Update prompt verb for reinstall (claude-proxy:1159-1167)**

Replace lines 1159-1167:

```bash
  # Detect direction: downgrade if new < installed
  local _lo _prompt_verb
  _lo="$(printf '%s\n%s\n' "${VERSION}" "${_target_version#v}" | sort -V | head -1)"
  if [[ "$_lo" == "${_target_version#v}" ]]; then
    _prompt_verb="Downgrade"
  else
    _prompt_verb="Upgrade"
  fi
  confirm "$_prompt_verb to $_target_version? [y/N] " || { echo "Aborted."; return 0; }
```

With:

```bash
  # Detect direction: reinstall / downgrade / upgrade
  local _lo _prompt_verb _prompt_to="to "
  if [[ "$_installed" == "$_target_version" ]]; then
    _prompt_verb="Reinstall"
    _prompt_to=""
  else
    _lo="$(printf '%s\n%s\n' "${VERSION}" "${_target_version#v}" | sort -V | head -1)"
    if [[ "$_lo" == "${_target_version#v}" ]]; then
      _prompt_verb="Downgrade"
    else
      _prompt_verb="Upgrade"
    fi
  fi
  confirm "$_prompt_verb ${_prompt_to}$_target_version? [y/N] " || { echo "Aborted."; return 0; }
```

This produces correct prompts: "Upgrade to v2.2.0?", "Downgrade to v2.1.0?", "Reinstall v2.1.8?" (no "to").

- [ ] **Step 13: Update help text (claude-proxy:524)**

Replace:

```
  claude-proxy update [--version <tag>]  → update to latest release (preview + confirmation)
```

With:

```
  claude-proxy update [--force] [--version <tag>]  → update/reinstall (preview + confirmation)
```

- [ ] **Step 14: Update header comment (claude-proxy:35)**

Replace:

```
#   claude-proxy update [--version <tag>]  → update to latest release (preview + confirmation)
```

With:

```
#   claude-proxy update [--force] [--version <tag>]  → update/reinstall (preview + confirmation)
```

- [ ] **Step 15: Update die Usage message (claude-proxy:1115)**

Already handled in step 10 — the Usage line in the die block was updated there.

- [ ] **Step 16: Run full test suite**

Run: `bats proxied-claude.bats`
Expected: all PASS.

- [ ] **Step 17: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: add --force flag to claude-proxy update

Allows re-baking CLAUDE_BIN without a version change. Useful when the
user switches Claude installation method (brew ↔ bootstrap) but
proxied-claude version stays the same."
```

---

### Task 4: install.sh — wizard skip when config exists

**Files:**
- Modify: `install.sh:146-155`

- [ ] **Step 1: Update wizard gate condition**

Replace lines 146-155:

```bash
# ── 6. First-run wizard (skipped on upgrade) ─────────────────────────────

if [[ "$IS_UPGRADE" == "1" ]]; then
  echo ""
  ok "Upgrade complete. All your profiles and proxies are unchanged."
  echo ""
  echo "Version : $_install_version"
  echo "Help    : claude-proxy help"
  exit 0
fi
```

With:

```bash
# ── 6. First-run wizard (skipped on upgrade or existing config) ──────────

if [[ "$IS_UPGRADE" == "1" ]]; then
  echo ""
  ok "Upgrade complete. All your profiles and proxies are unchanged."
  echo ""
  echo "Version : $_install_version"
  echo "Help    : claude-proxy help"
  exit 0
fi

if [[ -f "$CONF_DIR/profiles/default.conf" ]]; then
  echo ""
  ok "Installation complete. Existing config preserved. v$_install_version"
  echo ""
  echo "Run 'hash -r' or open a new terminal if commands aren't found yet."
  echo ""
  echo "Full help: claude-proxy help"
  exit 0
fi
```

- [ ] **Step 2: Run full test suite to verify nothing broke**

Run: `bats proxied-claude.bats`
Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "fix: skip wizard when config already exists

Previously the wizard ran on every manual 'bash install.sh' even with
existing profiles. Now it only runs on true first install (no
default.conf). Prevents user confusion on reinstall."
```

---

### Task 5: Documentation updates

**Files:**
- Modify: `README.md:476`
- Modify: `CLAUDE.md` (line count if changed)

- [ ] **Step 1: Update README limitation**

Replace line 476:

```
- `CLAUDE_BIN` path is fixed at install time — re-run `install.sh` if Claude is reinstalled to a different location
```

With:

```
- `CLAUDE_BIN` path is baked at install time — if the path becomes stale, proxied-claude auto-detects claude from PATH and warns; run `claude-proxy update --force` to re-bake permanently
```

- [ ] **Step 2: Verify proxied-claude line count for CLAUDE.md**

Run: `wc -l proxied-claude`

If the line count changed from 127 (currently stated as ~109 in CLAUDE.md), update CLAUDE.md accordingly. The "thin launcher (~109 lines)" count in CLAUDE.md is approximate — update only if significantly different.

- [ ] **Step 3: Run full test suite — final verification**

Run: `bats proxied-claude.bats`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update CLAUDE_BIN limitation text for new fallback behavior"
```