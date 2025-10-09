FROM alpine:latest

# Install Git, Curl, jq, and bash (removed cron - not needed anymore!)
RUN apk add --no-cache git curl jq bash

# Create necessary directories
RUN mkdir -p /var/log /app

# Copy scripts into the container
COPY sync_forks.sh /usr/local/bin/sync_forks.sh
COPY scheduler.sh /usr/local/bin/scheduler.sh
COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/sync_forks.sh /usr/local/bin/scheduler.sh /entrypoint.sh /usr/local/bin/healthcheck.sh

# Copy usernames.txt if it exists (optional)
COPY usernames.txt* /app/

# Set working directory
WORKDIR /app

# Set default environment variables
ENV REPO_BASE_DIR=/app/repos
ENV SYNC_SCHEDULE="0 0 * * *"
ENV RUN_ON_STARTUP=true

# Use the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]