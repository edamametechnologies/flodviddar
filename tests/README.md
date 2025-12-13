# Flodviddar Test Suite

Integration tests for supply chain attack detection and whitelist lifecycle management.

## Tests

### CVE-2025-30066 Detection

Tests detection of supply chain attacks similar to tj-actions/changed-files.

**What it does:**
1. Creates baseline from legitimate traffic (GitHub, PyPI, NPM)
2. Runs malicious script contacting gist.githubusercontent.com
3. Verifies violation is detected

**Run:** `sudo ./tests/test_cve_2025_30066.sh`

### Whitelist Lifecycle

Tests learning → augmentation → enforcement cycle.

**Phases:**
1. Learning - Create baseline (3 endpoints)
2. Augmentation - Add new endpoint (4 total)
3. Stability - 3 consecutive runs with no changes
4. Enforcement - Detect violations

**Run:** `sudo ./tests/test_whitelist_lifecycle.sh`

### Watch Daemon

Tests real-time monitoring with periodic violation checks.

**What it does:**
1. Creates baseline whitelist
2. Starts daemon with 10s poll interval
3. Introduces malicious traffic
4. Verifies detection within 30s

**Run:** `sudo ./tests/test_watch_daemon.sh`

## Prerequisites

```bash
sudo apt-get install -y libpcap-dev jq bc python3-pip
pip3 install requests
```

## Running All Tests

```bash
sudo ./tests/run_all_tests.sh
```

## CI Integration

Tests run automatically on GitHub Actions. See `.github/workflows/test.yml`.

## Notes

- Tests require sudo for packet capture
- Packet capture timing in CI can be unpredictable
- Tests are designed to handle timing issues gracefully
- For reliable results, run locally with adequate capture duration

## Test Environment

- **Target:** Ubuntu 18.04+
- **Temporary files:** `/tmp/flodviddar_*_test_<pid>`
- **Cleanup:** Automatic on exit

## Troubleshooting

**No sessions captured:** Common in CI due to timing. Not a test failure.

**DNS resolution pending:** L7 capture is asynchronous. Tests check both domain and IP-based violations.

**Permission denied:** Run with sudo or grant capabilities to binary.
