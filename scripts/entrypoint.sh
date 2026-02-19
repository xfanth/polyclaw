#!/usr/bin/env bash
# =============================================================================
# OpenClaw/PicoClaw Docker Entrypoint Script
# =============================================================================
# This script:
# 1. Detects which upstream is running (openclaw or picoclaw)
# 2. Installs extra apt packages if requested
# 3. Validates required environment variables
# 4. Generates configuration from environment variables
# 5. Configures nginx reverse proxy
# 6. Starts the gateway
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Detect upstream
# =============================================================================
detect_upstream() {
    if [ -f /opt/openclaw/app/openclaw.mjs ]; then
        echo "openclaw"
    elif [ -f /opt/zeroclaw/zeroclaw ]; then
        echo "zeroclaw"
    elif [ -f /opt/ironclaw/ironclaw ]; then
        echo "ironclaw"
    elif [ -f /opt/picoclaw/app/picoclaw.mjs ]; then
        echo "picoclaw"
    elif [ -f /opt/picoclaw/picoclaw ]; then
        echo "picoclaw"
    else
        log_error "No upstream application found!"
        log_error "Expected one of: /opt/openclaw/app/openclaw.mjs, /opt/picoclaw/picoclaw, /opt/ironclaw/ironclaw, or /opt/zeroclaw/zeroclaw"
        exit 1
    fi
}

DETECTED_UPSTREAM=$(detect_upstream)

if [ -n "${UPSTREAM:-}" ] && [ "$UPSTREAM" != "$DETECTED_UPSTREAM" ]; then
    log_warn "UPSTREAM env var ($UPSTREAM) doesn't match detected upstream ($DETECTED_UPSTREAM)"
    log_warn "Using detected upstream: $DETECTED_UPSTREAM"
fi

UPSTREAM="$DETECTED_UPSTREAM"
log_info "Detected upstream: $UPSTREAM"

# Set upstream-specific paths
case "$UPSTREAM" in
    openclaw)
        CLI_NAME="openclaw"
        DEFAULT_STATE_DIR="/data/.openclaw"
        ;;
    picoclaw)
        CLI_NAME="picoclaw"
        DEFAULT_STATE_DIR="/data/.picoclaw"
        ;;
    ironclaw)
        CLI_NAME="ironclaw"
        DEFAULT_STATE_DIR="/data/.ironclaw"
        ;;
    zeroclaw)
        CLI_NAME="zeroclaw"
        DEFAULT_STATE_DIR="/data/.zeroclaw"
        ;;
    *)
        log_error "Unknown upstream: $UPSTREAM"
        exit 1
        ;;
esac

# Determine if this is a Node.js upstream (has full CLI) or compiled binary
IS_NODEJS_UPSTREAM=false
case "$UPSTREAM" in
    openclaw)
        IS_NODEJS_UPSTREAM=true
        ;;
    picoclaw|ironclaw|zeroclaw)
        ;;
esac

# =============================================================================
# Root-level setup: permissions, config generation, nginx setup
# =============================================================================
if [ "$(id -u)" = "0" ]; then
    log_info "Running as root, fixing permissions and generating configuration for $UPSTREAM user..."

    # Check that user exists before proceeding
    if ! id "$UPSTREAM" >/dev/null 2>&1; then
        log_error "User '$UPSTREAM' does not exist!"
        log_error "This usually means the image was built for a different upstream."
        log_error "Detected files:"
        ls -la /opt/ 2>/dev/null || true
        exit 1
    fi

    # =============================================================================
    # Configuration (as root)
    # =============================================================================
    STATE_DIR="${OPENCLAW_STATE_DIR:-$DEFAULT_STATE_DIR}"
    WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
    EXTERNAL_GATEWAY_PORT="${OPENCLAW_EXTERNAL_GATEWAY_PORT:-8080}"
    INTERNAL_GATEWAY_PORT="${OPENCLAW_INTERNAL_GATEWAY_PORT:-18789}"

    log_info "Starting $UPSTREAM Docker Container"

    # Log version info if available
    if [ -f /app/VERSION ]; then
        log_info "Image version info:"
        while IFS= read -r line; do
            log_info "  $line"
        done < /app/VERSION
    fi

    log_info "State dir: $STATE_DIR"
    log_info "Workspace dir: $WORKSPACE_DIR"
    log_info "External gateway port: $EXTERNAL_GATEWAY_PORT"
    log_info "Internal gateway port: $INTERNAL_GATEWAY_PORT"

    # =============================================================================
    # Validate required environment variables (as root)
    # =============================================================================

    # Check for gateway token
    if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
        log_warn "OPENCLAW_GATEWAY_TOKEN not set, generating one..."
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        log_info "Generated gateway token: $OPENCLAW_GATEWAY_TOKEN"
        export OPENCLAW_GATEWAY_TOKEN
    fi

    # Check for at least one AI provider API key
    HAS_PROVIDER=0
    PROVIDER_VARS=(
        "ANTHROPIC_API_KEY"
        "OPENAI_API_KEY"
        "OPENROUTER_API_KEY"
        "GEMINI_API_KEY"
        "XAI_API_KEY"
        "GROQ_API_KEY"
        "MISTRAL_API_KEY"
        "CEREBRAS_API_KEY"
        "VENICE_API_KEY"
        "MOONSHOT_API_KEY"
        "KIMI_API_KEY"
        "MINIMAX_API_KEY"
        "ZAI_API_KEY"
        "AI_GATEWAY_API_KEY"
        "OPENCODE_API_KEY"
        "SYNTHETIC_API_KEY"
        "COPILOT_GITHUB_TOKEN"
        "XIAOMI_API_KEY"
    )

    for key in "${PROVIDER_VARS[@]}"; do
        if [ -n "${!key:-}" ]; then
            HAS_PROVIDER=1
            log_info "Found provider: $key"
            break
        fi
    done

    # Check for AWS Bedrock credentials
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        HAS_PROVIDER=1
        log_info "Found AWS Bedrock credentials"
    fi

    # Check for Ollama
    if [ -n "${OLLAMA_BASE_URL:-}" ]; then
        HAS_PROVIDER=1
        log_info "Found Ollama configuration"
    fi

    if [ "$HAS_PROVIDER" -eq 0 ]; then
        log_error "No AI provider API key configured!"
        log_error "Please set at least one of the following environment variables:"
        log_error "  - ANTHROPIC_API_KEY"
        log_error "  - OPENAI_API_KEY"
        log_error "  - OPENROUTER_API_KEY"
        log_error "  - GEMINI_API_KEY"
        log_error "  - GROQ_API_KEY"
        log_error "  - CEREBRAS_API_KEY"
        log_error "  - KIMI_API_KEY"
        log_error "  - ZAI_API_KEY"
        log_error "  - OPENCODE_API_KEY"
        log_error "  - COPILOT_GITHUB_TOKEN"
        log_error "  - AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (for Bedrock)"
        log_error "  - OLLAMA_BASE_URL (for local models)"
        exit 1
    fi

    # =============================================================================
    # Create necessary directories (as root)
    # =============================================================================
    log_info "Creating directories..."
    mkdir -p "$STATE_DIR" "$WORKSPACE_DIR"
    mkdir -p "$STATE_DIR/agents/main/sessions"
    mkdir -p "$STATE_DIR/credentials"
    mkdir -p "$STATE_DIR/skills"
    mkdir -p "$STATE_DIR/plugins"
    mkdir -p "$STATE_DIR/npm"
    mkdir -p "$STATE_DIR/brew"
    mkdir -p "$STATE_DIR/logs"
    mkdir -p "$STATE_DIR/identity"

    # Create nginx directories that need proper permissions
    mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi 2>/dev/null || true

    # Set proper permissions
    chmod 700 "$STATE_DIR"
    chmod 700 "$STATE_DIR/credentials" 2>/dev/null || true
    chmod 700 "$STATE_DIR/identity" 2>/dev/null || true

    # =============================================================================
    # Export environment variables for configure.js (as root)
    # =============================================================================
    export UPSTREAM="$UPSTREAM"
    export OPENCLAW_STATE_DIR="$STATE_DIR"
    export OPENCLAW_WORKSPACE_DIR="$WORKSPACE_DIR"
    export OPENCLAW_INTERNAL_GATEWAY_PORT="$INTERNAL_GATEWAY_PORT"
    # ZeroClaw expects config at ~/.zeroclaw/ so HOME must be /data (not /data/.zeroclaw)
    if [ "$UPSTREAM" = "zeroclaw" ]; then
        export HOME="/data"
    else
        export HOME="$STATE_DIR"
    fi

    # =============================================================================
    # Generate configuration from environment variables (as root)
    # =============================================================================
    log_info "Generating $UPSTREAM configuration..."
    node /app/scripts/configure.js

    # =============================================================================
    # Configure Nginx (as root - requires root for /etc/nginx)
    # =============================================================================
    log_info "Configuring Nginx..."

    # Generate nginx configuration
    # Use conf.d directory which is included by default in nginx Docker images
    tee "/etc/nginx/conf.d/${UPSTREAM}.conf" > /dev/null << EOF
# $UPSTREAM Nginx Configuration

# Upstream for $UPSTREAM Gateway
upstream ${UPSTREAM}_gateway {
    server 127.0.0.1:$INTERNAL_GATEWAY_PORT;
    keepalive 32;
}

# Rate limiting zone
limit_req_zone \$binary_remote_addr zone=${UPSTREAM}_limit:10m rate=10r/s;

server {
    listen $EXTERNAL_GATEWAY_PORT default_server;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Client body size
    client_max_body_size 50M;

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # Health check endpoint (no auth)
    location /healthz {
        proxy_pass http://${UPSTREAM}_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        access_log off;
    }

    # Hooks endpoint (special handling)
    location /hooks {
        proxy_pass http://${UPSTREAM}_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support for hooks
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Main application
    location / {
        # Rate limiting
        limit_req zone=${UPSTREAM}_limit burst=20 nodelay;

        # Basic auth if configured
        auth_basic "$UPSTREAM Gateway";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://${UPSTREAM}_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Buffer settings
        proxy_buffering off;
        proxy_cache off;
    }

    # Browser noVNC access (requires browser sidecar with noVNC on port 6080)
    # The browser host should provide noVNC on port 6080
    location /browser/ {
        proxy_pass http://browser:6080/vnc.html;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support for noVNC
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts for long-lived VNC sessions
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;

        # Buffer settings
        proxy_buffering off;
        proxy_cache off;
    }

    # noVNC websockify endpoint
    location /websockify {
        proxy_pass http://browser:6080/websockify;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts for long-lived connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;

        # Disable buffering for real-time communication
        proxy_buffering off;
    }
}
EOF

    # Create htpasswd file for basic auth if credentials are provided
    if [ -n "${AUTH_PASSWORD:-}" ]; then
        AUTH_USERNAME="${AUTH_USERNAME:-admin}"
        echo "$AUTH_USERNAME:$(openssl passwd -apr1 "$AUTH_PASSWORD")" | tee /etc/nginx/.htpasswd > /dev/null
        log_success "HTTP Basic Auth configured for user: $AUTH_USERNAME"
    else
        # Create empty htpasswd to allow all access
        echo "" | tee /etc/nginx/.htpasswd > /dev/null
        log_warn "No AUTH_PASSWORD set - gateway will be open (not recommended for production)"
    fi

    # Test nginx configuration
    nginx -t || {
        log_error "Nginx configuration test failed"
        exit 1
    }

    # =============================================================================
    # Fix legacy config keys (as root)
    # =============================================================================
    log_info "Running $CLI_NAME doctor..."
    # Only openclaw supports --fix flag; other upstreams just run basic doctor
    if [ "$IS_NODEJS_UPSTREAM" = true ]; then
        "/usr/local/bin/$CLI_NAME" doctor --fix || true
    else
        "/usr/local/bin/$CLI_NAME" doctor || true
    fi

    # Determine the correct HOME directory for supervisord
    # ZeroClaw expects config at ~/.zeroclaw/ so HOME must be /data (not /data/.zeroclaw)
    if [ "$UPSTREAM" = "zeroclaw" ]; then
        SUPERVISOR_HOME="/data"
    else
        SUPERVISOR_HOME="$STATE_DIR"
    fi

    # =============================================================================
    # Create supervisord configuration (as root)
    # =============================================================================
    log_info "Creating supervisord configuration..."

    mkdir -p /var/log/supervisor

    # Determine gateway command based on upstream type
    # Each upstream has different CLI for starting the gateway:
    # - OpenClaw: openclaw gateway --port X --bind Y
    # - PicoClaw: picoclaw gateway --port X
    # - ZeroClaw: zeroclaw gateway --port X
    # - IronClaw: ironclaw (no gateway subcommand - just runs agent with all channels)
    case "$UPSTREAM" in
        openclaw)
            GATEWAY_CMD="/usr/local/bin/$CLI_NAME gateway --port ${INTERNAL_GATEWAY_PORT} --bind loopback"
            ;;
        picoclaw)
            GATEWAY_CMD="/usr/local/bin/$CLI_NAME gateway --port ${INTERNAL_GATEWAY_PORT}"
            ;;
        zeroclaw)
            GATEWAY_CMD="/usr/local/bin/$CLI_NAME gateway --port ${INTERNAL_GATEWAY_PORT}"
            ;;
        ironclaw)
            # IronClaw has no 'gateway' subcommand - just run the binary
            # It starts REPL, HTTP webhooks, and web gateway together
            GATEWAY_CMD="/usr/local/bin/$CLI_NAME"
            ;;
        *)
            log_error "Unknown upstream: $UPSTREAM"
            exit 1
            ;;
    esac

    cat > "$STATE_DIR/supervisord.conf" << EOF
[supervisord]
nodaemon=true
user=$UPSTREAM
logfile=/var/log/supervisor/supervisord.log
pidfile=/tmp/supervisord.pid

[unix_http_server]
file=/tmp/supervisor.sock
chmod=0700

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx-error.log

[program:$UPSTREAM]
command=$GATEWAY_CMD
autostart=true
autorestart=true
priority=20
stdout_logfile=/var/log/supervisor/$UPSTREAM.log
stderr_logfile=/var/log/supervisor/$UPSTREAM-error.log
environment=HOME="${SUPERVISOR_HOME}",OPENCLAW_STATE_DIR="${STATE_DIR}",OPENCLAW_WORKSPACE_DIR="${WORKSPACE_DIR}",OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}",OPENCLAW_INTERNAL_GATEWAY_PORT="${INTERNAL_GATEWAY_PORT}",NODE_ENV="production"
EOF

    # =============================================================================
    # Log configuration summary (as root)
    # =============================================================================
    log_info "Gateway command: $GATEWAY_CMD"
    log_info "Supervisord config written to: $STATE_DIR/supervisord.conf"
    log_info "Environment variables passed to $UPSTREAM:"
    log_info "  HOME=${SUPERVISOR_HOME}"
    log_info "  OPENCLAW_STATE_DIR=${STATE_DIR}"
    log_info "  OPENCLAW_WORKSPACE_DIR=${WORKSPACE_DIR}"
    log_info "  OPENCLAW_INTERNAL_GATEWAY_PORT=${INTERNAL_GATEWAY_PORT}"
    log_info "  NODE_ENV=production"

    # Verify supervisord config is valid
    if [ -f "$STATE_DIR/supervisord.conf" ]; then
        log_info "Supervisord configuration file exists"
        log_info "Contents preview:"
        head -20 "$STATE_DIR/supervisord.conf" | while read line; do
            log_info "  $line"
        done
    fi

    # =============================================================================
    # Fix permissions for bind mounts (as root)
    # =============================================================================
    # Fix ownership - warn if chown fails (common with restrictive bind mounts)
    if ! chown -R "$UPSTREAM:$UPSTREAM" /data 2>/dev/null; then
        log_warn "Could not change ownership of /data - bind mount may have restrictive permissions"
        log_warn "If you see permission errors, fix ownership on the host: chown -R 10000:10000 <bind-mount-path>"
    fi
    chown -R "$UPSTREAM:$UPSTREAM" "/var/log/$UPSTREAM" 2>/dev/null || true
    chown -R "$UPSTREAM:$UPSTREAM" /var/log/supervisor 2>/dev/null || true
    chown -R "$UPSTREAM:$UPSTREAM" /var/lib/nginx 2>/dev/null || true
    if ! chown -R "$UPSTREAM:$UPSTREAM" /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null; then
        log_warn "Could not chown nginx directories"
        ls -la /etc/nginx/ 2>/dev/null || true
    fi

    sync  # Ensure all chown operations complete before proceeding

    # =============================================================================
    # Switch to non-root user and start supervisord
    # =============================================================================
    log_info "Switching to $UPSTREAM user and starting supervisord..."
    log_success "$UPSTREAM Gateway configured (external: $EXTERNAL_GATEWAY_PORT, internal: $INTERNAL_GATEWAY_PORT)"
    log_info "Web interface available at: http://localhost:$EXTERNAL_GATEWAY_PORT"
    log_info "Gateway token: ${OPENCLAW_GATEWAY_TOKEN:0:8}..."
    log_info ""
    log_info "=== Troubleshooting Info ==="
    log_info "If you see 404/502 errors:"
    log_info "  1. Check gateway logs: docker logs <container> | grep -A 20 '$UPSTREAM'"
    log_info "  2. Verify port binding: docker exec <container> netstat -tlnp | grep $INTERNAL_GATEWAY_PORT"
    log_info "  3. Test internal endpoint: docker exec <container> curl -s http://127.0.0.1:$INTERNAL_GATEWAY_PORT/healthz"
    log_info ""

    # Use su -p to preserve environment variables (Debian doesn't support --whitelist-environment)
    # Export critical vars and exec supervisord as non-root user
    exec su -p -s /bin/bash "$UPSTREAM" -c "export HOME='$SUPERVISOR_HOME'; export OPENCLAW_STATE_DIR='$STATE_DIR'; export OPENCLAW_WORKSPACE_DIR='$WORKSPACE_DIR'; export OPENCLAW_GATEWAY_TOKEN='$OPENCLAW_GATEWAY_TOKEN'; export OPENCLAW_INTERNAL_GATEWAY_PORT='$INTERNAL_GATEWAY_PORT'; export NODE_ENV='production'; cd /data && exec supervisord -c '$STATE_DIR/supervisord.conf'"
fi

# =============================================================================
# Non-root execution (should never reach here normally)
# =============================================================================
log_error "This script must be run as root!"
log_error "The entrypoint should switch to the non-root user automatically."
exit 1
