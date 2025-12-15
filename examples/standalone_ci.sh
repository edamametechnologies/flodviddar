#!/bin/bash
# Standalone CI Script for Flodviddar
# Use this as a before_script/after_script in any CI system

# === CONFIGURATION ===
FLODVIDDAR_VERSION="latest"  # or specific version/tag
WHITELIST_FILE="flodviddar_whitelist.json"
CAPTURE_DURATION=120  # seconds
MODE="auto"  # auto, enforce, learn

# === HELPER FUNCTIONS ===
install_flodviddar() {
    if command -v flodviddar &> /dev/null; then
        echo "Flodviddar already installed"
        return 0
    fi
    
    echo "Installing Flodviddar..."
    
    # Install dependencies
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y libpcap-dev jq bc
    fi
    
    # Install Rust
    if ! command -v cargo &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Build from source
    git clone https://github.com/yourusername/flodviddar /tmp/flodviddar
    cd /tmp/flodviddar
    cargo build --release
    
    sudo cp target/release/flodviddar /usr/local/bin/
    echo "Flodviddar installed successfully"
}

# === BEFORE SCRIPT (run at start of CI job) ===
before_script() {
    echo "========================================"
    echo "  Flodviddar Pre-Build Security Check"
    echo "========================================"
    
    install_flodviddar
    
    # Check if whitelist exists from previous run
    HAS_WHITELIST="false"
    if [[ -f "$WHITELIST_FILE" ]]; then
        HAS_WHITELIST="true"
        ENDPOINT_COUNT=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE")
        echo "Found existing whitelist: $ENDPOINT_COUNT endpoints"
    else
        echo "No existing whitelist (first run or learning mode)"
    fi
    
    # Start capture in background
    case $MODE in
        auto)
            if [[ "$HAS_WHITELIST" == "true" ]]; then
                echo "Starting capture with whitelist enforcement..."
                sudo flodviddar scan $CAPTURE_DURATION \
                    --custom-whitelist "$WHITELIST_FILE" \
                    --output report > /tmp/flodviddar_report.json 2>&1 &
            else
                echo "Starting capture in learning mode..."
                sudo flodviddar scan $CAPTURE_DURATION \
                    --no-whitelist \
                    --output whitelist > /tmp/flodviddar_whitelist_new.json 2>&1 &
            fi
            FLODVIDDAR_PID=$!
            echo "Flodviddar started (PID: $FLODVIDDAR_PID)"
            ;;
        
        enforce)
            if [[ "$HAS_WHITELIST" != "true" ]]; then
                echo "ERROR: Enforce mode requires existing whitelist"
                exit 1
            fi
            sudo flodviddar scan $CAPTURE_DURATION \
                --custom-whitelist "$WHITELIST_FILE" \
                --output report > /tmp/flodviddar_report.json 2>&1 &
            FLODVIDDAR_PID=$!
            ;;
        
        learn)
            sudo flodviddar create-whitelist $CAPTURE_DURATION false \
                --file "$WHITELIST_FILE" > /tmp/flodviddar.log 2>&1 &
            FLODVIDDAR_PID=$!
            ;;
    esac
    
    # Save PID for after_script
    echo "$FLODVIDDAR_PID" > /tmp/flodviddar.pid
    
    echo "Flodviddar monitoring started"
    echo "========================================"
}

# === AFTER SCRIPT (run at end of CI job) ===
after_script() {
    echo "========================================"
    echo "  Flodviddar Post-Build Analysis"
    echo "========================================"
    
    # Wait for capture to complete
    if [[ -f /tmp/flodviddar.pid ]]; then
        FLODVIDDAR_PID=$(cat /tmp/flodviddar.pid)
        wait $FLODVIDDAR_PID 2>/dev/null || true
    fi
    
    # Additional short capture to catch final traffic
    if [[ -f "$WHITELIST_FILE" ]]; then
        echo "Running final 10s capture for whitelist augmentation..."
        sudo flodviddar create-whitelist 10 true \
            --file "$WHITELIST_FILE" 2>&1 | tail -20
    fi
    
    # Analyze results
    if [[ -f "$WHITELIST_FILE" ]]; then
        ENDPOINT_COUNT=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' "$WHITELIST_FILE")
        echo "Final whitelist: $ENDPOINT_COUNT endpoints"
        
        echo "Sample endpoints:"
        jq -r '.whitelists[]? | .endpoints[]? | "  - \(.domain // .ip):\(.port)"' "$WHITELIST_FILE" | head -10
    fi
    
    # Check for violations
    if [[ -f "/tmp/flodviddar_report.json" ]]; then
        VIOLATION_COUNT=$(jq 'length' /tmp/flodviddar_report.json 2>/dev/null || echo "0")
        
        if [[ "$VIOLATION_COUNT" -gt 0 ]]; then
            echo ""
            echo "========================================"
            echo "  SECURITY VIOLATIONS DETECTED: $VIOLATION_COUNT"
            echo "========================================"
            jq -r '.[] | "\(.session.src_ip):\(.session.src_port) -> \(.dst_domain // .session.dst_ip):\(.session.dst_port) [\(.session.protocol)]"' /tmp/flodviddar_report.json
            echo "========================================"
            exit 1
        else
            echo "No security violations detected"
        fi
    fi
    
    echo "========================================"
}

# === MAIN ===
case "${1:-before}" in
    before)
        before_script
        ;;
    after)
        after_script
        ;;
    both)
        before_script
        # Your build commands would go here in real usage
        after_script
        ;;
    *)
        echo "Usage: $0 {before|after|both}"
        exit 1
        ;;
esac


