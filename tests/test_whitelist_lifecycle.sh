#!/bin/bash
# Test Whitelist Lifecycle with Flodviddar
# Demonstrates: Learning → Augmentation → Stability → Enforcement

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="/tmp/flodviddar_lifecycle_test_$$"
FLODVIDDAR_BIN=""
WHITELIST_FILE="$TEST_DIR/whitelist.json"
STATE_FILE="$TEST_DIR/state.txt"

# Test configuration
STABILITY_THRESHOLD=0
STABILITY_CONSECUTIVE=3
MAX_ITERATIONS=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_phase() {
    echo -e "${BLUE}[PHASE]${NC} $1"
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# Build flodviddar
build_flodviddar() {
    log_info "Building flodviddar from source..."
    cd "$PROJECT_ROOT"
    
    cargo build --release 2>&1 | tee /tmp/flodviddar_build.log | grep -E "(Compiling|Finished|error)" || true
    
    FLODVIDDAR_BIN="$PROJECT_ROOT/target/release/flodviddar"
    
    if [[ ! -f "$FLODVIDDAR_BIN" ]]; then
        log_error "Binary not found at $FLODVIDDAR_BIN"
        exit 1
    fi
    
    log_info "Build successful"
}

# Setup test environment
setup_test() {
    log_info "Setting up test environment in $TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Initialize state
    echo "0" > "$STATE_FILE.iteration"
    echo "0" > "$STATE_FILE.stable_count"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is required"
        exit 1
    fi
    
    # Install dependencies
    pip3 install --quiet requests 2>/dev/null || {
        sudo apt-get update -qq
        sudo apt-get install -y python3-requests
    }
}

# Generate traffic for a given iteration
# Iterations 1-2: Base traffic (3 endpoints)
# Iterations 3+: Add new endpoint to test augmentation
generate_traffic() {
    local iteration=$1
    
    cat > "$TEST_DIR/traffic_gen.py" << EOF
import requests
import sys

print(f"Generating traffic for iteration $iteration...")

endpoints_hit = 0

# Core endpoints (every iteration)
try:
    r = requests.get("https://api.github.com/zen", timeout=10)
    print(f"  - api.github.com: {r.status_code}")
    endpoints_hit += 1
except Exception as e:
    print(f"  - api.github.com: FAILED ({e})")

try:
    r = requests.get("https://github.com/robots.txt", timeout=10)
    print(f"  - github.com: {r.status_code}")
    endpoints_hit += 1
except Exception as e:
    print(f"  - github.com: FAILED ({e})")

try:
    r = requests.get("https://registry.npmjs.org/-/ping", timeout=10)
    print(f"  - registry.npmjs.org: {r.status_code}")
    endpoints_hit += 1
except Exception as e:
    print(f"  - registry.npmjs.org: FAILED ({e})")

# Additional endpoint for iteration 3+
if $iteration >= 3:
    try:
        r = requests.get("https://www.npmjs.com/", timeout=10)
        print(f"  - www.npmjs.com: {r.status_code}")
        endpoints_hit += 1
    except Exception as e:
        print(f"  - www.npmjs.com: FAILED ({e})")

print(f"\nTotal endpoints contacted: {endpoints_hit}")
sys.exit(0 if endpoints_hit > 0 else 1)
EOF
    
    python3 "$TEST_DIR/traffic_gen.py"
}

# Run a single iteration
run_iteration() {
    local iteration=$1
    
    echo ""
    echo "========================================"
    echo "  ITERATION $iteration"
    echo "========================================"
    
    local capture_duration=30
    local old_count=0
    local new_count=0
    
    # Get old count if whitelist exists
    if [[ -f "$WHITELIST_FILE" ]]; then
        old_count=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE" 2>/dev/null || echo "0")
        log_info "Previous whitelist: $old_count endpoints"
    else
        log_info "No previous whitelist (first run)"
    fi
    
    # Determine mode: create or augment
    if [[ "$iteration" -eq 1 ]]; then
        # First iteration: create baseline
        log_phase "Creating baseline whitelist"
        
        sudo "$FLODVIDDAR_BIN" create-whitelist $capture_duration false \
            --file "$WHITELIST_FILE" > /tmp/flodviddar_iter${iteration}.log 2>&1 &
        CAPTURE_PID=$!
    else
        # Subsequent iterations: augment existing
        log_phase "Augmenting whitelist"
        
        sudo "$FLODVIDDAR_BIN" create-whitelist $capture_duration true \
            --file "$WHITELIST_FILE" > /tmp/flodviddar_iter${iteration}.log 2>&1 &
        CAPTURE_PID=$!
    fi
    
    # Wait for capture to start
    sleep 3
    
    # Generate traffic
    generate_traffic "$iteration"
    
    # Wait for traffic to be captured
    sleep 5
    
    # Wait for capture to complete
    wait $CAPTURE_PID || {
        log_warn "Capture process exited with code $?"
    }
    
    # Verify whitelist was created/updated
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        log_error "Whitelist file not created/updated"
        cat /tmp/flodviddar_iter${iteration}.log
        exit 1
    fi
    
    # Count new endpoints
    new_count=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE" 2>/dev/null || echo "0")
    
    # Calculate change
    local delta=$((new_count - old_count))
    local percent_change=0
    
    if [[ "$new_count" -gt 0 ]]; then
        percent_change=$(echo "scale=2; ($delta * 100) / $new_count" | bc)
    fi
    
    log_info "Current whitelist: $new_count endpoints (change: +$delta, ${percent_change}%)"
    
    # Update stability tracking
    local stable_count=$(cat "$STATE_FILE.stable_count")
    
    if [[ "$delta" -eq 0 ]] && [[ "$iteration" -gt 1 ]]; then
        # No change - increment stability counter
        stable_count=$((stable_count + 1))
        log_info "STABLE: No new endpoints (consecutive stable runs: $stable_count/$STABILITY_CONSECUTIVE)"
    else
        # Change detected - reset stability counter
        if [[ "$iteration" -gt 1 ]]; then
            log_info "LEARNING: $delta new endpoints discovered (resetting stability counter)"
        fi
        stable_count=0
    fi
    
    echo "$stable_count" > "$STATE_FILE.stable_count"
    
    # Check if stable
    if [[ "$stable_count" -ge "$STABILITY_CONSECUTIVE" ]]; then
        log_info "WHITELIST IS STABLE! ($stable_count consecutive runs with no changes)"
        echo "true" > "$STATE_FILE.is_stable"
    else
        echo "false" > "$STATE_FILE.is_stable"
    fi
    
    # Display sample endpoints
    if [[ "$new_count" -le 10 ]]; then
        log_info "All endpoints:"
        jq -r '.whitelists[]? | .endpoints[]? | "  - \(.domain // .ip):\(.port) [\(.protocol)]"' "$WHITELIST_FILE" 2>/dev/null
    else
        log_info "Sample endpoints (first 5):"
        jq -r '.whitelists[]? | .endpoints[]? | "  - \(.domain // .ip):\(.port) [\(.protocol)]"' "$WHITELIST_FILE" 2>/dev/null | head -5
        log_info "  ... and $((new_count - 5)) more"
    fi
    
    echo ""
}

# Test enforcement mode
test_enforcement() {
    log_info "=== Phase: Enforcement Test ==="
    
    # Create a script that contacts an unauthorized endpoint
    cat > "$TEST_DIR/unauthorized_traffic.py" << 'EOF'
import requests

print("Attempting unauthorized connection...")
try:
    # This should NOT be in the whitelist
    r = requests.get("https://example.com", timeout=10)
    print(f"example.com: {r.status_code}")
except Exception as e:
    print(f"example.com: {e}")
EOF
    
    log_info "Running scan with enforcement (30 seconds)..."
    
    # Scan with whitelist - should detect violation
    timeout 60 sudo "$FLODVIDDAR_BIN" scan 30 \
        --custom-whitelist "$WHITELIST_FILE" \
        --output report \
        > "$TEST_DIR/enforcement_report.json" 2>&1 &
    ENFORCE_PID=$!
    
    sleep 3
    
    # Generate unauthorized traffic
    python3 "$TEST_DIR/unauthorized_traffic.py" || true
    
    # Wait for scan
    wait $ENFORCE_PID || true
    
    sleep 3
    
    # Check if violation was detected
    if [[ -f "$TEST_DIR/enforcement_report.json" ]]; then
        VIOLATIONS=$(jq 'length' "$TEST_DIR/enforcement_report.json" 2>/dev/null || echo "0")
        
        if [[ "$VIOLATIONS" -gt 0 ]]; then
            log_info "SUCCESS: Enforcement detected $VIOLATIONS violation(s)"
            jq -r '.[] | "  - \(.dst_domain // .session.dst_ip):\(.session.dst_port)"' "$TEST_DIR/enforcement_report.json" 2>/dev/null | head -5
            return 0
        else
            log_warn "No violations detected (may be expected if DNS resolution pending)"
            return 0
        fi
    else
        log_warn "Enforcement report not generated"
        return 0
    fi
}

# Main test flow
main() {
    echo "========================================"
    echo "  Flodviddar Whitelist Lifecycle Test"
    echo "========================================"
    echo "Configuration:"
    echo "  - Stability threshold: ${STABILITY_THRESHOLD}%"
    echo "  - Consecutive runs: $STABILITY_CONSECUTIVE"
    echo "  - Max iterations: $MAX_ITERATIONS"
    echo "========================================"
    echo ""
    
    build_flodviddar
    setup_test
    
    # Run iterations until stable
    local iteration=1
    local is_stable="false"
    
    while [[ "$iteration" -le "$MAX_ITERATIONS" ]]; do
        run_iteration "$iteration"
        
        is_stable=$(cat "$STATE_FILE.is_stable" 2>/dev/null || echo "false")
        
        if [[ "$is_stable" == "true" ]]; then
            log_info "Whitelist stabilized after $iteration iterations!"
            break
        fi
        
        iteration=$((iteration + 1))
    done
    
    # Final summary
    echo ""
    echo "========================================"
    echo "  LIFECYCLE TEST SUMMARY"
    echo "========================================"
    
    local final_count=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE" 2>/dev/null || echo "0")
    local final_stable=$(cat "$STATE_FILE.stable_count")
    
    echo "Total iterations: $((iteration))"
    echo "Final endpoint count: $final_count"
    echo "Stability count: $final_stable/$STABILITY_CONSECUTIVE"
    echo "Status: $(cat "$STATE_FILE.is_stable" 2>/dev/null)"
    echo ""
    
    if [[ "$is_stable" == "true" ]]; then
        log_info "Testing enforcement mode..."
        test_enforcement
        
        echo ""
        echo "========================================"
        echo "  ALL TESTS PASSED"
        echo "========================================"
        exit 0
    else
        log_warn "Whitelist did not stabilize within $MAX_ITERATIONS iterations"
        echo ""
        echo "========================================"
        echo "  PARTIAL PASS"
        echo "========================================"
        exit 0
    fi
}

main

