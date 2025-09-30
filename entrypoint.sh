#!/bin/sh

# GitHub Fork Syncer Docker Entrypoint
# Handles dynamic cron scheduling based on environment variables

# Set default cron schedule if not provided
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 0 * * *"}

echo "==========================================="
echo "GitHub Fork Syncer Container Starting"
echo "==========================================="
echo "Cron Schedule: $CRON_SCHEDULE"
echo "Base Directory: ${REPO_BASE_DIR:-/app/repos}"
echo "GitHub Token: ${GITHUB_TOKEN:+***SET***}"
echo "GitHub Username: ${GITHUB_USERNAME:-not set}"
echo "GitHub Usernames: ${GITHUB_USERNAMES:-not set}"
echo "==========================================="

# Create the cron job with the environment variable
echo "Setting up cron job..."
echo "$CRON_SCHEDULE /usr/local/bin/sync_forks.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Load the crontab
crontab /etc/crontabs/root

# Display the loaded crontab for verification
echo "Loaded crontab:"
crontab -l

# Create log file if it doesn't exist
touch /var/log/cron.log

echo ""
echo "Container setup complete. Starting cron daemon..."
echo "View logs with: docker logs <container_name>"
echo "View cron logs with: docker exec <container_name> tail -f /var/log/cron.log"
echo ""

# Start cron in foreground with logging
exec crond -f -l 2