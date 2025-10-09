#!/bin/bash

# Scheduler script - runs fork sync on a schedule without cron
# This script parses cron-like syntax and executes tasks at the appropriate times

set -e

# Load environment variables
export GITHUB_TOKEN="${GITHUB_TOKEN}"
export GITHUB_USERNAME="${GITHUB_USERNAME}"
export GITHUB_USERNAMES="${GITHUB_USERNAMES}"
export REPO_BASE_DIR="${REPO_BASE_DIR:-/app/repos}"
export SYNC_MODE="${SYNC_MODE:-all}"
export SYNC_BRANCHES="${SYNC_BRANCHES:-main,master,develop,dev,feature/*,release/*}"
export CREATE_NEW_BRANCHES="${CREATE_NEW_BRANCHES:-true}"
export GIT_USER_NAME="${GIT_USER_NAME:-GitHub Fork Syncer}"
export GIT_USER_EMAIL="${GIT_USER_EMAIL:-github-fork-syncer@users.noreply.github.com}"

# Get schedule from environment (cron-like syntax)
SYNC_SCHEDULE="${SYNC_SCHEDULE:-0 0 * * *}"

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Parse cron expression and check if current time matches
# Format: minute hour day month weekday
check_cron_match() {
    local cron_expr="$1"
    local current_min=$(date +%M | sed 's/^0//')
    local current_hour=$(date +%H | sed 's/^0//')
    local current_day=$(date +%d | sed 's/^0//')
    local current_month=$(date +%m | sed 's/^0//')
    local current_weekday=$(date +%u)  # 1-7 (Monday-Sunday)
    
    # Handle Sunday as both 0 and 7
    if [ "$current_weekday" = "7" ]; then
        current_weekday="0"
    fi
    
    # Parse cron fields
    read -r min hour day month weekday <<< "$cron_expr"
    
    # Check each field
    # Minute
    if ! check_cron_field "$min" "$current_min" 0 59; then
        return 1
    fi
    
    # Hour
    if ! check_cron_field "$hour" "$current_hour" 0 23; then
        return 1
    fi
    
    # Day of month
    if ! check_cron_field "$day" "$current_day" 1 31; then
        return 1
    fi
    
    # Month
    if ! check_cron_field "$month" "$current_month" 1 12; then
        return 1
    fi
    
    # Day of week
    if ! check_cron_field "$weekday" "$current_weekday" 0 7; then
        return 1
    fi
    
    return 0
}

# Check if a cron field matches the current value
check_cron_field() {
    local field="$1"
    local current="$2"
    local min_val="$3"
    local max_val="$4"
    
    # Remove leading zeros for comparison
    current=$(echo "$current" | sed 's/^0*//')
    [ -z "$current" ] && current=0
    
    # * means any value
    if [ "$field" = "*" ]; then
        return 0
    fi
    
    # */n means every n units
    if [[ "$field" =~ ^\*/([0-9]+)$ ]]; then
        local step="${BASH_REMATCH[1]}"
        if [ $((current % step)) -eq 0 ]; then
            return 0
        else
            return 1
        fi
    fi
    
    # Check for ranges (e.g., 1-5)
    if [[ "$field" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        if [ "$current" -ge "$start" ] && [ "$current" -le "$end" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    # Check for lists (e.g., 1,3,5)
    if [[ "$field" =~ , ]]; then
        IFS=',' read -ra values <<< "$field"
        for val in "${values[@]}"; do
            val=$(echo "$val" | sed 's/^0*//')
            [ -z "$val" ] && val=0
            if [ "$val" -eq "$current" ]; then
                return 0
            fi
        done
        return 1
    fi
    
    # Direct value comparison
    field=$(echo "$field" | sed 's/^0*//')
    [ -z "$field" ] && field=0
    if [ "$field" -eq "$current" ]; then
        return 0
    fi
    
    return 1
}

# Run fork sync
run_sync() {
    log "🔄 Starting scheduled fork synchronization..."
    if /usr/local/bin/sync_forks.sh >> /var/log/sync.log 2>&1; then
        log "✅ Fork synchronization completed successfully"
    else
        log "❌ Fork synchronization failed"
    fi
}

# Initial startup tasks
log "=========================================="
log "🔄 GitHub Fork Syncer Scheduler Starting"
log "=========================================="
log "Sync schedule: $SYNC_SCHEDULE"
log "Base directory: $REPO_BASE_DIR"
log "Sync mode: $SYNC_MODE"
log "GitHub Username: ${GITHUB_USERNAME:-not set}"
log "GitHub Usernames: ${GITHUB_USERNAMES:-not set}"
log "=========================================="

# Run sync on startup if requested
if [ "${RUN_ON_STARTUP:-true}" = "true" ]; then
    log "🚀 Running initial sync on startup..."
    run_sync
else
    log "⏭️  Skipping initial sync on startup (RUN_ON_STARTUP=false)"
fi

# Track last execution time to avoid running multiple times in the same minute
last_sync_minute=""

log "=========================================="
log "⏰ Scheduler is now running..."
log "=========================================="

# Main loop - check every minute
while true; do
    # Get current minute marker
    current_minute=$(date +%Y%m%d%H%M)
    
    # Check sync schedule
    if [ "$last_sync_minute" != "$current_minute" ]; then
        if check_cron_match "$SYNC_SCHEDULE"; then
            run_sync
            last_sync_minute="$current_minute"
        fi
    fi
    
    # Sleep for 60 seconds
    sleep 60
done
