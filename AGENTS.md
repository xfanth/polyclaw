# AGENTS.md

This document provides guidelines for AI agents working on this repository.

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
Commit changes with descriptive messages and push:

```bash
git add .
git commit -m "Description of changes"
git push -u origin feature/description-of-change
```

### Pull Request and Merge
Create a pull request for review before merging. Use the GitHub CLI:

```bash
gh pr create --title "Description" --body "Details"
```

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
