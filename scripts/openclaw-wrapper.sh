#!/usr/bin/env bash
# =============================================================================
# OpenClaw Command Wrapper
# =============================================================================
# This script ensures OpenClaw commands are run as the correct user
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we need to switch users
if [ "$(id -u)" = "0" ] && id openclaw >/dev/null 2>&1; then
    # Running as root, openclaw user exists - switch to it
    # Use a heredoc to properly escape arguments
    exec su -s /bin/bash openclaw << 'EOF'
cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw exec /usr/local/bin/openclaw.real "$@"
EOF
elif [ "$(id -u)" != "0" ] && [ "$(id -un)" != "openclaw" ] && id openclaw >/dev/null 2>&1; then
    # Not running as root or openclaw, switch to openclaw user
    echo -e "${BLUE}[INFO]${NC} Switching to openclaw user..."
    exec su -s /bin/bash openclaw << 'EOF'
cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw exec /usr/local/bin/openclaw.real "$@"
EOF
else
    # Already running as correct user or openclaw user doesn't exist
    exec /usr/local/bin/openclaw.real "$@"
fi
