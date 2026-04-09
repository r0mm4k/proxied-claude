# copy-settings Path Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After copying `settings.json`, rewrite all claude profile dir references (`$HOME/.claude` or `$HOME/.claude-<name>`) to point to the destination profile dir.

**Architecture:** One `sed -i ''` call added to `do_copy_settings()` in `claude-proxy`, immediately after the files-copy loop. The same line added to the bats mirror of `do_copy_settings()` in `proxied-claude.bats` so tests can verify it. Pattern `$HOME/\.claude\(-[a-zA-Z0-9_-]*\)?` matches any claude profile dir without matching longer prefixes.

**Tech Stack:** bash, BSD sed (macOS), bats-core (tests)

---

## File map

| File | Action | What changes |
|------|--------|--------------|
| `proxied-claude.bats` | Modify | Add 3 tests + sed line to bats mirror of `do_copy_settings` |
| `claude-proxy` | Modify | Add sed line to `do_copy_settings` after files-copy loop |
| `CHANGELOG.md` | Modify | Add entry under `### Fixed` in `[2.0.0]` |

---

## Task 1: Write failing tests

**Files:**
- Modify: `proxied-claude.bats` — add 3 tests after existing `# copy-settings — files` group

- [ ] **Step 1: Add 3 tests after the last test in the `# copy-settings — files` group**

Find the last test before `# copy-settings — directories` (around line 610). Insert these three tests before that section:

```bash
@test "copy-settings: rewrites ~/.claude path in settings.json to dst_dir" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"statusLine":{"command":"bash %s/hooks/statusline.sh"}}' \
    "$HOME/.claude" > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [[ "$output" == *"${dst}/hooks/statusline.sh"* ]]
}

@test "copy-settings: rewrites ~/.claude-name path in settings.json to dst_dir" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  printf '{"statusLine":{"command":"bash %s/hooks/statusline.sh"}}' \
    "$HOME/.claude-personal" > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [[ "$output" == *"${dst}/hooks/statusline.sh"* ]]
}

@test "copy-settings: settings.json without profile paths is copied unchanged" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"dark"}' ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats proxied-claude.bats --filter "rewrites ~/.claude\|without profile paths"
```

Expected: all 3 FAIL — bats mirror doesn't have the sed line yet.

---

## Task 2: Add sed to bats mirror

**Files:**
- Modify: `proxied-claude.bats` — `do_copy_settings()` mirror (~line 160-167)

- [ ] **Step 1: Find the files-copy loop in the bats mirror**

In `proxied-claude.bats`, the bats mirror's `do_copy_settings()` has this pattern around line 160-167:

```bash
    # Pass 2: copy
    for f in "${SETTINGS_FILES[@]}"; do
      if [[ -f "$src_dir/$f" ]]; then
        cp "$src_dir/$f" "$dst_dir/$f"
        info "Copied $f"
        (( copied++ )) || true
      fi
    done
```

- [ ] **Step 2: Add sed line after the files-copy loop in the bats mirror**

After the closing `done` of the files-copy loop, add:

```bash
    # Rewrite claude profile dir paths in settings.json
    [[ -f "$dst_dir/settings.json" ]] && \
      sed -i '' "s|$HOME/\.claude\(-[a-zA-Z0-9_-]*\)\?|$dst_dir|g" \
        "$dst_dir/settings.json"
```

- [ ] **Step 3: Run the 3 new tests — must pass**

```bash
bats proxied-claude.bats --filter "rewrites ~/.claude\|without profile paths"
```

Expected: 3/3 pass.

- [ ] **Step 4: Run full suite — must still pass**

```bash
bats proxied-claude.bats
```

Expected: all tests pass (154 total).

---

## Task 3: Add sed to claude-proxy

**Files:**
- Modify: `claude-proxy` — `do_copy_settings()` at line ~213-220

- [ ] **Step 1: Find the files-copy loop in claude-proxy**

In `claude-proxy`, `do_copy_settings()` has this pattern at lines 213-220:

```bash
  # Pass 2: copy files and dirs
  for f in "${SETTINGS_FILES[@]}"; do
    if [[ -f "$src_dir/$f" ]]; then
      cp "$src_dir/$f" "$dst_dir/$f"
      info "Copied $f"
      (( copied++ )) || true
    fi
  done
```

- [ ] **Step 2: Add sed line after the files-copy loop in claude-proxy**

After the closing `done` of the files-copy loop, add:

```bash
  # Rewrite claude profile dir paths in settings.json
  [[ -f "$dst_dir/settings.json" ]] && \
    sed -i '' "s|$HOME/\.claude\(-[a-zA-Z0-9_-]*\)\?|$dst_dir|g" \
      "$dst_dir/settings.json"
```

- [ ] **Step 3: Run full suite — must still pass**

```bash
bats proxied-claude.bats
```

Expected: all 154 tests pass.

- [ ] **Step 4: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: rewrite claude profile dir paths in settings.json on copy-settings"
```

---

## Task 4: Update CHANGELOG and push

**Files:**
- Modify: `CHANGELOG.md` — add to `### Fixed` in `[2.0.0]`

- [ ] **Step 1: Add entry to `### Fixed` section in `[2.0.0]`**

Find the existing `### Fixed` section (which has the HOST column fix) and add:

```markdown
- **`copy-settings` path rewrite** — after copying `settings.json`, rewrites any
  `~/.claude` or `~/.claude-<name>` path to the destination profile dir; fixes
  `statusLine.command` (and any other absolute paths) becoming stale after copying
```

- [ ] **Step 2: Commit and push**

```bash
git add CHANGELOG.md
git commit -m "docs: update changelog — copy-settings path rewrite"
git push
```
