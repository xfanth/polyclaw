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

- **NEVER push directly to main** - Always create a branch and PR
- **Always create a PR** - Every code change must go through a pull request
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

- **Architecture naming**:
  - `uname -m` returns `x86_64` but Go download URLs use `amd64`
  - For Docker linux/amd64 builds, use hardcoded `amd64` in download URL

## GitHub Actions Workflow Dependencies

- **Job dependency race condition**: Jobs with `needs:` dependency can sometimes start before the dependency job's outputs are fully available
  - In `.github/workflows/docker-build.yml`, build jobs depend on `check-pr-status` to get `can_skip_build` output
  - However, outputs aren't immediately available to dependent jobs - there's a small delay
  - If dependent jobs start too early, they can't access the output and fail with "State not set" or similar errors
  - **Solution**: Don't have build jobs depend on external output. Instead, check the PR status logic inside each build job itself

- **Workflow `needs` clause behavior**:
  - `needs: [job1, job2]` means the job waits for BOTH jobs to complete
  - The dependency job must finish completely (including output setting) before the dependent job starts
  - GitHub Actions has a delay of several seconds between job completion and output availability
  - **Pattern**: Have self-contained logic in each job that can independently decide whether to run, rather than relying on outputs from a separate job

- **Correct pattern for PR artifact reuse**:
  - Each build job should check if it came from a PR merge and has available artifacts
  - If yes, skip build and download artifacts from PR run
  - If no, build fresh images
  - This avoids the race condition where jobs try to access outputs before they're available

## Upstream Variants

This project builds Docker images for three upstream variants:

1. **OpenClaw** (`openclaw/openclaw`) - Node.js-based, official implementation
   - Built with `pnpm install && pnpm build`
   - Has UI components (`pnpm ui:build`)
   - Entry point: `node /opt/openclaw/app/openclaw.mjs`

2. **PicoClaw** (`sipeed/picoclaw`) - Go-based, lightweight implementation
   - Built with `go build`
   - No UI components
   - Entry point: `/opt/picoclaw/picoclaw`

3. **IronClaw** (`nearai/ironclaw`) - Rust-based, privacy-focused implementation
   - Built with `cargo build --release`
   - No UI components
   - Entry point: `/opt/ironclaw/ironclaw`

When adding a new upstream:
- Update `Dockerfile` clone logic with GitHub owner/repo
- Add build step for the new language/toolchain
- Update binary handling and CLI wrappers
- Add to CI matrix in `.github/workflows/docker-build.yml` and `manual-release.yml`
- Skip smoke tests if architecture differs (e.g., Rust binary has different API)

## Trivy/Code Scanning Matrix Changes

When changing the `security-scan` job matrix (e.g., adding a new upstream):
- GitHub Code Scanning shows warning: "X configurations not found"
- This happens because the old matrix categories no longer match the new ones
- **The warning is expected and will resolve after merge to main**
- Do NOT try to "fix" this warning - it's informational only
- All security scans still run and upload SARIF results correctly

Example: Adding `ironclaw` to matrix `[openclaw, picoclaw]` → `[openclaw, picoclaw, ironclaw]`
causes Code Scanning to not find a baseline for the new `ironclaw` category.
## Environment Variable Whitelist in Docker Entrypoint

When the entrypoint script runs as root and then switches to the upstream user via `su`, only whitelisted environment variables are passed through.

- **Problem**: If an env var is not in the `--whitelist-environment` list, it gets lost when switching users
- **Symptom**: Config shows correct values but the application doesn't see them because configure.js runs as the switched user
- **Location**: `scripts/entrypoint.sh` line ~85 in the `su` command
- **Fix**: Add any new environment variables that configure.js reads to the whitelist

Current whitelist (from `scripts/entrypoint.sh` line 85):
```
UPSTREAM
OPENCLAW_STATE_DIR
OPENCLAW_WORKSPACE_DIR
OPENCLAW_GATEWAY_PORT
PORT
OPENCLAW_GATEWAY_TOKEN
AUTH_USERNAME
AUTH_PASSWORD
OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS
OPENCLAW_GATEWAY_BIND
OPENCLAW_PRIMARY_MODEL
BROWSER_CDP_URL
BROWSER_DEFAULT_PROFILE
WHATSAPP_ENABLED
WHATSAPP_DM_POLICY
WHATSAPP_ALLOW_FROM
TELEGRAM_BOT_TOKEN
TELEGRAM_DM_POLICY
DISCORD_BOT_TOKEN
DISCORD_DM_POLICY
SLACK_BOT_TOKEN
SLACK_DM_POLICY
HOOKS_ENABLED
HOOKS_TOKEN
HOOKS_PATH
ANTHROPIC_API_KEY
OPENAI_API_KEY
OPENROUTER_API_KEY
GEMINI_API_KEY
XAI_API_KEY
GROQ_API_KEY
MISTRAL_API_KEY
CEREBRAS_API_KEY
MOONSHOT_API_KEY
KIMI_API_KEY
ZAI_API_KEY
OPENCODE_API_KEY
COPILOT_GITHUB_TOKEN
XIAOMI_API_KEY
```

When adding new env vars to `configure.js`, **always add them to the whitelist** in `entrypoint.sh`.

## Repository and Package Naming

- **Repository**: `xfanth/polyclaw` (formerly `xfanth/openclaw`)
- **Docker Images**: `ghcr.io/xfanth/{upstream}` where upstream is `openclaw`, `picoclaw`, or `ironclaw`
- **Image tags**: `xfanth_main`, `oc_main`, `pc_main`, `ic_main`, or version tags like `v2026.2.1`

When renaming a repository:
1. Update README.md badge URLs
2. Update workflow IMAGE_NAME references to use hardcoded `ghcr.io/xfanth/{upstream}`
3. Update local git remote: `git remote set-url origin git@github.com:xfanth/polyclaw.git`
4. **CodeQL Default Setup**: After renaming, disable and re-enable CodeQL in repository settings to clear cached database with old path
   - Go to Settings → Security → Code Security
   - Disable CodeQL, then re-enable it
   - Otherwise builds fail with "Invalid working directory: /home/runner/work/openclaw/openclaw"

## Hadolint Configuration

The Dockerfile uses a retry pattern for apt-get commands:
```dockerfile
RUN for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y ... && \
        rm -rf /var/lib/apt/lists/* && \
        break || \
        (echo "Retry $i failed, waiting 10 seconds..." && sleep 10); \
    done
```

This triggers hadolint SC2015 warning (`A && B || C is not if-then-else`). The pattern is intentional for retry logic, so we ignore SC2015 in `.hadolint.yaml`.

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
- `memory_*` - Knowledge graph operations
- `gemini-cli_*` - Gemini AI interactions
- `mcp-server-analyzer_*` - Code analysis (ruff, vulture)
- `filesystem_*` - File operations
- `mcp_everything_*` - Utility functions

## Project Structure

```
openclaw-docker/
├── .github/workflows/    # CI/CD workflows
├── config/               # Example configurations
├── scripts/              # Entry point and configuration scripts
├── .env.example          # Environment variable template
├── docker-compose.yml    # Docker Compose configuration
├── Dockerfile            # Multi-stage Docker build
├── Makefile              # Convenience commands
├── nginx.conf            # Nginx reverse proxy config
├── pyproject.toml        # Python project config (for tests)
└── tests/                # Test suite
```

## Common Commands

```bash
# Setup
cp .env.example .env && nano .env

# Start/stop
docker compose up -d
docker compose down

# Logs
docker compose logs -f gateway

# Shell
docker compose exec gateway bash

# Update
docker compose pull && docker compose up -d

# Makefile shortcuts
make help
make up
make logs
make shell
```
