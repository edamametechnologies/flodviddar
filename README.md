# flodviddar
What is Flodviddar?

Flodviddar is an open-source security tool, specifically designed to monitor, detect, and prevent supply chain attacks by scrutinizing outbound (egress) network traffic.

It uses the Flodbadd library for packet inspection, enabling it to:

- Enforce strict traffic whitelists to ensure only known and approved outbound communications defined with l3 to l7 criteria.

- Block threats using regularly updated blacklists to quickly respond to known malicious hosts and domains.

- Identify suspicious or anomalous behaviors through intelligent anomaly detection, catching previously unknown threats or deviations in traffic patterns.

- Automatically halt the pipeline upon detection of suspicious or unauthorized traffic.

## Command-line Usage

The Rust implementation ships a small CLI that can be invoked directly or as part of a CI workflow.

### Scan for policy violations and auto-cancel the pipeline

```bash
# Capture for two minutes and cancel the current GitHub / GitLab run if
# blacklisted or anomalous sessions are detected.
flodviddar scan 120 true
```

### Manually cancel the pipeline

```bash
flodviddar halt "Build blocked by security policy"
```

Both commands rely on standard CI environment variables.  When executed in
GitHub Actions (`GITHUB_ACTIONS=1`) the tool talks to the GitHub CLI (`gh`)
to cancel the current workflow run.  In GitLab CI (`GITLAB_CI=1`) it calls the
GitLab REST API via `curl`.  Outside of CI the commands are no-ops.

The CLI offers additional flags to tailor behaviour:
• `--custom-whitelist <file>` – pre-load a JSON whitelist before capturing (scan/watch).
• `--output <whitelist|report>` – after scan finishes, either write a freshly generated whitelist or dump all sessions as JSON.
• `--until-signal` – run until Ctrl-C / SIGTERM instead of a fixed duration.
• `--no-*` flags – disable individual checks (`--no-whitelist`, `--no-blacklist`, `--no-anomaly`, `--no-cancel`).

#### Incremental whitelist workflow
```bash
# Record baseline traffic and write to file
flodviddar create-whitelist 120 --file whitelist.json

# Re-run later, merge new exceptions into the same whitelist
flodviddar create-whitelist 30 --augment --file whitelist.json
```

#### Using a custom whitelist while scanning
```bash
flodviddar scan 60 --custom-whitelist whitelist.json --output report
```

#### Continuous monitoring in CI
```bash
flodviddar watch 15 --custom-whitelist whitelist.json --no-cancel
```

When violations are found the tool prints:
```
=== Violating Sessions ===
<timestamp> 192.0.2.1:12345 -> 203.0.113.50:443 TLS blacklist:malware_c2
...
Policy violations detected. Halting CI pipeline...
```
which gives immediate feedback about the offending connections before cancelling the pipeline.

## Installation

### From Source (Ubuntu/Debian)

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y build-essential libpcap-dev jq bc

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Build Flodviddar
git clone https://github.com/yourusername/flodviddar
cd flodviddar
cargo build --release

# Install binary
sudo cp target/release/flodviddar /usr/local/bin/
```

### System Requirements

- Linux (Ubuntu 18.04+, Debian, or other distributions with libpcap)
- Root/sudo privileges (for packet capture)
- Network connectivity for CI/CD integration

## Testing

Flodviddar includes comprehensive integration tests that demonstrate its capabilities:

### Test Suite

1. **Whitelist Lifecycle Test** - Complete learning → augmentation → enforcement flow
2. **CVE-2025-30066 Detection** - Supply chain attack detection demonstration
3. **Watch Daemon Test** - Real-time monitoring and violation detection

### Running Tests

```bash
# Run all tests
sudo ./tests/run_all_tests.sh

# Run individual tests
sudo ./tests/test_whitelist_lifecycle.sh
sudo ./tests/test_cve_2025_30066.sh
sudo ./tests/test_watch_daemon.sh
```

See [tests/README.md](tests/README.md) for detailed test documentation.

## CI/CD Integration

Flodviddar is designed for seamless integration into CI/CD pipelines. It provides pure bash implementation that works with any CI system.

### Quick Start: GitHub Actions

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Flodviddar
        run: |
          sudo apt-get update
          sudo apt-get install -y libpcap-dev jq bc
          cargo build --release
          export FLODVIDDAR_BIN=$PWD/target/release/flodviddar
      
      - name: Download whitelist
        uses: actions/download-artifact@v4
        with:
          name: whitelist
          path: .
        continue-on-error: true
      
      - name: Start monitoring
        run: |
          if [[ -f whitelist.json ]]; then
            sudo $FLODVIDDAR_BIN scan 300 \
              --custom-whitelist whitelist.json \
              --output report > violations.json 2>&1 &
          else
            sudo $FLODVIDDAR_BIN create-whitelist 300 \
              --file whitelist.json > /tmp/flodviddar.log 2>&1 &
          fi
          sleep 5
      
      # YOUR BUILD/TEST STEPS
      - name: Build
        run: npm install && npm test
      
      - name: Check violations
        if: always()
        run: |
          if [[ -f violations.json ]] && [[ $(jq 'length' violations.json) -gt 0 ]]; then
            echo "Violations detected!"
            jq . violations.json
            exit 1
          fi
      
      - name: Upload whitelist
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: whitelist
          path: whitelist.json
```

### Quick Start: GitLab CI

```yaml
security_scan:
  before_script:
    - apt-get update
    - apt-get install -y libpcap-dev jq bc
    - cargo build --release
  script:
    - export FLODVIDDAR_BIN=$PWD/target/release/flodviddar
    
    # Start monitoring
    - |
      sudo $FLODVIDDAR_BIN scan 300 \
        $(if [[ -f whitelist.json ]]; then echo "--custom-whitelist whitelist.json"; fi) \
        --output report > violations.json 2>&1 &
      sleep 5
    
    # Your build/test commands
    - npm install && npm test
    
    # Check results
    - |
      if [[ $(jq 'length' violations.json 2>/dev/null || echo 0) -gt 0 ]]; then
        jq . violations.json
        exit 1
      fi
  
  artifacts:
    paths:
      - whitelist.json
      - violations.json
```

### Standalone CI Script

For any CI system, use the standalone integration script:

```bash
# Before your build
./tests/ci_integration_example.sh

# Set mode via environment
export FLODVIDDAR_MODE=learn  # or scan, augment, watch
./tests/ci_integration_example.sh
```

See [examples/](examples/) directory for complete integration examples.

## Whitelist Lifecycle Management

Flodviddar supports a three-phase whitelist lifecycle:

### Phase 1: Learning (Generate Baseline)

Capture all legitimate traffic and create a baseline whitelist:

```bash
# Run your normal build/test workflow
sudo flodviddar create-whitelist 120 false --file whitelist.json

# This captures all network traffic and generates a whitelist
```

### Phase 2: Augmentation (Incremental Updates)

Add new legitimate endpoints to an existing whitelist:

```bash
# Load existing whitelist and merge new endpoints
sudo flodviddar create-whitelist 60 true --file whitelist.json

# New endpoints are added, existing ones preserved
```

### Phase 3: Enforcement (Lock Down)

Detect and fail on unauthorized connections:

```bash
# Scan with whitelist enforcement
sudo flodviddar scan 120 \
  --custom-whitelist whitelist.json \
  --output report

# Exits with code 1 if violations detected
```

## Real-Time Monitoring

The `watch` command provides continuous monitoring during CI/CD execution:

```bash
# Monitor every 30 seconds, cancel pipeline on violations
sudo flodviddar watch 30 \
  --custom-whitelist whitelist.json

# For testing without cancellation
sudo flodviddar watch 30 \
  --custom-whitelist whitelist.json \
  --no-cancel
```

## Use Cases

### Supply Chain Attack Detection (CVE-2025-30066)

Detect when compromised dependencies attempt unauthorized network connections:

```bash
# Create whitelist from legitimate build
sudo flodviddar create-whitelist 120 false --file whitelist.json

# Run build again with enforcement
sudo flodviddar scan 120 \
  --custom-whitelist whitelist.json \
  --output report

# Any unauthorized connections (like CVE-2025-30066) will be detected
```

### Zero-Trust CI/CD Networking

Implement "deny by default, allow by exception" for builds:

```bash
# Start watch daemon
sudo flodviddar watch 15 --custom-whitelist whitelist.json &

# Run your build
npm install && npm test

# Daemon automatically detects and blocks violations in real-time
```

### Compliance Enforcement

Ensure builds only access approved services:

```bash
# Audit mode: capture without failing
sudo flodviddar scan 300 \
  --custom-whitelist approved_services.json \
  --output report \
  --no-cancel

# Review report and update whitelist as needed
```

## Architecture

Flodviddar is built on the **flodbadd** packet capture library and provides:

- **Egress-only policy**: Only outbound traffic is evaluated
- **L3-L7 matching**: Domain, IP, port, protocol, ASN, and process-based rules
- **CDN-aware**: Requires domain resolution for CDN providers to prevent false positives
- **Factorization**: Merges related endpoints to ensure whitelist stability
- **Incremental recomputation**: Efficient updates without full rescans

## Comparison with EDAMAME Posture

| Feature | Flodviddar (Open Source) | EDAMAME Posture (Proprietary) |
|---------|-------------------------|-------------------------------|
| Supply chain attack detection | ✓ | ✓ |
| Custom whitelists | ✓ | ✓ |
| Real-time monitoring | ✓ | ✓ |
| CI/CD integration | ✓ Bash | ✓ GitHub Action |
| Security posture scanning | - | ✓ |
| Domain authentication | - | ✓ |
| Central management | - | ✓ via Hub |
| License | MIT | Proprietary |

Flodviddar focuses specifically on **network traffic monitoring** and **supply chain attack prevention**, making it ideal for CI/CD security. For comprehensive device security posture management, consider EDAMAME Posture.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please ensure tests pass:

```bash
sudo ./tests/run_all_tests.sh
```


