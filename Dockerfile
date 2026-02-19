# =============================================================================
# OpenClaw/PicoClaw/IronClaw/ZeroClaw Docker Image - Debian Bookworm (LTS) Based
# =============================================================================
# This Dockerfile builds OpenClaw, PicoClaw, IronClaw, or ZeroClaw from source
# and creates a production-ready image with all necessary components for 24/7 operation.
#
# Build Arguments:
#   UPSTREAM        - Which upstream to build: "openclaw", "picoclaw", "ironclaw", or "zeroclaw" (default: openclaw)
#   UPSTREAM_VERSION - Version/branch to build (default: main)
#
# Examples:
#   docker build -t openclaw:latest .
#   docker build --build-arg UPSTREAM=picoclaw -t picoclaw:latest .
#   docker build --build-arg UPSTREAM=ironclaw -t ironclaw:latest .
#   docker build --build-arg UPSTREAM=zeroclaw -t zeroclaw:latest .
#   docker build --build-arg UPSTREAM=openclaw --build-arg UPSTREAM_VERSION=v2026.2.1 -t openclaw:v2026.2.1 .
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build from source
# -----------------------------------------------------------------------------
FROM node:25-bookworm AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build arguments for upstream selection
ARG UPSTREAM=openclaw
ARG UPSTREAM_VERSION=main

# Install build dependencies with retry logic for transient network issues
RUN for i in 1 2 3; do \
        apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-missing \
            git \
            ca-certificates \
            curl \
            python3 \
            make \
            g++ \
            pkg-config && \
        rm -rf /var/lib/apt/lists/* && \
        break || \
        (echo "Retry $i failed, waiting 10 seconds..." && sleep 10); \
    done

# Install Go 1.25.7 from official distribution
RUN curl -fsSL "https://go.dev/dl/go1.25.7.linux-amd64.tar.gz" -o go.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz \
    && for bin in /usr/local/go/bin/*; do ln -sf "$bin" /usr/local/bin; done

# Install Rust for IronClaw/ZeroClaw builds
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Bun for faster builds
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/usr/local/go/bin:/root/.bun/bin:/root/.cargo/bin:${PATH}"

# Enable corepack for pnpm (install globally first as it's not bundled in node:25)
RUN npm install -g corepack@0.34.6 --force && corepack enable

# Clone the appropriate upstream repository
WORKDIR /build

# Clone based on upstream type and version
RUN set -eux && \
    if [ "${UPSTREAM}" = "picoclaw" ]; then \
        GITHUB_OWNER="sipeed"; \
        GITHUB_REPO="picoclaw"; \
    elif [ "${UPSTREAM}" = "ironclaw" ]; then \
        GITHUB_OWNER="nearai"; \
        GITHUB_REPO="ironclaw"; \
    elif [ "${UPSTREAM}" = "zeroclaw" ]; then \
        GITHUB_OWNER="zeroclaw-labs"; \
        GITHUB_REPO="zeroclaw"; \
    else \
        GITHUB_OWNER="openclaw"; \
        GITHUB_REPO="openclaw"; \
    fi && \
    if [ "${UPSTREAM_VERSION}" = "oc_main" ] || [ "${UPSTREAM_VERSION}" = "pc_main" ] || [ "${UPSTREAM_VERSION}" = "ic_main" ] || [ "${UPSTREAM_VERSION}" = "zc_main" ]; then \
        git clone --depth 1 --branch main "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" .; \
    else \
        git clone --depth 1 --branch "${UPSTREAM_VERSION}" "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" .; \
    fi

# Patch workspace dependencies for standalone build (only for OpenClaw)
RUN if [ "${UPSTREAM}" = "openclaw" ]; then \
        set -eux; \
        find ./extensions -name 'package.json' -type f 2>/dev/null | while read -r f; do \
            sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
            sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
        done; \
    fi

# Patch upstream TypeScript errors (OpenClaw/IronClaw only)
# These patches fix type errors in upstream code that breaks the build
# Using @ts-ignore instead of @ts-expect-error so patches work regardless of upstream state
RUN if [ "${UPSTREAM}" != "picoclaw" ] && [ "${UPSTREAM}" != "zeroclaw" ]; then \
        set -eux; \
        if [ -f src/channels/plugins/actions/telegram.ts ]; then \
            sed -i '237a\        // @ts-ignore poll action not in type union' src/channels/plugins/actions/telegram.ts; \
        fi; \
        if [ -f src/web/inbound/send-api.ts ]; then \
            sed -i -E '/^\s*linkPreview:/d' src/web/inbound/send-api.ts; \
            sed -i -E 's/,\s*linkPreview:\s*[^,}\n]+//g' src/web/inbound/send-api.ts; \
        fi; \
        if [ -f src/agents/tool-loop-detection.ts ]; then \
            sed -i '60a\        // @ts-ignore value may be undefined' src/agents/tool-loop-detection.ts; \
            sed -i '57a\            // @ts-ignore value may be undefined' src/agents/tool-loop-detection.ts; \
        fi; \
    fi

# Build based on upstream type
RUN if [ "${UPSTREAM}" = "picoclaw" ]; then \
        echo "Building PicoClaw (Go binary)..."; \
        cd /build && \
        go generate ./... && \
        go build -v -ldflags="-X main.version=${UPSTREAM_VERSION}" -o /build/picoclaw ./cmd/picoclaw && \
        echo "PicoClaw binary built successfully"; \
    elif [ "${UPSTREAM}" = "ironclaw" ]; then \
        echo "Building IronClaw (Rust binary)..."; \
        cd /build && \
        cargo build --release && \
        cp target/release/ironclaw /build/ironclaw && \
        echo "IronClaw binary built successfully"; \
    elif [ "${UPSTREAM}" = "zeroclaw" ]; then \
        echo "Building ZeroClaw (Rust binary)..."; \
        cd /build && \
        cargo build --release && \
        mv target/release/zeroclaw /build/zeroclaw && \
        echo "ZeroClaw binary built successfully"; \
    else \
        echo "Building OpenClaw (Node.js)..."; \
        pnpm install --no-frozen-lockfile && \
        pnpm build && \
        echo "OpenClaw build complete"; \
    fi

# Build UI components (OpenClaw only)
RUN if [ "${UPSTREAM}" = "openclaw" ]; then \
        echo "Building OpenClaw UI components..."; \
        OPENCLAW_PREFER_PNPM=1 pnpm ui:install && \
        pnpm ui:build && \
        echo "OpenClaw UI build complete"; \
    else \
        echo "Skipping UI build for ${UPSTREAM} (no UI components)"; \
    fi

# Store upstream info for later stages
RUN echo "${UPSTREAM}" > /tmp/upstream_name && \
    echo "${UPSTREAM_VERSION}" > /tmp/upstream_version

# -----------------------------------------------------------------------------
# Stage 2: Production Runtime
# -----------------------------------------------------------------------------
FROM node:25-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build arguments (repeated for this stage)
ARG UPSTREAM=openclaw
ARG UPSTREAM_VERSION=main

# Labels with upstream info
LABEL maintainer="OpenClaw Docker Community"
LABEL description="${UPSTREAM} - Self-hosted AI agent gateway"
LABEL org.opencontainers.image.source="https://github.com/${UPSTREAM}/${UPSTREAM}"
LABEL upstream="${UPSTREAM}"
LABEL upstream_version="${UPSTREAM_VERSION}"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production

# Install runtime dependencies including nginx for reverse proxy
# Uses retry logic to handle transient Debian mirror sync issues
RUN for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y --no-install-recommends --fix-missing \
            ca-certificates \
            curl \
            wget \
            git \
            openssl \
            procps \
            supervisor \
            neovim \
            vim-tiny \
            nano \
            build-essential \
            python3 \
            make \
            g++ \
            pkg-config \
            file \
            net-tools \
            iputils-ping \
            dnsutils \
            sudo \
            htop \
            nginx \
            apache2-utils \
            jq \
            unzip \
            zip \
            rsync \
            cron \
            logrotate && \
        rm -rf /var/lib/apt/lists/* && \
        apt-get clean && \
        break || \
        (echo "Retry $i failed, waiting 10 seconds..." && sleep 10); \
    done

# Install Homebrew (Linuxbrew) for additional package management
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true

# Install Bun runtime
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -sf /root/.bun/bin/bun /usr/local/bin/bun \
    && ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx

# Install npm via Node.js and enable corepack for pnpm and yarn
RUN npm install -g npm@11.10.0 && npm install -g corepack@0.34.6 --force && corepack enable

# Install GitHub CLI with retry logic
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y --no-install-recommends --fix-missing gh && \
        rm -rf /var/lib/apt/lists/* && \
        break || \
        (echo "Retry $i failed, waiting 10 seconds..." && sleep 10); \
    done

# Install 1Password CLI with retry logic
RUN ARCH=$(dpkg --print-architecture) \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" | tee /etc/apt/sources.list.d/1password.list \
    && mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
    && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | tee /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    && mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    && for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y --no-install-recommends --fix-missing 1password-cli && \
        rm -rf /var/lib/apt/lists/* && \
        break || \
        (echo "Retry $i failed, waiting 10 seconds..." && sleep 10); \
    done

# Create non-root user for running the application
# Use high UID/GID to avoid conflicts with existing users in base image
# Username matches the upstream for consistency
RUN groupadd -r ${UPSTREAM} -g 10000 \
    && useradd -r -g ${UPSTREAM} -u 10000 -m -s /bin/bash ${UPSTREAM} \
    && usermod -aG sudo ${UPSTREAM} \
    && echo "${UPSTREAM} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${UPSTREAM} \
    && chmod 0440 /etc/sudoers.d/${UPSTREAM} \
    && chmod u+s /bin/ping \
    && mkdir -p /data/.${UPSTREAM}/.bun/bin \
    && ln -sf /root/.bun/bin/bun /data/.${UPSTREAM}/.bun/bin/bun \
    && ln -sf /root/.bun/bin/bunx /data/.${UPSTREAM}/.bun/bin/bunx \
    && chown -R ${UPSTREAM}:${UPSTREAM} /data

# Copy application from builder
COPY --from=builder --chown=${UPSTREAM}:${UPSTREAM} /build /opt/${UPSTREAM}/app

# For PicoClaw/IronClaw/ZeroClaw, move binary to correct location and clean up
RUN if [ "${UPSTREAM}" = "picoclaw" ]; then \
        echo "Moving PicoClaw binary..."; \
        mv /opt/picoclaw/app/picoclaw /opt/picoclaw/picoclaw && \
        rm -rf /opt/picoclaw/app && \
        chmod +x /opt/picoclaw/picoclaw && \
        echo "PicoClaw binary moved to /opt/picoclaw/picoclaw"; \
    elif [ "${UPSTREAM}" = "ironclaw" ]; then \
        echo "Moving IronClaw binary..."; \
        mv /opt/ironclaw/app/ironclaw /opt/ironclaw/ironclaw && \
        rm -rf /opt/ironclaw/app && \
        chmod +x /opt/ironclaw/ironclaw && \
        echo "IronClaw binary moved to /opt/ironclaw/ironclaw"; \
    elif [ "${UPSTREAM}" = "zeroclaw" ]; then \
        echo "Moving ZeroClaw binary..."; \
        mv /opt/zeroclaw/app/zeroclaw /opt/zeroclaw/zeroclaw && \
        rm -rf /opt/zeroclaw/app && \
        chmod +x /opt/zeroclaw/zeroclaw && \
        echo "ZeroClaw binary moved to /opt/zeroclaw/zeroclaw"; \
    else \
        echo "OpenClaw application is in /opt/openclaw/app/"; \
    fi

# Create symlinks for proper path resolution (OpenClaw only)
RUN if [ "${UPSTREAM}" = "openclaw" ]; then \
        echo "Creating OpenClaw symlinks..."; \
        ln -s /opt/openclaw/app/docs /opt/openclaw/docs && \
        ln -s /opt/openclaw/app/assets /opt/openclaw/assets && \
        ln -s /opt/openclaw/app/package.json /opt/openclaw/package.json && \
        echo "OpenClaw symlinks created"; \
    fi

# Create CLI wrapper using the upstream's entrypoint (no .real suffix - this IS the main binary)
# hadolint ignore=SC2016
RUN printf '%s\n' '#!/usr/bin/env bash' "UPSTREAM=\"${UPSTREAM}\"" 'if [ "$UPSTREAM" = "picoclaw" ]; then' \
    '    exec /opt/picoclaw/picoclaw "$@"' \
    'elif [ "$UPSTREAM" = "zeroclaw" ]; then' \
    '    exec /opt/zeroclaw/zeroclaw "$@"' \
    'elif [ "$UPSTREAM" = "ironclaw" ]; then' \
    '    exec /opt/ironclaw/ironclaw "$@"' \
    'else' \
    '    exec node /opt/openclaw/app/openclaw.mjs "$@"' \
    'fi' > /usr/local/bin/${UPSTREAM} \
    && chmod +x /usr/local/bin/${UPSTREAM}

# Create universal CLI wrapper that works regardless of upstream
RUN printf '%s\n' '#!/usr/bin/env bash' \
    'if [ -f /opt/openclaw/app/openclaw.mjs ]; then' \
    '    exec node /opt/openclaw/app/openclaw.mjs "$@"' \
    'elif [ -f /opt/picoclaw/picoclaw ]; then' \
    '    exec /opt/picoclaw/picoclaw "$@"' \
    'elif [ -f /opt/ironclaw/ironclaw ]; then' \
    '    exec /opt/ironclaw/ironclaw "$@"' \
    'elif [ -f /opt/zeroclaw/zeroclaw ]; then' \
    '    exec /opt/zeroclaw/zeroclaw "$@"' \
    'else' \
    '    echo "Error: No upstream application found" >&2' \
    '    exit 1' \
    'fi' > /usr/local/bin/upstream \
    && chmod +x /usr/local/bin/upstream

# Set up directories with proper permissions
RUN mkdir -p /data/.${UPSTREAM}/identity /data/.${UPSTREAM}/workspace /data/workspace /app/config /var/log/${UPSTREAM} \
    && chown -R ${UPSTREAM}:${UPSTREAM} /data/.${UPSTREAM} \
    && chown -R ${UPSTREAM}:${UPSTREAM} /data/workspace \
    && chown -R ${UPSTREAM}:${UPSTREAM} /var/log/${UPSTREAM} \
    && chown -R ${UPSTREAM}:${UPSTREAM} /var/log/nginx

# Remove default nginx site and make nginx directories writable
RUN rm -f /etc/nginx/sites-enabled/default \
    && chown -R ${UPSTREAM}:${UPSTREAM} /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d \
    && chmod 755 /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d \
    && touch /etc/nginx/.htpasswd \
    && chown ${UPSTREAM}:${UPSTREAM} /etc/nginx/.htpasswd \
    && chmod 644 /etc/nginx/.htpasswd \
    && mkdir -p /var/log/nginx \
    && chown -R ${UPSTREAM}:${UPSTREAM} /var/log/nginx \
    && mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi \
    && chown -R ${UPSTREAM}:${UPSTREAM} /tmp/nginx \
    && sed -i 's|pid /run/nginx.pid|pid /tmp/nginx.pid|' /etc/nginx/nginx.conf \
    && sed -i '/^http {/a\    client_body_temp_path /tmp/nginx/client_body;\n    proxy_temp_path /tmp/nginx/proxy;\n    fastcgi_temp_path /tmp/nginx/fastcgi;' /etc/nginx/nginx.conf \
    && mkdir -p /var/log/supervisor \
    && chown -R ${UPSTREAM}:${UPSTREAM} /var/log/supervisor \
    && mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi \
    && chown -R ${UPSTREAM}:${UPSTREAM} /var/lib/nginx

# Copy scripts and configuration
COPY --chown=${UPSTREAM}:${UPSTREAM} scripts/ /app/scripts/
COPY --chown=${UPSTREAM}:${UPSTREAM} nginx.conf /etc/nginx/sites-available/${UPSTREAM}
RUN chmod +x /app/scripts/*.sh

# Create health check script
RUN printf '%s\n' '#!/bin/bash' "curl -f http://localhost:\${PORT:-8080}/healthz || exit 1" > /app/scripts/healthcheck.sh \
    && chmod +x /app/scripts/healthcheck.sh

# Build arguments for version info
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG IMAGE_VERSION=unknown

# Create version file for debugging
RUN printf '%s\n' "UPSTREAM=${UPSTREAM}" "UPSTREAM_VERSION=${UPSTREAM_VERSION}" "GIT_COMMIT=${GIT_COMMIT}" "BUILD_DATE=${BUILD_DATE}" "IMAGE_VERSION=${IMAGE_VERSION}" > /app/VERSION \
    && chown ${UPSTREAM}:${UPSTREAM} /app/VERSION

# Environment variable defaults
# Note: OPENCLAW_STATE_DIR, HOME are set by entrypoint.sh based on detected upstream
ENV UPSTREAM=${UPSTREAM}
ENV PORT=8080
ENV OPENCLAW_GATEWAY_PORT=18789
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.${UPSTREAM}/${UPSTREAM}.json
ENV OPENCLAW_CUSTOM_CONFIG=/app/config/${UPSTREAM}.json
ENV PATH="/data/.${UPSTREAM}/.bun/bin:/root/.bun/bin:${PATH}"

# Expose ports
EXPOSE 8080 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD /app/scripts/healthcheck.sh

# Note: Container starts as root to fix bind mount permissions,
# then entrypoint switches to the appropriate user

# Set working directory
WORKDIR /data

# Entrypoint
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
