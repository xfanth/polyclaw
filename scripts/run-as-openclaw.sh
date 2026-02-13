#!/usr/bin/env bash
# =============================================================================
# OpenClaw Run As Script
# =============================================================================
# Run a command as the openclaw user
# Usage: run-as-openclaw <command>
# =============================================================================

if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

if ! id openclaw >/dev/null 2>&1; then
    echo "Error: openclaw user does not exist"
    exit 1
fi

# Execute command as openclaw user
exec su -s /bin/bash openclaw -c "cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw \"\$@\""
