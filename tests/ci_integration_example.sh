#!/bin/bash
# Flodviddar CI Integration Example
# This script shows how to integrate Flodviddar into any CI/CD pipeline
# Works with GitHub Actions, GitLab CI, Jenkins, or any bash-capable CI

set -e

# Configuration
WHITELIST_FILE="${WHITELIST_FILE:-whitelist.json}"
CAPTURE_DURATION="${CAPTURE_DURATION:-120}"  # 2 minutes default
MODE="${FLODVIDDAR_MODE:-scan}"  # scan, learn, augment, or watch
POLL_INTERVAL="${POLL_INTERVAL:-30}"  # for watch mode

# Detect CI environment
detect_ci() {
    if [[ -n "${GITHUB_ACTIONS}" ]]; then
        echo "github"
    elif [[ -n "${GITLAB_CI}" ]]; then
        echo "gitlab"
    elif [[ -n "${JENKINS_HOME}" ]]; then
        echo "jenkins"
    else
        echo "unknown"
    fi
}

CI_ENV=$(detect_ci)
echo "Detected CI environment: $CI_ENV"

# Install flodviddar (or build from source)
install_flodviddar() {
    if command -v flodviddar &> /dev/null; then
        echo "Flodviddar already installed: $(flodviddar --version 2>&1 || echo 'version unknown')"
        return 0
    fi
    
    echo "Building flodviddar from source..."
    
    # Install Rust if needed
    if ! command -v cargo &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Install system dependencies
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y libpcap-dev jq bc
    elif command -v yum &> /dev/null; then
        sudo yum install -y libpcap-devel jq bc
    fi
    
    # Clone or use existing source
    if [[ -d "/tmp/flodviddar" ]]; then
        cd /tmp/flodviddar
        git pull
    else
        git clone https://github.com/yourusername/flodviddar /tmp/flodviddar
        cd /tmp/flodviddar
    fi
    
    cargo build --release
    export PATH="/tmp/flodviddar/target/release:$PATH"
    
    echo "Flodviddar installed successfully"
}

# Download previous whitelist (if in artifact storage)
download_whitelist() {
    case $CI_ENV in
        github)
            if gh run download --name flodviddar-whitelist --dir . 2>/dev/null; then
                echo "Downloaded previous whitelist from artifacts"
                return 0
            fi
            ;;
        gitlab)
            # GitLab artifacts are automatically available in subsequent jobs
            if [[ -f "$WHITELIST_FILE" ]]; then
                echo "Using whitelist from previous job"
                return 0
            fi
            ;;
    esac
    
    echo "No previous whitelist found (first run)"
    return 1
}

# Upload whitelist for next run
upload_whitelist() {
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        echo "No whitelist to upload"
        return 1
    fi
    
    case $CI_ENV in
        github)
            # In GitHub Actions, this would be done via actions/upload-artifact
            echo "In GitHub Actions, use: actions/upload-artifact@v4"
            echo "Whitelist ready at: $WHITELIST_FILE"
            ;;
        gitlab)
            # In GitLab, artifacts are specified in .gitlab-ci.yml
            echo "In GitLab CI, add to artifacts:paths in .gitlab-ci.yml"
            echo "Whitelist ready at: $WHITELIST_FILE"
            ;;
        *)
            echo "For custom CI, upload $WHITELIST_FILE to artifact storage"
            ;;
    esac
}

# Run flodviddar based on mode
run_flodviddar() {
    local flodviddar_cmd="flodviddar"
    
    # Use built binary if available
    if [[ -f "/tmp/flodviddar/target/release/flodviddar" ]]; then
        flodviddar_cmd="/tmp/flodviddar/target/release/flodviddar"
    fi
    
    case $MODE in
        learn)
            echo "=== LEARNING MODE: Creating baseline whitelist ==="
            sudo $flodviddar_cmd create-whitelist $CAPTURE_DURATION false \
                --file "$WHITELIST_FILE"
            ;;
        
        augment)
            echo "=== AUGMENTATION MODE: Adding new endpoints to whitelist ==="
            if download_whitelist; then
                sudo $flodviddar_cmd create-whitelist $CAPTURE_DURATION true \
                    --file "$WHITELIST_FILE"
            else
                echo "No baseline found, creating new one"
                sudo $flodviddar_cmd create-whitelist $CAPTURE_DURATION false \
                    --file "$WHITELIST_FILE"
            fi
            ;;
        
        scan)
            echo "=== SCAN MODE: One-time capture with enforcement ==="
            download_whitelist || {
                echo "WARNING: No whitelist found, running without enforcement"
            }
            
            if [[ -f "$WHITELIST_FILE" ]]; then
                sudo $flodviddar_cmd scan $CAPTURE_DURATION \
                    --custom-whitelist "$WHITELIST_FILE" \
                    --output report
            else
                sudo $flodviddar_cmd scan $CAPTURE_DURATION \
                    --no-whitelist \
                    --output report
            fi
            ;;
        
        watch)
            echo "=== WATCH MODE: Continuous monitoring ==="
            download_whitelist || {
                echo "ERROR: Watch mode requires a whitelist"
                exit 1
            }
            
            sudo $flodviddar_cmd watch $POLL_INTERVAL \
                --custom-whitelist "$WHITELIST_FILE"
            ;;
        
        *)
            echo "ERROR: Unknown mode '$MODE'"
            echo "Valid modes: learn, augment, scan, watch"
            exit 1
            ;;
    esac
}

# Main flow
main() {
    echo "========================================"
    echo "  Flodviddar CI Integration"
    echo "========================================"
    echo "Mode: $MODE"
    echo "CI: $CI_ENV"
    echo "Whitelist: $WHITELIST_FILE"
    echo "========================================"
    echo ""
    
    install_flodviddar
    run_flodviddar
    upload_whitelist
    
    echo ""
    echo "========================================"
    echo "  COMPLETE"
    echo "========================================"
}

main


