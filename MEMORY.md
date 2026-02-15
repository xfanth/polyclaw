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

## Important Rules

- **Never merge PRs without approval** - Create the PR and wait for review/approval before merging
- Do not use `--admin` flag to bypass branch protection rules

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
