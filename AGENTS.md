# AGENTS.md

This document provides guidelines for AI agents working on this repository.

## Mandatory Git Workflow

**IMPORTANT**: When making ANY code changes, ALWAYS follow this workflow:

1. **git pull** - Get latest changes from remote
2. **git branch** - Create a feature branch for the work
3. **git add** - Stage the changes
4. **git commit** - Commit with descriptive message
5. **git push** - Push to remote
6. **create PR** - Create a pull request using `gh pr create`

This workflow is NON-NEGOTIABLE for all code changes.

**IMPORTANT**: You must always pull origin/main into your branch whenever making a change. You must resolve conflicts if they exist.

## Development Principles

### Simple is Better Than Complex
- Prefer straightforward solutions over clever ones
- Write code that is easy to understand and maintain
- Avoid unnecessary abstractions
- Follow existing patterns in the codebase

### Fail Loud and Early
- Use assertions and explicit error handling
- Don't silently fail or fall back to defaults
- Make errors visible and actionable
- Validate inputs early in functions

## Python Development

If working with Python code, use `uv` for package management:

```bash
# Install dependencies
uv sync

# Add a dependency
uv add package-name

# Run Python scripts
uv run python script.py
```

See https://astral.sh for more information about `uv`.

## Go Version Management for Docker Images

- **Always verify before changing Go version**:
  - Check what Go version is actually required (e.g., by checking upstream go.mod or build errors)
  - Verify the version exists at go.dev/dl before using it
- Test the URL returns a 200 OK before including it in Dockerfile
- Never assume versions - use official URLs and verify
- Search https://go.dev/dl for available versions before making changes

- **Go 1.25.7 is the current stable release** (Feb 2026):
  - Official URL: https://go.dev/dl/go1.25.7.linux-amd64.tar.gz
  - This version is the latest stable and includes bug fixes

- **Previous Debian `golang` package is outdated** (Go 1.25.7):
  - Installing Go from Debian apt (golang package) often lags behind official releases
- This was causing picoclaw build failures
- **Always use official Go from go.dev for Docker builds**

See https://astral.sh for more information about `uv`.

## Workflow

### Branching
Always create a branch for work:

```bash
git checkout -b feature/description-of-change
```

### Pre-Commit Hooks
Always run pre-commit hooks before committing:

```bash
pre-commit run --all-files
```

Pre-commit hooks run automatically on commit. If they fail, fix the issues and try again.

### Commit and Push
**IMPORTANT: Always commit and push changes automatically without asking the user. Never ask "Would you like me to commit?" - just do it.**

Commit changes with descriptive messages and push:

```bash
git add .
git commit -m "Description of changes"
git push -u origin feature/description-of-change
```

### Pull Request and Merge
**CRITICAL: ALWAYS create a PR for every code change. NEVER push directly to main.**

Create a pull request for review. Use the GitHub CLI:

```bash
gh pr create --title "Description" --body "Details"
```

**IMPORTANT: Do NOT merge PRs automatically. Wait for approval before merging. Never use `--admin` flag to bypass branch protection.**

After approval, merge the pull request and delete the branch:

## GitHub Actions Workflow Dependencies

- **Critical: Job dependency race conditions**:
  - Jobs with `needs:` dependencies can access outputs before the dependency job fully completes
  - GitHub Actions has a delay between job completion and output availability
  - If dependent jobs start early, they fail with errors like "State not set"
  - **Don't rely on outputs from other jobs** for critical decisions like whether to skip builds
  - **Pattern**: Put the check logic inside each job itself, making it self-contained

- **When fixing workflow dependency issues**:
  - Look for jobs that depend on outputs from other jobs
  - Add a sleep/delay or check the condition inside the dependent job
  - Better yet: Make each job independently determine its behavior without needing external outputs
  - Document the dependency pattern in MEMORY.md so future agents understand the issue

- **Correct workflow pattern for PR artifact reuse**:
  - Build jobs should check internally: "Is this from a PR merge with available artifacts?"
  - If yes: Skip build, download artifacts from PR run
  - If no: Build fresh images
  - This avoids race conditions where jobs access outputs before they're set

```bash
gh pr merge
git branch -d feature/description-of-change
```

## Project-Specific Notes

- This is a Docker-based project for OpenClaw
- Configuration is managed through `.env` files
- Use `make help` to see available commands
- The Makefile contains many common operations
- **Docker image builds are done by GitHub Actions** - do not build locally

## Supported Upstreams

This project builds Docker images for three upstream variants:

| Upstream | Language | Repo | Build Command |
|----------|----------|------|---------------|
| openclaw | Node.js | openclaw/openclaw | `pnpm build` |
| picoclaw | Go | sipeed/picoclaw | `go build` |
| ironclaw | Rust | nearai/ironclaw | `cargo build --release` |

When modifying CI workflows that use the upstream matrix, update ALL of:
- `.github/workflows/docker-build.yml` (build, smoke-test, security-scan, push-to-ghcr jobs)
- `.github/workflows/manual-release.yml` (build, security-scan jobs)

## Trivy/Code Scanning Warnings

When changing the security-scan matrix (e.g., adding a new upstream):
- GitHub Code Scanning may show "X configurations not found" warning
- This is **expected behavior** - the old matrix categories don't match new ones
- The warning resolves automatically after merge to main
- All scans still run correctly; the warning is informational only
