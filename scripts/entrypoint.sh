#!/usr/bin/env bash
# =============================================================================
# OpenClaw Docker Entrypoint Script
# =============================================================================
# This script:
# 1. Installs extra apt packages if requested
# 2. Validates required environment variables
# 3. Generates openclaw.json from environment variables
# 4. Configures nginx reverse proxy
# 5. Starts the OpenClaw gateway
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
# Configuration
# =============================================================================
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
PORT="${PORT:-8080}"

log_info "Starting OpenClaw Docker Container"
log_info "State dir: $STATE_DIR"
log_info "Workspace dir: $WORKSPACE_DIR"
log_info "Gateway port: $GATEWAY_PORT"
log_info "External port: $PORT"

# =============================================================================
# Validate required environment variables
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
    "OPENCODE_API_KEY"
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
# Create necessary directories
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

# Set proper permissions
chmod 700 "$STATE_DIR"
chmod 700 "$STATE_DIR/credentials" 2>/dev/null || true

# =============================================================================
# Export environment variables for configure.js
# =============================================================================
export OPENCLAW_STATE_DIR="$STATE_DIR"
export OPENCLAW_WORKSPACE_DIR="$WORKSPACE_DIR"
export HOME="$STATE_DIR"

# =============================================================================
# Generate openclaw.json from environment variables
# =============================================================================
log_info "Generating OpenClaw configuration..."
node /app/scripts/configure.js

# =============================================================================
# Configure Nginx
# =============================================================================
log_info "Configuring Nginx..."

# Generate nginx configuration
tee /etc/nginx/sites-available/openclaw > /dev/null << 'EOF'
# OpenClaw Nginx Configuration

# Upstream for OpenClaw Gateway
upstream openclaw_gateway {
    server 127.0.0.1:18789;
    keepalive 32;
}

# Rate limiting zone
limit_req_zone $binary_remote_addr zone=openclaw_limit:10m rate=10r/s;

server {
    listen 8080 default_server;
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
        proxy_pass http://openclaw_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        access_log off;
    }
    
    # Hooks endpoint (special handling)
    location /hooks {
        proxy_pass http://openclaw_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for hooks
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Main application
    location / {
        # Rate limiting
        limit_req zone=openclaw_limit burst=20 nodelay;
        
        # Basic auth if configured
        auth_basic "OpenClaw Gateway";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://openclaw_gateway;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for noVNC
        proxy_set_header Upgrade $http_upgrade;
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
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
# Create supervisord configuration
# =============================================================================
log_info "Creating supervisord configuration..."

mkdir -p /var/log/supervisor

cat > /app/supervisord.conf << EOF
[supervisord]
nodaemon=true
user=openclaw
logfile=/var/log/supervisor/supervisord.log
pidfile=/tmp/supervisord.pid

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx-error.log

[program:openclaw]
command=openclaw gateway --port ${GATEWAY_PORT} --bind loopback
autostart=true
autorestart=true
priority=20
stdout_logfile=/var/log/supervisor/openclaw.log
stderr_logfile=/var/log/supervisor/openclaw-error.log
environment=HOME="${STATE_DIR}",OPENCLAW_STATE_DIR="${STATE_DIR}",OPENCLAW_WORKSPACE_DIR="${WORKSPACE_DIR}",OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}"
EOF

# =============================================================================
# Start supervisord (which manages nginx and openclaw)
# =============================================================================
log_success "Starting OpenClaw Gateway on port $GATEWAY_PORT"
log_info "Web interface available at: http://localhost:$PORT"
log_info "Gateway token: ${OPENCLAW_GATEWAY_TOKEN:0:8}..."
log_info "Starting supervisord to manage services..."

exec supervisord -c /app/supervisord.conf
