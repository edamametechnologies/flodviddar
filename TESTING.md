# Flodviddar Testing Guide

Comprehensive guide to testing Flodviddar's security capabilities.

## Test Files Overview

```
flodviddar/
├── tests/
│   ├── test_cve_2025_30066.sh          # CVE detection test
│   ├── test_whitelist_lifecycle.sh     # Lifecycle test  
│   ├── test_watch_daemon.sh            # Real-time monitoring test
│   ├── run_all_tests.sh                # Master test runner
│   ├── ci_integration_example.sh       # CI integration template
│   ├── cli.rs                          # Rust unit tests
│   └── README.md                       # Test documentation
├── examples/
│   ├── github_actions.yml              # GitHub Actions example
│   ├── gitlab_ci.yml                   # GitLab CI example
│   ├── standalone_ci.sh                # Generic CI script
│   ├── complete_ci_pipeline.sh         # Full pipeline example
│   └── auto_whitelist_demo.sh          # Auto-whitelist demo
└── Makefile                            # Build & test targets
```

## Quick Test

Run all tests with one command:

```bash
make test
```

Or manually:

```bash
sudo ./tests/run_all_tests.sh
```

## Individual Tests

### 1. CVE-2025-30066 Detection Test

**Purpose:** Verify Flodviddar can detect supply chain attacks.

**What it tests:**
- Creating baseline whitelist from legitimate traffic
- Detecting unauthorized gist.githubusercontent.com connections
- Simulating the tj-actions/changed-files attack vector
- Verification that violations are reported

**Run:**
```bash
sudo ./tests/test_cve_2025_30066.sh
```

**Expected output:**
```
========================================
  Flodviddar CVE-2025-30066 Test
========================================
[INFO] Building flodviddar from source...
[INFO] Build successful
[INFO] === Phase 1: Creating Baseline Whitelist ===
[INFO] Baseline created with 15 endpoints
[INFO] === Phase 2: CVE-2025-30066 Detection Test ===
[INFO] Executing malicious build script...
[INFO] === Phase 3: Verifying CVE Detection ===
[INFO] SUCCESS: CVE-2025-30066 attack vector was DETECTED!
========================================
  TEST PASSED
========================================
```

**How it works:**

1. **Phase 1 - Learning:**
   - Runs legitimate Python script accessing GitHub, PyPI, NPM
   - Captures traffic for 30 seconds
   - Generates baseline whitelist

2. **Phase 2 - Attack:**
   - Loads baseline whitelist
   - Runs malicious script that contacts gist.githubusercontent.com
   - Captures violations

3. **Phase 3 - Verification:**
   - Checks scan report for gist.githubusercontent.com entries
   - Verifies violation was detected
   - Reports success/failure

### 2. Whitelist Lifecycle Test

**Purpose:** Validate complete learning → augmentation → enforcement cycle.

**What it tests:**
- Baseline creation from scratch
- Incremental endpoint addition
- Stability detection across runs
- Enforcement mode activation
- Violation detection in enforcement mode

**Run:**
```bash
sudo ./tests/test_whitelist_lifecycle.sh
```

**Expected output:**
```
========================================
  Flodviddar Whitelist Lifecycle Test
========================================
========================================
  ITERATION 1
========================================
[INFO] No previous whitelist (first run)
[PHASE] Creating baseline whitelist
[INFO] Current whitelist: 12 endpoints (change: +12, 100.00%)

========================================
  ITERATION 2
========================================
[INFO] Previous whitelist: 12 endpoints
[PHASE] Augmenting whitelist
[INFO] Current whitelist: 12 endpoints (change: +0, 0.00%)
[INFO] STABLE: No new endpoints (consecutive stable runs: 1/3)

========================================
  ITERATION 3
========================================
[INFO] Adding new endpoint...
[INFO] Current whitelist: 13 endpoints (change: +1, 7.69%)
[INFO] LEARNING: 1 new endpoints discovered (resetting stability counter)

========================================
  ITERATION 4-6
========================================
[INFO] STABLE: No new endpoints (consecutive stable runs: 3/3)
[INFO] WHITELIST IS STABLE! (3 consecutive runs with no changes)

[INFO] Testing enforcement mode...
[INFO] SUCCESS: Enforcement detected violations

========================================
  ALL TESTS PASSED
========================================
```

**How it works:**

1. **Iteration 1:** Create baseline (3 core endpoints)
2. **Iteration 2:** Same traffic (stable: 1/3)
3. **Iteration 3:** Add new endpoint www.npmjs.com (4 total, reset stability)
4. **Iterations 4-6:** No changes (stability reaches 3/3)
5. **Enforcement:** Test with unauthorized traffic
6. **Verification:** Confirm violations detected

### 3. Watch Daemon Test

**Purpose:** Test real-time monitoring and immediate violation detection.

**What it tests:**
- Baseline creation
- Daemon startup and configuration
- Real-time violation detection (10-second polling)
- Violation logging and reporting

**Run:**
```bash
sudo ./tests/test_watch_daemon.sh
```

**Expected output:**
```
========================================
  Flodviddar Watch Daemon Test
========================================
[INFO] === Creating Baseline Whitelist ===
[INFO] Baseline created with 8 endpoints
[INFO] === Testing Watch Daemon ===
[INFO] Starting watch daemon (poll every 10s, 60s timeout)...
[INFO] Daemon PID: 12345
[INFO] Generating legitimate traffic...
[INFO] Introducing violation...
[INFO] SUCCESS: Daemon detected violations
========================================
  TEST COMPLETE
========================================
```

**How it works:**

1. Creates baseline from legitimate traffic
2. Starts watch daemon with 10s poll interval
3. Generates legitimate traffic (should pass)
4. Introduces malicious gist.githubusercontent.com connection
5. Daemon detects violation within 10-30 seconds
6. Logs violations and exits

## Test Requirements

### System Requirements

- **OS:** Ubuntu 18.04+ (or Debian-based)
- **Privileges:** sudo (for packet capture)
- **Disk:** ~500MB (for Rust toolchain + build)
- **Network:** Internet connectivity for traffic generation

### Software Dependencies

```bash
sudo apt-get install -y \
    build-essential \
    libpcap-dev \
    jq \
    bc \
    python3 \
    python3-pip \
    curl

pip3 install requests
```

### Rust Toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## Test Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CAPTURE_DURATION` | 30-120s | How long to capture per iteration |
| `STABILITY_THRESHOLD` | 0 | Percentage change allowed for stability |
| `STABILITY_CONSECUTIVE` | 3 | Consecutive stable runs required |
| `MAX_ITERATIONS` | 10 | Maximum lifecycle iterations |
| `WHITELIST_FILE` | `whitelist.json` | Where to save whitelist |

**Example:**
```bash
CAPTURE_DURATION=15 STABILITY_CONSECUTIVE=2 sudo ./tests/test_whitelist_lifecycle.sh
```

## Interpreting Test Results

### Success Indicators

✓ **"TEST PASSED"** or **"ALL TESTS PASSED"**  
✓ Exit code 0  
✓ Violations detected when expected  
✓ Whitelist stability achieved  

### Warning Indicators (Not Failures)

⚠️ **"DNS resolution pending"** - Normal, L7 capture is async  
⚠️ **"No violations detected"** - May occur if timing is off  
⚠️ **"Partial pass"** - Some tests passed, others had timing issues  

These are **expected** in CI environments where:
- DNS resolution is slow
- Network conditions vary
- Packet timing is unpredictable

### Failure Indicators

✗ **"TEST FAILED"**  
✗ Exit code 1  
✗ **"Build failed"**  
✗ **"Binary not found"**  
✗ **"Missing prerequisites"**  

These indicate real problems that need fixing.

## Debugging Failed Tests

### Problem: "Permission denied"

**Cause:** Packet capture requires root.

**Fix:**
```bash
# Run with sudo
sudo ./tests/test_cve_2025_30066.sh

# Or grant capabilities
sudo setcap cap_net_raw,cap_net_admin=eip target/release/flodviddar
```

### Problem: "No sessions captured"

**Cause:** Network connectivity or firewall issues.

**Fix:**
```bash
# Check network
ping -c 1 github.com

# Check firewall
sudo iptables -L

# Run with verbose logging
sudo flodviddar -vvv scan 30
```

### Problem: "Whitelist not created"

**Cause:** Flodviddar crashed or no traffic generated.

**Fix:**
```bash
# Check logs
cat /tmp/flodviddar_*.log

# Run manually
sudo flodviddar create-whitelist 30 --file test.json
```

### Problem: "DNS resolution pending"

**Cause:** L7/DNS capture is asynchronous.

**Fix:** This is normal! The tests account for it:
- Tests check both domain and IP-based violations
- Longer capture durations improve resolution rates
- CDN guard handles unresolved CDN sessions correctly

## CI-Specific Testing

### GitHub Actions

Run tests in GitHub Actions:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: make deps
      
      - name: Run tests
        run: make test
```

### GitLab CI

```yaml
test:
  image: ubuntu:latest
  before_script:
    - apt-get update
    - apt-get install -y build-essential libpcap-dev jq bc python3-pip curl
    - curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    - source $HOME/.cargo/env
  script:
    - make test
```

### Local Docker

Test in a clean Ubuntu environment:

```bash
docker run -it --rm \
    --privileged \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    -v $PWD:/flodviddar \
    -w /flodviddar \
    ubuntu:latest \
    bash -c "
        apt-get update && \
        apt-get install -y build-essential libpcap-dev jq bc python3-pip curl && \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
        source \$HOME/.cargo/env && \
        make test
    "
```

## Test Coverage

### What's Tested

✓ Binary compilation  
✓ Baseline whitelist creation  
✓ Whitelist augmentation  
✓ Stability detection  
✓ Enforcement mode  
✓ CVE-2025-30066 attack vector  
✓ Watch daemon monitoring  
✓ Violation reporting  
✓ CI environment detection  

### What's NOT Tested (Yet)

- Cross-platform (macOS, Windows)
- High-concurrency scenarios
- Very large whitelists (1000+ endpoints)
- Network error handling
- Partial packet capture scenarios

Contributions welcome to expand test coverage!

## Continuous Testing

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running Flodviddar tests..."
if make test-quick; then
    echo "Tests passed"
    exit 0
else
    echo "Tests failed - commit aborted"
    exit 1
fi
```

### Nightly Testing

```bash
# Add to crontab
0 2 * * * cd /path/to/flodviddar && make test 2>&1 | mail -s "Flodviddar Test Results" you@example.com
```

## Performance Benchmarking

Want to benchmark whitelist performance?

```bash
# Large whitelist test
for i in {1..100}; do
    curl -s https://httpbin.org/delay/0 > /dev/null &
done

time sudo flodviddar scan 30 --custom-whitelist large_whitelist.json
```

Typical results:
- 100 endpoints: < 5s total overhead
- 1000 endpoints: < 15s total overhead
- 10000 endpoints: < 60s total overhead

## Contributing Tests

Want to add tests? Follow this pattern:

```bash
#!/bin/bash
# tests/test_your_feature.sh

set -e

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build
cargo build --release
FLODVIDDAR="$PROJECT_ROOT/target/release/flodviddar"

# Test logic
# ...

# Cleanup
rm -rf /tmp/test_artifacts

# Report
echo "TEST PASSED"
exit 0
```

Then add to `run_all_tests.sh`:

```bash
if run_test "Your Feature" "$SCRIPT_DIR/test_your_feature.sh"; then
    ((passed++))
else
    ((failed++))
fi
```

## Getting Help

- Read [tests/README.md](tests/README.md) for test descriptions
- Check [ARCHITECTURE.md](ARCHITECTURE.md) for implementation details
- Review [examples/](examples/) for integration patterns
- Open an issue on GitHub if tests fail unexpectedly

