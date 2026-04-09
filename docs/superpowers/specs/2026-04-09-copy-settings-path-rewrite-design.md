# Design: Path Rewrite in copy-settings

**Date:** 2026-04-09

---

## Problem

`copy-settings` copies `settings.json` verbatim. Any absolute paths referencing the
source profile's Claude dir (e.g. `~/.claude/hooks/statusline.sh`) are preserved
unchanged in the destination profile. After copying, all profiles point to the same
hook — the one from the original profile.

The problem occurs in all copy directions:
- `default → personal`: `~/.claude` stays, should become `~/.claude-personal`
- `personal → work`: `~/.claude` stays (never was `~/.claude-personal`), should become `~/.claude-work`

---

## Solution

After copying `settings.json`, rewrite all claude profile dir references in the
copied file using `sed`. Replace any path matching `$HOME/.claude(-<name>)?` with
`dst_dir`.

One line added to `do_copy_settings()` in `claude-proxy`, immediately after the
`cp settings.json` call.

---

## Implementation

```bash
sed -i '' "s|$HOME/\.claude\(-[a-zA-Z0-9_-]*\)\?|$dst_dir|g" \
  "$dst_dir/settings.json"
```

- `-i ''` — BSD sed (macOS only, consistent with project scope)
- Pattern matches `~/.claude` and `~/.claude-<any-valid-name>` as complete path
  components — does not match `~/.claude-personal` as a prefix of something longer
  because profile names are `[a-zA-Z0-9_-]+` and paths end at `/` or `"` which
  are not in the character class
- Replaces with `dst_dir` (absolute path, already known at call site)
- Applied only to the destination copy — source file untouched
- No-op if `settings.json` contains no matching paths

---

## Scope

Only `settings.json` is rewritten. Other copied files (`CLAUDE.md`, `keybindings.json`,
`policy-limits.json`, `hooks/`) contain no local absolute paths — verified by
inspection of all three existing profiles.

---

## Changes

| File | Change |
|------|--------|
| `claude-proxy` | 1 line added in `do_copy_settings()` after `cp settings.json` |
| `proxied-claude.bats` | New tests for path rewrite in copy-settings |

---

## Tests

Three new bats tests in the existing `# copy-settings` group:

1. `copy-settings: rewrites ~/.claude path in settings.json` — source has
   `~/.claude/hooks/foo`, destination should have `dst_dir/hooks/foo`
2. `copy-settings: rewrites ~/.claude-<name> path in settings.json` — source has
   `~/.claude-personal/hooks/foo`, destination should have `dst_dir/hooks/foo`
3. `copy-settings: no-op when settings.json has no profile paths` — source has
   settings.json with no paths, destination is identical copy
