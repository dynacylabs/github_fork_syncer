#!/bin/sh

# GitHub Fork Syncer Health Check Script
# This script checks if the container is healthy by verifying:
# 1. cron daemon is running
# 2. Required environment variables are set
# 3. Script file exists and is executable

# Check if cron daemon is running
if ! pgrep crond > /dev/null 2>&1; then
    echo "ERROR: cron daemon is not running"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is not set"
    exit 1
fi

# Check if we have at least one username configured
if [ -z "$GITHUB_USERNAME" ] && [ -z "$GITHUB_USERNAMES" ] && [ ! -f "/app/usernames.txt" ]; then
    echo "ERROR: No usernames configured (GITHUB_USERNAME, GITHUB_USERNAMES, or usernames.txt)"
    exit 1
fi

# Check if sync script exists and is executable
if [ ! -x "/usr/local/bin/sync_forks.sh" ]; then
    echo "ERROR: sync_forks.sh is missing or not executable"
    exit 1
fi

# Check if crontab is loaded
if ! crontab -l > /dev/null 2>&1; then
    echo "ERROR: No crontab is loaded"
    exit 1
fi

# All checks passed
echo "HEALTHY: All health checks passed"
echo "- cron daemon: running"
echo "- environment: configured"
echo "- sync script: ready"
echo "- crontab: loaded"
exit 0