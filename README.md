# GitHub Fork Syncer

A simple, automated solution to keep your GitHub forks in sync with their upstream repositories using Docker and cron scheduling.

## Overview

GitHub Fork Syncer automatically synchronizes your forked repositories with their upstream sources. It uses the GitHub API to discover your forks and their upstream repositories, then performs git operations to merge the latest changes from upstream into your forks.

## Features

- 🔄 **Automatic synchronization** of all your GitHub forks
- 📅 **Configurable cron scheduling** for regular updates
- 🐳 **Docker containerized** for easy deployment
- 🔍 **Upstream detection** using GitHub API
- 🌿 **Smart branch handling** respects default branch settings
- 📊 **Logging support** for monitoring sync operations

## Quick Start

### Prerequisites

- Docker installed on your system
- GitHub Personal Access Token with `repo` permissions

### 1. Clone the Repository

```bash
git clone https://github.com/dynacylabs/github_fork_syncer.git
cd github_fork_syncer
```

### 2. Configure Environment Variables

Copy the example environment file and configure your settings:

```bash
cp example.env .env
```

Edit `.env` file:
```plaintext
GITHUB_TOKEN=your_github_personal_access_token
CRON_SCHEDULE="0 0 * * *"  # Daily at midnight
```

### 3. Update Configuration

Edit `sync_forks.sh` to configure your settings:

```bash
# Update line 8 with your GitHub username
GITHUB_USERNAME="your-username"

# Update line 22 with your local repositories path
REPO_DIR="/path/to/your/forks/$REPO"
```

### 4. Build and Run with Docker

```bash
# Build the Docker image
docker build -t github-fork-syncer .

# Run the container
docker run -d \
  --name fork-syncer \
  --env-file .env \
  -v /path/to/your/forks:/path/to/your/forks \
  github-fork-syncer
```

## Manual Usage

You can also run the sync script manually:

```bash
export GITHUB_TOKEN=your_token
./sync_forks.sh
```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `GITHUB_TOKEN` | GitHub Personal Access Token with repo permissions | - | ✅ |
| `CRON_SCHEDULE` | Cron expression for scheduling sync operations | `"0 0 * * *"` | ❌ |

### Script Configuration

The `sync_forks.sh` script requires manual configuration of:

- **GitHub Username**: Update `GITHUB_USERNAME` variable with your GitHub username
- **Local Repository Path**: Update `REPO_DIR` with the path where your forked repositories are stored locally

### Cron Schedule Examples

| Schedule | Description |
|----------|-------------|
| `"0 0 * * *"` | Daily at midnight |
| `"0 */6 * * *"` | Every 6 hours |
| `"0 0 * * 1"` | Weekly on Monday |
| `"0 0 1 * *"` | Monthly on the 1st |

## How It Works

1. **Discovery**: Uses GitHub API to fetch all your forked repositories
2. **Analysis**: Identifies upstream repository and default branch for each fork
3. **Synchronization**: For each fork:
   - Adds upstream remote if not present
   - Fetches latest changes from upstream
   - Merges upstream changes into the default branch
   - Pushes updates to your fork

## Repository Structure

```
.
├── Dockerfile          # Docker configuration
├── sync_forks.sh      # Main synchronization script
├── example.env        # Environment variables template
└── README.md          # This file
```

## Requirements

### System Requirements
- Docker (for containerized deployment)
- Git (if running locally)
- curl and jq (if running locally)

### GitHub Token Permissions
Your GitHub Personal Access Token needs the following scopes:
- `repo` - Full control of private repositories
- `public_repo` - Access to public repositories

## Logging

Container logs can be viewed using:

```bash
docker logs fork-syncer
```

For more detailed logging, you can also check the cron logs inside the container:

```bash
docker exec fork-syncer tail -f /var/log/cron.log
```

## Troubleshooting

### Common Issues

**Authentication Error**
- Verify your `GITHUB_TOKEN` is correct and has proper permissions
- Ensure the token hasn't expired

**Repository Not Found**
- Check that the `REPO_DIR` path is correctly configured
- Ensure your local repositories exist and are properly initialized

**Permission Denied**
- Verify you have write access to your forked repositories
- Check that your GitHub token has the necessary permissions

### Debug Mode

To run the script in debug mode, add debugging to the script:

```bash
#!/bin/bash
set -x  # Enable debug mode
# ... rest of the script
```

## Contributing

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open source. Feel free to use, modify, and distribute as needed.

## Security Note

⚠️ **Important**: Never commit your actual GitHub token to version control. Always use environment variables or secure secret management systems.

## Support

If you encounter any issues or have questions, please open an issue in this repository.