# Profile Statusline Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepend `personal › nigeria` (or just `personal` when no proxy, or nothing when proxied-claude absent) to the Claude Code statusline.

**Architecture:** A standalone `_pc_info()` shell function reads two files directly (`active_profile` + `profiles/<name>.conf`) using grep/tr — no subprocess to `claude-proxy`. Shipped as a README snippet; applied manually by the user to their `statusline.sh`. The function is also mirrored in `proxied-claude.bats` and tested there.

**Tech Stack:** bash, bats-core (tests), grep, tr (POSIX)

---

## File map

| File | Action | What changes |
|------|--------|--------------|
| `proxied-claude.bats` | Modify | Add `_pc_info` to `_define_helpers`; add test group `# statusline` |
| `~/.claude-personal/hooks/statusline.sh` | Modify | Add CYAN, `_pc_info()`, PREFIX logic, prepend PREFIX to final printf |
| `README.md` | Modify | Add section "Claude Code statusline integration" after "IDE integration" |
| `TODO.md` | Modify | Task 13: narrow to statusline only, remove zsh PS1 mention |

---

## Task 1: Add `_pc_info` to bats helpers and write failing tests

**Files:**
- Modify: `proxied-claude.bats` — `_define_helpers()` function (line ~80), add test group at end

- [ ] **Step 1: Add `_pc_info` to `_define_helpers`**

In `proxied-claude.bats`, find the closing `}` of `_define_helpers()` and insert the function before it:

```bash
  _pc_info() {
    local conf="${CONF_DIR}"
    [[ -f "${conf}/active_profile" ]] || return 0
    local profile; profile=$(tr -d '[:space:]' < "${conf}/active_profile")
    [[ -n "$profile" ]] || return 0
    local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
    proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
    [[ -n "$proxy" ]] && printf '%s › %s' "$profile" "$proxy" || printf '%s' "$profile"
  }
```

Note: in tests we use `CONF_DIR` (the temp dir), not `$HOME/.config/proxied-claude`. The function uses the same `read_conf`-style grep pattern used everywhere else in the project.

- [ ] **Step 2: Add test group at end of `proxied-claude.bats`**

Append after the last `@test` block:

```bash
# statusline
# ═══════════════════════════════════════════════════════════════════════════════

@test "statusline _pc_info: no active_profile → empty output" {
  _define_helpers
  run _pc_info
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "statusline _pc_info: empty active_profile → empty output" {
  _define_helpers
  echo "" > "$ACTIVE_FILE"
  run _pc_info
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "statusline _pc_info: profile with no proxy → profile name only" {
  _define_helpers
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY=""\n' \
    "$HOME/.claude-personal" > "$CONF_DIR/profiles/personal.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "statusline _pc_info: profile with proxy → profile › proxy" {
  _define_helpers
  echo "personal" > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY="nigeria"\n' \
    "$HOME/.claude-personal" > "$CONF_DIR/profiles/personal.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "personal › nigeria" ]
}

@test "statusline _pc_info: whitespace in active_profile is stripped" {
  _define_helpers
  printf '  work  \n' > "$ACTIVE_FILE"
  mkdir -p "$CONF_DIR/profiles"
  printf 'CONFIG_VERSION=1\nPROFILE_CLAUDE_DIR="%s"\nPROFILE_PROXY="germany"\n' \
    "$HOME/.claude-work" > "$CONF_DIR/profiles/work.conf"
  run _pc_info
  [ "$status" -eq 0 ]
  [ "$output" = "work › germany" ]
}
```

- [ ] **Step 3: Run tests to verify they fail before implementation**

```bash
bats proxied-claude.bats --filter statusline
```

Expected: all 5 tests FAIL (function not yet defined or wrong output).

- [ ] **Step 4: Verify `_pc_info` is now in `_define_helpers` and run tests again**

```bash
bats proxied-claude.bats --filter statusline
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Run full suite to check nothing is broken**

```bash
bats proxied-claude.bats
```

Expected: all tests pass (same count as before + 5 new).

- [ ] **Step 6: Commit**

```bash
git add proxied-claude.bats
git commit -m "test: add _pc_info statusline helper tests"
```

---

## Task 2: Apply snippet to `statusline.sh`

**Files:**
- Modify: `~/.claude-personal/hooks/statusline.sh`

- [ ] **Step 1: Add CYAN color variable after existing color declarations (line 8)**

After the line `R=$'\033[0m'`, add:

```bash
CYAN=$'\033[36m'
```

- [ ] **Step 2: Add `_pc_info()` function after color declarations, before `color_pct`**

After the CYAN line, add:

```bash
_pc_info() {
  local conf="${HOME}/.config/proxied-claude"
  [[ -f "${conf}/active_profile" ]] || return 0
  local profile; profile=$(tr -d '[:space:]' < "${conf}/active_profile")
  [[ -n "$profile" ]] || return 0
  local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
  proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
  [[ -n "$proxy" ]] && printf '%s' "${CYAN}${profile}${R} ${DIM}›${R} ${proxy}" \
                    || printf '%s' "${CYAN}${profile}${R}"
}

PC_INFO=$(_pc_info)
[[ -n "$PC_INFO" ]] && PREFIX="${PC_INFO} ${DIM}|${R} " || PREFIX=""
```

- [ ] **Step 3: Prepend PREFIX to the final printf (line 58)**

Change:

```bash
printf '%s' "ctx:$(color_pct "$CTX")${CTX}%${R} ${DIM}|${R} ${GREEN}▲${LINES_ADD}${R} ${RED}▼${LINES_REM}${R} ${DIM}|${R} \$${COST} ${DIM}|${R} ${LIMITS}"
```

To:

```bash
printf '%s' "${PREFIX}ctx:$(color_pct "$CTX")${CTX}%${R} ${DIM}|${R} ${GREEN}▲${LINES_ADD}${R} ${RED}▼${LINES_REM}${R} ${DIM}|${R} \$${COST} ${DIM}|${R} ${LIMITS}"
```

- [ ] **Step 4: Verify output manually**

```bash
echo '{}' | bash ~/.claude-personal/hooks/statusline.sh
```

Expected: `personal › nigeria | ctx:0% | ▲0 ▼0 | $0.00 | 5h:-- 7d:--`

- [ ] **Step 5: Commit**

```bash
git add ~/.claude-personal/hooks/statusline.sh
```

Note: `statusline.sh` is not in the `proxied-claude` repo — it lives in `~/.claude-personal/hooks/`. No commit needed in this repo for this step. Skip to Task 3.

---

## Task 3: Update README with snippet

**Files:**
- Modify: `README.md` — insert new section after `## IDE integration` block (after line 338)

- [ ] **Step 1: Add new section after the IDE integration `---` separator (after line 338)**

Insert between `---` (line 338) and `## What gets copied with copy-settings` (line 340):

```markdown
## Claude Code statusline integration

If you use a custom `statusline.sh` hook, you can prepend the active profile and proxy
to the status line:

```
personal › nigeria | ctx:30% | ▲13 ▼5 | $1.22 | 5h:15% ~4h 7d:65% ~2d
```

Add to your `~/.claude-<profile>/hooks/statusline.sh`, near the top after color declarations:

```bash
CYAN=$'\033[36m'

_pc_info() {
  local conf="${HOME}/.config/proxied-claude"
  [[ -f "${conf}/active_profile" ]] || return 0
  local profile; profile=$(tr -d '[:space:]' < "${conf}/active_profile")
  [[ -n "$profile" ]] || return 0
  local proxy; proxy=$(grep -m1 '^PROFILE_PROXY=' "${conf}/profiles/${profile}.conf" 2>/dev/null || true)
  proxy="${proxy#PROFILE_PROXY=}"; proxy="${proxy#\"}"; proxy="${proxy%\"}"
  [[ -n "$proxy" ]] && printf '%s' "${CYAN}${profile}${R} ${DIM}›${R} ${proxy}" \
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add Claude Code statusline integration snippet"
```

---

## Task 4: Update TODO.md

**Files:**
- Modify: `TODO.md` — task 13

- [ ] **Step 1: Replace task 13 text**

Change:

```markdown
- [ ] 13. **Active profile display** — lightweight shell helper that reads
  `active_profile` + `profiles/<n>.conf` (no subprocess) and returns
  `profile › proxy` (or just `profile` when no proxy, or nothing when
  proxied-claude is not configured). Ships as two optional snippets in README:
  - **zsh/bash `$PS1`** — like git branch display
  - **Claude Code `statusline.sh`** — appended to the existing statusline hook
```

To:

```markdown
- [x] 13. **Active profile display in Claude Code statusline** — `_pc_info()` shell
  helper reads `active_profile` + `profiles/<n>.conf` directly (no subprocess).
  Outputs `profile › proxy` (or just `profile`, or nothing). Ships as an optional
  snippet in README under "Claude Code statusline integration".
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: mark task 13 complete — statusline snippet shipped"
```

---

## Task 5: Push

- [ ] **Step 1: Push all commits**

```bash
git push
```

Expected: branch `v2.0.0` updated on remote.
