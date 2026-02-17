# OpenClaw/PicoClaw Docker

[![CodeQL](https://github.com/xfanth/claw-builder/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/xfanth/claw-builder/actions/workflows/github-code-scanning/codeql)
[![Docker Build and Push](https://github.com/xfanth/claw-builder/actions/workflows/docker-build.yml/badge.svg)](https://github.com/xfanth/claw-builder/actions/workflows/docker-build.yml)
[![Pre-Commit Checks](https://github.com/xfanth/claw-builder/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/xfanth/claw-builder/actions/workflows/pre-commit.yml)
[![Docker Build](https://github.com/openclaw/openclaw-docker/actions/workflows/docker-build.yml/badge.svg)](https://github.com/openclaw/openclaw-docker/actions/workflows/docker-build.yml)
[![Docker Image](https://img.shields.io/badge/docker-ghcr.io-blue?logo=docker)](https://ghcr.io/openclaw/openclaw-docker)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A production-ready Docker setup for AI agent gateways. Supports both:

- **[OpenClaw](https://github.com/openclaw/openclaw)** - The official self-hosted AI agent gateway
- **[PicoClaw](https://github.com/sipeed/picoclaw)** - Sipeed's lightweight AI agent gateway for embedded devices

## Features

- **Debian Bookworm (LTS) Base** - Stable and secure foundation
- **Multi-Architecture Support** - AMD64 and ARM64 builds
- **Multiple Upstream Support** - Choose between OpenClaw or PicoClaw
- **Environment Variable Configuration** - Configure everything via `.env` file
- **Persistent Data Storage** - Config, sessions, skills, plugins, and npm packages survive container restarts
- **Nginx Reverse Proxy** - Built-in authentication and rate limiting
- **Browser Automation** - Optional Chrome sidecar for web automation
- **Health Checks & Auto-Restart** - Designed for 24/7 operation
- **Security Hardened** - Non-root user, minimal capabilities, security headers

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/openclaw/openclaw-docker.git
cd openclaw-docker
```

### 2. Configure Environment Variables

```bash
cp .env.example .env
# Edit .env with your favorite editor
nano .env
```

At minimum, you need to set:
- `UPSTREAM=openclaw` or `UPSTREAM=picoclaw` (choose your upstream)
- One AI provider API key (e.g., `ANTHROPIC_API_KEY`, `KIMI_API_KEY`, `OPENROUTER_API_KEY`)
- `AUTH_PASSWORD` for web UI protection
- `OPENCLAW_GATEWAY_TOKEN` for API access

### 3. Start the Gateway

```bash
docker compose up -d
```

### 4. Access the Web Interface

Open your browser to `http://localhost:8080` and log in with:
- Username: `admin` (or your `AUTH_USERNAME`)
- Password: Your `AUTH_PASSWORD`

## Upstream Selection

This Docker setup supports two upstream projects:

### OpenClaw (Default)

The official self-hosted AI agent gateway that connects your favorite chat apps to AI coding agents.

```env
UPSTREAM=openclaw
UPSTREAM_VERSION=main
```

- **GitHub:** https://github.com/openclaw/openclaw
- **Documentation:** https://docs.openclaw.ai/
- **Community:** [Discord](https://discord.gg/openclaw)

### PicoClaw

Sipeed's lightweight AI agent gateway, optimized for embedded devices and resource-constrained environments.

```env
UPSTREAM=picoclaw
UPSTREAM_VERSION=main
```

- **GitHub:** https://github.com/sipeed/picoclaw
- **Ideal for:** MAIX devices, embedded systems, lightweight deployments

### Switching Between Upstreams

Simply change the `UPSTREAM` variable in your `.env` file:

```env
# Use OpenClaw
UPSTREAM=openclaw
UPSTREAM_VERSION=main

# Or use PicoClaw
UPSTREAM=picoclaw
UPSTREAM_VERSION=main
```

Then restart the container:

```bash
docker compose down
docker compose up -d
```

## Configuration

### AI Providers

At least one AI provider API key is required:

| Provider | Environment Variable |
|----------|---------------------|
| Anthropic | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Google Gemini | `GEMINI_API_KEY` |
| Groq | `GROQ_API_KEY` |
| Cerebras | `CEREBRAS_API_KEY` |
| Moonshot Kimi | `KIMI_API_KEY` |
| Z.AI | `ZAI_API_KEY` |
| OpenCode | `OPENCODE_API_KEY` |
| GitHub Copilot | `COPILOT_GITHUB_TOKEN` |

### Model Selection

Set your preferred model:

```env
OPENCLAW_PRIMARY_MODEL=anthropic/claude-sonnet-4-5-20250929
```

Popular options:
- `anthropic/claude-sonnet-4-5-20250929` - Claude Sonnet 4.5
- `anthropic/claude-opus-4-5-20250929` - Claude Opus 4.5
- `openrouter/anthropic/claude-opus-4-5` - Claude via OpenRouter
- `google/gemini-2.5-pro` - Gemini Pro
- `opencode/kimi-k2.5` - Kimi K2.5
- `zai/glm-4.7` - Z.AI GLM-4.7

#### Fallback Models

Configure fallback models for when the primary model fails:

```env
OPENCLAW_FALLBACK_MODELS=openrouter/anthropic/claude-opus-4-5,google/gemini-2.5-pro
```

#### Image Models

Configure models for image generation:

```env
OPENCLAW_IMAGE_MODEL_PRIMARY=openai/gpt-4o-image
OPENCLAW_IMAGE_MODEL_FALLBACKS=openai/dall-e-3,stability-ai/stable-diffusion
```

### Data Persistence

The following directories are persisted:

| Host Path | Container Path | Contents |
|-----------|---------------|----------|
| `/mnt/shuttle/share/app-data/openclaw3` | `/data/.openclaw` or `/data/.picoclaw` | Config, sessions, skills, plugins |
| `/mnt/shuttle/share/app-data/openclaw3/workspace` | `/data/workspace` | Agent projects |
| `./logs` | `/var/log/openclaw` or `/var/log/picoclaw` | Application logs |

### WhatsApp Configuration

```env
WHATSAPP_ENABLED=true
WHATSAPP_DM_POLICY=pairing
WHATSAPP_ALLOW_FROM=+1234567890,+0987654321
```

When enabled, scan the QR code in the logs to pair:

```bash
docker compose logs -f gateway
```

### Telegram Configuration

```env
TELEGRAM_BOT_TOKEN=your-bot-token-from-botfather
TELEGRAM_DM_POLICY=pairing
```

### Discord Configuration

```env
DISCORD_BOT_TOKEN=your-bot-token
DISCORD_DM_POLICY=pairing
```

### Browser Automation

Enable browser automation with the included Chrome sidecar:

```env
BROWSER_CDP_URL=http://browser:9222
BROWSER_DEFAULT_PROFILE=openclaw
BROWSER_EVALUATE_ENABLED=true
```

Access the browser desktop via noVNC at `http://localhost:8080/browser/`

**Note:** The browser sidecar must provide noVNC on port `6080`. The `/browser/` route proxies to `browser:6080/vnc.html`.

Example browser image that includes noVNC on port 6080:
- `ghcr.io/xfanth/cdp_vnc_browser:latest`

When using a custom browser image, ensure it exposes noVNC on port 6080.

### Webhook Hooks

Enable webhook automation:

```env
HOOKS_ENABLED=true
HOOKS_TOKEN=your-secret-hook-token
```

Trigger actions via:

```bash
curl -X POST http://localhost:8080/hooks/wake \
  -H "Authorization: Bearer your-secret-hook-token"
```

## Docker Compose Examples

### Minimal Setup (OpenClaw)

```yaml
services:
  gateway:
    image: ghcr.io/n00b001/openclaw:latest
    ports:
      - "8080:8080"
    environment:
      - UPSTREAM=openclaw
      - ANTHROPIC_API_KEY=sk-ant-...
      - AUTH_PASSWORD=secure-password
      - OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    volumes:
      - ./data:/data/.openclaw
    restart: unless-stopped
```

### Minimal Setup (PicoClaw)

```yaml
services:
  gateway:
    image: ghcr.io/n00b001/picoclaw:latest
    ports:
      - "8080:8080"
    environment:
      - UPSTREAM=picoclaw
      - ANTHROPIC_API_KEY=sk-ant-...
      - AUTH_PASSWORD=secure-password
      - OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    volumes:
      - ./data:/data/.picoclaw
    restart: unless-stopped
```

### Full Setup with All Features

See the included [`docker-compose.yml`](docker-compose.yml) for a complete example with:
- Browser automation sidecar
- All channel integrations
- Persistent volumes
- Health checks
- Resource limits

### Using Pre-built Image

```yaml
services:
  gateway:
    image: ghcr.io/n00b001/${UPSTREAM:-openclaw}:latest
    # ... rest of configuration
```

### Building Locally

```yaml
services:
  gateway:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        UPSTREAM: ${UPSTREAM:-openclaw}
        UPSTREAM_VERSION: ${UPSTREAM_VERSION:-main}
    # ... rest of configuration
```

## Environment Variables Reference

### Upstream Selection

| Variable | Description | Default |
|----------|-------------|---------|
| `UPSTREAM` | Which upstream to use (`openclaw` or `picoclaw`) | `openclaw` |
| `UPSTREAM_VERSION` | Version/branch to build | `main` |

### Required

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` or other provider | AI provider API key | - |
| `AUTH_PASSWORD` | Web UI password | - |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway API token | Auto-generated |

### Authentication

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTH_USERNAME` | Web UI username | `admin` |
| `AUTH_PASSWORD` | Web UI password | - |

### Gateway

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCLAW_GATEWAY_TOKEN` | Bearer token for API | Auto-generated |
| `OPENCLAW_GATEWAY_PORT` | Internal gateway port | `18789` |
| `OPENCLAW_GATEWAY_BIND` | Bind mode (loopback/lan) | `loopback` |
| `PORT` | External port (nginx) | `8080` |

### Models

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCLAW_PRIMARY_MODEL` | Primary text model | - |
| `OPENCLAW_FALLBACK_MODELS` | Comma-separated fallback models | - |
| `OPENCLAW_IMAGE_MODEL_PRIMARY` | Primary image generation model | - |
| `OPENCLAW_IMAGE_MODEL_FALLBACKS` | Comma-separated fallback image models | - |

### Storage

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCLAW_DATA_DIR` | Host path for data | `./data/.openclaw` |
| `OPENCLAW_WORKSPACE_DIR` | Host path for workspace | `./data/workspace` |
| `OPENCLAW_LOGS_DIR` | Host path for logs | `./logs` |

### Browser

| Variable | Description | Default |
|----------|-------------|---------|
| `BROWSER_CDP_URL` | Chrome DevTools URL | - |
| `BROWSER_DEFAULT_PROFILE` | Browser profile name | - |
| `BROWSER_EVALUATE_ENABLED` | Enable JS evaluation | `false` |

### Hooks

| Variable | Description | Default |
|----------|-------------|---------|
| `HOOKS_ENABLED` | Enable webhooks | `false` |
| `HOOKS_TOKEN` | Webhook auth token | - |
| `HOOKS_PATH` | Webhook path prefix | `/hooks` |

### WhatsApp

| Variable | Description | Default |
|----------|-------------|---------|
| `WHATSAPP_ENABLED` | Enable WhatsApp | `false` |
| `WHATSAPP_DM_POLICY` | DM policy | `pairing` |
| `WHATSAPP_ALLOW_FROM` | Allowed phone numbers | - |
| `WHATSAPP_GROUP_POLICY` | Group policy | - |

### System

| Variable | Description | Default |
|----------|-------------|---------|
| `TZ` | Timezone | `UTC` |

## Updating

### Automatic Updates

The image includes an auto-update workflow that checks for new releases daily and rebuilds automatically.

### Manual Update

```bash
# Pull latest image
docker compose pull

# Recreate containers
docker compose up -d

# View logs
docker compose logs -f gateway
```

### Update with Data Migration

Your data is persisted in volumes, so updates are safe:

```bash
# Stop containers
docker compose down

# Pull latest
docker compose pull

# Start with new version
docker compose up -d
```

## Troubleshooting

### Container Won't Start

Check logs:
```bash
docker compose logs -f gateway
```

Common issues:
- Missing API key: Set at least one provider API key
- Missing auth password: Set `AUTH_PASSWORD` for production

### WhatsApp Not Connecting

1. Check that `WHATSAPP_ENABLED=true` is set
2. View logs to see QR code: `docker compose logs -f gateway`
3. Scan QR code with WhatsApp mobile app

### Browser Automation Not Working

1. Ensure browser sidecar is running: `docker compose ps`
2. Check `BROWSER_CDP_URL=http://browser:9222` is set
3. Verify network connectivity: `docker compose exec gateway curl http://browser:9222/json/version`

### Permission Issues

If you see permission errors:

```bash
# Fix ownership (Gateway runs as UID/GID 10000)
sudo chown -R 10000:10000 ./data

# Or run as root (not recommended for production)
docker compose exec --user root gateway bash
```

### Reset Configuration

To start fresh:

```bash
# Stop and remove containers
docker compose down

# Remove data (WARNING: This deletes all configuration!)
sudo rm -rf ./data

# Start fresh
docker compose up -d
```

## Security Considerations

1. **Always set `AUTH_PASSWORD`** for production deployments
2. **Use strong `OPENCLAW_GATEWAY_TOKEN`** (generate with `openssl rand -hex 32`)
3. **Keep API keys in `.env` file** - never commit them
4. **Use HTTPS** in production (put behind reverse proxy with SSL)
5. **Restrict WhatsApp/Telegram allowlists** to known contacts
6. **Regularly update** the Docker image for security patches

## Building from Source

```bash
# Clone repository
git clone https://github.com/openclaw/openclaw-docker.git
cd openclaw-docker

# Build OpenClaw image
docker build -t openclaw:local .

# Or build PicoClaw image
docker build --build-arg UPSTREAM=picoclaw -t picoclaw:local .

# Or build with specific version
docker build --build-arg UPSTREAM=openclaw --build-arg UPSTREAM_VERSION=v2026.2.1 -t openclaw:local .
```

## Testing

This project includes a comprehensive test suite using Python and pytest.

### Running Tests

```bash
# Install dependencies with uv
uv sync

# Run all tests
uv run pytest

# Run only unit tests
uv run pytest tests/unit -v

# Run with coverage
uv run pytest --cov=lib tests/
```

### Test Structure

- `tests/unit/` - Unit tests for configuration modules
- `tests/integration/` - Integration tests for GitHub API and Dockerfile validation

## CI/CD

This repository includes GitHub Actions workflows for:

- **Docker Build and Push** - Builds and pushes multi-arch images on every push to main
- **Auto-Update Check** - Daily check for new releases
- **Security Scanning** - Trivy vulnerability scanning

Images are published to:
- `ghcr.io/n00b001/openclaw:latest`
- `ghcr.io/n00b001/openclaw:<version>`
- `ghcr.io/n00b001/picoclaw:latest`
- `ghcr.io/n00b001/picoclaw:<version>`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

### Development Setup

#### Pre-Commit Hooks

We use pre-commit to ensure code quality and consistency. To set it up:

```bash
pip install pre-commit
pre-commit install
```

Pre-commit hooks will run automatically before each commit. To run them manually:

```bash
pre-commit run --all-files
```

The hooks include:
- YAML syntax validation
- Shell script linting
- Dockerfile linting
- Trailing whitespace cleanup
- File size checks
- Merge conflict detection

## Support

### OpenClaw
- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [Discord Community](https://discord.gg/openclaw)

### PicoClaw
- [PicoClaw GitHub](https://github.com/sipeed/picoclaw)
- [Sipeed Website](https://www.sipeed.com/)

## Acknowledgments

- [OpenClaw](https://github.com/openclaw/openclaw) - The official AI agent gateway
- [PicoClaw](https://github.com/sipeed/picoclaw) - Sipeed's lightweight AI agent gateway
- [coollabsio/openclaw](https://github.com/coollabsio/openclaw) - Inspiration for Docker setup
