#!/bin/bash
# Automated Whitelist Lifecycle Demo
# Demonstrates how to implement auto-whitelist behavior with Flodviddar

set -e

# Configuration
WHITELIST_FILE="${WHITELIST_FILE:-whitelist.json}"
STATE_FILE="${STATE_FILE:-whitelist_state.json}"
CAPTURE_DURATION="${CAPTURE_DURATION:-60}"
THRESHOLD="${THRESHOLD:-0}"          # 0% change = fully stable
CONSECUTIVE="${CONSECUTIVE:-3}"      # 3 stable runs required
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[AUTO-WL]${NC} $1"; }
warn() { echo -e "${YELLOW}[AUTO-WL]${NC} $1"; }
error() { echo -e "${RED}[AUTO-WL]${NC} $1"; }

# Initialize state
init_state() {
    if [[ -f "$STATE_FILE" ]]; then
        ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE")
        STABLE_COUNT=$(jq -r '.stable_count // 0' "$STATE_FILE")
        IS_STABLE=$(jq -r '.is_stable // false' "$STATE_FILE")
        LAST_COUNT=$(jq -r '.endpoint_count // 0' "$STATE_FILE")
    else
        ITERATION=0
        STABLE_COUNT=0
        IS_STABLE="false"
        LAST_COUNT=0
    fi
    ITERATION=$((ITERATION + 1))
}

# Save state
save_state() {
    local current_count=$1
    cat > "$STATE_FILE" << EOF
{
  "iteration": $ITERATION,
  "stable_count": $STABLE_COUNT,
  "is_stable": $IS_STABLE,
  "endpoint_count": $current_count,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Check if flodviddar is available
check_flodviddar() {
    if ! command -v flodviddar &> /dev/null; then
        if [[ -f "./target/release/flodviddar" ]]; then
            export PATH="./target/release:$PATH"
        else
            error "Flodviddar not found. Build with: cargo build --release"
            exit 1
        fi
    fi
}

# Run one iteration
run_iteration() {
    echo ""
    echo "========================================"
    echo "  Iteration $ITERATION"
    echo "========================================"
    
    local old_count=$LAST_COUNT
    
    # Determine mode
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        log "Creating baseline whitelist..."
        sudo flodviddar create-whitelist $CAPTURE_DURATION false \
            --file "$WHITELIST_FILE" > /tmp/flodviddar_auto_wl.log 2>&1 &
    else
        log "Augmenting existing whitelist..."
        sudo flodviddar create-whitelist $CAPTURE_DURATION true \
            --file "$WHITELIST_FILE" > /tmp/flodviddar_auto_wl.log 2>&1 &
    fi
    
    local pid=$!
    
    # Generate test traffic (in real usage, this would be your build/test)
    sleep 5
    generate_test_traffic
    
    # Wait for capture
    wait $pid || warn "Capture exited with code $?"
    
    # Count endpoints
    local new_count=0
    if [[ -f "$WHITELIST_FILE" ]]; then
        new_count=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE")
    fi
    
    # Calculate change
    local delta=$((new_count - old_count))
    local percent=0
    
    if [[ "$new_count" -gt 0 ]]; then
        percent=$(echo "scale=2; ($delta * 100) / $new_count" | bc)
    fi
    
    log "Endpoints: $new_count (change: +$delta, ${percent}%)"
    
    # Update stability
    if [[ "$ITERATION" -gt 1 ]]; then
        if [[ $(echo "$percent <= $THRESHOLD" | bc -l) -eq 1 ]]; then
            STABLE_COUNT=$((STABLE_COUNT + 1))
            log "Stable run ($STABLE_COUNT/$CONSECUTIVE)"
            
            if [[ "$STABLE_COUNT" -ge "$CONSECUTIVE" ]]; then
                log "WHITELIST IS STABLE!"
                IS_STABLE="true"
            fi
        else
            warn "Not stable (${percent}% > ${THRESHOLD}%), resetting counter"
            STABLE_COUNT=0
            IS_STABLE="false"
        fi
    fi
    
    # Save state
    save_state "$new_count"
    LAST_COUNT=$new_count
    
    # Display status
    if [[ "$IS_STABLE" == "true" ]]; then
        echo "Status: ENFORCING (stable)"
    elif [[ "$STABLE_COUNT" -gt 0 ]]; then
        echo "Status: CONFIRMING ($STABLE_COUNT/$CONSECUTIVE)"
    else
        echo "Status: LEARNING"
    fi
}

# Generate test traffic (placeholder)
generate_test_traffic() {
    if command -v curl &> /dev/null; then
        curl -s https://api.github.com/zen > /dev/null 2>&1 || true
        curl -s https://github.com/robots.txt > /dev/null 2>&1 || true
        
        # Add more traffic after iteration 2
        if [[ "$ITERATION" -ge 3 ]]; then
            curl -s https://registry.npmjs.org/-/ping > /dev/null 2>&1 || true
        fi
    fi
}

# Test enforcement
test_enforcement() {
    log "=== Testing Enforcement Mode ==="
    
    # Try to access unauthorized endpoint
    log "Scanning with enforcement..."
    
    sudo flodviddar scan 20 \
        --custom-whitelist "$WHITELIST_FILE" \
        --output report \
        > enforcement_report.json 2>&1 &
    
    local pid=$!
    sleep 3
    
    # Generate unauthorized traffic
    if command -v curl &> /dev/null; then
        curl -s https://example.com > /dev/null 2>&1 || true
    fi
    
    wait $pid || true
    
    # Check for violations
    if [[ -f enforcement_report.json ]]; then
        local violations=$(jq 'length' enforcement_report.json 2>/dev/null || echo "0")
        if [[ "$violations" -gt 0 ]]; then
            log "Enforcement detected $violations violation(s)"
            return 0
        else
            warn "No violations detected (traffic may not have been captured)"
        fi
    fi
}

# Main
main() {
    echo "========================================"
    echo "  Flodviddar Auto-Whitelist Demo"
    echo "========================================"
    echo "Configuration:"
    echo "  - Stability threshold: ${THRESHOLD}%"
    echo "  - Consecutive stable: $CONSECUTIVE"
    echo "  - Max iterations: $MAX_ITERATIONS"
    echo "========================================"
    echo ""
    
    check_flodviddar
    init_state
    
    log "Starting at iteration $ITERATION"
    
    # Run iterations until stable or max reached
    while [[ "$ITERATION" -le "$MAX_ITERATIONS" ]]; do
        run_iteration
        
        if [[ "$IS_STABLE" == "true" ]]; then
            log "Whitelist stabilized after $ITERATION iterations!"
            break
        fi
        
        if [[ "$ITERATION" -lt "$MAX_ITERATIONS" ]]; then
            ITERATION=$((ITERATION + 1))
            sleep 2
        else
            break
        fi
    done
    
    # Final summary
    echo ""
    echo "========================================"
    echo "  SUMMARY"
    echo "========================================"
    echo "Total iterations: $ITERATION"
    echo "Endpoint count: $LAST_COUNT"
    echo "Stable count: $STABLE_COUNT/$CONSECUTIVE"
    echo "Status: $(if [[ "$IS_STABLE" == "true" ]]; then echo "STABLE (enforcing)"; else echo "LEARNING"; fi)"
    echo "========================================"
    
    # Test enforcement if stable
    if [[ "$IS_STABLE" == "true" ]]; then
        echo ""
        test_enforcement
    fi
    
    echo ""
    echo "Whitelist saved to: $WHITELIST_FILE"
    echo "State saved to: $STATE_FILE"
    echo ""
    
    if [[ "$IS_STABLE" == "true" ]]; then
        echo "Next run will ENFORCE this whitelist"
    else
        echo "Next run will continue LEARNING"
    fi
}

# Show help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOF
Automated Whitelist Lifecycle Demo

Usage: $0 [OPTIONS]

Environment Variables:
  WHITELIST_FILE       Path to whitelist JSON (default: whitelist.json)
  STATE_FILE           Path to state JSON (default: whitelist_state.json)
  CAPTURE_DURATION     Seconds to capture per iteration (default: 60)
  THRESHOLD            Stability threshold percentage (default: 0)
  CONSECUTIVE          Consecutive stable runs required (default: 3)
  MAX_ITERATIONS       Maximum iterations before stopping (default: 10)

Example:
  # Run with custom configuration
  CAPTURE_DURATION=30 CONSECUTIVE=2 $0
  
  # Reset and start fresh
  rm -f whitelist.json whitelist_state.json
  $0

Note: Requires sudo for packet capture
EOF
    exit 0
fi

main



