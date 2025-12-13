# Flodviddar Tests

This directory contains integration tests for Flodviddar, demonstrating its capabilities for detecting supply chain attacks and managing network whitelists in CI/CD environments.

## Test Suite

### 1. Whitelist Lifecycle Test (`test_whitelist_lifecycle.sh`)

Tests the complete whitelist management lifecycle:

1. **Learning Phase**: Creates baseline from legitimate traffic
2. **Augmentation Phase**: Adds new endpoints incrementally
3. **Stability Detection**: Tracks consecutive unchanged runs
4. **Enforcement Phase**: Detects violations after whitelist stabilizes

**Expected Flow:**
```
Iteration 1: Create baseline (3 endpoints)
Iteration 2: Same traffic (stable count: 1/3)
Iteration 3: Add new endpoint (4 total, reset stability)
Iteration 4: Same traffic (stable count: 1/3)
Iteration 5: Same traffic (stable count: 2/3)
Iteration 6: Same traffic (stable count: 3/3) → STABLE
Iteration 7: Test enforcement with unauthorized traffic
```

**Usage:**
```bash
sudo ./tests/test_whitelist_lifecycle.sh
```

### 2. CVE-2025-30066 Detection Test (`test_cve_2025_30066.sh`)

Demonstrates how Flodviddar detects supply chain attacks similar to the tj-actions/changed-files vulnerability.

**Phases:**
1. Capture legitimate build traffic (GitHub, PyPI, NPM)
2. Create baseline whitelist
3. Run malicious script that contacts gist.githubusercontent.com
4. Verify violation is detected

**Usage:**
```bash
sudo ./tests/test_cve_2025_30066.sh
```

### 3. Watch Daemon Test (`test_watch_daemon.sh`)

Tests real-time monitoring and violation detection.

**Tests:**
1. Baseline creation
2. Daemon startup with custom whitelist
3. Real-time violation detection (poll every 10s)
4. Verification that violations are logged

**Usage:**
```bash
sudo ./tests/test_watch_daemon.sh
```

### 4. Master Test Runner (`run_all_tests.sh`)

Runs all tests sequentially and provides a summary.

**Usage:**
```bash
sudo ./tests/run_all_tests.sh
```

## Prerequisites

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libpcap-dev \
    python3 \
    python3-pip \
    jq \
    bc
```

### Python Dependencies
```bash
pip3 install requests
```

### Rust Toolchain
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## Running Tests

### All Tests
```bash
cd /path/to/flodviddar
sudo ./tests/run_all_tests.sh
```

### Individual Tests
```bash
# Whitelist lifecycle
sudo ./tests/test_whitelist_lifecycle.sh

# CVE detection
sudo ./tests/test_cve_2025_30066.sh

# Watch daemon
sudo ./tests/test_watch_daemon.sh
```

## Integration with CI/CD

These tests can be easily integrated into CI/CD pipelines:

### GitHub Actions Example
```yaml
jobs:
  security-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libpcap-dev jq bc python3-requests
      
      - name: Run Flodviddar tests
        run: sudo ./tests/run_all_tests.sh
```

### GitLab CI Example
```yaml
test:
  image: ubuntu:latest
  before_script:
    - apt-get update
    - apt-get install -y build-essential libpcap-dev python3 python3-pip jq bc curl
    - curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    - source $HOME/.cargo/env
  script:
    - ./tests/run_all_tests.sh
```

### Standalone CI Script
```bash
#!/bin/bash
# ci_test.sh - Standalone CI test script

# Install prerequisites
sudo apt-get update
sudo apt-get install -y libpcap-dev jq bc python3-requests

# Clone and test
git clone https://github.com/yourusername/flodviddar
cd flodviddar
sudo ./tests/run_all_tests.sh
```

## What These Tests Demonstrate

### Supply Chain Attack Prevention
The CVE test shows how Flodviddar can detect:
- Unauthorized network connections from build processes
- Data exfiltration attempts
- Compromised dependencies
- Malicious package behavior

### Zero-Trust Networking
The lifecycle test demonstrates:
- Automated whitelist generation from observed traffic
- Incremental refinement as dependencies change
- Automatic enforcement after stability is reached
- Detection of new/unauthorized endpoints

### Real-Time Protection
The watch daemon test proves:
- Continuous monitoring during CI/CD execution
- Immediate detection within seconds
- Pipeline cancellation on violations
- Defense-in-depth beyond end-of-workflow checks

## Interpreting Results

### Success Output
```
========================================
  ALL TESTS PASSED
========================================
```

### Partial Success
Some tests may show warnings if:
- DNS resolution is slow (L7 domain capture pending)
- Network conditions affect timing
- Sessions are captured but domain not yet resolved

This is expected and doesn't indicate failure - the tests are designed to be resilient.

### Failure Output
True failures indicate:
- Build errors
- Missing dependencies
- Actual bugs in Flodviddar

## Test Artifacts

Tests create temporary directories under `/tmp/flodviddar_*_test_<pid>`:
- `whitelist.json`: Generated whitelists
- `*.log`: Capture and scan logs
- `*_report.json`: Session reports
- `state.txt.*`: Lifecycle state files

These are automatically cleaned up on exit.

## Notes

- Tests require **sudo** for packet capture (libpcap)
- Tests are **non-destructive** (use temporary directories)
- Tests **clean up after themselves** (trap EXIT)
- Tests work on **Ubuntu 18.04+** and other Debian-based distributions
- For non-Debian systems, adjust package installation commands

## Troubleshooting

### "Permission denied" on packet capture
```bash
# Grant capabilities to binary (alternative to sudo)
sudo setcap cap_net_raw,cap_net_admin=eip target/release/flodviddar
```

### "No sessions captured"
- Ensure network connectivity is available
- Check firewall rules aren't blocking outbound HTTPS
- Verify libpcap is installed correctly

### "DNS resolution pending"
- This is normal - tests account for this
- L7/DNS capture may take time to resolve domains
- Tests verify both domain-based and IP-based violations

