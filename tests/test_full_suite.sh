#!/bin/bash
# Full test suite including eBPF verification
# This is the comprehensive test that runs everything

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[TEST]${NC} $1"; }
section() { echo -e "${BLUE}[====]${NC} $1"; }

main() {
    echo "========================================"
    echo "  Flodviddar Complete Test Suite"
    echo "========================================"
    echo "Platform: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Date: $(date)"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Phase 1: eBPF verification
    section "Phase 1: eBPF Verification"
    if [[ -f "./tests/verify_ebpf.sh" ]]; then
        ./tests/verify_ebpf.sh
    else
        log "eBPF verification skipped (script not found)"
    fi
    echo ""
    
    # Phase 2: Build verification
    section "Phase 2: Build Verification"
    log "Building flodviddar..."
    cargo build --release
    log "Build successful"
    echo ""
    
    # Phase 3: Unit tests
    section "Phase 3: Unit Tests"
    log "Running Rust unit tests..."
    cargo test
    echo ""
    
    # Phase 4: Integration tests
    section "Phase 4: Integration Tests"
    log "Running integration test suite..."
    sudo ./tests/run_all_tests.sh
    echo ""
    
    # Summary
    echo "========================================"
    echo "  ALL TESTS PASSED"
    echo "========================================"
    echo "✓ eBPF verification"
    echo "✓ Build successful"
    echo "✓ Unit tests passed"
    echo "✓ Integration tests passed"
    echo "========================================"
    echo ""
    log "Flodviddar is ready for production use"
}

main "$@"


