# Flodviddar vs EDAMAME Posture

Comparison between Flodviddar (open-source) and EDAMAME Posture (proprietary).

## Summary

**Flodviddar:** Focused network monitoring tool for CI/CD pipelines. Detects supply chain attacks through whitelist enforcement, blacklist matching, and anomaly detection.

**EDAMAME Posture:** Complete security posture management platform with 200+ security checks, auto-remediation, network monitoring, and centralized management.

## Feature Matrix

| Feature | Flodviddar | EDAMAME Posture |
|---------|-----------|-----------------|
| **License** | MIT | Proprietary |
| **Packet capture** | ✓ | ✓ |
| **Custom whitelists** | ✓ | ✓ |
| **Blacklist enforcement** | ✓ | ✓ |
| **Anomaly detection** | ✓ | ✓ |
| **Pipeline cancellation** | ✓ | ✓ |
| **Security posture assessment** | - | ✓ |
| **Auto-remediation** | - | ✓ |
| **Centralized management** | - | ✓ (Hub) |
| **Automated whitelist lifecycle** | Manual | ✓ |
| **CI integration** | Bash scripts | GitHub Action |

## Integration Comparison

### Flodviddar (Bash)

```bash
# Simple 3-line integration
sudo flodviddar create-whitelist 120 --file whitelist.json &
npm install && npm test
wait && sudo flodviddar scan 30 --custom-whitelist whitelist.json
```

**Advantages:**
- Pure bash - works anywhere
- No external dependencies
- Easy to understand and modify
- Self-contained

### EDAMAME Posture (GitHub Action)

```yaml
- uses: edamametechnologies/edamame_posture_action@v0
  with:
    auto_whitelist: true
    network_scan: true
```

**Advantages:**
- Fully automated lifecycle
- Built-in artifact management
- Declarative configuration
- Professional support

## When to Choose

### Choose Flodviddar

- You need open-source with code visibility
- You want bash integration without platform lock-in
- You only need network monitoring
- You prefer manual control
- You want minimal dependencies

### Choose EDAMAME Posture

- You need complete security posture assessment
- You want automated whitelist lifecycle
- You require centralized management
- You need enterprise features
- You prefer GitHub Action integration

## Interoperability

Both tools use the same whitelist JSON format and share the underlying Flodbadd library, enabling:

- Migration paths in both directions
- Mixed usage (Flodviddar in GitLab, EDAMAME in GitHub)
- Shared whitelist files
- Consistent policy enforcement

## Links

- **Flodviddar:** https://github.com/edamametechnologies/flodviddar
- **EDAMAME Posture:** https://github.com/edamametechnologies/edamame_posture_cli
- **EDAMAME Hub:** https://hub.edamame.tech
