#!/bin/bash
# Test cancellation script functionality
# Verifies that the script is created correctly and works as expected

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  Cancellation Script Test"
echo "========================================"
echo ""

# Set fake CI environment
export GITHUB_ACTIONS="true"
export GITHUB_RUN_ID="test-12345"
export GITHUB_REPOSITORY="test/repo"
export GITHUB_TOKEN="fake-token-for-testing"

log "Creating cancellation script..."
cd "$PROJECT_ROOT"

# Run the creation script
if ./scripts/create_cancel_script.sh; then
    log "Script creation succeeded"
else
    error "Script creation failed"
    exit 1
fi

# Verify script exists
CANCEL_SCRIPT="$HOME/cancel_pipeline.sh"
if [[ ! -f "$CANCEL_SCRIPT" ]]; then
    error "Cancellation script not created at $CANCEL_SCRIPT"
    exit 1
fi

log "Script exists at: $CANCEL_SCRIPT"

# Verify script is executable
if [[ -x "$CANCEL_SCRIPT" ]]; then
    log "Script is executable"
else
    error "Script is not executable"
    exit 1
fi

# Check script contains expected variables
log "Verifying script contents..."

if grep -q "GITHUB_RUN_ID=\"test-12345\"" "$CANCEL_SCRIPT"; then
    log "GitHub run ID embedded correctly"
else
    error "GitHub run ID not found in script"
    cat "$CANCEL_SCRIPT"
    exit 1
fi

if grep -q "GITHUB_REPOSITORY=\"test/repo\"" "$CANCEL_SCRIPT"; then
    log "GitHub repository embedded correctly"
else
    error "GitHub repository not found in script"
    exit 1
fi

# Test script execution (with fake gh command)
log "Testing script execution..."

# Create fake gh command
mkdir -p /tmp/fake_bin
cat > /tmp/fake_bin/gh << 'EOF'
#!/bin/bash
echo "Fake gh command called with: $@" >> /tmp/gh_test.log
echo "Would cancel run: $3 for repo: $5"
exit 0
EOF
chmod +x /tmp/fake_bin/gh

# Run script with fake gh in PATH
export PATH="/tmp/fake_bin:$PATH"

if bash "$CANCEL_SCRIPT" "Test violation"; then
    log "Script executed successfully"
else
    error "Script execution failed"
    exit 1
fi

# Verify gh was called
if [[ -f /tmp/gh_test.log ]]; then
    log "Fake gh command was invoked:"
    cat /tmp/gh_test.log
else
    error "gh command was not called"
    exit 1
fi

# Verify log file was created
LOGFILE="$HOME/cancel_pipeline_test-12345.log"
if [[ -f "$LOGFILE" ]]; then
    log "Log file created at: $LOGFILE"
    log "Log contents:"
    cat "$LOGFILE"
else
    error "Log file not created"
    exit 1
fi

# Cleanup
rm -f "$CANCEL_SCRIPT" "$LOGFILE" /tmp/gh_test.log
rm -rf /tmp/fake_bin

echo ""
echo "========================================"
echo "  TEST PASSED"
echo "========================================"
exit 0

