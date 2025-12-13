# Flodviddar Quick Start Guide

Get started with Flodviddar in 5 minutes.

## 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y build-essential libpcap-dev jq bc python3-pip
pip3 install requests

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## 2. Build Flodviddar

```bash
git clone https://github.com/yourusername/flodviddar
cd flodviddar
make build

# Or manually
cargo build --release
```

## 3. Run Your First Scan

```bash
# Capture traffic for 30 seconds and generate a whitelist
sudo ./target/release/flodviddar create-whitelist 30 false --file whitelist.json

# During these 30 seconds, generate some traffic
# (in another terminal)
curl https://api.github.com/zen
curl https://github.com/robots.txt
```

## 4. View Your Whitelist

```bash
cat whitelist.json | jq .
```

You should see entries for GitHub endpoints.

## 5. Test Enforcement

```bash
# Run a scan with your whitelist
sudo ./target/release/flodviddar scan 20 \
  --custom-whitelist whitelist.json \
  --output report

# Generate traffic to an unauthorized endpoint
curl https://example.com  # This should be detected

# Check for violations
cat scan_report.json 2>/dev/null | jq .
```

## Next Steps

### Run the Test Suite

Verify everything works:

```bash
make test
```

### Integrate with Your CI

See [examples/](examples/) for integration templates:
- `github_actions.yml` - GitHub Actions workflow
- `gitlab_ci.yml` - GitLab CI pipeline
- `standalone_ci.sh` - Generic CI script

### Learn the Whitelist Lifecycle

The lifecycle test demonstrates best practices:

```bash
sudo ./tests/test_whitelist_lifecycle.sh
```

This shows:
1. Creating a baseline from legitimate traffic
2. Augmenting with new endpoints as dependencies change
3. Detecting when the whitelist is stable
4. Enforcing and detecting violations

### Test CVE Detection

See how Flodviddar detects supply chain attacks:

```bash
sudo ./tests/test_cve_2025_30066.sh
```

This simulates the CVE-2025-30066 attack vector and verifies detection.

## Common Patterns

### Pattern 1: Learning Mode (First Run)

```bash
# Start capture
sudo flodviddar create-whitelist 120 false --file whitelist.json &

# Run your build/test
npm install
npm run build
npm test

# Wait for capture to complete
wait

# Review generated whitelist
jq '.whitelists[0].endpoints | length' whitelist.json
```

### Pattern 2: Augmentation Mode (Adding Dependencies)

```bash
# Load existing whitelist and add new endpoints
sudo flodviddar create-whitelist 60 true --file whitelist.json &

# Run build with new dependencies
npm install new-package
npm test

wait
```

### Pattern 3: Enforcement Mode (Production)

```bash
# Fail build if violations detected
sudo flodviddar scan 120 \
  --custom-whitelist whitelist.json \
  --output report

if [[ $(jq 'length' violations.json 2>/dev/null || echo 0) -gt 0 ]]; then
  echo "Security violations detected!"
  jq . violations.json
  exit 1
fi
```

### Pattern 4: Watch Mode (Long-Running Pipelines)

```bash
# Start daemon (polls every 15 seconds)
sudo flodviddar watch 15 \
  --custom-whitelist whitelist.json &

WATCH_PID=$!

# Run long build/test
./long_running_build.sh

# Stop daemon
sudo kill -TERM $WATCH_PID
```

## Troubleshooting

### Problem: "Permission denied" on packet capture

**Solution:** Run with sudo or grant capabilities:
```bash
sudo setcap cap_net_raw,cap_net_admin=eip target/release/flodviddar
```

### Problem: No sessions captured

**Solutions:**
- Ensure network connectivity
- Check firewall rules
- Verify libpcap is installed: `dpkg -l | grep libpcap`
- Run with verbose logging: `flodviddar -vv scan 30`

### Problem: DNS resolution pending (domains show as "Unknown")

**This is normal!** Domain resolution happens asynchronously. The whitelist will:
- Include both IP and domain when available
- Fall back to IP-only matching if domain not resolved
- CDN providers are handled specially (require domain resolution)

### Problem: Whitelist grows too large

**Solutions:**
- Review and prune unused entries manually
- Use shorter capture durations
- Split whitelists by environment (dev/staging/prod)
- Consider process-based matching for stricter control

## Performance Notes

- Capture overhead: < 1% CPU on typical CI workloads
- Memory usage: ~50MB base + ~1KB per active session
- Disk usage: Whitelist JSON typically < 100KB for most projects
- Scan duration: Adjust based on your build time (typical: 120-300s)

## Security Considerations

- Flodviddar requires **root/sudo** for packet capture (libpcap requirement)
- Whitelists should be stored in version control or secure artifact storage
- Review whitelists periodically to remove stale entries
- Use process-based matching for high-security environments
- Combine with blacklist and anomaly detection for defense-in-depth

## Getting Help

- Check [tests/README.md](tests/README.md) for detailed test documentation
- Review [examples/](examples/) for CI integration patterns
- Read the main [README.md](README.md) for command reference
- Open an issue on GitHub for bugs or questions

