# Flodviddar vs EDAMAME Posture: Feature Comparison

This document compares **Flodviddar** (open-source) with **EDAMAME Posture** (proprietary) to help you choose the right tool for your needs.

## Quick Summary

| Aspect | Flodviddar | EDAMAME Posture |
|--------|-----------|-----------------|
| **License** | MIT (Open Source) | Proprietary |
| **Focus** | Network traffic monitoring | Complete security posture |
| **Integration** | Pure bash scripts | GitHub Action + CLI |
| **Authentication** | None required | Optional (Hub integration) |
| **Best For** | CI/CD network security | Enterprise security management |

## Detailed Feature Comparison

### Network Traffic Monitoring

| Feature | Flodviddar | EDAMAME Posture | Notes |
|---------|-----------|-----------------|-------|
| Packet capture | ✓ | ✓ | Both use libpcap/flodbadd |
| Custom whitelists | ✓ | ✓ | Same JSON format |
| Whitelist lifecycle | ✓ Manual | ✓ Automated | EDAMAME has auto-whitelist mode |
| Blacklist enforcement | ✓ | ✓ | Both use same threat DB |
| Anomaly detection | ✓ | ✓ | Both use ML-based detection |
| Real-time monitoring | ✓ (`watch`) | ✓ (daemon) | Similar capabilities |
| Pipeline cancellation | ✓ | ✓ | Both support GitHub/GitLab |
| L7/Process matching | ✓ | ✓ | Full L3-L7 support |
| CDN-aware whitelisting | ✓ | ✓ | Prevents false positives |

### Security Posture Assessment

| Feature | Flodviddar | EDAMAME Posture |
|---------|-----------|-----------------|
| Security score | - | ✓ |
| Threat detection | - | ✓ |
| Auto-remediation | - | ✓ |
| LAN scanning | - | ✓ |
| Device profiling | - | ✓ |
| Vulnerability assessment | - | ✓ |
| Policy compliance | - | ✓ |

### CI/CD Integration

| Feature | Flodviddar | EDAMAME Posture |
|---------|-----------|-----------------|
| GitHub Actions | ✓ Examples | ✓ Official Action |
| GitLab CI | ✓ Examples | ✓ Official Integration |
| Jenkins | ✓ Bash scripts | ✓ Via CLI |
| Generic CI | ✓ Bash scripts | ✓ Via CLI |
| Artifact management | Manual | Automatic |
| Disconnected mode | ✓ (always) | ✓ (optional) |

### Management & Reporting

| Feature | Flodviddar | EDAMAME Posture |
|---------|-----------|-----------------|
| Web dashboard | - | ✓ (EDAMAME Hub) |
| Email reports | - | ✓ |
| Centralized policy | - | ✓ |
| Multi-device management | - | ✓ |
| Historical tracking | - | ✓ |
| AI assistant | - | ✓ (Claude/OpenAI/Ollama) |

### Advanced Features

| Feature | Flodviddar | EDAMAME Posture |
|---------|-----------|-----------------|
| Whitelist factorization | ✓ | ✓ |
| Process-based rules | ✓ | ✓ |
| ASN-based rules | ✓ | ✓ |
| Port range support | ✓ | ✓ |
| Domain wildcards | ✓ | ✓ |
| CIDR notation | ✓ | ✓ |
| Session dismissal | - | ✓ |
| Custom blacklists | ✓ | ✓ |

## Use Case Comparison

### Use Case 1: Basic CI/CD Network Security

**Scenario:** You want to detect unauthorized network connections in your build pipeline.

**Flodviddar:**
```bash
# Simple and straightforward
sudo flodviddar scan 120 --output report
```
✓ Perfect fit - minimal setup, no authentication needed

**EDAMAME Posture:**
```bash
edamame_posture start --network-scan --packet-capture
# ... your build ...
edamame_posture get-sessions --fail-on-whitelist
```
✓ Also works well, but requires more setup

**Winner:** Flodviddar (simpler for this use case)

### Use Case 2: Enterprise CI/CD with Centralized Management

**Scenario:** Large organization needs centralized security policy enforcement across 100+ repositories.

**Flodviddar:**
- Each repo manages its own whitelist
- No central dashboard
- Manual policy enforcement
- Requires per-repo configuration

**EDAMAME Posture:**
- EDAMAME Hub provides centralized dashboard
- Policies defined once, enforced everywhere
- Automatic compliance reporting
- Single configuration for all repos

**Winner:** EDAMAME Posture (built for this)

### Use Case 3: Supply Chain Attack Prevention (CVE-2025-30066)

**Scenario:** Detect compromised dependencies attempting unauthorized connections.

**Flodviddar:**
```bash
# Create baseline
sudo flodviddar create-whitelist 120 --file whitelist.json

# Enforce
sudo flodviddar scan 120 \
  --custom-whitelist whitelist.json \
  --output report
```
✓ Excellent - purpose-built for this

**EDAMAME Posture:**
```yaml
- uses: edamametechnologies/edamame_posture_action@v0
  with:
    network_scan: true
    whitelist: github_ubuntu
    exit_on_whitelist_exceptions: true
```
✓ Also excellent - more automated

**Winner:** Tie (both excellent, different approaches)

### Use Case 4: Complete Security Posture + Network Monitoring

**Scenario:** You need both network monitoring AND security posture assessment (encryption, firewall, patches, etc.).

**Flodviddar:**
- Only provides network monitoring
- No security posture features
- Would need additional tools

**EDAMAME Posture:**
- Complete security assessment
- 200+ security checks
- Auto-remediation
- Network monitoring included

**Winner:** EDAMAME Posture (only option)

## Integration Complexity

### Flodviddar Integration (Bash)

```bash
# Simple 3-command integration
sudo flodviddar create-whitelist 120 --file whitelist.json &
# ... your build ...
wait && sudo flodviddar scan 30 --custom-whitelist whitelist.json
```

**Pros:**
- Pure bash - works anywhere
- No external dependencies (beyond system libraries)
- Easy to understand and modify
- Self-contained

**Cons:**
- Manual artifact management
- No automatic lifecycle management
- Requires bash scripting knowledge

### EDAMAME Posture Integration (GitHub Action)

```yaml
- uses: edamametechnologies/edamame_posture_action@v0
  with:
    auto_whitelist: true
    network_scan: true
```

**Pros:**
- Fully automated lifecycle
- Built-in artifact management
- Declarative configuration
- Professional support

**Cons:**
- GitHub/GitLab specific
- Requires authentication for some features
- Less transparent (closed source)

## When to Choose Flodviddar

Choose **Flodviddar** if you:

✓ Want **open-source** with full code visibility  
✓ Need **simple bash integration** without platform lock-in  
✓ Only need **network traffic monitoring** (not full posture)  
✓ Prefer **manual control** over automation  
✓ Want to **avoid authentication** requirements  
✓ Are comfortable with **bash scripting**  
✓ Need to **customize** the security logic  
✓ Want **minimal dependencies**  

## When to Choose EDAMAME Posture

Choose **EDAMAME Posture** if you:

✓ Need **complete security posture** assessment  
✓ Want **automated whitelist lifecycle** management  
✓ Require **centralized management** (EDAMAME Hub)  
✓ Need **enterprise features** (reporting, policies, AI)  
✓ Prefer **GitHub Action** integration  
✓ Want **professional support**  
✓ Need **auto-remediation** of security issues  
✓ Manage **multiple teams/repos** centrally  

## Can You Use Both?

**Yes!** They complement each other:

### Pattern 1: Flodviddar for Network, EDAMAME for Posture

```yaml
# Check security posture
- uses: edamametechnologies/edamame_posture_action@v0
  with:
    auto_remediate: true
    network_scan: false

# Monitor network with Flodviddar
- name: Network monitoring
  run: |
    sudo flodviddar scan 120 \
      --custom-whitelist whitelist.json
```

### Pattern 2: Flodviddar in GitLab, EDAMAME in GitHub

Use Flodviddar for GitLab projects and EDAMAME Action for GitHub projects, with consistent security policies.

## Migration Path

### From Flodviddar to EDAMAME Posture

1. Your flodviddar whitelists work with EDAMAME (same JSON format)
2. Replace bash scripts with GitHub Action
3. Optionally enable Hub integration for centralization

```yaml
# Before (Flodviddar)
- run: sudo flodviddar scan 120 --custom-whitelist whitelist.json

# After (EDAMAME)
- uses: edamametechnologies/edamame_posture_action@v0
  with:
    custom_whitelists_path: whitelist.json
    set_custom_whitelists: true
```

### From EDAMAME Posture to Flodviddar

1. Extract whitelists from EDAMAME artifacts
2. Replace GitHub Action with bash scripts
3. Lose automated lifecycle (manage manually)

Not recommended unless you have specific requirements for open-source.

## Performance Comparison

| Metric | Flodviddar | EDAMAME Posture |
|--------|-----------|-----------------|
| Binary size | ~5MB | ~50MB (includes posture engine) |
| Memory usage | ~50MB | ~200MB (includes threat models) |
| CPU overhead | < 1% | < 5% (with posture scanning) |
| Startup time | < 1s | ~5s (initializes full core) |
| Network capture | Identical (same engine) | Identical (same engine) |

## Cost Comparison

### Flodviddar
- Software: **Free** (MIT license)
- Support: Community (GitHub issues)
- Updates: Manual (git pull && cargo build)
- Training: Self-service (documentation)

### EDAMAME Posture
- Software: **Free** for open-source projects
- Support: Professional (email, Slack)
- Updates: Automatic (package managers)
- Training: Documentation + professional support
- Hub: Optional subscription for enterprise features

## Conclusion

**Flodviddar** and **EDAMAME Posture** are complementary tools:

- **Flodviddar** = Pure network monitoring, open-source, bash-friendly
- **EDAMAME Posture** = Complete security platform, automated, enterprise-ready

For **most open-source projects** focusing on supply chain security: **Flodviddar is ideal**

For **enterprises** needing centralized management and complete posture: **EDAMAME Posture is better**

Both use the same underlying packet capture engine (flodbadd) and share whitelist formats, so you can:
- Start with Flodviddar (open, simple)
- Migrate to EDAMAME Posture later if needs grow
- Or use both in different contexts

## Getting Started

### Try Flodviddar
```bash
git clone https://github.com/yourusername/flodviddar
cd flodviddar
make test
```

### Try EDAMAME Posture
See: https://github.com/edamametechnologies/edamame_posture_action

### Questions?

- Flodviddar: Open a GitHub issue
- EDAMAME Posture: Contact support@edamame.tech

