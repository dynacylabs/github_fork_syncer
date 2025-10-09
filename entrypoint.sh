#!/bin/bash

# GitHub Fork Syncer Docker Entrypoint
# Runs a simple scheduler without cron

# Set default sync schedule if not provided
SYNC_SCHEDULE=${SYNC_SCHEDULE:-"0 0 * * *"}

echo "==========================================="
echo "GitHub Fork Syncer Container Starting"
echo "==========================================="
echo "Sync Schedule: $SYNC_SCHEDULE"
echo "Base Directory: ${REPO_BASE_DIR:-/app/repos}"
echo "GitHub Token: ${GITHUB_TOKEN:+***SET***}"
echo "GitHub Username: ${GITHUB_USERNAME:-not set}"
echo "GitHub Usernames: ${GITHUB_USERNAMES:-not set}"
echo "Sync Mode: ${SYNC_MODE:-all}"
echo "Run on Startup: ${RUN_ON_STARTUP:-true}"
echo "==========================================="

# Create log files with proper permissions
mkdir -p /var/log 2>/dev/null || true
touch /var/log/sync.log /var/log/scheduler.log 2>/dev/null || true
chmod 666 /var/log/sync.log /var/log/scheduler.log 2>/dev/null || true

echo ""
echo "Container setup complete. Starting scheduler..."
echo "View logs with: docker logs <container_name>"
echo "View sync logs with: docker exec <container_name> tail -f /var/log/sync.log"
echo ""

# Run scheduler directly
exec /usr/local/bin/scheduler.sh 2>&1 | tee /var/log/scheduler.log