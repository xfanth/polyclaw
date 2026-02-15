# Memory

## Mandatory Git Workflow

When making ANY code changes, ALWAYS follow this workflow:

1. **git pull** - Get latest changes from remote
2. **git branch** - Create a feature branch for the work
3. **git add** - Stage the changes
4. **git commit** - Commit with descriptive message
5. **git push** - Push to remote
6. **create PR** - Create a pull request using `gh pr create`

This workflow is NON-NEGOTIABLE for all code changes.

**IMPORTANT**: You must always pull origin/main into your branch whenever making a change. You must resolve conflicts if they exist.

## Important Rules

- **Never merge PRs without approval** - Create PR and wait for review/approval before merging
- Do not use `--admin` flag to bypass branch protection rules

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


## Available Tools

The following tools are available:
- `read` - Read files from filesystem
- `write` - Write files to filesystem
- `edit` - Edit existing files
- `bash` - Execute shell commands
- `glob` - Search for files by pattern
- `grep` - Search file contents
- `git_*` - Git operations (status, diff, commit, add, branch, etc.)
- `sequential-thinking` - Problem-solving through structured thinking
- `jina-mcp-server_*` - Web search, URL reading, image search, etc.
- `playwright_browser_*` - Browser automation
- `puppeteer_*` - Browser automation
- `memory_*` - Knowledge graph operations
- `gemini-cli_*` - Gemini AI interactions
- `mcp-server-analyzer_*` - Code analysis (ruff, vulture)
- `filesystem_*` - File operations
- `mcp_everything_*` - Utility functions
