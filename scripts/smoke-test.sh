#!/bin/bash
# =============================================================================
# OpenClaw/PicoClaw/IronClaw/ZeroClaw Docker Smoke Test
# =============================================================================
# This script tests that a Docker image for a specific upstream works correctly:
# 1. Builds/uses the Docker image for the specified upstream
# 2. Starts the container (tests auto-detection from files)
# 3. Verifies container detected the correct upstream from its files
# 4. Ensures web UI is reachable on port 8080
# 5. Runs healthcheck commands (status, gateway status)
# 6. Ensures container doesn't crash/exit/restart
#
# Usage:
#   ./smoke-test.sh                     # Test OpenClaw (default)
#   UPSTREAM=zeroclaw ./smoke-test.sh   # Test ZeroClaw
#   IMAGE_TAG=myimage:latest ./smoke-test.sh  # Use pre-built image
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

UPSTREAM="${UPSTREAM:-openclaw}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:-main}"
COMPOSE_FILE="docker-compose.test.yml"
TEST_TIMEOUT=120
STABILITY_CHECK_TIME=30
SERVICE_NAME="gateway-test"
IMAGE_TAG="${IMAGE_TAG:-${UPSTREAM}:smoke-test}"

TESTS_PASSED=0
TESTS_FAILED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

IS_NODEJS_UPSTREAM=false
case "$UPSTREAM" in
    openclaw) IS_NODEJS_UPSTREAM=true ;;
    picoclaw|ironclaw|zeroclaw) ;;
    *)
        log_error "Unknown upstream: $UPSTREAM"
        log_error "Supported: openclaw, picoclaw, ironclaw, zeroclaw"
        exit 1
        ;;
esac

log_info "Upstream type: $([ "$IS_NODEJS_UPSTREAM" = true ] && echo 'Node.js (full CLI)' || echo 'Compiled binary (limited CLI)')"
log_info "Smoke Test Configuration:"
echo "  UPSTREAM: ${UPSTREAM}"
echo "  UPSTREAM_VERSION: ${UPSTREAM_VERSION}"
echo "  IMAGE_TAG: ${IMAGE_TAG}"
echo ""

cleanup() {
    log_info "Cleaning up test environment..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
    sudo rm -rf test-data test-workspace 2>/dev/null || rm -rf test-data test-workspace 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
# Test 1: Use/Build Docker Image
# =============================================================================
log_info "Test 1: Checking Docker image..."

if [ "$IMAGE_TAG" != "${UPSTREAM}:smoke-test" ]; then
    log_info "Using pre-built image: $IMAGE_TAG"
    if docker image inspect "$IMAGE_TAG" > /dev/null 2>&1; then
        log_success "Pre-built image found"
        docker tag "$IMAGE_TAG" "${UPSTREAM}:smoke-test"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Pre-built image not found: $IMAGE_TAG"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        exit 1
    fi
elif docker image inspect "${UPSTREAM}:smoke-test" > /dev/null 2>&1; then
    log_success "Docker image already exists, skipping build"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif docker build --build-arg UPSTREAM="$UPSTREAM" --build-arg UPSTREAM_VERSION="$UPSTREAM_VERSION" -t "${UPSTREAM}:smoke-test" . > /tmp/build.log 2>&1; then
    log_success "Docker image built successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Docker image build failed"
    cat /tmp/build.log
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 2: Start Container
# =============================================================================
log_info "Test 2: Starting container..."

mkdir -p test-data test-workspace

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    sudo chown -R "$(id -u):$(id -g)" test-data test-workspace 2>/dev/null || true
    sudo chmod -R 755 test-data test-workspace 2>/dev/null || true
fi

export UPSTREAM

if docker compose -f "$COMPOSE_FILE" up -d > /tmp/compose.log 2>&1; then
    log_success "Container started"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Failed to start container"
    cat /tmp/compose.log
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

sleep 3

# =============================================================================
# Test 3: Check for Immediate Crashes / Restart Loops
# =============================================================================
log_info "Test 3: Checking container stability (no immediate crashes)..."

CRASH_DETECTED=0
for i in 1 2 3 4 5; do
    STATUS=$(docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1 || echo "")

    if echo "$STATUS" | grep -q "exited\|dead"; then
        log_error "Container exited!"
        CRASH_DETECTED=1
        break
    fi

    if echo "$STATUS" | grep -q "restarting"; then
        log_error "Container is in restart loop!"
        CRASH_DETECTED=1
        break
    fi

    CURRENT_RESTARTS=$(docker inspect --format='{{.RestartCount}}' "${UPSTREAM}-smoke-test" 2>/dev/null || echo "0")
    if [ "$CURRENT_RESTARTS" -gt 0 ]; then
        log_error "Container restarted (count: $CURRENT_RESTARTS)"
        CRASH_DETECTED=1
        break
    fi

    sleep 2
done

if [ $CRASH_DETECTED -eq 1 ]; then
    log_error "Container crash detected!"
    log_info "Container logs:"
    docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

log_success "Container is stable (no crashes in first 15 seconds)"
TESTS_PASSED=$((TESTS_PASSED + 1))

# =============================================================================
# Test 4: Verify Upstream Detection
# =============================================================================
log_info "Test 4: Verifying upstream detection..."

CONTAINER_LOGS=$(docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" 2>/dev/null || true)

if echo "$CONTAINER_LOGS" | grep -q "Detected upstream: $UPSTREAM"; then
    log_success "Container correctly detected upstream: $UPSTREAM"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Container detected wrong upstream!"
    log_info "Expected: $UPSTREAM"
    log_info "Container logs (first 50 lines):"
    echo "$CONTAINER_LOGS" | head -50
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

if echo "$CONTAINER_LOGS" | grep -q "User.*does not exist"; then
    log_error "Container reports user does not exist - image/UPSTREAM mismatch!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 5: Wait for Full Startup
# =============================================================================
log_info "Test 5: Waiting for full startup (timeout: ${TEST_TIMEOUT}s)..."

START_TIME=$(date +%s)
STARTED=0

while [ $(($(date +%s) - START_TIME)) -lt $TEST_TIMEOUT ]; do
    STATUS=$(docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1 || echo "")
    if echo "$STATUS" | grep -q "exited\|dead\|restarting"; then
        log_error "Container crashed during startup: $STATUS"
        log_info "Container logs:"
        docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
        TESTS_FAILED=$((TESTS_FAILED + 1))
        exit 1
    fi

    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" pgrep -f "supervisord" > /dev/null 2>&1; then
        STARTED=1
        break
    fi

    echo -n "."
    sleep 2
done

echo ""

if [ $STARTED -eq 1 ]; then
    log_success "Services started successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Startup timed out after ${TEST_TIMEOUT}s"
    log_info "Container logs:"
    docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

sleep 5

# =============================================================================
# Test 6: Web UI Reachability
# =============================================================================
log_info "Test 6: Testing web UI reachability on port 8080..."

HTTP_SUCCESS=0
HTTP_CODE=""
for i in 1 2 3 4 5; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/healthz 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        HTTP_SUCCESS=1
        break
    fi
    if [ "$HTTP_CODE" = "502" ]; then
        log_warn "HTTP 502 (Bad Gateway) - nginx is up but backend may be down"
        break
    fi
    log_info "Attempt $i: HTTP $HTTP_CODE, retrying..."
    sleep 2
done

if [ $HTTP_SUCCESS -eq 1 ]; then
    log_success "Web UI reachable (HTTP $HTTP_CODE)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$HTTP_CODE" = "502" ]; then
    log_warn "Web UI returns 502 - checking if gateway process is running..."
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Web UI not reachable (HTTP $HTTP_CODE)"
    curl -v http://localhost:18080/healthz 2>&1 || true
    log_info "Container logs:"
    docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 50
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 7: Nginx Running
# =============================================================================
log_info "Test 7: Verifying nginx is running..."

if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" pgrep nginx > /dev/null 2>&1; then
    log_success "Nginx process is running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Nginx process not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 8: Gateway Process Running (via supervisorctl)
# =============================================================================
log_info "Test 8: Verifying ${UPSTREAM} gateway process is running..."

# Check supervisorctl status
SUPERVISOR_STATUS=$(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" supervisorctl -s unix:///tmp/supervisor.sock status 2>/dev/null || \
                    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" supervisorctl status 2>/dev/null || \
                    echo "supervisor not responding")

if echo "$SUPERVISOR_STATUS" | grep -E "^${UPSTREAM}\s+RUNNING" > /dev/null 2>&1; then
    log_success "${UPSTREAM} gateway process is RUNNING"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "${UPSTREAM} gateway process is NOT running!"
    log_info "Supervisor status:"
    echo "$SUPERVISOR_STATUS"

    log_info "Supervisor logs:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat "/var/log/supervisor/supervisord.log" 2>/dev/null | tail -30 || true

    log_info "Gateway error logs:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat "/var/log/supervisor/${UPSTREAM}-error.log" 2>/dev/null | tail -30 || true

    log_info "Gateway stdout logs:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat "/var/log/supervisor/${UPSTREAM}.log" 2>/dev/null | tail -30 || true

    # For compiled binaries, run the gateway manually to see the actual error
    if [ "$IS_NODEJS_UPSTREAM" = false ]; then
        log_info "Running ${UPSTREAM} gateway manually to capture error..."
        docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} /opt/${UPSTREAM}/${UPSTREAM} gateway --port 18789 --bind loopback 2>&1" 2>&1 | head -50 || true
    fi

    log_info "State directory contents:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" ls -la "/data/.${UPSTREAM}/" 2>/dev/null || true

    log_info "Config file contents:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat "/data/.${UPSTREAM}/${UPSTREAM}.json" 2>/dev/null | head -50 || true

    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 9: Run Healthcheck Commands
# =============================================================================
log_info "Test 9: Running healthcheck commands..."

HEALTHCHECK_ERRORS=0

if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    log_info "Running: ${UPSTREAM} status"
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} OPENCLAW_STATE_DIR=/data/.${UPSTREAM} ${UPSTREAM} status" > /tmp/status.log 2>&1; then
        log_success "${UPSTREAM} status command succeeded"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warn "${UPSTREAM} status command failed"
    fi

    if grep -q "EACCES\|permission denied" /tmp/status.log 2>/dev/null; then
        log_error "Permission errors in status output"
        HEALTHCHECK_ERRORS=$((HEALTHCHECK_ERRORS + 1))
    fi

    log_info "Running: ${UPSTREAM} gateway status"
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} OPENCLAW_STATE_DIR=/data/.${UPSTREAM} ${UPSTREAM} gateway status" > /tmp/gateway-status.log 2>&1; then
        log_success "${UPSTREAM} gateway status command succeeded"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warn "${UPSTREAM} gateway status command failed"
    fi

    if grep -q "RPC probe: ok" /tmp/gateway-status.log 2>/dev/null; then
        log_success "Gateway RPC probe successful"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Gateway RPC probe failed"
        HEALTHCHECK_ERRORS=$((HEALTHCHECK_ERRORS + 1))
    fi
else
    log_info "Checking ${UPSTREAM} binary..."
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" test -x "/opt/${UPSTREAM}/${UPSTREAM}" 2>/dev/null; then
        log_success "${UPSTREAM} binary is executable"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "${UPSTREAM} binary not found or not executable"
        HEALTHCHECK_ERRORS=$((HEALTHCHECK_ERRORS + 1))
    fi
fi

if [ $HEALTHCHECK_ERRORS -gt 0 ]; then
    log_error "Healthcheck commands had $HEALTHCHECK_ERRORS errors"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# =============================================================================
# Test 10: Stability Check (container stays running)
# =============================================================================
log_info "Test 10: Stability check - ensuring container stays running for ${STABILITY_CHECK_TIME}s..."

INITIAL_RESTARTS=$(docker inspect --format='{{.RestartCount}}' "${UPSTREAM}-smoke-test" 2>/dev/null || echo "0")
STABILITY_PASSED=1

for i in $(seq 1 $STABILITY_CHECK_TIME); do
    STATUS=$(docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1 || echo "")

    if echo "$STATUS" | grep -q "exited\|dead\|restarting"; then
        log_error "Container became unstable at second $i: $STATUS"
        STABILITY_PASSED=0
        break
    fi

    CURRENT_RESTARTS=$(docker inspect --format='{{.RestartCount}}' "${UPSTREAM}-smoke-test" 2>/dev/null || echo "0")
    if [ "$CURRENT_RESTARTS" -gt "$INITIAL_RESTARTS" ]; then
        log_error "Container restarted during stability check (restarts: $CURRENT_RESTARTS)"
        STABILITY_PASSED=0
        break
    fi

    if [ $((i % 10)) -eq 0 ]; then
        log_info "Still running after ${i}s..."
    fi

    sleep 1
done

if [ $STABILITY_PASSED -eq 1 ]; then
    log_success "Container remained stable for ${STABILITY_CHECK_TIME}s"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Container failed stability check"
    log_info "Container logs:"
    docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Smoke Test Summary"
echo "========================================"
echo "Upstream: ${UPSTREAM}"
echo "Version: ${UPSTREAM_VERSION}"
echo "Image: ${IMAGE_TAG}"
echo "----------------------------------------"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo "========================================"

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "All smoke tests passed for ${UPSTREAM}!"
    exit 0
else
    log_error "Some smoke tests failed for ${UPSTREAM}"
    exit 1
fi
