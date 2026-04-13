# Contributing

## Git Workflow

Work happens in feature branches off `main`:

```bash
git checkout main && git pull
git checkout -b feat/my-feature
# ... make changes, commit ...
git push origin feat/my-feature
# Open PR → review → merge to main
```

Branch naming: `feat/`, `fix/`, `docs/`, `chore/` prefixes matching the commit type.

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use for | Changelog section |
|--------|---------|------------------|
| `feat:` | New features | Added |
| `fix:` | Bug fixes | Fixed |
| `refactor:` | Code restructuring without behavior change | Changed |
| `docs:` | Documentation updates | Documentation |
| `test:` | Test-only changes | (excluded) |
| `chore:` | Maintenance, tooling | (excluded) |

Breaking changes: use `feat!:` or `fix!:`, or add `BREAKING CHANGE:` in the commit footer.

## Running Tests

Requires: `brew install bats-core`

```bash
# Run all tests
bats proxied-claude.bats

# Run a specific group
bats proxied-claude.bats --filter migration
bats proxied-claude.bats --filter lock
```

## Linting

Requires: `brew install shellcheck`

```bash
shellcheck proxied-claude claude-proxy install.sh
```

## Release Process

Releases are tagged from `main`. GitHub Actions creates the GitHub Release automatically when a tag is pushed.

Requires: `brew install git-cliff`

### Steps

1. Ensure `main` is up to date and all tests pass locally

2. Update `VERSION` in `claude-proxy` — search for the line `VERSION="x.y.z"` near the top and change it:
   ```bash
   grep -n '^VERSION=' claude-proxy
   # edit that line
   ```

3. Regenerate `CHANGELOG.md`:
   ```bash
   git cliff --tag vX.Y.Z -o CHANGELOG.md
   ```

4. Commit, tag, push:
   ```bash
   git add CHANGELOG.md claude-proxy
   git commit -m "chore: release vX.Y.Z"
   git tag vX.Y.Z
   git push origin main --tags
   ```

GitHub Actions picks up the tag and creates the GitHub Release with generated release notes.

### Version Bump Guidelines

Following [Semantic Versioning](https://semver.org/):

| Change type | Bump | Example |
|-------------|------|---------|
| Bug fixes (`fix:`) | patch | `2.0.0` → `2.0.1` |
| New features (`feat:`) | minor | `2.0.0` → `2.1.0` |
| Breaking changes (`feat!:`) | major | `2.0.0` → `3.0.0` |