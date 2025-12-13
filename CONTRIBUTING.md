# Contributing to Flodviddar

Thank you for your interest in contributing to Flodviddar!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/flodviddar`
3. Build and test: `make build && make test`
4. Create a feature branch: `git checkout -b feature/your-feature`

## Development Setup

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install -y \
    build-essential \
    libpcap-dev \
    jq \
    bc \
    python3-pip

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Python dependencies (for tests)
pip3 install requests
```

### Build

```bash
# Debug build (faster compilation)
make build-debug

# Release build (optimized)
make build

# Check for errors
make check

# Format code
make fmt

# Lint
make clippy
```

## Code Structure

```
src/
├── main.rs        # CLI entry point, command parsing
└── daemon.rs      # Watch daemon implementation

tests/
├── cli.rs         # Rust unit tests
├── test_*.sh      # Integration tests
└── run_all_tests.sh  # Test runner

examples/
├── *.yml          # CI integration examples
└── *.sh           # Bash integration scripts
```

## Adding Features

### Adding a New Command

1. Add to CLI builder in `src/main.rs`:

```rust
.subcommand(
    ClapCommand::new("your-command")
        .about("Description of your command")
        .arg(arg!(<PARAM> "Parameter description"))
)
```

2. Add handler in `main()`:

```rust
Some(("your-command", sub_matches)) => {
    let param = sub_matches.get_one::<String>("PARAM").unwrap();
    your_function(param).await?;
}
```

3. Implement function:

```rust
async fn your_function(param: &str) -> Result<()> {
    let capture = FlodbaddCapture::new();
    // ... your logic ...
    Ok(())
}
```

### Adding a Test

1. Create `tests/test_your_feature.sh`:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build
cargo build --release
FLODVIDDAR="$PROJECT_ROOT/target/release/flodviddar"

# Test
echo "Testing your feature..."
sudo $FLODVIDDAR your-command test-param

# Verify
if [[ $? -eq 0 ]]; then
    echo "TEST PASSED"
    exit 0
else
    echo "TEST FAILED"
    exit 1
fi
```

2. Add to `tests/run_all_tests.sh`:

```bash
if run_test "Your Feature" "$SCRIPT_DIR/test_your_feature.sh"; then
    ((passed++))
else
    ((failed++))
fi
```

3. Make executable: `chmod +x tests/test_your_feature.sh`

### Adding CI Platform Support

Want to support a new CI platform (e.g., CircleCI)?

1. Update `halt_ci_pipeline()` in `src/main.rs`:

```rust
else if std::env::var("CIRCLECI").is_ok() {
    // Add CircleCI cancellation logic
    let api_token = std::env::var("CIRCLE_TOKEN")?;
    // ... API call to cancel build ...
}
```

2. Add example in `examples/circleci.yml`

3. Test with CircleCI environment variables set

## Coding Standards

### Rust Code

- Follow `rustfmt` formatting: `make fmt`
- Pass `clippy` lints: `make clippy`
- Add doc comments for public functions
- Use `tracing` for logging (not `println!` except in output)

### Bash Scripts

- Use `#!/bin/bash` shebang
- Use `set -e` for fail-fast
- Add cleanup trap: `trap cleanup EXIT`
- Use meaningful variable names
- Add comments for complex logic
- Check syntax: `bash -n script.sh`

### Documentation

- Use Markdown for all docs
- Include code examples
- Add prerequisites sections
- Provide usage examples
- Keep lines under 100 characters when possible

## Testing Requirements

All contributions must:

✓ Pass existing tests: `make test`  
✓ Add new tests for new features  
✓ Not break backwards compatibility  
✓ Include documentation updates  

## Pull Request Process

1. **Before submitting:**
   ```bash
   make fmt
   make clippy
   make test
   ```

2. **PR description should include:**
   - What problem does this solve?
   - How does it solve it?
   - What tests were added?
   - Any breaking changes?

3. **PR checklist:**
   - [ ] Tests pass locally
   - [ ] Code is formatted (`make fmt`)
   - [ ] No clippy warnings
   - [ ] Documentation updated
   - [ ] Examples added (if applicable)
   - [ ] Breaking changes documented

## Areas for Contribution

### High Priority

- [ ] macOS and Windows test support
- [ ] Process-based whitelist matching CLI flag
- [ ] Whitelist diff/comparison CLI commands
- [ ] JSON output for all commands
- [ ] SARIF output format support

### Medium Priority

- [ ] Docker-based test environment
- [ ] Whitelist visualization tool
- [ ] Integration with more CI platforms
- [ ] Performance benchmarks
- [ ] Whitelist validation/linting

### Nice to Have

- [ ] Web UI for whitelist management
- [ ] Prometheus metrics export
- [ ] Syslog integration
- [ ] Email alerting
- [ ] Slack/Discord webhooks

## Code Review Guidelines

When reviewing PRs:

1. **Security first:** Does this introduce vulnerabilities?
2. **Performance:** Any significant overhead?
3. **Compatibility:** Does this break existing workflows?
4. **Tests:** Are new features tested?
5. **Documentation:** Is it well-documented?

## Questions?

- Open an issue for bugs
- Start a discussion for feature requests
- Tag @maintainers for urgent security issues

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

