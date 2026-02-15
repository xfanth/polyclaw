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
Create a pull request for review. Use the GitHub CLI:

```bash
gh pr create --title "Description" --body "Details"
```

**IMPORTANT: Do NOT merge PRs automatically. Wait for approval before merging. Never use `--admin` flag to bypass branch protection.**

After approval, merge the pull request and delete the branch:

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
