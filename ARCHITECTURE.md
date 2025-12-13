# Architecture

Flodviddar implementation and design decisions.

## Overview

```
Flodviddar CLI
    ↓
Flodbadd Library
    ↓
libpcap (packet capture)
```

Flodviddar is a thin CLI layer over Flodbadd, the network visibility engine shared with EDAMAME Posture.

## Whitelist Guards

The whitelist engine implements several guards to ensure reliable detection without false positives.

### Egress-Only Evaluation

Only outbound traffic is checked. Inbound connections are automatically marked as conforming.

**Implementation:** `flodbadd/src/whitelists.rs` lines 1497-1504

```rust
let is_egress = snapshot.is_self_src || 
                (snapshot.is_local_src && !snapshot.is_local_dst);
if !is_egress {
    evaluation_results.push((session_key.clone(), true, None));
    continue;
}
```

This prevents false positives from CI infrastructure making inbound connections to the runner.

### CDN Provider Handling

CDN IPs are shared across thousands of domains. Flodviddar requires domain resolution for CDN endpoints to prevent overly permissive whitelisting.

**Implementation:** `flodbadd/src/whitelists.rs` lines 234-295

**Supported CDNs:** Fastly, Cloudflare, Amazon/AWS, Google, Microsoft/Azure, Akamai

**Behavior:** Sessions to CDN IPs without resolved domains are skipped during whitelist generation. Only sessions with Forward DNS or SNI are whitelisted.

### Domain Resolution Types

Three types of domain resolution, in order of reliability:

1. **Forward DNS** - From captured DNS queries (most reliable)
2. **SNI** - From TLS ClientHello (reliable)
3. **Reverse DNS** - From PTR lookups (unreliable for CDNs)

Flodviddar prefers Forward DNS and SNI, avoiding reverse DNS patterns like `cdn-185-199-111-133.github.com`.

### Whitelist Factorization

Merges related endpoints to prevent whitelist instability.

**Example:**
```json
// Before
[
  {"domain": "github.com", "ip": "140.82.114.3", "port": 443},
  {"domain": "github.com", "ip": "140.82.114.4", "port": 443}
]

// After
[
  {"domain": "github.com", "ips": ["140.82.114.3", "140.82.114.4"], "port": 443}
]
```

This ensures whitelists stabilize despite CDN IP rotation.

### Incremental Recomputation

The whitelist engine only recomputes sessions that changed since the last run, reducing CPU overhead in watch mode.

**Full recompute triggers:**
- Whitelist model changed
- `NEED_FULL_RECOMPUTE_WHITELIST` flag set

**Incremental recompute:**
- Only sessions with `last_modified` after last run
- Only sessions in `Unknown` state

### Deduplication

Endpoints are fingerprinted by (domain, IP, port, protocol, ASN, process) to prevent duplicates.

## Data Flow

### Scan Command

```
1. Load whitelist → set_custom_whitelists()
2. Start capture → FlodbaddCapture::start()
3. Capture packets (duration)
4. Get sessions → get_sessions()
5. Check conformance → get_whitelist_conformance()
6. Output report or whitelist
```

### Create-Whitelist Command

```
1. Start capture → FlodbaddCapture::start()
2. Capture packets (duration)
3. Get sessions → get_sessions()
4. Generate whitelist → Whitelists::new_from_sessions()
   - Apply CDN guard
   - Apply domain resolution filter
   - Deduplicate
5. If augment: merge with existing
6. Factorize → factorize_whitelist()
7. Write JSON
```

### Watch Command

```
1. Load whitelist
2. Start capture
3. Every N seconds:
   - Recompute whitelist (incremental)
   - Check conformance
   - If violations: halt_ci_pipeline()
```

## Performance

**Typical overhead:**
- Packet capture: <1% CPU
- Whitelist checking: <0.01% per session
- Full recompute: <5% CPU
- Memory: ~50MB base + ~500 bytes per session

**Optimization techniques:**
- Lock-free atomics for coordination
- Snapshot-based evaluation (release locks during work)
- Single-flight pattern for cache population
- Incremental recomputation

## Comparison with EDAMAME Posture

**Flodviddar:** Direct library calls
```
CLI → Flodbadd → libpcap
```

**EDAMAME Posture:** RPC-based daemon
```
CLI → tarpc RPC → edamame_core → Flodbadd → libpcap
```

The RPC layer in EDAMAME Posture enables:
- Daemon mode with multiple clients
- EDAMAME Hub integration
- Additional security features

Flodviddar trades these for simplicity and transparency.

## Design Decisions

**Why no daemon mode in Flodviddar?**
Simplicity. The `watch` command provides continuous monitoring without the complexity of RPC.

**Why bash for CI integration?**
Portability. Bash scripts work everywhere without platform-specific actions.

**Why separate from EDAMAME Posture?**
Focus. Flodviddar does one thing (network monitoring) and does it well. EDAMAME Posture provides comprehensive security posture management.

## Extension Points

Want to add features? Key areas:

**New CI platforms:**
Update `halt_ci_pipeline()` in `src/main.rs`

**Custom output formats:**
Add to `--output` handling in `scan` command

**Process-based matching:**
Add `--include-process` flag, call `create_custom_whitelists_with_process()`

## Related Documentation

- `README.md` - User documentation
- `COMPARISON.md` - vs EDAMAME Posture
- `TESTING.md` - Test suite details
- [Flodbadd README](https://github.com/edamametechnologies/flodbadd) - Library documentation
