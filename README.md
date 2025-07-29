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


