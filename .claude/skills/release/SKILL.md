---
name: release
description: Use when releasing a new version of proxied-claude — guides the full release flow: tests → version bump → commit → changelog → tag → push
---

# proxied-claude Release Process

## Overview

**Announce at start:** "Using release skill."

Exact steps from CONTRIBUTING.md. Do not improvise.

---

## Step 1 — Verify tests pass

```bash
bats proxied-claude.bats
```

**If any failures:** stop, fix, re-run. Do not proceed.

**Required output:** `191 tests, 0 failures` (update count if tests were added).

---

## Step 2 — Determine version bump

| Commits since last tag | Bump  | Example          |
|------------------------|-------|------------------|
| Only `fix:`            | patch | 2.1.5 → 2.1.6    |
| Any `feat:`            | minor | 2.1.5 → 2.2.0    |
| Any `feat!:` / `fix!:` | major | 2.1.5 → 3.0.0    |

Check current version and recent commits:
```bash
grep '^VERSION=' claude-proxy
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

---

## Step 3 — Update version in claude-proxy

```bash
# Edit VERSION="X.Y.Z" on line ~39
grep -n '^VERSION=' claude-proxy   # find the line
```

Update the line to the new version.

---

## Step 4 — Commit code changes

Stage **all changed source files** (not CHANGELOG.md yet):

```bash
git add claude-proxy install.sh proxied-claude   # whichever changed
git commit -m "<type>: <description>"
```

Use the appropriate conventional commit prefix (`feat:`, `fix:`, `refactor:`, etc.).

---

## Step 5 — Regenerate CHANGELOG.md via git-cliff

```bash
git cliff --tag vX.Y.Z -o CHANGELOG.md
```

Verify the new entry appears at the top:
```bash
head -15 CHANGELOG.md
```

---

## Step 6 — Commit changelog

```bash
git add CHANGELOG.md
git commit -m "chore: update changelog for vX.Y.Z"
```

---

## Step 7 — Tag

```bash
git tag vX.Y.Z
git log --oneline -4   # verify commits look right
```

---

## Step 8 — Ask confirmation, then push

Show the user what will be pushed:
```
Ready to push:
  git push origin main --tags

This will trigger GitHub Actions to create release vX.Y.Z.
Proceed?
```

Wait for explicit confirmation. Then:

```bash
git push origin main --tags
```

GitHub Actions creates the GitHub Release automatically from the tag.

---

## Quick checklist

- [ ] `bats proxied-claude.bats` → 0 failures
- [ ] VERSION updated in `claude-proxy`
- [ ] Code committed with conventional prefix
- [ ] `git cliff --tag vX.Y.Z -o CHANGELOG.md` run
- [ ] Changelog committed as `chore: update changelog for vX.Y.Z`
- [ ] Tag created
- [ ] User confirmed push
- [ ] `git push origin main --tags`

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Editing CHANGELOG.md manually | Always use `git cliff` |
| Forgetting `--tags` on push | GitHub Actions won't trigger without the tag |
| Pushing before user confirms | Always ask first — push affects shared state |
| Version in claude-proxy not updated | `claude-proxy version` would show old version |