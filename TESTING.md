# Testing Guide

Comprehensive testing documentation for Flodviddar.

## Test Suite

Flodviddar includes integration tests that validate supply chain attack detection and whitelist lifecycle management.

### Available Tests

**CVE-2025-30066 Detection** (`tests/test_cve_2025_30066.sh`)
Verifies detection of supply chain attacks similar to the tj-actions/changed-files vulnerability.

**Whitelist Lifecycle** (`tests/test_whitelist_lifecycle.sh`)
Tests the complete learning → augmentation → enforcement cycle.

**Watch Daemon** (`tests/test_watch_daemon.sh`)
Validates real-time monitoring and violation detection.

## Running Tests

### Complete Suite

```bash
make test
```

### Individual Tests

```bash
sudo ./tests/test_cve_2025_30066.sh
sudo ./tests/test_whitelist_lifecycle.sh
sudo ./tests/test_watch_daemon.sh
```

## Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install -y \
    build-essential \
    libpcap-dev \
    jq \
    bc \
    python3-pip

pip3 install requests
```

## CI Testing

Tests run automatically on push via GitHub Actions (see `.github/workflows/test.yml`).

### GitHub Actions

```yaml
- name: Run tests
  run: |
    sudo apt-get install -y libpcap-dev jq bc python3-pip
    pip3 install requests
    cargo build --release
    sudo ./tests/run_all_tests.sh
```

### GitLab CI

```yaml
test:
  image: ubuntu:latest
  before_script:
    - apt-get update
    - apt-get install -y build-essential libpcap-dev jq bc python3-pip
    - pip3 install requests
  script:
    - cargo build --release
    - ./tests/run_all_tests.sh
```

## Test Environment

Tests use temporary directories under `/tmp/flodviddar_*_test_<pid>` that are automatically cleaned up.

**Note:** Tests require sudo for packet capture. In CI environments, packet capture timing can be unpredictable - tests are designed to handle this gracefully.

## Local Testing with Lima

For macOS users, test in a clean Linux environment:

```bash
make lima-create   # Create VM
make lima-start    # Start VM
make lima-test     # Run tests in VM
make lima-delete   # Clean up
```

## Troubleshooting

### Permission Denied

Grant capabilities to binary:
```bash
sudo setcap cap_net_raw,cap_net_admin=eip target/release/flodviddar
```

### No Sessions Captured

Common in CI due to timing. Tests handle this gracefully and won't fail on timing issues.

### DNS Resolution Pending

L7/DNS capture is asynchronous. Tests check for both domain-based and IP-based violations.

## Test Details

See `tests/README.md` for detailed test documentation.
