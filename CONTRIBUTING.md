# Contributing

Contributions to Flodviddar are welcome.

## Development Setup

```bash
# Install dependencies
sudo apt-get install -y build-essential libpcap-dev jq bc python3-pip
pip3 install requests

# Clone and build
git clone https://github.com/edamametechnologies/flodviddar
cd flodviddar
cargo build --release
```

## Before Submitting

```bash
cargo fmt
cargo clippy
cargo test
sudo ./tests/run_all_tests.sh
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure tests pass
5. Submit PR with description of changes

## Code Standards

- Follow `rustfmt` formatting
- Pass `clippy` lints without warnings
- Add tests for new features
- Update documentation as needed

## Testing Requirements

All contributions must:
- Pass existing tests
- Add new tests for new features
- Not break backwards compatibility
- Include documentation updates

## Areas for Contribution

- macOS and Windows test support
- Additional CI platform integrations
- Performance optimizations
- Documentation improvements
- Bug fixes

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
