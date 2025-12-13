#!/bin/bash
# Master test runner for Flodviddar
# Runs all integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    local warnings=0
    
    # Check if binary exists (from CI build or previous local build)
    if [[ -f "$SCRIPT_DIR/../target/release/flodviddar" ]]; then
        log_info "Flodviddar binary found (cargo not required)"
    elif ! command -v cargo &> /dev/null; then
        log_error "cargo not found and no pre-built binary available"
        missing=1
    else
        log_info "cargo available for building"
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found"
        missing=1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq not found (install: sudo apt-get install jq)"
        missing=1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_error "bc not found (install: sudo apt-get install bc)"
        missing=1
    fi
    
    if [[ "$missing" -eq 1 ]]; then
        log_error "Missing prerequisites. Install them and try again."
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Run a single test
run_test() {
    local test_name=$1
    local test_script=$2
    
    log_test "Running: $test_name"
    echo "----------------------------------------"
    
    if bash "$test_script"; then
        log_info "$test_name: PASSED"
        return 0
    else
        log_error "$test_name: FAILED"
        return 1
    fi
}

main() {
    echo "========================================"
    echo "  Flodviddar Test Suite"
    echo "========================================"
    echo "Target: Ubuntu Latest"
    echo "Mode: Integration Tests"
    echo "========================================"
    echo ""
    
    check_prerequisites
    
    local failed=0
    local passed=0
    
    # Test 1: Whitelist Lifecycle
    if run_test "Whitelist Lifecycle" "$SCRIPT_DIR/test_whitelist_lifecycle.sh"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    echo ""
    echo "========================================"
    
    # Test 2: CVE-2025-30066 Detection
    if run_test "CVE-2025-30066 Detection" "$SCRIPT_DIR/test_cve_2025_30066.sh"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    echo ""
    echo "========================================"
    
    # Test 3: Watch Daemon
    if run_test "Watch Daemon" "$SCRIPT_DIR/test_watch_daemon.sh"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    # Summary
    echo ""
    echo "========================================"
    echo "  TEST SUMMARY"
    echo "========================================"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo "Total:  $((passed + failed))"
    echo "========================================"
    echo ""
    
    if [[ "$failed" -gt 0 ]]; then
        log_error "Some tests failed"
        exit 1
    else
        log_info "All tests passed!"
        exit 0
    fi
}

main "$@"

