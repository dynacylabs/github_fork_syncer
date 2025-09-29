#!/bin/bash

# Ensure required environment variables are set
if [ -z "${GITHUB_TOKEN}" ]; then
    echo "Error: GITHUB_TOKEN is not set."
    exit 1
fi

GITHUB_USERNAME="your-username"  # Update with your GitHub username

# Get a list of your forks and their upstream sources, along with their default branch
REPOS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/users/${GITHUB_USERNAME}/repos?type=forks" | \
    jq -r '.[] | "\(.name) \(.parent.full_name) \(.parent.default_branch)"')

# Loop through each repo and sync with its upstream
echo "$REPOS" | while read -r REPO UPSTREAM DEFAULT_BRANCH; do
    if [ -z "$REPO" ]; then
        continue
    fi
    echo "Updating fork: $REPO from upstream: $UPSTREAM, default branch: $DEFAULT_BRANCH"
    
    # Navigate to the local repo directory
    REPO_DIR="/path/to/your/forks/$REPO"  # Update this path
    cd "$REPO_DIR" || { echo "Repository $REPO not found"; continue; }

    # Add upstream remote if not already present
    git remote get-url upstream &> /dev/null || git remote add upstream "https://github.com/$UPSTREAM"

    # Fetch upstream changes
    git fetch upstream

    # Checkout the default branch
    git checkout "$DEFAULT_BRANCH"

    # Merge the upstream changes
    git merge "upstream/$DEFAULT_BRANCH"

    # Push the changes to your fork
    git push origin "$DEFAULT_BRANCH"
done