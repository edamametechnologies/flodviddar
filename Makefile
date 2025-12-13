.PHONY: help build test test-cve test-lifecycle test-watch install clean deps

help:
	@echo "Flodviddar Build & Test Targets"
	@echo "================================"
	@echo "build          - Build release binary"
	@echo "build-debug    - Build debug binary"
	@echo "test           - Run all integration tests"
	@echo "test-cve       - Run CVE-2025-30066 detection test"
	@echo "test-lifecycle - Run whitelist lifecycle test"
	@echo "test-watch     - Run watch daemon test"
	@echo "install        - Install to /usr/local/bin"
	@echo "deps           - Install system dependencies (Ubuntu/Debian)"
	@echo "clean          - Clean build artifacts"
	@echo ""
	@echo "Note: Tests require sudo for packet capture"

build:
	@echo "Building Flodviddar (release)..."
	cargo build --release
	@echo "Binary: target/release/flodviddar"

build-debug:
	@echo "Building Flodviddar (debug)..."
	cargo build
	@echo "Binary: target/debug/flodviddar"

deps:
	@echo "Installing system dependencies..."
	sudo apt-get update
	sudo apt-get install -y \
		build-essential \
		libpcap-dev \
		jq \
		bc \
		python3 \
		python3-pip
	pip3 install --user requests

test: build
	@echo "Running all integration tests..."
	sudo ./tests/run_all_tests.sh

test-cve: build
	@echo "Running CVE-2025-30066 detection test..."
	sudo ./tests/test_cve_2025_30066.sh

test-lifecycle: build
	@echo "Running whitelist lifecycle test..."
	sudo ./tests/test_whitelist_lifecycle.sh

test-watch: build
	@echo "Running watch daemon test..."
	sudo ./tests/test_watch_daemon.sh

install: build
	@echo "Installing Flodviddar to /usr/local/bin..."
	sudo cp target/release/flodviddar /usr/local/bin/
	@echo "Installation complete"
	@which flodviddar

clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -f whitelist.json
	rm -rf /tmp/flodviddar_*_test_*
	@echo "Clean complete"

# Development targets
dev: build-debug
	@echo "Development build ready"
	@echo "Run with: sudo ./target/debug/flodviddar --help"

check:
	cargo check

fmt:
	cargo fmt

clippy:
	cargo clippy -- -D warnings

# Quick test (no build)
test-quick:
	@echo "Running tests with existing binary..."
	sudo ./tests/run_all_tests.sh

# Lima VM targets for macOS testing
lima-create:
	@echo "Creating Lima VM for testing..."
	limactl create --name=flodviddar-test Lima.linux-test.yml

lima-start:
	@echo "Starting Lima VM..."
	limactl start flodviddar-test

lima-stop:
	@echo "Stopping Lima VM..."
	limactl stop flodviddar-test

lima-delete:
	@echo "Deleting Lima VM..."
	limactl delete flodviddar-test

lima-shell:
	@echo "Opening shell in Lima VM..."
	limactl shell flodviddar-test

lima-test:
	@echo "Running tests in Lima VM..."
	limactl shell flodviddar-test bash -c 'cd ~/Programming/flodviddar && source $$HOME/.cargo/env && make test'

lima-build:
	@echo "Building in Lima VM..."
	limactl shell flodviddar-test bash -c 'cd ~/Programming/flodviddar && source $$HOME/.cargo/env && cargo build --release'

lima-full-test:
	@echo "Running full test cycle in Lima VM..."
	limactl shell flodviddar-test bash -c 'cd ~/Programming/flodviddar && source $$HOME/.cargo/env && ./tests/verify_ebpf.sh && make test'

