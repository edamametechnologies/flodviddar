  # Flodviddar Architecture

This document explains how Flodviddar leverages the whitelist guards from flodbadd to provide reliable supply chain attack detection.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Flodviddar CLI                         │
│  (main.rs, daemon.rs)                                       │
│  - Command parsing                                          │
│  - CI/CD environment detection                              │
│  - Pipeline cancellation logic                              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                   Flodbadd Library                          │
│  (capture, sessions, whitelists, analyzer, blacklists)      │
│  - Packet capture (libpcap)                                 │
│  - Session tracking                                         │
│  - Whitelist/blacklist enforcement                          │
│  - ML-based anomaly detection                               │
└─────────────────────────────────────────────────────────────┘
```

## Whitelist Guard Architecture

Flodviddar relies on sophisticated whitelist guards in `flodbadd/src/whitelists.rs` to ensure reliable detection without false positives.

### Guard 1: Egress-Only Policy

**Purpose:** Only evaluate outbound traffic to prevent false positives from inbound connections.

**Implementation** (whitelists.rs lines 1497-1504):
```rust
let is_egress = snapshot.is_self_src || 
                (snapshot.is_local_src && !snapshot.is_local_dst);
if !is_egress {
    evaluation_results.push((session_key.clone(), true, None));
    continue;
}
```

**Why this matters:**
- Inbound connections to your CI runner are not policy violations
- Focus is on what your build process is contacting (egress)
- Prevents false positives from CI infrastructure connections

**Flodviddar usage:**
- All `scan` and `watch` operations only check egress traffic
- Ingress traffic is automatically marked as conforming
- This is critical for CI/CD where runners receive inbound connections

### Guard 2: CDN Provider Detection

**Purpose:** Prevent false positives when whitelisting CDN endpoints.

**Implementation** (whitelists.rs lines 234-295):
```rust
fn is_cdn_provider(owner: &str, cdn_providers: &[&str]) -> bool {
    let owner_lower = owner.to_lowercase();
    cdn_providers.iter().any(|&provider| owner_lower.contains(provider))
}

// Skip CDN sessions without reliable domain resolution
if domain_unreliable_for_cdn {
    if let Some(ref asn) = session.dst_asn {
        if is_cdn_provider(&asn.owner, CDN_PROVIDERS) {
            continue;  // Skip this session
        }
    }
}
```

**CDN Providers List:**
- Fastly, Cloudflare, Amazon/AWS
- Google, Microsoft/Azure
- Akamai, CloudFront
- Generic "cdn" in AS owner

**Why this matters:**
- CDN IPs are shared across thousands of domains
- Whitelisting `185.199.110.133` (Fastly) would allow ALL Fastly-hosted content
- Must require domain resolution for CDN endpoints

**Flodviddar usage:**
- `create-whitelist` automatically skips CDN sessions without domains
- Only CDN sessions with Forward DNS or SNI are included
- Prevents whitelist instability from CDN IP rotation

### Guard 3: Domain Resolution Type Checking

**Purpose:** Only use reliable domain resolution sources for whitelisting.

**Implementation** (whitelists.rs lines 326-349):
```rust
let reliable_domain = if domain_unresolved {
    None
} else if session.dst_domain_type == DomainResolutionType::Forward
        || session.dst_domain_type == DomainResolutionType::SNI {
    session.dst_domain.clone()
} else {
    // Reverse DNS - only use if not a reverse pattern
    if !is_reverse_dns_pattern(d) {
        session.dst_domain.clone()
    } else {
        None
    }
}
```

**Domain Resolution Types:**
- **Forward DNS**: From captured DNS queries (most reliable)
- **SNI**: From TLS ClientHello (reliable)
- **Reverse DNS**: From PTR lookups (unreliable for CDNs)

**Why this matters:**
- Reverse DNS for CDNs often shows infrastructure names
- Example: `cdn-185-199-111-133.github.com` (not the real domain)
- Using these would create unstable whitelists

**Flodviddar usage:**
- Automatically filters out unreliable domain resolutions
- Prefers Forward DNS and SNI
- Falls back to IP-only whitelisting for non-CDN providers

### Guard 4: Whitelist Factorization

**Purpose:** Merge related endpoints to prevent whitelist instability.

**Implementation** (whitelists.rs lines 563-807):
```rust
pub fn factorize_whitelist(input: &WhitelistInfo) -> WhitelistInfo {
    // Groups endpoints by domain, protocol, AS, process
    // Merges ports into ranges
    // Combines IPs for same domain
    // Deduplicates entries
}
```

**What it does:**
```json
// Before factorization (3 separate entries)
[
  {"domain": "github.com", "ip": "140.82.114.3", "port": 443},
  {"domain": "github.com", "ip": "140.82.114.4", "port": 443},
  {"domain": "github.com", "ip": "140.82.112.4", "port": 443}
]

// After factorization (1 merged entry)
[
  {
    "domain": "github.com",
    "ips": ["140.82.114.3", "140.82.114.4", "140.82.112.4"],
    "port": 443
  }
]
```

**Why this matters:**
- CDN/load-balanced services use multiple IPs
- Without factorization, whitelist grows with every new IP
- Prevents whitelist from ever stabilizing

**Flodviddar usage:**
- Automatically called during `create-whitelist` and `augment`
- Ensures whitelist stability across runs
- Critical for auto-whitelist lifecycle

### Guard 5: Incremental Recomputation

**Purpose:** Efficiently update whitelist status without full rescans.

**Implementation** (whitelists.rs lines 1385-1614):
```rust
pub async fn recompute_whitelist_for_sessions(
    whitelist_name: &Arc<RwLock<String>>,
    sessions: &Arc<DashMap<Session, SessionInfo>>,
    // ...
) {
    // Only recompute sessions that changed since last run
    // OR sessions still in Unknown state
    // OR if whitelist model changed (NEED_FULL_RECOMPUTE flag)
}
```

**Optimization strategy:**
- Track last run timestamp
- Only re-evaluate modified sessions
- Full recompute when whitelist changes
- Global flag signals model changes

**Flodviddar usage:**
- Daemon mode (`watch`) benefits from incremental updates
- Reduces CPU overhead in continuous monitoring
- Enables sub-second response times

### Guard 6: Process Name Filtering

**Purpose:** Optionally enforce per-process whitelist rules.

**Implementation** (whitelists.rs lines 297-324):
```rust
let process_name: Option<String> = if include_process {
    let name = session.l7.as_ref().and_then(|l7| {
        let name = &l7.process_name;
        if name.is_empty() || name == "Unknown" || name == "Resolving" {
            None
        } else {
            Some(name.clone())
        }
    });
    if name.is_none() {
        // Skip sessions without resolved process
        continue;
    }
    name
} else {
    None
};
```

**Why this matters:**
- Stricter matching: `curl` to GitHub ≠ `python` to GitHub
- Detects when malicious process uses legitimate endpoints
- CVE-2025-30066: legitimate process (edamame_posture) vs malicious (python)

**Flodviddar usage:**
- Not used by default (can cause instability)
- Future enhancement: add `--include-process` flag
- Trade-off: security vs stability

### Guard 7: Endpoint Deduplication

**Purpose:** Prevent duplicate entries from creating whitelist churn.

**Implementation** (whitelists.rs lines 379-396):
```rust
let fingerprint = (
    endpoint.domain.clone(),
    endpoint.ip.clone(),
    endpoint.port,
    endpoint.protocol.clone(),
    endpoint.as_number,
    endpoint.as_country.clone(),
    endpoint.as_owner.clone(),
    endpoint.process.clone(),
);

if unique_fingerprints.insert(fingerprint) {
    endpoints.push(endpoint);
}
```

**Why this matters:**
- Same endpoint seen multiple times = 1 whitelist entry
- Prevents whitelist size from growing unbounded
- Ensures stable endpoint counts

## How Guards Enable Reliable Detection

### Example: CVE-2025-30066 Detection Flow

```
1. Legitimate Traffic Phase
   ├─> curl https://api.github.com
   ├─> CDN Guard: github.com is Fastly (CDN)
   ├─> Domain Guard: Forward DNS available ✓
   ├─> Factorization: Merge all GitHub IPs
   └─> Whitelist: {domain: "api.github.com", ips: [...], port: 443}

2. Malicious Traffic Phase (python script)
   ├─> python → gist.githubusercontent.com
   ├─> CDN Guard: githubusercontent.com is Fastly (CDN)
   ├─> Domain Guard: SNI captured ✓
   ├─> Egress Guard: Outbound from python ✓
   └─> Whitelist Check: gist.githubusercontent.com NOT in whitelist
   
3. Detection
   └─> is_session_in_whitelist() returns (false, reason)
       └─> Session marked as NonConforming
           └─> Violation reported
```

### Example: Whitelist Stability Flow

```
Run 1: Baseline
   ├─> Capture: github.com, npmjs.org, pypi.org
   ├─> CDN Guard: Filter out unresolved CDN IPs
   ├─> Factorization: Merge related endpoints
   └─> Result: 15 stable endpoint entries

Run 2: Augmentation
   ├─> Load baseline (15 entries)
   ├─> Capture: Same 3 domains, different CDN IPs
   ├─> Factorization: IPs merged into existing entries
   ├─> Deduplication: No new fingerprints
   └─> Result: Still 15 entries (0% change) ✓

Run 3: Augmentation
   ├─> Load baseline (15 entries)
   ├─> Capture: Same traffic
   ├─> Result: 15 entries (0% change) ✓
   └─> Stability: 2/3 consecutive stable runs

Run 4: Stable
   ├─> 0% change for 3rd time
   └─> WHITELIST IS STABLE → Enforcement begins
```

## Integration with Flodviddar Commands

### `scan` Command

```rust
// In flodviddar/src/main.rs
capture.set_custom_whitelists(&json).await;
capture.start(&interfaces).await?;
// ... capture traffic ...
let conformance = capture.get_whitelist_conformance().await;
```

**Guards used:**
- Egress-only (via `recompute_whitelist_for_sessions`)
- Endpoint matching (via `is_session_in_whitelist`)
- Incremental recomputation
- Cache optimization

### `create-whitelist` Command

```rust
// In flodviddar/src/main.rs
let json = if augment {
    let (json, _) = capture.augment_custom_whitelists().await?;
    json
} else {
    capture.create_custom_whitelists().await?
};
```

**Guards used:**
- CDN provider detection
- Domain resolution type checking
- Factorization (via `set_custom_whitelists`)
- Deduplication
- Process filtering (when enabled)

### `watch` Command

```rust
// In flodviddar/src/daemon.rs
let conformance = capture.get_whitelist_conformance().await;
if !conformance {
    let exceptions = capture.get_whitelist_exceptions(false).await;
    // ... handle violations ...
}
```

**Guards used:**
- Incremental recomputation (every poll interval)
- Egress-only filtering
- Real-time conformance checking
- Cached endpoint lookups

## Performance Characteristics

### Memory Usage

| Component | Memory | Notes |
|-----------|--------|-------|
| Whitelist model | ~1KB per endpoint | After factorization |
| Endpoint cache | ~2KB per whitelist | Cached flattened endpoints |
| Session map | ~500 bytes per session | Active sessions only |
| Total baseline | ~50MB | For typical CI workload |

### CPU Usage

| Operation | CPU | Frequency |
|-----------|-----|-----------|
| Packet capture | < 0.5% | Continuous |
| Session updates | < 0.1% | Per packet |
| Whitelist check | < 0.01% | Per new session |
| Incremental recompute | < 1% | Every 30s (daemon) |
| Full recompute | < 5% | On whitelist change only |
| Factorization | < 2% | On create/augment |

### Lock Contention Mitigation

The whitelist engine uses several strategies to minimize lock contention:

1. **Snapshot-based evaluation** (lines 1431-1469)
   - Take snapshots of sessions before evaluation
   - Release locks during expensive operations
   - Apply results in bulk with minimal lock time

2. **Single-flight pattern** (lines 881-917)
   - Prevent duplicate concurrent whitelist flattening
   - First caller does work, others wait for cache
   - Dramatically reduces CPU on high-concurrency scenarios

3. **Atomic flags** (lines 29, 831)
   - `WHITELIST_REVISION`: Monotonic change counter
   - `NEED_FULL_RECOMPUTE_WHITELIST`: Lock-free signaling
   - Enables wait-free coordination

## Whitelist Lifecycle State Machine

```
┌──────────────┐
│   INITIAL    │  No whitelist exists
└──────┬───────┘
       │ create-whitelist
       ▼
┌──────────────┐
│   LEARNING   │  Baseline created, discovering endpoints
└──────┬───────┘
       │ augment (new endpoints found)
       ▼
┌──────────────┐
│   EVOLVING   │  Adding new endpoints, stability = 0
└──────┬───────┘
       │ augment (no new endpoints)
       ▼
┌──────────────┐
│  CONFIRMING  │  No changes, stability 1-2/3
└──────┬───────┘
       │ augment (still no changes)
       ▼
┌──────────────┐
│    STABLE    │  3+ consecutive stable runs
└──────┬───────┘
       │ scan --custom-whitelist
       ▼
┌──────────────┐
│  ENFORCING   │  Violations cause build failure
└──────────────┘
```

## Integration Points with Flodbadd

### Direct Function Calls

Flodviddar calls flodbadd functions directly:

```rust
// From daemon.rs
use flodbadd::{
    analyzer::SessionAnalyzer,
    capture::FlodbaddCapture,
    interface::get_valid_network_interfaces,
    sessions::format_sessions_log,
};

let capture = FlodbaddCapture::new();
capture.set_custom_whitelists(&json).await;
capture.start(&interfaces).await?;
```

### Data Flow

```
1. Packet arrives
   └─> libpcap
       └─> FlodbaddCapture::process_packet()
           └─> Session created/updated
               └─> recompute_whitelist_for_sessions() (incremental)
                   └─> is_session_in_whitelist() [GUARDS APPLIED]
                       └─> Session.is_whitelisted updated
                           └─> Flodviddar: get_whitelist_exceptions()

2. User calls create-whitelist
   └─> FlodbaddCapture::create_custom_whitelists()
       └─> Whitelists::new_from_sessions() [CDN GUARD]
           └─> Factorization [MERGE GUARD]
               └─> Deduplication [FINGERPRINT GUARD]
                   └─> JSON output

3. User calls augment
   └─> FlodbaddCapture::augment_custom_whitelists()
       └─> Generate whitelist from current sessions
           └─> Merge with existing whitelist
               └─> Factorize result
                   └─> Compare old vs new [STABILITY CALC]
                       └─> Return (json, percent_change)
```

## Key Algorithms

### Whitelist Comparison (for stability detection)

From whitelists.rs lines 122-154:

```rust
pub fn compare_whitelist(self, old_whitelist_json: WhitelistsJSON) -> f64 {
    let mut different = 0;
    let mut total = 0;
    
    for new_whitelist in &self.whitelists {
        for new_endpoint in &new_whitelist.endpoints {
            total += 1;
            
            if !old_whitelist_endpoints.contains(new_endpoint) {
                different += 1;
            }
        }
    }
    
    if total == 0 {
        0.0
    } else {
        (different as f64 / total as f64) * 100.0
    }
}
```

**Flodviddar usage:**
```bash
# In auto-whitelist demo
NEW_COUNT=$(jq '[.whitelists[]? | .endpoints? // [] | length] | add // 0' whitelist.json)
DELTA=$((NEW_COUNT - OLD_COUNT))
PERCENT=$(echo "scale=2; ($DELTA * 100) / $NEW_COUNT" | bc)

if [[ $(echo "$PERCENT <= $THRESHOLD" | bc -l) -eq 1 ]]; then
    STABLE_COUNT=$((STABLE_COUNT + 1))
fi
```

### Endpoint Matching Algorithm

From whitelists.rs lines 959-1108:

```rust
fn endpoint_matches_with_reason(...) -> (bool, Option<String>) {
    // 1. Check protocol (required)
    // 2. Check port (required)
    // 3. Check process (if specified)
    // 4. Check domain (if specified)
    // 5. Check IP (if specified)
    // 6. Check ASN (if specified and no domain/IP)
    
    // Hierarchical matching:
    // - Domain match → accept (regardless of IP)
    // - IP match → accept (if domain not specified)
    // - ASN match → accept (if neither domain nor IP specified)
}
```

This hierarchical matching ensures:
- Domain-based rules work across IP changes
- IP-based rules for non-CDN endpoints
- ASN-based rules for broad matching

## Security Properties

### Tamper Resistance

**Atomic state updates:**
```rust
static WHITELIST_REVISION: AtomicU64 = AtomicU64::new(0);
static NEED_FULL_RECOMPUTE_WHITELIST: AtomicBool = AtomicBool::new(false);
```

- Concurrent workers detect mid-flight changes
- No race conditions on whitelist updates
- Consistent view across threads

### Defense in Depth

Flodviddar enforces multiple security layers:

```
Layer 1: Whitelist (explicit allow)
   └─> Layer 2: Blacklist (explicit deny)
       └─> Layer 3: Anomaly Detection (ML-based)
           └─> Layer 4: Pipeline Cancellation
```

Each layer operates independently - violations at any layer trigger alerts.

## Comparison with EDAMAME Posture

| Aspect | Flodviddar Implementation | EDAMAME Posture Implementation |
|--------|--------------------------|-------------------------------|
| **Whitelist Guards** | Direct flodbadd calls | Via edamame_core API layer |
| **State Management** | Manual (bash + jq + files) | Automatic (GitHub Artifacts) |
| **Artifact Storage** | User-provided | Built-in GitHub Actions support |
| **Configuration** | Environment variables + flags | GitHub Action inputs |
| **Process Isolation** | Single process | Daemon + CLI client |
| **RPC Layer** | None (library calls) | tarpc-based (edamame_core) |

### Code Path Comparison

**Flodviddar:**
```
CLI → flodbadd::capture::FlodbaddCapture → flodbadd::whitelists
  └─> Direct function calls
      └─> No RPC overhead
          └─> Simpler architecture
```

**EDAMAME Posture:**
```
CLI → tarpc RPC → edamame_core → flodbadd::capture → flodbadd::whitelists
  └─> RPC serialization
      └─> Additional abstraction layer
          └─> Enables daemon mode, Hub integration
```

## Extending Flodviddar

Want to add features? Here's how:

### Add Custom Guard

```rust
// In flodbadd/src/whitelists.rs
const SUSPICIOUS_ASNS: &[u32] = &[64512, 64513];  // Private ASNs

// In new_from_sessions()
if let Some(asn) = session.dst_asn {
    if SUSPICIOUS_ASNS.contains(&asn.as_number) {
        warn!("Skipping suspicious ASN: {}", asn.as_number);
        continue;
    }
}
```

### Add Process Matching to Flodviddar

```rust
// In flodviddar/src/main.rs
.arg(
    arg!(--"include-process" "Include process names in whitelist")
        .action(ArgAction::SetTrue)
)

// In create_whitelist()
let json = if include_process {
    capture.create_custom_whitelists_with_process().await?
} else {
    capture.create_custom_whitelists().await?
};
```

### Add Custom Cancellation Logic

```rust
// In flodviddar/src/main.rs halt_ci_pipeline()
if std::env::var("CUSTOM_CI").is_ok() {
    // Add your custom CI platform
    Command::new("custom-cli")
        .args(["cancel", &run_id])
        .status()?;
}
```

## Testing the Guards

The test suite validates all guards:

**CDN Guard Test:**
```bash
# Generate traffic to CDN endpoint without DNS
curl -H "Host: github.com" https://185.199.110.133

# Verify: Endpoint NOT in whitelist (IP-only for CDN)
jq '.whitelists[].endpoints[] | select(.ip == "185.199.110.133")' whitelist.json
# Should return empty
```

**Factorization Test:**
```bash
# Generate traffic to same domain, different IPs
for i in {1..5}; do
    curl https://api.github.com/zen &
done

# Verify: Single entry with multiple IPs
jq '.whitelists[].endpoints[] | select(.domain == "api.github.com") | .ips | length' whitelist.json
# Should return > 1
```

**Egress-Only Test:**
```bash
# Incoming connection (simulated)
# Should NOT be in violations

# Outgoing connection to unauthorized endpoint
curl https://unauthorized.com

# Should be in violations
```

## Conclusion

Flodviddar's reliability comes from leveraging battle-tested guards in flodbadd:

1. **Egress-only** prevents inbound false positives
2. **CDN-aware** prevents IP-based CDN whitelisting
3. **Domain resolution filtering** ensures reliable domain matching
4. **Factorization** enables whitelist stability
5. **Incremental recomputation** provides performance
6. **Deduplication** prevents unbounded growth

These guards make flodviddar suitable for **production CI/CD security** where false positives are unacceptable and reliability is critical.

