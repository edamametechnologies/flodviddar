# Quick Start Guide

Get Flodviddar running in 5 minutes.

## Installation

### Ubuntu/Debian

```bash
# System dependencies
sudo apt-get update
sudo apt-get install -y build-essential libpcap-dev

# Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Build Flodviddar
git clone https://github.com/edamametechnologies/flodviddar
cd flodviddar
cargo build --release
```

## First Scan

Create a baseline whitelist from your normal workflow:

```bash
# Start capture (runs for 30 seconds)
sudo ./target/release/flodviddar create-whitelist 30 false --file whitelist.json &

# Generate traffic in another terminal
curl https://api.github.com/zen
curl https://github.com/robots.txt

# Wait for capture to complete
wait
```

View the generated whitelist:

```bash
cat whitelist.json | jq .
```

## Enforce Whitelist

Test violation detection:

```bash
# Run scan with your baseline
sudo ./target/release/flodviddar scan 20 \
  --custom-whitelist whitelist.json \
  --output report > violations.json &

# Generate unauthorized traffic
sleep 3
curl https://example.com

# Check results
wait
jq . violations.json
```

## CI Integration

Basic GitHub Actions workflow:

```yaml
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      
      - name: Build Flodviddar
        run: |
          sudo apt-get install -y libpcap-dev
          cargo build --release
      
      - name: Monitor build
        run: |
          sudo ./target/release/flodviddar scan 300 \
            --custom-whitelist whitelist.json \
            --output report > violations.json 2>&1 &
          sleep 5
          npm install && npm test
          wait
          [[ $(jq 'length' violations.json) -eq 0 ]] || exit 1
```

## Next Steps

- Read `ARCHITECTURE.md` for implementation details
- Review `examples/` for complete CI templates
- Run test suite: `make test`
- Compare with EDAMAME Posture: `COMPARISON.md`
