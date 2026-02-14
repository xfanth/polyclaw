# =============================================================================
# OpenClaw Docker Image - Debian Bookworm (LTS) Based
# =============================================================================
# This Dockerfile builds OpenClaw from source and creates a production-ready
# image with all necessary components for 24/7 operation.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build OpenClaw from source
# -----------------------------------------------------------------------------
FROM node:22-bookworm AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install build dependencies
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        python3 \
        make \
        g++ \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Bun for faster builds
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable corepack for pnpm
RUN corepack enable

# Clone OpenClaw repository
WORKDIR /build
ARG OPENCLAW_VERSION=main
RUN if [ "${OPENCLAW_VERSION}" = "oc_main" ]; then \
        git clone --depth 1 --branch main https://github.com/openclaw/openclaw.git .; \
    else \
        git clone --depth 1 --branch "${OPENCLAW_VERSION}" https://github.com/openclaw/openclaw.git .; \
    fi

# Patch workspace dependencies for standalone build
RUN set -eux; \
    find ./extensions -name 'package.json' -type f | while read -r f; do \
        sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
        sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
    done

# Install dependencies and build
RUN pnpm install --no-frozen-lockfile && pnpm build

# Build UI components
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build

# -----------------------------------------------------------------------------
# Stage 2: Production Runtime
# -----------------------------------------------------------------------------
FROM node:22-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL maintainer="OpenClaw Docker Community"
LABEL description="OpenClaw - Self-hosted AI agent gateway"
LABEL org.opencontainers.image.source="https://github.com/openclaw/openclaw"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production

# Install runtime dependencies including nginx for reverse proxy
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        # Core utilities
        ca-certificates \
        curl \
        wget \
        git \
        # Security
        openssl \
        # Process management
        procps \
        supervisor \
        # Text editors and tools
        neovim \
        vim-tiny \
        nano \
        # Build tools (for native modules)
        build-essential \
        python3 \
        make \
        g++ \
        pkg-config \
        # File utilities
        file \
        # Network tools
        net-tools \
        iputils-ping \
        dnsutils \
        # System utilities
        sudo \
        htop \
        # Nginx for reverse proxy
        nginx \
        apache2-utils \
        # Additional useful packages
        jq \
        unzip \
        zip \
        rsync \
        cron \
        logrotate \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Homebrew (Linuxbrew) for additional package management
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true

# Install Bun runtime
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -sf /root/.bun/bin/bun /usr/local/bin/bun \
    && ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx

# Install npm via Node.js (node is already installed via node:22-bookworm base) and enable corepack for pnpm and yarn
RUN npm install -g npm@latest && corepack enable

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install 1Password CLI
RUN ARCH=$(dpkg --print-architecture) \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" | tee /etc/apt/sources.list.d/1password.list \
    && mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
    && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | tee /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    && mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends 1password-cli \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for running OpenClaw
# Use high UID/GID to avoid conflicts with existing users in base image
RUN groupadd -r openclaw -g 10000 \
    && useradd -r -g openclaw -u 10000 -m -s /bin/bash openclaw \
    && usermod -aG sudo openclaw \
    && echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw \
    && chmod 0440 /etc/sudoers.d/openclaw \
    && chmod u+s /bin/ping \
    && mkdir -p /data/.openclaw/.bun/bin \
    && ln -sf /root/.bun/bin/bun /data/.openclaw/.bun/bin/bun \
    && ln -sf /root/.bun/bin/bunx /data/.openclaw/.bun/bin/bunx \
    && chown -R openclaw:openclaw /data

# Copy OpenClaw from builder
COPY --from=builder --chown=openclaw:openclaw /build /opt/openclaw/app

# Create symlinks for proper path resolution
RUN ln -s /opt/openclaw/app/docs /opt/openclaw/docs \
    && ln -s /opt/openclaw/app/assets /opt/openclaw/assets \
    && ln -s /opt/openclaw/app/package.json /opt/openclaw/package.json

# Create openclaw CLI wrapper
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /opt/openclaw/app/openclaw.mjs "$@"' > /usr/local/bin/openclaw.real \
    && chmod +x /usr/local/bin/openclaw.real

# Copy and install the user switching wrapper
COPY --chown=openclaw:openclaw scripts/openclaw-wrapper.sh /usr/local/bin/openclaw
RUN chmod +x /usr/local/bin/openclaw

# Set up directories with proper permissions
RUN mkdir -p /data/.openclaw /data/workspace /app/config /var/log/openclaw \
    && chown -R openclaw:openclaw /var/log/openclaw \
    && chown -R openclaw:openclaw /var/log/nginx

# Remove default nginx site and make nginx directories writable by openclaw
RUN rm -f /etc/nginx/sites-enabled/default \
    && chown -R openclaw:openclaw /etc/nginx/sites-available /etc/nginx/sites-enabled \
    && chmod 755 /etc/nginx/sites-available /etc/nginx/sites-enabled \
    && touch /etc/nginx/.htpasswd \
    && chown openclaw:openclaw /etc/nginx/.htpasswd \
    && chmod 644 /etc/nginx/.htpasswd \
    && mkdir -p /var/log/nginx \
    && chown -R openclaw:openclaw /var/log/nginx \
    && mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi \
    && chown -R openclaw:openclaw /tmp/nginx \
    && sed -i 's|pid /run/nginx.pid|pid /tmp/nginx.pid|' /etc/nginx/nginx.conf \
    && sed -i '/^http {/a\    client_body_temp_path /tmp/nginx/client_body;\n    proxy_temp_path /tmp/nginx/proxy;\n    fastcgi_temp_path /tmp/nginx/fastcgi;' /etc/nginx/nginx.conf \
    && mkdir -p /var/log/supervisor \
    && chown -R openclaw:openclaw /var/log/supervisor \
    && mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi \
    && chown -R openclaw:openclaw /var/lib/nginx

# Copy scripts and configuration
COPY --chown=openclaw:openclaw scripts/ /app/scripts/
COPY --chown=openclaw:openclaw nginx.conf /etc/nginx/sites-available/openclaw
RUN chmod +x /app/scripts/*.sh \
    && chmod +x /usr/local/bin/openclaw \
    && ln -s /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/openclaw \
    && cp /usr/local/bin/openclaw /usr/local/bin/run-as-openclaw \
    && chmod +x /usr/local/bin/run-as-openclaw

# Create health check script
RUN printf '%s\n' '#!/bin/bash' "curl -f http://localhost:\${PORT:-8080}/healthz || exit 1" > /app/scripts/healthcheck.sh \
    && chmod +x /app/scripts/healthcheck.sh

# Environment variable defaults
ENV PORT=8080
ENV OPENCLAW_GATEWAY_PORT=18789
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json
ENV OPENCLAW_CUSTOM_CONFIG=/app/config/openclaw.json
ENV HOME=/data/.openclaw
ENV PATH="/data/.openclaw/.bun/bin:/root/.bun/bin:${PATH}"

# Expose ports
EXPOSE 8080 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD /app/scripts/healthcheck.sh

# Note: Container starts as root to fix bind mount permissions,
# then entrypoint switches to openclaw user

# Set working directory
WORKDIR /data

# Entrypoint
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
