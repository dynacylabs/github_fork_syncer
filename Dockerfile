FROM alpine:latest

# Install Git, Cron, Curl, and jq
RUN apk add --no-cache git curl jq

# Create necessary directories
RUN mkdir -p /var/log /app

# Copy scripts into the container
COPY sync_forks.sh /usr/local/bin/sync_forks.sh
COPY entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/sync_forks.sh /entrypoint.sh

# Copy usernames.txt if it exists (optional)
COPY usernames.txt* /app/

# Set working directory
WORKDIR /app

# Set default environment variables
ENV REPO_BASE_DIR=/app/repos
ENV CRON_SCHEDULE="* * * * *"

# Use the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]