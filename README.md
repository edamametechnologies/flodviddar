# Flodviddar

Open-source CI/CD egress traffic monitor and supply chain attack detector.

## Overview

Flodviddar monitors outbound network connections from CI/CD pipelines to detect and prevent supply chain attacks. It enforces strict traffic whitelists, blocks known malicious destinations, and uses machine learning to identify anomalous behavior.

**Key capabilities:**
- Whitelist enforcement (L3–L7: IP, domain, port, protocol, ASN, process)
- Real-time blacklist matching against threat intelligence
- ML-based anomaly detection for unknown threats
- Automatic pipeline cancellation on violations

## Quick Start

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y build-essential libpcap-dev

# Build from source
cargo build --release

# Create baseline whitelist
sudo ./target/release/flodviddar create-whitelist 120 false --file whitelist.json

# Run scan with enforcement
sudo ./target/release/flodviddar scan 120 \
  --custom-whitelist whitelist.json \
  --output report
```

## Commands

### scan

Capture traffic for a fixed duration and check for violations.

```bash
flodviddar scan <seconds> [OPTIONS]
```

**Options:**
- `--custom-whitelist <file>` - Load whitelist JSON before scanning
- `--output <whitelist|report>` - Output mode (whitelist creation or violation report)
- `--until-signal` - Run until SIGTERM instead of fixed duration
- `--no-whitelist` - Disable whitelist checking
- `--no-blacklist` - Disable blacklist checking
- `--no-anomaly` - Disable anomaly detection
- `--no-cancel` - Don't cancel pipeline on violations

**Example:**
```bash
flodviddar scan 120 --custom-whitelist baseline.json --output report
```

### watch

Continuous monitoring with periodic violation checks.

```bash
flodviddar watch <poll_interval> [OPTIONS]
```

Monitors traffic continuously and checks for violations every N seconds.

**Example:**
```bash
flodviddar watch 30 --custom-whitelist whitelist.json
```

### create-whitelist

Generate a whitelist from observed traffic.

```bash
flodviddar create-whitelist <seconds> <augment> --file <path>
```

**Parameters:**
- `seconds` - Capture duration
- `augment` - `true` to merge with existing, `false` to create new
- `--file` - Output path for whitelist JSON

**Example:**
```bash
# Create baseline
flodviddar create-whitelist 120 false --file whitelist.json

# Augment existing
flodviddar create-whitelist 60 true --file whitelist.json
```

### halt

Manually cancel the current CI pipeline.

```bash
flodviddar halt "reason"
```

Detects GitHub Actions or GitLab CI environment and calls the appropriate API. Supports external cancellation scripts via `FLODVIDDAR_CANCEL_SCRIPT` environment variable.

**Cancellation Script:**

Create a script at `$HOME/cancel_pipeline.sh` (or custom path via `FLODVIDDAR_CANCEL_SCRIPT`) to handle pipeline cancellation. Flodviddar will execute this script instead of using built-in logic.

```bash
# Create cancellation script
./scripts/create_cancel_script.sh

# Or manually
export FLODVIDDAR_CANCEL_SCRIPT=/path/to/custom_script.sh
```

The script receives the violation reason as `$1` and should handle cancellation based on detected CI environment.

## CI/CD Integration

### GitHub Actions

#### Basic Integration

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Flodviddar
        run: |
          sudo apt-get install -y libpcap-dev
          cargo build --release
      
      - name: Start monitoring
        run: |
          sudo ./target/release/flodviddar scan 300 \
            --custom-whitelist whitelist.json \
            --output report > violations.json 2>&1 &
          sleep 5
      
      - name: Build application
        run: npm install && npm test
      
      - name: Check violations
        run: |
          if [[ $(jq 'length' violations.json) -gt 0 ]]; then
            jq . violations.json
            exit 1
          fi
```

#### With Pipeline Cancellation

For real-time cancellation when violations are detected:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      actions: write  # Required for gh run cancel
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Flodviddar
        run: |
          sudo apt-get install -y libpcap-dev
          cargo build --release
      
      - name: Create cancellation script
        run: ./scripts/create_cancel_script.sh
      
      - name: Start watch daemon
        run: |
          export FLODVIDDAR_CANCEL_SCRIPT="$HOME/cancel_pipeline.sh"
          sudo -E ./target/release/flodviddar watch 10 \
            --custom-whitelist whitelist.json \
            > watch.log 2>&1 &
          sleep 5
      
      - name: Build application
        run: npm install && npm test
      
      # If violations occur, workflow will be cancelled before reaching here
```

### GitLab CI

```yaml
test:
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y libpcap-dev build-essential
    - cargo build --release
  script:
    - ./target/release/flodviddar scan 300 --custom-whitelist whitelist.json &
    - npm install && npm test
    - wait
```

See `examples/` for complete integration templates.

## Whitelist System

Flodviddar uses the same whitelist format as EDAMAME Posture, enabling interoperability between open-source and proprietary tools.

### Whitelist Structure

```json
{
  "date": "December 13th 2025",
  "whitelists": [{
    "name": "custom_whitelist",
    "endpoints": [
      {
        "domain": "api.github.com",
        "port": 443,
        "protocol": "TCP"
      },
      {
        "domain": "registry.npmjs.org",
        "port": 443,
        "protocol": "TCP"
      }
    ]
  }]
}
```

### Matching Hierarchy

Endpoints are matched in priority order:

1. **Protocol/Port/Process** (if specified) - Must match
2. **Domain** (if specified) - Highest priority
3. **IP/CIDR** (if specified) - Medium priority
4. **ASN** (if specified) - Lowest priority

### Wildcard Support

- **Prefix:** `*.example.com` - Matches subdomains only
- **Suffix:** `example.*` - Matches all TLDs
- **Middle:** `api.*.example.com` - Matches one segment

### CDN Handling

Flodviddar automatically handles CDN providers (Cloudflare, Fastly, AWS, Google, etc.) by requiring domain resolution. This prevents IP-based whitelisting that would allow all traffic through that CDN.

## Testing

Run the complete test suite:

```bash
make test
```

Individual tests:

```bash
sudo ./tests/test_cve_2025_30066.sh        # CVE detection
sudo ./tests/test_whitelist_lifecycle.sh   # Lifecycle management
sudo ./tests/test_watch_daemon.sh          # Real-time monitoring
```

## Architecture

Flodviddar is built on [Flodbadd](https://github.com/edamametechnologies/flodbadd), the network visibility engine that powers EDAMAME's packet capture capabilities.

**Core components:**
- **Packet capture** - libpcap-based traffic inspection
- **Session tracking** - Connection state management
- **Whitelist engine** - L3-L7 policy enforcement with CDN awareness
- **Blacklist engine** - Threat intelligence integration
- **Anomaly detection** - ML-based behavioral analysis
- **CI integration** - GitHub Actions and GitLab CI support

**Design principles:**
- Egress-only evaluation (outbound traffic only)
- Incremental recomputation for performance
- Lock-free coordination where possible
- Automatic whitelist factorization for stability

See `ARCHITECTURE.md` for implementation details.

## Relation to EDAMAME Posture

Flodviddar provides a focused, open-source alternative to the network monitoring capabilities of [EDAMAME Posture](https://github.com/edamametechnologies/edamame_posture_cli). Both tools:

- Use the same Flodbadd library for packet capture
- Share the same whitelist/blacklist JSON format
- Provide similar anomaly detection
- Support CI/CD pipeline integration

**Key differences:**

| Aspect | Flodviddar | EDAMAME Posture |
|--------|-----------|-----------------|
| **License** | MIT (open source) | Proprietary |
| **Scope** | Network monitoring only | Complete security posture |
| **Integration** | Pure bash scripts | GitHub Action + CLI |
| **Features** | Traffic monitoring, whitelists | 200+ security checks, auto-remediation |
| **Management** | Local only | Optional EDAMAME Hub integration |

**When to use Flodviddar:**
- You need open-source network monitoring
- You want maximum flexibility with bash integration
- You only need supply chain attack detection
- You prefer local-only operation

**When to use EDAMAME Posture:**
- You need complete security posture assessment
- You want centralized policy management
- You require auto-remediation capabilities
- You need enterprise support

Both tools can be used together - Flodviddar for network monitoring in open-source projects, EDAMAME Posture for comprehensive security in enterprise environments.
Both tools can be used together—Flodviddar for network monitoring in open-source projects, and EDAMAME Posture for comprehensive security in enterprise environments.

## Use Cases

### Supply Chain Attack Detection

Protect against compromised dependencies like CVE-2025-30066 (tj-actions/changed-files):

```bash
# Create baseline from clean build
flodviddar create-whitelist 120 false --file baseline.json

# Enforce on every build
flodviddar scan 120 --custom-whitelist baseline.json --output report
```

### Zero-Trust CI/CD

Implement "deny by default" networking:

```bash
# Watch mode: immediate detection and cancellation
flodviddar watch 15 --custom-whitelist approved_services.json
```

### Compliance Auditing

Generate audit trails of network behavior:

```bash
flodviddar scan 300 --custom-whitelist policy.json --output report
```

## Requirements

**System:**
- Linux (Ubuntu 18.04+, Debian, Alpine)
- libpcap development headers
- Root/sudo privileges for packet capture

**Build:**
- Rust 1.70+
- cargo

**Runtime:**
- jq (for test scripts)
- bc (for stability calculations)

## Contributing

Contributions are welcome. Before submitting:

```bash
cargo fmt
cargo clippy
cargo test
sudo ./tests/run_all_tests.sh
```

See `CONTRIBUTING.md` for guidelines.

## License

Apache License 2.0 - see LICENSE file for details.

## Related Projects
**EDAMAME Ecosystem:**
- [EDAMAME Security](https://github.com/edamametechnologies/edamame_security) - Desktop security application
- [EDAMAME Posture](https://github.com/edamametechnologies/edamame_posture_cli) - CLI for complete security posture
- [EDAMAME Posture GitHub Action](https://github.com/edamametechnologies/edamame_posture_action) - GitHub Action wrapper
- [Flodbadd](https://github.com/edamametechnologies/flodbadd) - Network visibility library
- [Threat Models](https://github.com/edamametechnologies/threatmodels) - Security benchmarks database
- [EDAMAME Hub](https://hub.edamame.tech) - Centralized management platform**Support:**
- Flodviddar: GitHub issues
- EDAMAME Posture: [support@edamame.tech](mailto:support@edamame.tech)
