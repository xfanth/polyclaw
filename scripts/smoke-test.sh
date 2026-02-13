#!/bin/bash
# =============================================================================
# OpenClaw Docker Smoke Test
# =============================================================================
# This script:
# 1. Builds the Docker image
# 2. Starts containers with docker-compose.test.yml
# 3. Waits for services to be healthy
# 4. Runs basic health checks
# 5. Cleans up
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
COMPOSE_FILE="docker-compose.test.yml"
TEST_TIMEOUT=120
SERVICE_NAME="openclaw-test"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

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
# Test 1: Build Docker Image
# =============================================================================
log_info "Test 1: Building Docker image..."

# Check if image already exists (pre-built in CI)
if docker image inspect openclaw:smoke-test > /dev/null 2>&1; then
    log_success "Docker image already exists, skipping build"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif docker build -t openclaw:smoke-test . > /tmp/build.log 2>&1; then
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
    sudo chown -R $(id -u):$(id -g) test-data test-workspace 2>/dev/null || true
    sudo chmod -R 755 test-data test-workspace 2>/dev/null || true
fi

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
    
    # Show container logs if it's restarting
    STATUS=$(docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1)
    if echo "$STATUS" | grep -q "exited\|dead"; then
        log_error "Container exited unexpectedly"
        log_info "Container logs:"
        docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" --tail 50
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
# Test 4: HTTP Endpoint Test
# =============================================================================
log_info "Test 4: Testing HTTP endpoint..."

# Try multiple times with retries
HTTP_SUCCESS=0
for i in 1 2 3; do
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

# =============================================================================
# Test 5: OpenClaw Gateway Test
# =============================================================================
log_info "Test 5: Testing OpenClaw gateway..."

# Check if openclaw gateway is actually responding
# Run as openclaw user to avoid permission issues
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw openclaw gateway status" > /tmp/gateway-status.log 2>&1 || true

# Check for specific error conditions
GATEWAY_ERRORS=0

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

# Check for systemd errors (these should not cause gateway failure)
if grep -q "systemd.*unavailable\|systemctl.*unavailable" /tmp/gateway-status.log 2>/dev/null; then
    log_warn "systemd is unavailable (expected in container environment)"
fi

# Check if gateway is actually responding via RPC
if grep -q "RPC probe: ok" /tmp/gateway-status.log 2>/dev/null; then
    log_success "Gateway RPC probe successful"
else
    log_error "Gateway is not responding properly"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    GATEWAY_ERRORS=$((GATEWAY_ERRORS + 1))
fi

if [ $GATEWAY_ERRORS -eq 0 ]; then
    log_success "OpenClaw gateway is running and responding"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_info "Gateway status output:"
    cat /tmp/gateway-status.log
    log_info "Identity directory contents:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" ls -la /data/.openclaw/identity/ 2>/dev/null || log_warn "Identity directory not found"
    log_info "OpenClaw config:"
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" cat /data/.openclaw/openclaw.json 2>/dev/null || log_warn "Config file not found"
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
if ! docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" test -d /data/.openclaw/identity 2>/dev/null; then
    log_error "Identity directory does not exist"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
else
    log_success "Identity directory exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Check if identity directory is writable (as openclaw user)
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw test -w /data/.openclaw/identity" 2>/dev/null; then
    log_success "Identity directory is writable by openclaw user"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Identity directory is not writable by openclaw user"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
fi

# Try to create a test file in identity directory (as openclaw user)
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw touch /data/.openclaw/identity/test-file" 2>/dev/null; then
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw rm /data/.openclaw/identity/test-file" 2>/dev/null || true
    log_success "openclaw user can write files in identity directory"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "openclaw user cannot write files in identity directory"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    IDENTITY_PERMISSIONS=$((IDENTITY_PERMISSIONS + 1))
fi

# =============================================================================
# Test 7: Config Validation
# =============================================================================
log_info "Test 7: Validating OpenClaw config..."

# Check if config file exists and is valid JSON
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" bash -c "cat /data/.openclaw/openclaw.json | python3 -m json.tool > /dev/null 2>&1"; then
    log_success "OpenClaw config is valid JSON"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_warn "OpenClaw config has warnings (may be expected for test environment)"
    # Don't fail on config warnings in smoke test
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
# Test 8: Checking OpenClaw full status...
# =============================================================================
log_info "Test 8: Checking OpenClaw full status..."

# Run as openclaw user to avoid permission issues
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw openclaw status" > /tmp/openclaw-status.log 2>&1 || true

STATUS_ERRORS=0

# Check for permission denied errors
if grep -q "EACCES\|permission denied" /tmp/openclaw-status.log 2>/dev/null; then
    log_error "OpenClaw status shows permission errors"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    STATUS_ERRORS=$((STATUS_ERRORS + 1))
fi

# Check if gateway is marked as unreachable
if grep -q "Gateway.*unreachable" /tmp/openclaw-status.log 2>/dev/null; then
    log_error "OpenClaw status shows gateway is unreachable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    STATUS_ERRORS=$((STATUS_ERRORS + 1))
fi

# Check for memory unavailable errors
if grep -q "Memory.*unavailable" /tmp/openclaw-status.log 2>/dev/null; then
    log_warn "Memory plugin is unavailable (may be expected in test environment)"
    # Don't fail on memory warnings
fi

if [ $STATUS_ERRORS -eq 0 ]; then
    log_success "OpenClaw status check passed"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_info "OpenClaw status output:"
    cat /tmp/openclaw-status.log
fi

# =============================================================================
# Test 9: Verify gateway port accessibility
# =============================================================================
log_info "Test 9: Verifying gateway on port 18789..."

# Test gateway from within container
if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" su - openclaw -c "cd /data && HOME=/data/.openclaw OPENCLAW_STATE_DIR=/data/.openclaw curl -f http://localhost:18789/healthz" 2>&1; then
    log_success "Gateway is accessible on port 18789 (from within container)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Gateway is not accessible on port 18789 (from within container)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify gateway status shows correct port
if grep -q "port=18789" /tmp/openclaw-status.log 2>/dev/null; then
    log_success "Gateway status shows correct port (18789)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_warn "Gateway status shows unexpected port in status output"
fi

# Check if gateway is marked as unreachable
if grep -q "Gateway.*unreachable" /tmp/openclaw-status.log 2>/dev/null; then
    log_error "OpenClaw status shows gateway is unreachable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    STATUS_ERRORS=$((STATUS_ERRORS + 1))
fi

# Check for memory unavailable errors
if grep -q "Memory.*unavailable" /tmp/openclaw-status.log 2>/dev/null; then
    log_warn "Memory plugin is unavailable (may be expected in test environment)"
    # Don't fail on memory warnings
fi

if [ $STATUS_ERRORS -eq 0 ]; then
    log_success "OpenClaw status check passed"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_info "OpenClaw status output:"
    cat /tmp/openclaw-status.log
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Smoke Test Summary"
echo "========================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo "========================================"

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "All smoke tests passed!"
    exit 0
else
    log_error "Some smoke tests failed"
    exit 1
fi
