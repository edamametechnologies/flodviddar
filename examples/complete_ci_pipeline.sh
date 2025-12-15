#!/bin/bash
# Complete CI Pipeline Example with Flodviddar
# This script demonstrates a full production-ready CI security setup

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

FLODVIDDAR_VERSION="latest"
WHITELIST_FILE="whitelist.json"
STATE_FILE="whitelist_state.json"
CAPTURE_DURATION=180  # 3 minutes
STABILITY_THRESHOLD=0  # 0% = no new endpoints
STABILITY_REQUIRED=3   # 3 consecutive stable runs

# Artifact storage (customize for your CI)
ARTIFACT_STORAGE="${ARTIFACT_STORAGE:-./artifacts}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Install Flodviddar
install_flodviddar() {
    if command -v flodviddar &> /dev/null; then
        log "Flodviddar already installed"
        return 0
    fi
    
    log "Installing Flodviddar from source..."
    
    # Dependencies
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y libpcap-dev jq bc
    fi
    
    # Rust
    if ! command -v cargo &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Build
    if [[ ! -d "/tmp/flodviddar" ]]; then
        git clone https://github.com/yourusername/flodviddar /tmp/flodviddar
    fi
    
    cd /tmp/flodviddar
    cargo build --release
    sudo cp target/release/flodviddar /usr/local/bin/
    
    log "Flodviddar installed successfully"
}

# Download artifacts from previous run
download_artifacts() {
    mkdir -p "$ARTIFACT_STORAGE"
    
    # Try to download from your artifact system
    # This example assumes artifacts are stored locally for demo purposes
    if [[ -f "$ARTIFACT_STORAGE/$WHITELIST_FILE" ]]; then
        cp "$ARTIFACT_STORAGE/$WHITELIST_FILE" ./
        log "Downloaded whitelist from artifacts"
        return 0
    fi
    
    if [[ -f "$ARTIFACT_STORAGE/$STATE_FILE" ]]; then
        cp "$ARTIFACT_STORAGE/$STATE_FILE" ./
        log "Downloaded state from artifacts"
    fi
    
    return 1
}

# Upload artifacts for next run
upload_artifacts() {
    mkdir -p "$ARTIFACT_STORAGE"
    
    if [[ -f "$WHITELIST_FILE" ]]; then
        cp "$WHITELIST_FILE" "$ARTIFACT_STORAGE/"
        log "Uploaded whitelist to artifacts"
    fi
    
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "$ARTIFACT_STORAGE/"
        log "Uploaded state to artifacts"
    fi
}

# Initialize or load state
init_state() {
    if [[ -f "$STATE_FILE" ]]; then
        ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE")
        STABLE_COUNT=$(jq -r '.stable_count // 0' "$STATE_FILE")
        IS_STABLE=$(jq -r '.is_stable // false' "$STATE_FILE")
        log "Loaded state: iteration=$ITERATION, stable_count=$STABLE_COUNT, is_stable=$IS_STABLE"
    else
        ITERATION=0
        STABLE_COUNT=0
        IS_STABLE="false"
        log "No previous state, starting fresh"
    fi
    
    ITERATION=$((ITERATION + 1))
}

# Save state
save_state() {
    cat > "$STATE_FILE" << EOF
{
  "iteration": $ITERATION,
  "stable_count": $STABLE_COUNT,
  "is_stable": $IS_STABLE,
  "last_run": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "endpoint_count": $ENDPOINT_COUNT
}
EOF
    log "Saved state: iteration=$ITERATION, stable_count=$STABLE_COUNT"
}

# ============================================================================
# MAIN WORKFLOW
# ============================================================================

main() {
    echo "========================================"
    echo "  Flodviddar CI Pipeline"
    echo "========================================"
    echo "Start: $(date)"
    echo "========================================"
    echo ""
    
    # Setup
    install_flodviddar
    download_artifacts || true
    init_state
    
    # Determine whitelist status
    OLD_COUNT=0
    if [[ -f "$WHITELIST_FILE" ]]; then
        OLD_COUNT=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE" 2>/dev/null || echo "0")
        log "Previous whitelist: $OLD_COUNT endpoints"
        HAS_WHITELIST="true"
    else
        log "No previous whitelist (iteration $ITERATION)"
        HAS_WHITELIST="false"
    fi
    
    # ========================================================================
    # PHASE 1: START MONITORING
    # ========================================================================
    
    log "=== Phase 1: Starting Security Monitoring ==="
    
    if [[ "$HAS_WHITELIST" == "true" ]]; then
        if [[ "$IS_STABLE" == "true" ]]; then
            log "Whitelist is STABLE - running in ENFORCEMENT mode"
            
            # Enforcement: scan with violations causing exit
            sudo flodviddar scan $CAPTURE_DURATION \
                --custom-whitelist "$WHITELIST_FILE" \
                --output report \
                > violations_report.json 2>&1 &
        else
            log "Whitelist is LEARNING - running in AUGMENTATION mode"
            
            # Augmentation: capture for later merge
            sudo flodviddar scan $CAPTURE_DURATION \
                --custom-whitelist "$WHITELIST_FILE" \
                --output whitelist \
                > new_whitelist.json 2>&1 &
        fi
    else
        log "First run - LEARNING mode (creating baseline)"
        
        sudo flodviddar create-whitelist $CAPTURE_DURATION false \
            --file "$WHITELIST_FILE" \
            > /tmp/flodviddar_baseline.log 2>&1 &
    fi
    
    FLODVIDDAR_PID=$!
    log "Flodviddar started (PID: $FLODVIDDAR_PID)"
    sleep 5
    
    # ========================================================================
    # PHASE 2: YOUR BUILD/TEST STEPS (PLACEHOLDER)
    # ========================================================================
    
    log "=== Phase 2: Running Build and Tests ==="
    
    # YOUR ACTUAL CI COMMANDS GO HERE
    # Examples:
    # npm install
    # npm run build
    # npm test
    # python -m pytest
    # make test
    
    # For demonstration, generate some test traffic
    if command -v python3 &> /dev/null && pip3 list 2>/dev/null | grep -q requests; then
        cat > /tmp/test_traffic.py << 'EOF'
import requests
print("Generating test traffic...")
try:
    requests.get("https://api.github.com/zen", timeout=10)
    requests.get("https://registry.npmjs.org/-/ping", timeout=10)
    print("Traffic generated successfully")
except Exception as e:
    print(f"Traffic generation failed: {e}")
EOF
        python3 /tmp/test_traffic.py || true
    fi
    
    log "Build and tests completed"
    
    # ========================================================================
    # PHASE 3: STOP MONITORING AND ANALYZE
    # ========================================================================
    
    log "=== Phase 3: Analyzing Security Results ==="
    
    # Wait for capture to complete
    wait $FLODVIDDAR_PID || {
        FLODVIDDAR_EXIT=$?
        log "Flodviddar exited with code: $FLODVIDDAR_EXIT"
    }
    
    # Additional augmentation capture if needed
    if [[ "$HAS_WHITELIST" == "true" ]] && [[ "$IS_STABLE" == "false" ]]; then
        log "Augmenting whitelist with captured traffic..."
        sudo flodviddar create-whitelist 10 true --file "$WHITELIST_FILE" 2>&1 | tail -10
    fi
    
    # Calculate new endpoint count
    ENDPOINT_COUNT=0
    if [[ -f "$WHITELIST_FILE" ]]; then
        ENDPOINT_COUNT=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE" 2>/dev/null || echo "0")
    fi
    
    log "Current whitelist: $ENDPOINT_COUNT endpoints"
    
    # ========================================================================
    # PHASE 4: STABILITY ANALYSIS
    # ========================================================================
    
    log "=== Phase 4: Whitelist Stability Analysis ==="
    
    DELTA=$((ENDPOINT_COUNT - OLD_COUNT))
    
    if [[ "$ENDPOINT_COUNT" -gt 0 ]] && [[ "$OLD_COUNT" -gt 0 ]]; then
        PERCENT_CHANGE=$(echo "scale=2; ($DELTA * 100) / $ENDPOINT_COUNT" | bc)
    else
        PERCENT_CHANGE=0
    fi
    
    log "Endpoint change: +$DELTA ($PERCENT_CHANGE%)"
    
    # Check stability
    if [[ "$ITERATION" -gt 1 ]] && [[ "$DELTA" -eq 0 ]]; then
        STABLE_COUNT=$((STABLE_COUNT + 1))
        log "STABLE run (consecutive: $STABLE_COUNT/$STABILITY_REQUIRED)"
        
        if [[ "$STABLE_COUNT" -ge "$STABILITY_REQUIRED" ]]; then
            log "WHITELIST IS FULLY STABLE!"
            log "Future runs will enforce this whitelist"
            IS_STABLE="true"
        else
            IS_STABLE="false"
        fi
    elif [[ "$ITERATION" -gt 1 ]]; then
        log "EVOLVING: New endpoints added (resetting stability)"
        STABLE_COUNT=0
        IS_STABLE="false"
    fi
    
    # ========================================================================
    # PHASE 5: VIOLATION CHECKING
    # ========================================================================
    
    if [[ "$IS_STABLE" == "true" ]] && [[ -f "violations_report.json" ]]; then
        log "=== Phase 5: Checking for Violations ==="
        
        VIOLATION_COUNT=$(jq 'length' violations_report.json 2>/dev/null || echo "0")
        
        if [[ "$VIOLATION_COUNT" -gt 0 ]]; then
            error "SECURITY VIOLATIONS DETECTED: $VIOLATION_COUNT"
            echo "Violating sessions:"
            jq -r '.[] | "  - \(.dst_domain // .session.dst_ip):\(.session.dst_port) [\(.session.protocol)]"' violations_report.json
            
            # In stable/enforcement mode, violations are fatal
            echo "========================================"
            echo "  BUILD FAILED (Security Violation)"
            echo "========================================"
            exit 1
        else
            log "No violations detected (whitelist conformance: OK)"
        fi
    fi
    
    # ========================================================================
    # PHASE 6: SAVE STATE AND ARTIFACTS
    # ========================================================================
    
    save_state
    upload_artifacts
    
    # ========================================================================
    # SUMMARY
    # ========================================================================
    
    echo ""
    echo "========================================"
    echo "  PIPELINE SUMMARY"
    echo "========================================"
    echo "Iteration: $ITERATION"
    echo "Endpoints: $ENDPOINT_COUNT (change: +$DELTA)"
    echo "Stability: $STABLE_COUNT/$STABILITY_REQUIRED consecutive stable runs"
    echo "Status: $(if [[ "$IS_STABLE" == "true" ]]; then echo "ENFORCING"; elif [[ "$STABLE_COUNT" -gt 0 ]]; then echo "CONFIRMING"; else echo "LEARNING"; fi)"
    echo "========================================"
    echo "End: $(date)"
    echo ""
    
    if [[ "$IS_STABLE" == "true" ]]; then
        log "Whitelist is stable - enforcement active"
    elif [[ "$STABLE_COUNT" -gt 0 ]]; then
        log "Whitelist is stabilizing ($STABLE_COUNT/$STABILITY_REQUIRED)"
    else
        log "Whitelist is still learning"
    fi
    
    echo "========================================"
    echo "  BUILD SUCCESSFUL"
    echo "========================================"
}

main "$@"



