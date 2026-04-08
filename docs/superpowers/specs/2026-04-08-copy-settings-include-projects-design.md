# Design: `copy-settings --include-projects` + Batch Conflict UX

**Date:** 2026-04-08
**Branch:** v2.0.0
**TODO items:** #2 (copy-settings --include-projects)

---

## Summary

Two related changes shipped together:

1. **`--include-projects` flag** — extend `copy-settings` (and `profile create`) to also copy per-project memory (`projects/*/memory/`) in addition to the existing settings files and dirs.
2. **Batch conflict UX** — replace per-item `warn` on overwrite with a pre-flight scan: show a summary of all conflicts, ask once for confirmation. Non-interactive with conflicts → `die`.

---

## What `projects/*/memory/` contains

`~/.claude/projects/` holds per-repo directories named after the absolute path (e.g. `-Users-name-work-myrepo`). Each contains:

- `.jsonl` files — conversation history (can be hundreds of MB) — **not copied**
- UUID dirs — session artifacts — **not copied**
- `memory/` — per-project memory files (CLAUDE.md, memory bank) — **copied**

Only `memory/` is worth copying between profiles: it holds accumulated project context. History is session-specific and meaningless on a different profile.

---

## Architecture

Single approach: extend `do_copy_settings` with one new parameter.

### `do_copy_settings` signature

```bash
do_copy_settings() {
  local src_dir="$1" dst_dir="$2" src_label="$3" dst_label="$4" \
        include_projects="${5:-0}"
```

### Pass 1 — conflict scan

Before copying anything, build a `conflicts` array by checking every item that would be overwritten:

- `SETTINGS_FILES` — check `[[ -f "$dst_dir/$f" ]]`
- `SETTINGS_DIRS` — check `[[ -e "$dst_dir/$d/$(basename "$item")" ]]` for each item
- If `include_projects=1` — for each `src_dir/projects/*/memory/*`: check corresponding path in dst

### Conflict resolution

If `${#conflicts[@]} > 0`:

- **Interactive** (`[[ -t 0 ]]`): print summary, ask once:
  ```
  ⚠️  3 item(s) already exist in 'work' and will be overwritten:
     settings.json
     hooks/pre-tool
     projects/-Users-name-myrepo/memory/MEMORY.md

  Overwrite? [y/N]
  ```
  `N` (default) → exit without changes.

- **Non-interactive**: `die "N conflicting item(s) in '<dst>'. Run interactively to confirm overwrite."`
  Consistent with `proxy delete` and `uninstall`.

### Pass 2 — copy

If no conflicts or user confirmed: copy everything. No per-item `warn`.

For `projects/*/memory/`:
```bash
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
```

---

## Call sites

### `profile copy-settings` subcommand

Parse `--include-projects` flag, pass to `do_copy_settings`:

```bash
copy-settings)
  ...
  local include_projects=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) shift; from_profile="${1:-}"; shift ;;
      --include-projects) include_projects=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  ...
  do_copy_settings "$src_dir" "$dst_dir" "$from_profile" "$name" "$include_projects"
```

### `profile create` — non-interactive path (`--from`)

Add `--include-projects` to `create` arg parser. `--include-projects` without `--from` → `die`.

```bash
claude-proxy profile create work --from default --include-projects
```

The destination dir is always freshly created inside `create` → no conflicts possible → two-pass completes without prompts.

### `profile create` — interactive wizard

After the user chooses a source profile, ask a second question:

```
Copy settings from profile? [profile name or Enter to skip]: default
Copy project memory too? [y/N]:
```

Pass result as `include_projects` to `do_copy_settings`.

---

## Help text changes

Two usage blocks need updating (lines 343 and 660 in `claude-proxy`):

```
claude-proxy profile create <n> [--from <source>] [--include-projects]
claude-proxy profile copy-settings <profile> --from <source> [--include-projects]
```

---

## Test changes

### Bats mirror of `do_copy_settings`

`proxied-claude.bats` contains a verbatim mirror of `do_copy_settings` (lines ~92–130). Must be kept in sync: add `include_projects` param and the two-pass logic.

### Tests that need rewriting

| Old test | New behavior | Change |
|---|---|---|
| `"warns on overwrite"` | non-interactive + conflict → `die` | Assert `status != 0`, output contains conflict summary |
| `"overwrites existing file despite warning"` | non-interactive → `die`, file NOT overwritten | Rename to "non-interactive: dies on conflict, dst unchanged" |

### New tests to add

- `copy-settings: --include-projects copies projects memory`
- `copy-settings: --include-projects skips projects .jsonl history`
- `copy-settings: --include-projects skips projects without memory/`
- `copy-settings: interactive confirm overwrites (stdin mock)`
  *(or skip if interactive testing is impractical in bats)*

---

## What is NOT changing

- `SETTINGS_FILES` (4 entries) — unchanged, architecture tests pass
- `SETTINGS_DIRS` (2 entries) — unchanged, architecture tests pass
- `projects/` is not added to `SETTINGS_DIRS` — it gets separate handling inside `do_copy_settings`
- `profile create` fresh dir path: dir is `mkdir -p`'d before copy → always empty → conflict scan finds nothing → no prompt, no die