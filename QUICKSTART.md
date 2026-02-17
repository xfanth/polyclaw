# OpenClaw Docker - 5-Minute Quick Start

## Step 1: Configure Environment

```bash
cd openclaw-docker
cp .env.example .env
```

Edit `.env` and add:

```env
# Required: Your AI provider API key
ANTHROPIC_API_KEY=sk-ant-api03-...

# Required: Web UI password
AUTH_PASSWORD=your-secure-password

# Required: Gateway token (generate: openssl rand -hex 32)
OPENCLAW_GATEWAY_TOKEN=...

# Data directories (defaults work for most setups)
OPENCLAW_DATA_DIR=./data/.openclaw
OPENCLAW_WORKSPACE_DIR=./data/workspace
```

## Step 2: Start OpenClaw

```bash
docker compose up -d
```

## Step 3: Access Web Interface

Open http://localhost:8080

- Username: `admin`
- Password: Your `AUTH_PASSWORD`

## Step 4: Configure WhatsApp (Optional)

```bash
# View QR code
docker compose logs -f gateway | grep -A 20 "QR"
```

Scan with WhatsApp mobile app.

## Done!

Your OpenClaw instance is now running 24/7 with:
- Persistent data storage
- All AI providers configured
- Web UI with authentication
- Auto-restart on failure

## Useful Commands

```bash
# View logs
docker compose logs -f gateway

# Restart
docker compose restart

# Update to latest image
docker compose pull && docker compose up -d

# Shell access
docker compose exec gateway bash

# Stop
docker compose down
```

## Troubleshooting

**Container won't start?**
```bash
docker compose logs gateway | tail -50
```

**Permission issues?**
```bash
sudo chown -R 10000:10000 ./data
```

**Reset everything?**
```bash
docker compose down
sudo rm -rf ./data
docker compose up -d
```
