FROM alpine:latest

# Install Git, Cron, Curl, and jq
RUN apk add --no-cache git curl jq

# Copy the sync script into the container
COPY sync_forks.sh /usr/local/bin/sync_forks.sh
RUN chmod +x /usr/local/bin/sync_forks.sh

# Create the cron job entry
RUN echo "* * * * * /usr/local/bin/sync_forks.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Run the command on container startup
CMD ["sh", "-c", "echo \"$CRON_SCHEDULE /usr/local/bin/sync_forks.sh >> /var/log/cron.log 2>&1\" > /etc/crontabs/root && crontab /etc/crontabs/root && crond -f"]