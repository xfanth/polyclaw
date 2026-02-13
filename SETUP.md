# OpenClaw Docker - Quick Setup Guide

## Overview

This Docker setup provides a production-ready, 24/7 capable OpenClaw deployment with:
- **Debian Bookworm (LTS)** base image
- **All your requested environment variables** supported
- **Persistent data** that survives container recreation
- **GitHub Actions CI/CD** for automated builds
- **Multi-architecture support** (AMD64 & ARM64)

## File Structure

```
openclaw-docker/
├── .github/workflows/
│   ├── auto-update.yml       # Daily OpenClaw version checks
│   └── docker-build.yml      # Build & push to GHCR
├── config/
│   └── openclaw.json.example # Example configuration
├── scripts/
│   ├── configure.js          # Converts env vars to openclaw.json
│   └── entrypoint.sh         # Container startup script
├── .env.example              # All environment variables
├── docker-compose.yml        # Full compose configuration
├── Dockerfile                # Debian-based image
├── Makefile                  # Convenience commands
├── nginx.conf                # Reverse proxy config
└── README.md                 # Full documentation
```

## Quick Start

### 1. Set Up Your Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your settings
nano .env
```

### 2. Configure Required Variables

Edit `.env` and set at minimum:

```env
# Required: At least one AI provider API key
ANTHROPIC_API_KEY=sk-ant-...
# OR
KIMI_API_KEY=...
# OR
OPENROUTER_API_KEY=...
# etc.

# Required: Web UI password
AUTH_PASSWORD=your-secure-password

# Required: Gateway token (generate with: openssl rand -hex 32)
OPENCLAW_GATEWAY_TOKEN=...

# Required: Your data directory
OPENCLAW_DATA_DIR=/mnt/shuttle/share/app-data/openclaw3
OPENCLAW_WORKSPACE_DIR=/mnt/shuttle/share/app-data/openclaw3/workspace

```

### 3. Start OpenClaw

```bash
# Using docker compose
docker compose up -d

# Or using Make
make up
```

### 4. Access the Interface

- Web UI: http://localhost:8080
- Login with username `admin` and your `AUTH_PASSWORD`

## Data Persistence

Your data is stored in these locations:

| Path | Contents |
|------|----------|
| `/mnt/shuttle/share/app-data/openclaw3` | Config, sessions, credentials |
| `/mnt/shuttle/share/app-data/openclaw3/workspace` | Agent projects |
| `/mnt/shuttle/share/app-data/openclaw3/npm` | NPM packages for skills |
| `/mnt/shuttle/share/app-data/openclaw3/brew` | Homebrew packages |
| `/mnt/shuttle/share/app-data/openclaw3/skills` | Installed skills |
| `/mnt/shuttle/share/app-data/openclaw3/plugins` | Installed plugins |

**If the container is destroyed and recreated, all data persists!**

## Environment Variables

### AI Providers (at least one required)

```env
ZAI_API_KEY=                    # Z.AI GLM models
KIMI_API_KEY=                   # Moonshot Kimi
COPILOT_GITHUB_TOKEN=           # GitHub Copilot
GEMINI_API_KEY=                 # Google Gemini
GROQ_API_KEY=                   # Groq inference
CEREBRAS_API_KEY=               # Cerebras
OPENROUTER_API_KEY=             # OpenRouter multi-provider
OPENCODE_API_KEY=               # OpenCode
ANTHROPIC_API_KEY=              # Claude
OPENAI_API_KEY=                 # GPT models
# ... and more in .env.example
```

### Model Selection

```env
OPENCLAW_PRIMARY_MODEL=anthropic/claude-sonnet-4-5

# Fallback models (comma-separated) when primary fails
OPENCLAW_FALLBACK_MODELS=openrouter/anthropic/claude-opus-4-5,google/gemini-2.5-pro

# Image generation models
OPENCLAW_IMAGE_MODEL_PRIMARY=openai/gpt-4o-image
OPENCLAW_IMAGE_MODEL_FALLBACKS=openai/dall-e-3,stability-ai/stable-diffusion
```

### Authentication

```env
AUTH_USERNAME=admin             # Web UI username
AUTH_PASSWORD=                  # Web UI password (REQUIRED)
OPENCLAW_GATEWAY_TOKEN=         # API token (REQUIRED)
```

### Browser Automation

```env
BROWSER_CDP_URL=http://browser:9222
BROWSER_DEFAULT_PROFILE=openclaw
BROWSER_EVALUATE_ENABLED=true
```

### Webhook Hooks

```env
HOOKS_ENABLED=true
HOOKS_TOKEN=your-secret-token
```

### WhatsApp

```env
WHATSAPP_ENABLED=true
WHATSAPP_DM_POLICY=pairing
WHATSAPP_ALLOW_FROM=+1234567890
WHATSAPP_GROUP_POLICY=allowlist
```

### 1Password

```env
OP_SERVICE_ACCOUNT_TOKEN=       # 1Password service account
```



### Port

```env
PORT=8080                       # External web port
```

## GitHub Actions CI/CD

The repository includes automated workflows:

### 1. Docker Build and Push (`.github/workflows/docker-build.yml`)

**Triggers:**
- Push to `main` branch
- New tags (e.g., `v1.0.0`)
- Manual workflow dispatch

**Actions:**
- Builds multi-arch images (AMD64 & ARM64)
- Pushes to GitHub Container Registry
- Runs security scanning with Trivy
- Creates GitHub releases for tags

**Published Images:**
```
ghcr.io/YOUR_USERNAME/openclaw-docker:latest
ghcr.io/YOUR_USERNAME/openclaw-docker:v1.0.0
ghcr.io/YOUR_USERNAME/openclaw-docker:sha-abc123
```

### 2. Auto-Update Check (`.github/workflows/auto-update.yml`)

**Triggers:**
- Daily at 2 AM UTC
- Manual workflow dispatch

**Actions:**
- Checks for new OpenClaw releases
- Triggers rebuild if new version available
- Creates tracking issue

## Using the Pre-built Image

Once CI/CD is set up, use the image in your `docker-compose.yml`:

```yaml
services:
  openclaw:
    image: ghcr.io/YOUR_USERNAME/openclaw-docker:latest
    # ... rest of config
```

## Makefile Commands

```bash
make help          # Show all commands
make setup         # Initial setup
make up            # Start OpenClaw
make down          # Stop OpenClaw
make logs          # View logs
make shell         # Open container shell
make update        # Pull latest and restart
make backup        # Backup data
make status        # Show container status
make health        # Check health endpoint
```

## Updating OpenClaw

### Automatic (with CI/CD)

The auto-update workflow checks daily and rebuilds automatically.

### Manual

```bash
# Pull latest image
docker compose pull

# Restart with new image
docker compose up -d
```

### Local Build

```bash
# Rebuild from source
docker compose build --no-cache

# Restart
docker compose up -d
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker compose logs -f openclaw

# Common issues:
# - Missing API key: Set at least one provider
# - Missing AUTH_PASSWORD: Set for production
# - Missing OPENCLAW_GATEWAY_TOKEN: Will auto-generate
```

### Permission issues

```bash
# Fix ownership
sudo chown -R 1000:1000 /mnt/shuttle/share/app-data/openclaw3
```

### Reset everything

```bash
# Stop and remove
docker compose down

# Remove data (WARNING: destructive!)
sudo rm -rf /mnt/shuttle/share/app-data/openclaw3

# Start fresh
docker compose up -d
```

## Security Notes

1. **Always set `AUTH_PASSWORD`** for production
2. **Use strong `OPENCLAW_GATEWAY_TOKEN`** (32+ hex chars)
3. **Keep `.env` file secure** - never commit it
4. **Use HTTPS** in production (put behind reverse proxy)
5. **Restrict allowlists** for WhatsApp/Telegram

## Next Steps

1. Push this repository to GitHub
2. Set up repository secrets for CI/CD (if needed)
3. Configure your `.env` file
4. Run `docker compose up -d`
5. Access http://localhost:8080

## Support

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
