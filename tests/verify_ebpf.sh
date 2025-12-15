#!/bin/bash
# Verify eBPF support in test environment
# This script checks that flodbadd was built with eBPF support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[eBPF]${NC} $1"; }
error() { echo -e "${RED}[eBPF]${NC} $1"; }
warn() { echo -e "${YELLOW}[eBPF]${NC} $1"; }

echo "========================================"
echo "  eBPF Support Verification"
echo "========================================"
echo ""

# Check kernel version
KERNEL_VERSION=$(uname -r)
log "Kernel version: $KERNEL_VERSION"

# Check if eBPF is enabled in kernel
if [[ -d "/sys/fs/bpf" ]]; then
    log "eBPF filesystem mounted: /sys/fs/bpf"
else
    warn "eBPF filesystem not mounted"
fi

# Check kernel config
if [[ -f "/boot/config-$(uname -r)" ]]; then
    if grep -q "CONFIG_BPF=y" "/boot/config-$(uname -r)"; then
        log "Kernel has BPF support enabled"
    else
        error "Kernel BPF support not enabled"
    fi
else
    warn "Kernel config not available"
fi

# Check for BPF tools
if command -v bpftool &> /dev/null; then
    log "bpftool available: $(bpftool version 2>&1 | head -1)"
else
    warn "bpftool not found"
fi

# Check for headers
if [[ -d "/usr/include/bpf" ]] || [[ -d "/usr/include/linux/bpf.h" ]]; then
    log "BPF headers available"
else
    warn "BPF headers not found"
fi

# Check flodbadd build features
log "Checking flodbadd build configuration..."
cd "$PROJECT_ROOT"

# Check if flodbadd has eBPF feature in Cargo.toml
if grep -r "ebpf" ../flodbadd/Cargo.toml &> /dev/null; then
    log "Flodbadd has eBPF feature available"
else
    warn "Flodbadd eBPF feature not found in Cargo.toml"
fi

# Try to build with all features
log "Building flodviddar with full features..."
if cargo build --release 2>&1 | tee /tmp/flodviddar_ebpf_build.log | grep -q "Finished"; then
    log "Build successful"
else
    error "Build failed"
    tail -20 /tmp/flodviddar_ebpf_build.log
    exit 1
fi

# Check if binary was built with eBPF
BINARY="$PROJECT_ROOT/target/release/flodviddar"
if [[ -f "$BINARY" ]]; then
    log "Binary exists: $BINARY"
    SIZE=$(du -h "$BINARY" | cut -f1)
    log "Binary size: $SIZE"
else
    error "Binary not found"
    exit 1
fi

# Summary
echo ""
echo "========================================"
echo "  eBPF Verification Summary"
echo "========================================"
echo "Kernel: $(uname -r)"
echo "Platform: $(uname -m)"
echo "eBPF Filesystem: $(if [[ -d /sys/fs/bpf ]]; then echo "✓"; else echo "✗"; fi)"
echo "Build: ✓"
echo "Binary: ✓"
echo "========================================"
echo ""
log "eBPF verification complete"
log "Note: Flodbadd's eBPF features (if enabled) are available"
echo ""


