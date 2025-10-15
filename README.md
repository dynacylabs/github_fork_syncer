# GitHub Fork Syncer

A powerful, automated solution to keep your GitHub forks in sync with their upstream repositories. Features multi-user support, comprehensive branch synchronization, and containerized deployment with Docker.

## Overview

GitHub Fork Syncer automatically synchronizes your forked repositories with their upstream sources across multiple GitHub accounts. It uses the GitHub API to discover forks and their upstream repositories, then performs intelligent git operations to merge the latest changes from upstream into your forks.

## ✨ Features

- 🔄 **Multi-branch synchronization** - Sync all branches, not just the default
- 👥 **Multi-user support** - Manage forks across multiple GitHub accounts/organizations
- 📅 **Configurable scheduling** with cron-like syntax (no cron daemon needed!)
- 🐳 **Docker containerized** with health checks for reliable deployment
- 🔍 **Smart upstream detection** using GitHub API
- 🌿 **Intelligent branch handling** with pattern matching and conflict resolution
- 📊 **Comprehensive logging** and progress reporting
- 🛡️ **Safe operations** with force-with-lease and conflict handling
- ⚙️ **Flexible configuration** via environment variables or files
- 🏗️ **Auto-directory creation** and repository cloning
- ⏰ **Simple scheduler** using sleep loops instead of cron for better container compatibility

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- GitHub Personal Access Token with `repo` permissions

### 1. Clone and Configure

```bash
git clone https://github.com/dynacylabs/github_fork_syncer.git
cd github_fork_syncer
cp example.env .env
```

### 2. Edit Configuration

Edit `.env` file with your settings:
```bash
GITHUB_TOKEN=your_github_personal_access_token
GITHUB_USERNAMES=user1,user2,organization1
SYNC_MODE=all
SYNC_SCHEDULE="0 0 * * *"
RUN_ON_STARTUP=true
```

### 3. Deploy with Docker Compose

```bash
docker-compose up -d
```

### 4. Monitor Progress

```bash
# Check container status
docker ps

# View real-time logs
docker logs -f github-fork-syncer

# Check sync execution logs
docker exec github-fork-syncer tail -f /var/log/sync.log

# Check scheduler logs
docker exec github-fork-syncer tail -f /var/log/scheduler.log
```

## 🎯 Branch Synchronization Modes

### **All Branches (Default)**
Syncs every branch from upstream to your fork:
```bash
SYNC_MODE=all
CREATE_NEW_BRANCHES=true
```
- ✅ Syncs all existing branches
- ✅ Creates new branches from upstream
- ✅ Comprehensive coverage

### **Default Branch Only**
Legacy mode - syncs only the main/master branch:
```bash
SYNC_MODE=default
```
- ✅ Fast and lightweight
- ✅ Minimal risk

### **Selective Patterns**
Sync only branches matching specific patterns:
```bash
SYNC_MODE=selective
SYNC_BRANCHES="main,develop,feature/*,release/*"
```
- ✅ Configurable with wildcards
- ✅ Fine-grained control

## 👥 Multi-User Configuration

### Method 1: Environment Variables (Recommended)
```bash
# Multiple users
GITHUB_USERNAMES="dynacylabs,octocat,myorg"

# Single user (legacy)
GITHUB_USERNAME="dynacylabs"
```

### Method 2: Command Line
```bash
./sync_forks.sh user1 user2 user3
```

### Method 3: Docker Compose
```yaml
environment:
  - GITHUB_USERNAMES=user1,user2,user3
  - SYNC_MODE=all
```

## ⚙️ Configuration Reference

### Core Environment Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `GITHUB_TOKEN` | GitHub Personal Access Token | - | **Required** |
| `GITHUB_USERNAMES` | Comma/space separated usernames | - | `user1,user2,user3` |
| `SYNC_MODE` | Branch synchronization mode | `all` | `default`, `all`, `selective` |
| `SYNC_BRANCHES` | Branch patterns (selective mode) | `main,master,develop,dev,feature/*,release/*` | Comma-separated patterns |
| `CREATE_NEW_BRANCHES` | Create new upstream branches | `true` | `true`, `false` |
| `REPO_BASE_DIR` | Local repository storage path | `/app/repos` | Any valid path |
| `SYNC_SCHEDULE` | Automated sync schedule | `0 0 * * *` | Cron-like expression |
| `RUN_ON_STARTUP` | Run sync immediately on startup | `true` | `true`, `false` |

### Branch Pattern Examples

| Pattern | Description |
|---------|-------------|
| `main,master` | Exact branch names |
| `feature/*,bugfix/*` | Wildcard patterns |
| `main,dev*,release/*` | Mixed exact and wildcards |
| `develop,staging,feature/auth` | Specific branches |

### Cron Schedule Examples

| Schedule | Description |
|----------|-------------|
| `"0 0 * * *"` | Daily at midnight |
| `"0 */6 * * *"` | Every 6 hours |
| `"0 2 * * 1-5"` | Weekdays at 2 AM |
| `"0 0 * * 0"` | Weekly on Sunday |
| `"*/30 * * * *"` | Every 30 minutes |

### Scheduler Configuration

The scheduler uses a simple loop-based approach instead of cron for better container compatibility:

| Variable | Description | Default |
|----------|-------------|---------|
| `SYNC_SCHEDULE` | When to run sync (cron-like syntax) | `0 0 * * *` |
| `RUN_ON_STARTUP` | Run sync immediately when container starts | `true` |

**Benefits over cron:**
- ✅ No cron daemon required (smaller image, fewer processes)
- ✅ Environment variables properly passed to sync script
- ✅ Better logging and error handling
- ✅ Immediate feedback in container logs
- ✅ More reliable in containerized environments

## 🐳 Docker Deployment

### Using Docker Compose (Recommended)

1. **Configure environment**:
```bash
cp example.env .env
# Edit .env with your settings
```

2. **Deploy**:
```bash
docker-compose up -d
```

3. **Monitor**:
```bash
docker logs -f github-fork-syncer
```

### Using Docker Run

```bash
docker run -d \
  --name github-fork-syncer \
  -e GITHUB_TOKEN="your_token" \
  -e GITHUB_USERNAMES="user1,user2" \
  -e SYNC_MODE="all" \
  -e SYNC_SCHEDULE="0 0 * * *" \
  -e RUN_ON_STARTUP="true" \
  -v ./repos:/app/repos \
  github-fork-syncer
```

### Health Monitoring

The container includes comprehensive health checks:

```bash
# Check health status
docker ps
# STATUS should show "healthy"

# View health check details
docker inspect github-fork-syncer --format='{{.State.Health.Status}}'

# Manual health check
docker exec github-fork-syncer /usr/local/bin/healthcheck.sh
```

## 🔧 Manual Usage

### Quick Test Run
```bash
export GITHUB_TOKEN="your_token"
export GITHUB_USERNAMES="user1,user2"
export SYNC_MODE="all"
./sync_forks.sh
```

### Local Development
```bash
# Install dependencies (Alpine/Ubuntu)
sudo apk add git curl jq bash  # Alpine
sudo apt-get install git curl jq bash  # Ubuntu

# Run locally
chmod +x sync_forks.sh
./sync_forks.sh
```

## 🔍 Advanced Troubleshooting

### Common Issues & Solutions

#### 1. Authentication Errors
```bash
# Verify token validity
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Test repository access
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/user/repo
```

#### 2. Docker Health Check Failing
```bash
# Check container status
docker logs github-fork-syncer

# Verify internal processes
docker exec github-fork-syncer ps aux | grep scheduler

# Run manual health check
docker exec github-fork-syncer /usr/local/bin/healthcheck.sh
```

#### 3. Repository Sync Issues
- **Not a fork**: Verify repository is actually a fork (not original)
- **Upstream access**: Check if upstream repository is accessible
- **Branch mismatch**: Ensure target branches exist on upstream
- **Pattern mismatch**: Review sync patterns in selective mode

#### 4. Rate Limiting
```bash
# Check API rate limit status
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit
```

### Debug Mode

Enable verbose logging:
```bash
# Docker environment
docker run -e DEBUG=true github-fork-syncer

# Manual execution
DEBUG=true ./sync_forks.sh
```

### Log Analysis

```bash
# Real-time monitoring
docker logs -f github-fork-syncer

# Error filtering
docker logs github-fork-syncer 2>&1 | grep -i error

# User-specific logs
docker logs github-fork-syncer 2>&1 | grep "Processing user:"
```

## 📊 Monitoring & Metrics

### Health Checks

The container provides comprehensive health monitoring:

```bash
# Container health status
docker inspect github-fork-syncer --format='{{.State.Health.Status}}'

# Detailed health logs
docker inspect github-fork-syncer --format='{{range .State.Health.Log}}{{.Output}}{{end}}'
```

### Performance Monitoring

```bash
# Resource usage
docker stats github-fork-syncer

# Sync operation timing
docker logs github-fork-syncer | grep "Synchronization completed"
```

## 🛡️ Security Best Practices

### Token Management
- Use environment variables for tokens
- Rotate tokens regularly
- Limit token scope to minimum required permissions
- Never commit tokens to version control

### Container Security
```bash
# Run with non-root user
docker run --user 1000:1000 github-fork-syncer

# Read-only filesystem where possible
docker run --read-only --tmpfs /tmp github-fork-syncer
```

## ⚙️ How the Scheduler Works

The GitHub Fork Syncer uses a simple, reliable scheduler implementation instead of traditional cron:

### Architecture

1. **No cron daemon** - The scheduler runs as a single bash process with a sleep loop
2. **Cron-like syntax** - Uses the same schedule format you're familiar with (e.g., `0 0 * * *`)
3. **Transparent logging** - All output goes directly to container logs
4. **Environment-aware** - All environment variables are properly passed to the sync script

### How It Works

```bash
# The scheduler:
1. Parses cron-like expressions (e.g., "0 0 * * *")
2. Checks every 60 seconds if the current time matches the schedule
3. Executes sync_forks.sh when the schedule matches
4. Logs all operations with timestamps
5. Prevents duplicate runs in the same minute
```

### Benefits

| Benefit | Description |
|---------|-------------|
| **Simpler** | No cron daemon to manage or debug |
| **Reliable** | Environment variables always available |
| **Visible** | All logs appear in `docker logs` output |
| **Portable** | Works consistently across all platforms |
| **Lightweight** | One less process running in the container |

### Scheduler Features

The scheduler supports full cron syntax:
- **Exact times**: `0 0 * * *` (daily at midnight)
- **Intervals**: `*/30 * * * *` (every 30 minutes)
- **Ranges**: `0 9-17 * * *` (hourly from 9 AM to 5 PM)
- **Lists**: `0 0,12 * * *` (at midnight and noon)
- **Combinations**: `0 2 * * 1-5` (weekdays at 2 AM)

## 🔗 Integration Examples

### CI/CD Pipeline Integration

```yaml
# GitHub Actions example
name: Sync Forks
on:
  schedule:
    - cron: '0 0 * * *'
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Sync Forks
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_USERNAMES: ${{ vars.USERNAMES }}
        run: ./sync_forks.sh
```

### Webhook Integration

```bash
# Trigger sync via webhook
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"users":["user1","user2"]}' \
  http://your-server/api/sync-forks
```

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### Development Setup

```bash
# Fork and clone
git clone https://github.com/yourusername/github_fork_syncer.git
cd github_fork_syncer

# Create feature branch
git checkout -b feature/your-feature

# Test your changes
./sync_forks.sh --dry-run
```

### Contribution Guidelines

1. **Code Quality**: Follow existing bash scripting patterns
2. **Testing**: Test with multiple user scenarios
3. **Documentation**: Update README for new features
4. **Backward Compatibility**: Maintain existing API/environment variables

### Pull Request Process

1. Update README.md with details of changes
2. Ensure Docker builds successfully
3. Test with real GitHub repositories
4. Submit PR with clear description

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support & Community

- **Issues**: [GitHub Issues](https://github.com/dynacylabs/github_fork_syncer/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dynacylabs/github_fork_syncer/discussions)
- **Wiki**: [Project Wiki](https://github.com/dynacylabs/github_fork_syncer/wiki)

## 🔗 Related Projects

- [GitHub CLI](https://cli.github.com/) - Official GitHub command line tool
- [Hub](https://hub.github.com/) - Command line wrapper for git
- [GitHub Sync Action](https://github.com/marketplace/actions/fork-sync) - GitHub Action for fork syncing

---

<p align="center">
  <strong>Made with ❤️ by <a href="https://github.com/dynacylabs">DynacyLabs</a></strong><br>
  <em>Automating developer workflows, one fork at a time</em>
</p>