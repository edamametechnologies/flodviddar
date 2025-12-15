#!/bin/bash
# Example: Using Flodviddar with Pipeline Cancellation
# This script demonstrates how to set up cancellation on security violations

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLODVIDDAR="$PROJECT_ROOT/target/release/flodviddar"

echo "========================================"
echo "  Flodviddar Cancel on Violation Demo"
echo "========================================"
echo ""

# Step 1: Create cancellation script
echo "[1/4] Creating cancellation script..."
"$PROJECT_ROOT/scripts/create_cancel_script.sh"

echo ""

# Step 2: Create baseline whitelist
echo "[2/4] Creating baseline whitelist..."
cat > /tmp/demo_whitelist.json << 'EOF'
{
  "date": "December 13th 2025",
  "whitelists": [{
    "name": "custom_whitelist",
    "endpoints": [
      {"domain": "api.github.com", "port": 443, "protocol": "TCP"},
      {"domain": "github.com", "port": 443, "protocol": "TCP"}
    ]
  }]
}
EOF

echo "Whitelist created with GitHub endpoints only"

echo ""

# Step 3: Start watch daemon
echo "[3/4] Starting watch daemon..."
echo "The daemon will check for violations every 10 seconds"
echo "When a violation is detected, it will execute $HOME/cancel_pipeline.sh"

sudo -E "$FLODVIDDAR" watch 10 \
  --custom-whitelist /tmp/demo_whitelist.json \
  > /tmp/flodviddar_watch.log 2>&1 &

DAEMON_PID=$!
echo "Daemon started (PID: $DAEMON_PID)"

sleep 5

echo ""

# Step 4: Generate violation
echo "[4/4] Generating test violation..."
echo "Connecting to example.com (not in whitelist)..."

curl -s --max-time 5 https://example.com > /dev/null || true

echo "Violation generated. Daemon will detect it within 10-30 seconds."
echo ""
echo "In a real CI environment, the cancellation script would:"
echo "  1. Detect the violation"
echo "  2. Execute cancel_pipeline.sh"
echo "  3. Call 'gh run cancel' (GitHub) or GitLab API"
echo "  4. Stop the pipeline immediately"
echo ""

# Wait for detection
sleep 30

# Stop daemon
sudo kill -TERM $DAEMON_PID 2>/dev/null || true
wait $DAEMON_PID 2>/dev/null || true

echo "========================================"
echo "  Demo Complete"
echo "========================================"
echo ""
echo "Check daemon logs: cat /tmp/flodviddar_watch.log"
echo "Check cancel log: cat \$HOME/cancel_pipeline_*.log"
echo ""

# Cleanup
rm -f /tmp/demo_whitelist.json


