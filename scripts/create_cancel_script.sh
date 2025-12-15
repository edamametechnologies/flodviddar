#!/bin/bash
# Creates a pipeline cancellation script for CI/CD environments
# This script is called by flodviddar before starting monitoring

# Determine script path
CANCEL_SCRIPT_PATH="${FLODVIDDAR_CANCEL_SCRIPT:-$HOME/cancel_pipeline.sh}"

echo "Creating cancellation script at: $CANCEL_SCRIPT_PATH"

# Capture CI environment variables
CAPTURED_GITHUB_ACTIONS="${GITHUB_ACTIONS:-}"
CAPTURED_GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
CAPTURED_GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
CAPTURED_GITHUB_TOKEN="${GITHUB_TOKEN:-}"
CAPTURED_GITLAB_CI="${GITLAB_CI:-}"
CAPTURED_CI_PROJECT_ID="${CI_PROJECT_ID:-}"
CAPTURED_CI_PIPELINE_ID="${CI_PIPELINE_ID:-}"
CAPTURED_GITLAB_TOKEN="${GITLAB_TOKEN:-}"
CAPTURED_CI_JOB_TOKEN="${CI_JOB_TOKEN:-}"

# Create cancellation script
cat > "$CANCEL_SCRIPT_PATH" << 'SCRIPT_EOF'
#!/bin/sh
# Flodviddar Pipeline Cancellation Script

GITHUB_ACTIONS="__GITHUB_ACTIONS__"
GITHUB_RUN_ID="__GITHUB_RUN_ID__"
GITHUB_REPOSITORY="__GITHUB_REPOSITORY__"
GITHUB_TOKEN="__GITHUB_TOKEN__"
GITLAB_CI="__GITLAB_CI__"
CI_PROJECT_ID="__CI_PROJECT_ID__"
CI_PIPELINE_ID="__CI_PIPELINE_ID__"
GITLAB_TOKEN="__GITLAB_TOKEN__"
CI_JOB_TOKEN="__CI_JOB_TOKEN__"

# Log file with run ID
if [ -n "$GITHUB_RUN_ID" ]; then
  LOGFILE="$HOME/cancel_pipeline_${GITHUB_RUN_ID}.log"
elif [ -n "$CI_PIPELINE_ID" ]; then
  LOGFILE="$HOME/cancel_pipeline_${CI_PIPELINE_ID}.log"
else
  LOGFILE="$HOME/cancel_pipeline.log"
fi

log() { echo "$1" >> "$LOGFILE"; sync 2>/dev/null; echo "$1"; }

log ""
log "========================================"
log "Flodviddar Pipeline Cancellation"
log "Timestamp: $(date +%Y-%m-%dT%H:%M:%S)"
log "========================================"

REASON="${1:-Policy violation detected}"
log "Reason: $REASON"
log "GITHUB_ACTIONS=$GITHUB_ACTIONS"
log "GITHUB_RUN_ID=$GITHUB_RUN_ID"
log "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
log "LOGFILE=$LOGFILE"

if [ -n "$GITHUB_ACTIONS" ]; then
  log "Detected GitHub Actions environment"
  export GH_TOKEN="$GITHUB_TOKEN"
  log "Executing: gh run cancel $GITHUB_RUN_ID --repo $GITHUB_REPOSITORY"
  sync 2>/dev/null
  
  if gh run cancel "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" >> "$LOGFILE" 2>&1; then
    log "[OK] Pipeline cancellation command succeeded"
  else
    log "[ERROR] Pipeline cancellation command failed with exit code: $?"
  fi
elif [ -n "$GITLAB_CI" ]; then
  log "Detected GitLab CI environment"
  TOKEN="${GITLAB_TOKEN:-$CI_JOB_TOKEN}"
  URL="https://gitlab.com/api/v4/projects/${CI_PROJECT_ID}/pipelines/${CI_PIPELINE_ID}/cancel"
  log "Executing: curl -X POST $URL"
  
  curl -s -X POST -H "PRIVATE-TOKEN: $TOKEN" "$URL" >> "$LOGFILE" 2>&1
  log "[OK] Pipeline cancellation command executed"
else
  log "[ERROR] No CI environment detected"
  log "Set GITHUB_ACTIONS or GITLAB_CI environment variable"
  exit 1
fi

log "Script completed at: $(date +%Y-%m-%dT%H:%M:%S)"
log "========================================"
sync 2>/dev/null
SCRIPT_EOF

# Replace placeholders with actual values
sed -i "s|__GITHUB_ACTIONS__|$CAPTURED_GITHUB_ACTIONS|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__GITHUB_RUN_ID__|$CAPTURED_GITHUB_RUN_ID|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__GITHUB_REPOSITORY__|$CAPTURED_GITHUB_REPOSITORY|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__GITHUB_TOKEN__|$CAPTURED_GITHUB_TOKEN|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__GITLAB_CI__|$CAPTURED_GITLAB_CI|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__CI_PROJECT_ID__|$CAPTURED_CI_PROJECT_ID|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__CI_PIPELINE_ID__|$CAPTURED_CI_PIPELINE_ID|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__GITLAB_TOKEN__|$CAPTURED_GITLAB_TOKEN|g" "$CANCEL_SCRIPT_PATH"
sed -i "s|__CI_JOB_TOKEN__|$CAPTURED_CI_JOB_TOKEN|g" "$CANCEL_SCRIPT_PATH"

chmod 700 "$CANCEL_SCRIPT_PATH"
echo "[OK] Cancellation script created and ready"
echo "Path: $CANCEL_SCRIPT_PATH"


