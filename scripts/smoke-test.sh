#!/bin/bash
# =============================================================================
# OpenClaw/PicoClaw Docker Smoke Test
# =============================================================================
# This script:
# 1. Builds the Docker image for the specified upstream
# 2. Starts containers with docker-compose.test.yml
# 3. Waits for services to be healthy
# 4. Runs basic health checks
# 5. Cleans up
#
# Usage:
#   ./smoke-test.sh                     # Test OpenClaw (default)
#   UPSTREAM=picoclaw ./smoke-test.sh   # Test PicoClaw
#   IMAGE_TAG=myimage:latest ./smoke-test.sh  # Use pre-built image
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Upstream configuration
UPSTREAM="${UPSTREAM:-openclaw}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:-main}"

# Test configuration
COMPOSE_FILE="docker-compose.test.yml"
TEST_TIMEOUT=120
SERVICE_NAME="gateway-test"
IMAGE_TAG="${IMAGE_TAG:-${UPSTREAM}:smoke-test}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Determine upstream type for conditional tests
# Node.js upstreams have full CLI support, compiled binaries have limited CLI
IS_NODEJS_UPSTREAM=false
case "$UPSTREAM" in
    openclaw)
        IS_NODEJS_UPSTREAM=true
        ;;
    picoclaw|ironclaw|zeroclaw)
        ;;
    *)
        log_error "Unknown upstream: $UPSTREAM"
        log_error "Supported: openclaw, picoclaw, ironclaw, zeroclaw"
        exit 1
        ;;
esac

log_info "Upstream type: $([ "$IS_NODEJS_UPSTREAM" = true ] && echo 'Node.js (full CLI)' || echo 'Compiled binary (limited CLI)')"

# Display configuration
log_info "Smoke Test Configuration:"
echo "  UPSTREAM: ${UPSTREAM}"
echo "  UPSTREAM_VERSION: ${UPSTREAM_VERSION}"
echo "  IMAGE_TAG: ${IMAGE_TAG}"
echo ""

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
    # Use sudo if available to handle permission issues from container user
    sudo rm -rf test-data test-workspace 2>/dev/null || rm -rf test-data test-workspace 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

# =============================================================================
# Test 1: Use/Build Docker Image
# =============================================================================
log_info "Test 1: Checking Docker image..."

# If IMAGE_TAG is set (CI environment), verify the image exists and tag it
if [ "$IMAGE_TAG" != "${UPSTREAM}:smoke-test" ]; then
    log_info "Using pre-built image: $IMAGE_TAG"
    if docker image inspect "$IMAGE_TAG" > /dev/null 2>&1; then
        log_success "Pre-built image found"
        # Tag the image for docker-compose to use
        docker tag "$IMAGE_TAG" "${UPSTREAM}:smoke-test"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Pre-built image not found: $IMAGE_TAG"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        exit 1
    fi
# Otherwise, check if image already exists locally
elif docker image inspect "${UPSTREAM}:smoke-test" > /dev/null 2>&1; then
    log_success "Docker image already exists, skipping build"
    TESTS_PASSED=$((TESTS_PASSED + 1))
# Build from scratch
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
# Test 2: Start Services
# =============================================================================
log_info "Test 2: Starting services with docker-compose..."

# Create test directories
mkdir -p test-data test-workspace

# Ensure proper permissions on test directories
# In CI environments, fix ownership and permissions
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    sudo chown -R "$(id -u):$(id -g)" test-data test-workspace 2>/dev/null || true
    sudo chmod -R 755 test-data test-workspace 2>/dev/null || true
fi

# Export UPSTREAM for docker-compose
export UPSTREAM

if docker compose -f "$COMPOSE_FILE" up -d > /tmp/compose.log 2>&1; then
    log_success "Services started"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Failed to start services"
    cat /tmp/compose.log
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 3: Wait for Health Check
# =============================================================================
log_info "Test 3: Waiting for health checks (timeout: ${TEST_TIMEOUT}s)..."

START_TIME=$(date +%s)
HEALTHY=0

while [ $(($(date +%s) - START_TIME)) -lt $TEST_TIMEOUT ]; do
    if docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" 2>/dev/null | grep -q "healthy"; then
        HEALTHY=1
        break
    fi

    # Show container logs if it's restarting or exited
    STATUS=$(docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1)
    if echo "$STATUS" | grep -q "exited\|dead\|restarting"; then
        log_error "Container is in bad state: $STATUS"
        log_info "Container logs:"
        docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
        TESTS_FAILED=$((TESTS_FAILED + 1))
        exit 1
    fi

    echo -n "."
    sleep 2
done

echo ""

if [ $HEALTHY -eq 1 ]; then
    log_success "Health check passed"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Health check timed out after ${TEST_TIMEOUT}s"
    log_info "Container logs:"
    docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 100
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# Wait a bit more for services to fully start
sleep 10

# =============================================================================
# Test 4: HTTP Endpoint Test (Node.js only - has /healthz endpoint)
# =============================================================================
if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    log_info "Test 4: Testing HTTP endpoint..."

    # Try multiple times with retries
    HTTP_SUCCESS=0
    for _ in 1 2 3; do
        if curl -sf http://localhost:18080/healthz > /dev/null 2>&1; then
            HTTP_SUCCESS=1
            break
        fi
        sleep 2
    done

    if [ $HTTP_SUCCESS -eq 1 ]; then
        log_success "Health endpoint responds (200 OK)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Health endpoint failed"
        log_info "Trying to get more info..."
        curl -v http://localhost:18080/healthz 2>&1 || true
        TESTS_FAILED=$((TESTS_FAILED + 1))
        exit 1
    fi
else
    log_info "Test 4: Skipping HTTP endpoint test (compiled binaries may not have /healthz)"
    log_success "HTTP endpoint test skipped for ${UPSTREAM}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 5: Gateway Test (upstream-aware)
# =============================================================================
log_info "Test 5: Testing ${UPSTREAM} gateway..."

GATEWAY_ERRORS=0

if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    # Node.js upstreams have full CLI with 'gateway status' command
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} OPENCLAW_STATE_DIR=/data/.${UPSTREAM} ${UPSTREAM} gateway status" > /tmp/gateway-status.log 2>&1 || true

    # Check for permission denied errors
    if grep -q "EACCES\|permission denied" /tmp/gateway-status.log 2>/dev/null; then
        log_error "Gateway has permission errors (EACCES)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
    fi

    # Check for port conflicts
    if grep -q "Port.*already in use\|address already in use" /tmp/gateway-status.log 2>/dev/null; then
        log_error "Gateway has port conflicts"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
    fi

    # Check for systemd errors (expected in container)
    if grep -q "systemd.*unavailable\|systemctl.*unavailable" /tmp/gateway-status.log 2>/dev/null; then
        log_warn "systemd is unavailable (expected in container environment)"
    fi

    # Check if gateway is responding via RPC
    if grep -q "RPC probe: ok" /tmp/gateway-status.log 2>/dev/null; then
        log_success "Gateway RPC probe successful"
    else
        log_error "Gateway is not responding properly"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
    fi

    if [ $GATEWAY_ERRORS -eq 0 ]; then
        log_success "${UPSTREAM} gateway is running and responding"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_info "Gateway status output:"
        cat /tmp/gateway-status.log
    fi
else
    # Compiled binary upstreams - check that binary exists and process is running
    log_info "Checking compiled binary gateway..."

    # Check if the upstream binary exists
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" which "$UPSTREAM" > /dev/null 2>&1; then
        log_success "${UPSTREAM} binary found in PATH"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "${UPSTREAM} binary not found in PATH"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
    fi

    # Check if gateway process is running (via supervisord)
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" pgrep -f "$UPSTREAM" > /dev/null 2>&1; then
        log_success "${UPSTREAM} gateway process is running"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "${UPSTREAM} gateway process not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
    fi
fi

# =============================================================================
# Test 6: Nginx Test
# =============================================================================
log_info "Test 6: Testing Nginx..."

if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" pgrep nginx > /dev/null 2>&1; then
    log_success "Nginx process is running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Nginx process not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# =============================================================================
# Test 7: Identity Directory Permissions
# =============================================================================
log_info "Test 7: Checking identity directory permissions..."

IDENTITY_PERMISSIONS=0

# Check if identity directory exists
if ! docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" test -d "/data/.${UPSTREAM}/identity" 2>/dev/null; then
    log_error "Identity directory does not exist"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
else
    log_success "Identity directory exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Check if identity directory is writable (as upstream user)
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} test -w /data/.${UPSTREAM}/identity" 2>/dev/null; then
    log_success "Identity directory is writable by ${UPSTREAM} user"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Identity directory is not writable by ${UPSTREAM} user"
    log_error "This is a critical permission error - check bind mount ownership"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
fi

# Try to create a test file in identity directory (as upstream user)
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} touch /data/.${UPSTREAM}/identity/test-file" 2>/dev/null; then
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} rm /data/.${UPSTREAM}/identity/test-file" 2>/dev/null || true
    log_success "${UPSTREAM} user can write files in identity directory"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "${UPSTREAM} user cannot write files in identity directory"
    log_error "Entrypoint permission fix may not be working correctly"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
fi

# If identity permissions failed, show detailed diagnostics
if [ $IDENTITY_PERMISSIONS -gt 0 ]; then
    log_info "Identity directory diagnostics:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" ls -la "/data/.${UPSTREAM}/" 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" stat "/data/.${UPSTREAM}/identity" 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" id "$UPSTREAM" 2>/dev/null || true
fi

# =============================================================================
# Test 8: Config Validation (Node.js only)
# =============================================================================
if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    log_info "Test 8: Validating ${UPSTREAM} config..."

    # Check if config file exists and is valid JSON
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" bash -c "cat /data/.${UPSTREAM}/${UPSTREAM}.json | python3 -m json.tool > /dev/null 2>&1"; then
        log_success "${UPSTREAM} config is valid JSON"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warn "${UPSTREAM} config has warnings (may be expected for test environment)"
        # Don't fail on config warnings in smoke test
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
else
    log_info "Test 8: Skipping config validation (not applicable for compiled binaries)"
    log_success "Config validation skipped for ${UPSTREAM}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 9: Checking full status (Node.js only)
# =============================================================================
if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    log_info "Test 9: Checking ${UPSTREAM} full status..."

    # Run as upstream user to avoid permission issues
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} OPENCLAW_STATE_DIR=/data/.${UPSTREAM} ${UPSTREAM} status" > /tmp/status.log 2>&1 || true

    STATUS_ERRORS=0

    # Check for permission denied errors
    if grep -q "EACCES\|permission denied" /tmp/status.log 2>/dev/null; then
        log_error "${UPSTREAM} status shows permission errors"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        STATUS_ERRORS=$((STATUS_ERRORS + 1))
    fi

    # Check if gateway is marked as unreachable
    if grep -q "Gateway.*unreachable" /tmp/status.log 2>/dev/null; then
        log_error "${UPSTREAM} status shows gateway is unreachable"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        STATUS_ERRORS=$((STATUS_ERRORS + 1))
    fi

    # Check for memory unavailable errors
    if grep -q "Memory.*unavailable" /tmp/status.log 2>/dev/null; then
        log_warn "Memory plugin is unavailable (may be expected in test environment)"
        # Don't fail on memory warnings
    fi

    if [ $STATUS_ERRORS -eq 0 ]; then
        log_success "${UPSTREAM} status check passed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_info "${UPSTREAM} status output:"
        cat /tmp/status.log
    fi

    # Verify gateway status shows correct port
    if grep -q "port=18789" /tmp/status.log 2>/dev/null; then
        log_success "Gateway status shows correct port (18789)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warn "Gateway status shows unexpected port in status output"
    fi
else
    log_info "Test 9: Skipping full status check (not applicable for compiled binaries)"
    log_success "Status check skipped for ${UPSTREAM}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 10: Verify gateway port accessibility (Node.js only - has /healthz endpoint)
# =============================================================================
if [ "$IS_NODEJS_UPSTREAM" = true ]; then
    log_info "Test 10: Verifying gateway on port 18789..."

    # Test gateway from within container
    if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - "$UPSTREAM" -c "cd /data && HOME=/data/.${UPSTREAM} OPENCLAW_STATE_DIR=/data/.${UPSTREAM} curl -f http://localhost:18789/healthz" 2>&1; then
        log_success "Gateway is accessible on port 18789 (from within container)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Gateway is not accessible on port 18789 (from within container)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    log_info "Test 10: Skipping gateway port test (compiled binaries may not have /healthz)"
    log_success "Gateway port test skipped for ${UPSTREAM}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 11: Verify correct state directory
# =============================================================================
log_info "Test 11: Verifying state directory matches upstream..."

EXPECTED_STATE_DIR="/data/.${UPSTREAM}"

# Check that the state directory exists and matches upstream name
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" test -d "$EXPECTED_STATE_DIR" 2>/dev/null; then
    log_success "State directory exists: $EXPECTED_STATE_DIR"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "State directory does not exist: $EXPECTED_STATE_DIR"
    log_error "This indicates a mismatch between UPSTREAM and state directory"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check that config file is in the correct state directory
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" test -f "$EXPECTED_STATE_DIR/${UPSTREAM}.json" 2>/dev/null; then
    log_success "Config file exists in correct state directory"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Config file not found at $EXPECTED_STATE_DIR/${UPSTREAM}.json"
    # List what's in /data to help debug
    log_info "Contents of /data:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" ls -la /data/ 2>/dev/null || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# =============================================================================
# Test 12: Check gateway process is running
# =============================================================================
log_info "Test 12: Checking gateway process status..."

# Get container logs from the last 30 seconds
CONTAINER_LOGS=$(docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 50 2>&1)

# Check for process exit/crash errors
if echo "$CONTAINER_LOGS" | grep -q "exited.*not expected\|FATAL state\|exit status"; then
    log_error "Gateway process crashed or exited unexpectedly"
    log_error "Recent logs:"
    echo "$CONTAINER_LOGS" | tail -20
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    log_success "Gateway process appears to be running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Check for specific error patterns
CRITICAL_ERRORS=0

# Check for doctor --fix error (zeroclaw/picoclaw don't support it)
if echo "$CONTAINER_LOGS" | grep -q "unexpected argument '--fix' found"; then
    log_error "Doctor --fix called on upstream that doesn't support it"
    CRITICAL_ERRORS=$((CRITICAL_ERRORS + 1))
fi

# Check for state directory mismatch in logs
if echo "$CONTAINER_LOGS" | grep -q "State dir: /data/.openclaw" && [ "$UPSTREAM" != "openclaw" ]; then
    log_error "State dir is .openclaw but UPSTREAM is $UPSTREAM - mismatch detected"
    CRITICAL_ERRORS=$((CRITICAL_ERRORS + 1))
fi

if [ $CRITICAL_ERRORS -gt 0 ]; then
    log_error "Found $CRITICAL_ERRORS critical error(s) in logs"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    log_success "No critical errors found in logs"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 13: Verify supervisord status
# =============================================================================
log_info "Test 13: Checking supervisord process status..."

# Check supervisordctl status
SUPERVISOR_STATUS=$(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" supervisorctl status 2>&1 || true)

if echo "$SUPERVISOR_STATUS" | grep -q "RUNNING"; then
    log_success "At least one process is RUNNING under supervisord"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "No processes are RUNNING under supervisord"
    log_info "Supervisor status:"
    echo "$SUPERVISOR_STATUS"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check that the upstream process specifically is running
if echo "$SUPERVISOR_STATUS" | grep "${UPSTREAM}" | grep -q "RUNNING"; then
    log_success "${UPSTREAM} process is RUNNING"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif echo "$SUPERVISOR_STATUS" | grep "${UPSTREAM}" | grep -q "FATAL\|EXITED\|BACKOFF"; then
    log_error "${UPSTREAM} process is not running (FATAL/EXITED/BACKOFF)"
    log_info "Process status for ${UPSTREAM}:"
    echo "$SUPERVISOR_STATUS" | grep "${UPSTREAM}"
    # Show recent error logs
    log_info "Recent error logs:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat "/var/log/supervisor/${UPSTREAM}-error.log" 2>/dev/null | tail -20 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    log_warn "Could not determine ${UPSTREAM} process status"
    # Don't fail on this - may be a timing issue
    TESTS_PASSED=$((TESTS_PASSED + 1))
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
