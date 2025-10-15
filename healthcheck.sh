#!/bin/sh

# GitHub Fork Syncer Health Check Script
# This script checks if the container is healthy by verifying:
# 1. Scheduler process is running
# 2. Required environment variables are set
# 3. Script file exists and is executable

# Check if scheduler is running
if ! pgrep -f "scheduler.sh" > /dev/null 2>&1; then
    echo "ERROR: scheduler process is not running"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is not set"
    exit 1
fi

# Check if we have at least one username configured
if [ -z "$GITHUB_USERNAME" ] && [ -z "$GITHUB_USERNAMES" ]; then
    echo "ERROR: No usernames configured (GITHUB_USERNAME or GITHUB_USERNAMES)"
    exit 1
fi

# Check if sync script exists and is executable
if [ ! -x "/usr/local/bin/sync_forks.sh" ]; then
    echo "ERROR: sync_forks.sh is missing or not executable"
    exit 1
fi

# Check if scheduler script exists and is executable
if [ ! -x "/usr/local/bin/scheduler.sh" ]; then
    echo "ERROR: scheduler.sh is missing or not executable"
    exit 1
fi

# All checks passed
echo "HEALTHY: All health checks passed"
echo "- scheduler: running"
echo "- environment: configured"
echo "- sync script: ready"
echo "- scheduler script: ready"
exit 0