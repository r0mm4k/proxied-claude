# copy-settings --include-projects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--include-projects` flag to `copy-settings` and `profile create` that copies `projects/*/memory/` between profiles, plus replace per-item conflict warnings with a single batch confirmation (non-interactive → die).

**Architecture:** Extend `do_copy_settings` with one new param (`include_projects`) and a two-pass approach: scan for conflicts, confirm or die, then copy. The bats test file mirrors `do_copy_settings` — it must be updated in the same step as the implementation. All three call sites (`copy-settings`, `profile create --from`, `profile create` interactive wizard) receive the updated signature.

**Tech Stack:** bash, bats-core

---

## Files

- Modify: `claude-proxy` — main implementation
- Modify: `proxied-claude.bats` — test suite + mirrored `do_copy_settings`

---

### Task 1: Rewrite conflict behavior tests to reflect new expected behavior

These two tests currently pass (old behavior: warn + overwrite). Rewrite them for the new behavior — they will **fail** until Task 2 is implemented.

**Files:**
- Modify: `proxied-claude.bats:514-531`

- [ ] **Step 1: Replace lines 514–531 in `proxied-claude.bats`**

Old code to remove:
```bash
@test "copy-settings: warns on overwrite" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [[ "$output" == *"already exists"* ]]
}

@test "copy-settings: overwrites existing file despite warning" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"dark"}' ]
}
```

New code to put in their place:
```bash
@test "copy-settings: dies on conflict in non-interactive mode" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  run do_copy_settings "$src" "$dst" "src" "dst"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicting"* ]]
}

@test "copy-settings: dst unchanged on non-interactive conflict" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  echo '{"theme":"dark"}' > "$src/settings.json"
  echo '{"theme":"light"}' > "$dst/settings.json"
  run do_copy_settings "$src" "$dst" "src" "dst"
  run cat "$dst/settings.json"
  [ "$output" = '{"theme":"light"}' ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats proxied-claude.bats --filter "dies on conflict\|dst unchanged"
```

Expected: both tests FAIL (old implementation warns + overwrites).

- [ ] **Step 3: Commit failing tests**

```bash
git add proxied-claude.bats
git commit -m "test: rewrite conflict tests to expect batch die behavior"
```

---

### Task 2: Implement batch conflict UX in `do_copy_settings` (no `--include-projects` logic yet)

Replace `do_copy_settings` in **both** `claude-proxy` and the bats mirror. Add the `include_projects` param but leave its behavior unimplemented for now — the `projects/*/memory/` loops will be added in Task 4.

**Files:**
- Modify: `claude-proxy:158-196`
- Modify: `proxied-claude.bats:92-120`

- [ ] **Step 1: Replace `do_copy_settings` in `claude-proxy` (lines 158–196)**

```bash
do_copy_settings() {
  local src_dir="$1" dst_dir="$2" src_label="$3" dst_label="$4" \
        include_projects="${5:-0}"
  local copied=0
  mkdir -p "$dst_dir"

  # Pass 1: collect conflicts
  local conflicts=()
  for f in "${SETTINGS_FILES[@]}"; do
    [[ -f "$src_dir/$f" ]] || continue
    [[ -f "$dst_dir/$f" ]] && conflicts+=("$f")
  done
  for d in "${SETTINGS_DIRS[@]}"; do
    [[ -d "$src_dir/$d" ]] || continue
    for item in "$src_dir/$d"/*; do
      [[ -e "$item" ]] || continue
      [[ -e "$dst_dir/$d/$(basename "$item")" ]] && conflicts+=("$d/$(basename "$item")")
    done
  done

  # Resolve conflicts
  if [[ ${#conflicts[@]} -gt 0 ]]; then
    if [[ -t 0 ]]; then
      warn "${#conflicts[@]} item(s) already exist in '$dst_label' and will be overwritten:"
      for c in "${conflicts[@]}"; do info "  $c"; done
      echo ""
      read -r -p "  Overwrite? [y/N] " _confirm
      [[ "${_confirm:-}" =~ ^[Yy]$ ]] || return 0
    else
      die "${#conflicts[@]} conflicting item(s) in '$dst_label'. Run interactively to confirm overwrite."
    fi
  fi

  # Pass 2: copy files and dirs
  for f in "${SETTINGS_FILES[@]}"; do
    if [[ -f "$src_dir/$f" ]]; then
      cp "$src_dir/$f" "$dst_dir/$f"
      info "Copied $f"
      (( copied++ )) || true
    fi
  done
  for d in "${SETTINGS_DIRS[@]}"; do
    if [[ -d "$src_dir/$d" ]]; then
      mkdir -p "$dst_dir/$d"
      local dir_copied=0
      for item in "$src_dir/$d"/*; do
        [[ -e "$item" ]] || continue
        cp -r "$item" "$dst_dir/$d/$(basename "$item")"
        (( dir_copied++ )) || true
      done
      if [[ $dir_copied -gt 0 ]]; then
        info "Copied $d/ ($dir_copied item(s))"
        (( copied++ )) || true
      fi
    fi
  done

  if [[ $copied -eq 0 ]]; then
    info "No settings found in '$src_label' (nothing copied)"
  else
    ok "Settings copied from '$src_label' → '$dst_label'"
    info "Note: you still need to log in to Claude in the new profile"
  fi
}
```

- [ ] **Step 2: Replace `do_copy_settings` in `proxied-claude.bats` (lines 92–120)**

```bash
  do_copy_settings() {
    local src_dir="$1" dst_dir="$2" src_label="$3" dst_label="$4" \
          include_projects="${5:-0}"
    local copied=0
    mkdir -p "$dst_dir"
    # Pass 1: collect conflicts
    local conflicts=()
    for f in "${SETTINGS_FILES[@]}"; do
      [[ -f "$src_dir/$f" ]] || continue
      [[ -f "$dst_dir/$f" ]] && conflicts+=("$f")
    done
    for d in "${SETTINGS_DIRS[@]}"; do
      [[ -d "$src_dir/$d" ]] || continue
      for item in "$src_dir/$d"/*; do
        [[ -e "$item" ]] || continue
        [[ -e "$dst_dir/$d/$(basename "$item")" ]] && conflicts+=("$d/$(basename "$item")")
      done
    done
    # Resolve conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
      if [[ -t 0 ]]; then
        warn "${#conflicts[@]} item(s) already exist in '$dst_label' and will be overwritten:"
        for c in "${conflicts[@]}"; do info "  $c"; done
        echo ""
        read -r -p "  Overwrite? [y/N] " _confirm
        [[ "${_confirm:-}" =~ ^[Yy]$ ]] || return 0
      else
        die "${#conflicts[@]} conflicting item(s) in '$dst_label'. Run interactively to confirm overwrite."
      fi
    fi
    # Pass 2: copy
    for f in "${SETTINGS_FILES[@]}"; do
      if [[ -f "$src_dir/$f" ]]; then
        cp "$src_dir/$f" "$dst_dir/$f"
        info "Copied $f"
        (( copied++ )) || true
      fi
    done
    for d in "${SETTINGS_DIRS[@]}"; do
      if [[ -d "$src_dir/$d" ]]; then
        mkdir -p "$dst_dir/$d"
        local dir_copied=0
        for item in "$src_dir/$d"/*; do
          [[ -e "$item" ]] || continue
          cp -r "$item" "$dst_dir/$d/$(basename "$item")"
          (( dir_copied++ )) || true
        done
        [[ $dir_copied -gt 0 ]] && { info "Copied $d/"; (( copied++ )) || true; }
      fi
    done
    [[ $copied -eq 0 ]] && info "No settings found in '$src_label'" || \
      ok "Settings copied from '$src_label' → '$dst_label'"
  }
```

- [ ] **Step 3: Run conflict tests to verify they now pass**

```bash
bats proxied-claude.bats --filter "dies on conflict\|dst unchanged"
```

Expected: both PASS.

- [ ] **Step 4: Run full copy-settings suite**

```bash
bats proxied-claude.bats --filter copy-settings
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: replace per-item conflict warn with batch confirm/die in do_copy_settings"
```

---

### Task 3: Write failing `--include-projects` tests

**Files:**
- Modify: `proxied-claude.bats` — add after the last `copy-settings` test block (before the next `# ═══` section)

- [ ] **Step 1: Add the new test block**

```bash
# ═══════════════════════════════════════════════════════════════════════════════
# copy-settings — --include-projects
# ═══════════════════════════════════════════════════════════════════════════════

@test "copy-settings: --include-projects copies project memory file" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# memory" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ -f "$dst/projects/my-repo/memory/MEMORY.md" ]
}

@test "copy-settings: --include-projects preserves memory file content" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# custom context" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  run cat "$dst/projects/my-repo/memory/MEMORY.md"
  [ "$output" = "# custom context" ]
}

@test "copy-settings: --include-projects skips .jsonl history" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo"
  echo '{}' > "$src/projects/my-repo/session.jsonl"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ ! -f "$dst/projects/my-repo/session.jsonl" ]
}

@test "copy-settings: --include-projects skips project dirs without memory/" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo"
  echo '{}' > "$src/projects/my-repo/session.jsonl"
  do_copy_settings "$src" "$dst" "src" "dst" 1
  [ ! -d "$dst/projects/my-repo" ]
}

@test "copy-settings: --include-projects no-op when projects/ missing" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src" "$dst"
  run do_copy_settings "$src" "$dst" "src" "dst" 1
  [ "$status" -eq 0 ]
}

@test "copy-settings: --include-projects dies on project memory conflict (non-interactive)" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory" "$dst/projects/my-repo/memory"
  echo "# src" > "$src/projects/my-repo/memory/MEMORY.md"
  echo "# dst" > "$dst/projects/my-repo/memory/MEMORY.md"
  run do_copy_settings "$src" "$dst" "src" "dst" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicting"* ]]
}

@test "copy-settings: without --include-projects does not copy project memory" {
  local src="$TEST_DIR/src" dst="$TEST_DIR/dst"
  mkdir -p "$src/projects/my-repo/memory"
  echo "# memory" > "$src/projects/my-repo/memory/MEMORY.md"
  do_copy_settings "$src" "$dst" "src" "dst"
  [ ! -d "$dst/projects" ]
}
```

- [ ] **Step 2: Run new tests to verify they fail**

```bash
bats proxied-claude.bats --filter "include-projects"
```

Expected: most tests FAIL (projects copy logic not yet in `do_copy_settings`).

- [ ] **Step 3: Commit failing tests**

```bash
git add proxied-claude.bats
git commit -m "test: add --include-projects tests (failing)"
```

---

### Task 4: Implement `projects/*/memory/` copy logic in `do_copy_settings`

Add the projects scan (pass 1) and copy (pass 2) blocks to both files.

**Files:**
- Modify: `claude-proxy:158-196` (the function written in Task 2)
- Modify: `proxied-claude.bats:92-120` (the mirror written in Task 2)

- [ ] **Step 1: Add projects conflict scan to pass 1 in `claude-proxy`**

Insert after the `SETTINGS_DIRS` loop in pass 1 (before the `# Resolve conflicts` comment):

```bash
  if [[ "$include_projects" == "1" ]]; then
    shopt -s nullglob
    for proj_dir in "$src_dir/projects"/*/; do
      [[ -d "$proj_dir/memory" ]] || continue
      local repo; repo="$(basename "$proj_dir")"
      for mf in "$proj_dir/memory"/*; do
        [[ -e "$mf" ]] || continue
        [[ -e "$dst_dir/projects/$repo/memory/$(basename "$mf")" ]] && \
          conflicts+=("projects/$repo/memory/$(basename "$mf")")
      done
    done
    shopt -u nullglob
  fi
```

- [ ] **Step 2: Add projects copy to pass 2 in `claude-proxy`**

Insert after the `SETTINGS_DIRS` loop in pass 2 (before the final `if [[ $copied -eq 0 ]]`):

```bash
  if [[ "$include_projects" == "1" ]]; then
    shopt -s nullglob
    for proj_dir in "$src_dir/projects"/*/; do
      [[ -d "$proj_dir/memory" ]] || continue
      local repo; repo="$(basename "$proj_dir")"
      mkdir -p "$dst_dir/projects/$repo/memory"
      for mf in "$proj_dir/memory"/*; do
        [[ -e "$mf" ]] || continue
        cp -r "$mf" "$dst_dir/projects/$repo/memory/$(basename "$mf")"
        (( copied++ )) || true
      done
    done
    shopt -u nullglob
  fi
```

- [ ] **Step 3: Add the same two blocks to the bats mirror**

In `proxied-claude.bats`, insert after the `SETTINGS_DIRS` scan loop (before `# Resolve conflicts`):

```bash
    if [[ "$include_projects" == "1" ]]; then
      shopt -s nullglob
      for proj_dir in "$src_dir/projects"/*/; do
        [[ -d "$proj_dir/memory" ]] || continue
        local repo; repo="$(basename "$proj_dir")"
        for mf in "$proj_dir/memory"/*; do
          [[ -e "$mf" ]] || continue
          [[ -e "$dst_dir/projects/$repo/memory/$(basename "$mf")" ]] && \
            conflicts+=("projects/$repo/memory/$(basename "$mf")")
        done
      done
      shopt -u nullglob
    fi
```

And after the `SETTINGS_DIRS` copy loop (before `[[ $copied -eq 0 ]]`):

```bash
    if [[ "$include_projects" == "1" ]]; then
      shopt -s nullglob
      for proj_dir in "$src_dir/projects"/*/; do
        [[ -d "$proj_dir/memory" ]] || continue
        local repo; repo="$(basename "$proj_dir")"
        mkdir -p "$dst_dir/projects/$repo/memory"
        for mf in "$proj_dir/memory"/*; do
          [[ -e "$mf" ]] || continue
          cp -r "$mf" "$dst_dir/projects/$repo/memory/$(basename "$mf")"
          (( copied++ )) || true
        done
      done
      shopt -u nullglob
    fi
```

- [ ] **Step 4: Run `--include-projects` tests**

```bash
bats proxied-claude.bats --filter "include-projects"
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Run full suite**

```bash
bats proxied-claude.bats
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add claude-proxy proxied-claude.bats
git commit -m "feat: implement --include-projects (copy projects/*/memory/) in do_copy_settings"
```

---

### Task 5: Update `copy-settings` subcommand to accept `--include-projects`

**Files:**
- Modify: `claude-proxy:580-598`

- [ ] **Step 1: Replace the `copy-settings` case in `cmd_profile`**

```bash
    copy-settings)
      local name="${1:-}"; shift || true
      [[ -n "$name" ]] || die "Usage: claude-proxy profile copy-settings <profile> --from <source> [--include-projects]"
      validate_name "$name" "profile name"
      local from_profile="" include_projects=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --from) shift; from_profile="${1:-}"; shift ;;
          --include-projects) include_projects=1; shift ;;
          *) die "Unknown option: $1" ;;
        esac
      done
      [[ -n "$from_profile" ]] || die "Usage: claude-proxy profile copy-settings <profile> --from <source> [--include-projects]"
      validate_name "$from_profile" "source profile name"
      require_profile "$name"
      require_profile "$from_profile"
      local src_dir; src_dir="$(profile_claude_dir "$from_profile")"
      local dst_dir; dst_dir="$(profile_claude_dir "$name")"
      do_copy_settings "$src_dir" "$dst_dir" "$from_profile" "$name" "$include_projects"
      ;;
```

- [ ] **Step 2: Run full suite**

```bash
bats proxied-claude.bats
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add claude-proxy
git commit -m "feat: add --include-projects flag to profile copy-settings"
```

---

### Task 6: Update `profile create` to accept `--include-projects`

**Files:**
- Modify: `claude-proxy:397-476`

- [ ] **Step 1: Update the arg parser in the `create` case (around lines 399–409)**

Replace the existing arg-parsing block:

```bash
      local name="${1:-}"; shift || true
      [[ -n "$name" ]] || die "Usage: claude-proxy profile create <n> [--from <source>] [--include-projects]"
      validate_name "$name" "profile name"
      local copy_from="" include_projects=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --from) shift; copy_from="${1:-}"; shift ;;
          --include-projects) include_projects=1; shift ;;
          *) die "Unknown option: $1" ;;
        esac
      done
      [[ "$include_projects" == "1" && -z "$copy_from" ]] && \
        die "--include-projects requires --from <source>"
      [[ -n "$copy_from" ]] && validate_name "$copy_from" "source profile name"
```

- [ ] **Step 2: Pass `include_projects` to the `--from` non-interactive call (line ~433)**

```bash
      if [[ -n "$copy_from" ]]; then
        require_profile "$copy_from"
        local src_dir; src_dir="$(profile_claude_dir "$copy_from")"
        do_copy_settings "$src_dir" "$claude_dir" "$copy_from" "$name" "$include_projects"
```

- [ ] **Step 3: Add "Copy projects too?" to the interactive wizard (lines ~450–458)**

Replace the inner `if [[ -f "$PROFILES_DIR/${_choice}.conf" ]]` block:

```bash
          if [[ -f "$PROFILES_DIR/${_choice}.conf" ]]; then
            local src_dir; src_dir="$(profile_claude_dir "$_choice")"
            local _inc_proj=0
            read -r -p "  Copy projects too? [y/N] " _proj_choice
            [[ "${_proj_choice:-}" =~ ^[Yy]$ ]] && _inc_proj=1
            do_copy_settings "$src_dir" "$claude_dir" "$_choice" "$name" "$_inc_proj"
```

- [ ] **Step 4: Run full suite**

```bash
bats proxied-claude.bats
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-proxy
git commit -m "feat: add --include-projects to profile create"
```

---

### Task 7: Update all help text

Four locations in `claude-proxy` need the updated usage strings:

1. File header comment — line ~9 (`create`) and ~16 (`copy-settings`)
2. `print_help()` — lines 336 (`create`) and 343 (`copy-settings`)
3. `cmd_profile` `*)` usage block — lines ~653 (`create`) and ~660 (`copy-settings`)

**Files:**
- Modify: `claude-proxy`

- [ ] **Step 1: Update file header (lines ~9 and ~16)**

```bash
#   claude-proxy profile create <n> [--from <source>] [--include-projects]
```
```bash
#   claude-proxy profile copy-settings <profile> --from <source> [--include-projects]
```

- [ ] **Step 2: Update `print_help()` (lines ~336 and ~343)**

```
  claude-proxy profile create <n> [--from <source>] [--include-projects]
```
```
  claude-proxy profile copy-settings <profile> --from <source> [--include-projects]
```

- [ ] **Step 3: Update `cmd_profile` `*)` usage block (lines ~653 and ~660)**

```
  claude-proxy profile create <n> [--from <source>] [--include-projects]
```
```
  claude-proxy profile copy-settings <profile> --from <source> [--include-projects]
```

- [ ] **Step 4: Run full suite one final time**

```bash
bats proxied-claude.bats
```

Expected: all tests PASS.

- [ ] **Step 5: Final commit**

```bash
git add claude-proxy
git commit -m "docs: update help text for --include-projects"
```