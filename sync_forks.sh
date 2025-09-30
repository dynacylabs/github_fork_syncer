#!/bin/bash

# Ensure required environment variables are set
if [ -z "${GITHUB_TOKEN}" ]; then
    echo "Error: GITHUB_TOKEN is not set."
    exit 1
fi

# Set the base directory for repositories (can be overridden by environment variable)
BASE_REPO_DIR="${REPO_BASE_DIR:-}"

# Create the base directory if it doesn't exist
mkdir -p "$BASE_REPO_DIR"

# Function to get usernames to process
get_usernames() {
    local usernames=""
    
    # Priority 1: Command line arguments
    if [ $# -gt 0 ]; then
        usernames="$*"
        echo "Using usernames from command line: $usernames"
    # Priority 2: GITHUB_USERNAMES environment variable (comma or space separated)
    elif [ -n "${GITHUB_USERNAMES}" ]; then
        usernames=$(echo "${GITHUB_USERNAMES}" | tr ',' ' ')
        echo "Using usernames from GITHUB_USERNAMES: $usernames"
    # Priority 3: GITHUB_USERNAME environment variable (single user)
    elif [ -n "${GITHUB_USERNAME}" ]; then
        usernames="${GITHUB_USERNAME}"
        echo "Using username from GITHUB_USERNAME: $usernames"
    # Priority 4: usernames.txt file
    elif [ -f "usernames.txt" ]; then
        usernames=$(grep -v '^#' usernames.txt | grep -v '^[[:space:]]*$' | tr '\n' ' ')
        echo "Using usernames from usernames.txt: $usernames"
    else
        echo "Error: No usernames specified!"
        echo ""
        echo "Please specify usernames using one of these methods:"
        echo "1. Command line: $0 username1 username2 username3"
        echo "2. Environment variable: GITHUB_USERNAMES=\"user1,user2,user3\""
        echo "3. Environment variable: GITHUB_USERNAME=\"single_user\""
        echo "4. Create usernames.txt file with one username per line"
        exit 1
    fi
    
    echo "$usernames"
}

# Function to process forks for a single user
process_user_forks() {
    local username="$1"
    echo ""
    echo "========================================="
    echo "Processing forks for user: $username"
    echo "========================================="

    # Get a list of your forks and their upstream sources, along with their default branch
    echo "Fetching all repositories for user: $username"

    # Get all repositories with more complete information
    API_RESPONSE=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/users/${username}/repos?per_page=100")

    echo "API Response status check..."
    if [ -z "$API_RESPONSE" ]; then
        echo "Error: Empty response from GitHub API for user $username"
        return 1
    fi

    # Check if we got an error response
    ERROR_MESSAGE=$(echo "$API_RESPONSE" | jq -r '.message // empty' 2>/dev/null)
    if [ -n "$ERROR_MESSAGE" ]; then
        echo "GitHub API Error for user $username: $ERROR_MESSAGE"
        return 1
    fi

    echo "Repository count: $(echo "$API_RESPONSE" | jq '. | length' 2>/dev/null || echo "unknown")"

    # Get list of fork repository names
    FORK_NAMES=$(echo "$API_RESPONSE" | jq -r '.[] | select(.fork == true) | .name' 2>/dev/null)

    if [ -z "$FORK_NAMES" ]; then
        echo "No fork repositories found for user: $username"
        return 0
    fi

    echo "Found fork repositories: $(echo "$FORK_NAMES" | tr '\n' ' ')"
    echo ""

    # For each fork, get detailed information including parent data
    REPOS=""
    while IFS= read -r REPO_NAME; do
        if [ -z "$REPO_NAME" ]; then
            continue
        fi
        
        echo "Fetching detailed info for: $REPO_NAME"
        REPO_DETAIL=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${username}/${REPO_NAME}")
        
        # Check if this call was successful
        DETAIL_ERROR=$(echo "$REPO_DETAIL" | jq -r '.message // empty' 2>/dev/null)
        if [ -n "$DETAIL_ERROR" ]; then
            echo "  Error fetching details: $DETAIL_ERROR"
            continue
        fi
        
        # Extract parent information
        PARENT_FULL_NAME=$(echo "$REPO_DETAIL" | jq -r '.parent.full_name // empty')
        PARENT_DEFAULT_BRANCH=$(echo "$REPO_DETAIL" | jq -r '.parent.default_branch // empty')
        
        if [ -n "$PARENT_FULL_NAME" ] && [ "$PARENT_FULL_NAME" != "null" ]; then
            # Use the parent's default branch, or fallback to main
            if [ -z "$PARENT_DEFAULT_BRANCH" ] || [ "$PARENT_DEFAULT_BRANCH" = "null" ]; then
                PARENT_DEFAULT_BRANCH="main"
            fi
            
            echo "  ✓ Found upstream: $PARENT_FULL_NAME (default branch: $PARENT_DEFAULT_BRANCH)"
            REPOS="${REPOS}${REPO_NAME} ${PARENT_FULL_NAME} ${PARENT_DEFAULT_BRANCH} ${username}\n"
        else
            echo "  ✗ No upstream found - may be broken fork or orphaned repository"
        fi
    done <<< "$FORK_NAMES"

    # Check if we found any valid forks with upstream
    if [ -z "$REPOS" ]; then
        echo ""
        echo "No valid fork repositories with upstream found for user: $username"
        return 0
    fi

    echo ""
    echo "Valid fork repositories with upstream for $username:"
    echo -e "$REPOS"
    echo "Starting synchronization process for $username..."

    # Loop through each repo and sync with its upstream
    echo -e "$REPOS" | while IFS= read -r line; do
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Parse the line (format: "REPO UPSTREAM DEFAULT_BRANCH USERNAME")
        read -r REPO UPSTREAM DEFAULT_BRANCH REPO_USERNAME <<< "$line"
        
        # Skip if we don't have all required information
        if [ -z "$REPO" ] || [ -z "$UPSTREAM" ] || [ -z "$DEFAULT_BRANCH" ] || [ -z "$REPO_USERNAME" ]; then
            echo "Skipping invalid repository data: '$line'"
            continue
        fi
        
        echo "Processing fork: $REPO from upstream: $UPSTREAM, default branch: $DEFAULT_BRANCH (user: $REPO_USERNAME)"
        
        # Set the repository directory path (include username to avoid conflicts)
        REPO_DIR="$BASE_REPO_DIR/$REPO_USERNAME/$REPO"
        
        # Create user-specific directory
        mkdir -p "$BASE_REPO_DIR/$REPO_USERNAME"
        
        # Check if repository directory exists, if not, clone it
        if [ ! -d "$REPO_DIR" ]; then
            echo "Repository directory not found. Cloning $REPO for user $REPO_USERNAME..."
            cd "$BASE_REPO_DIR/$REPO_USERNAME"
            git clone "https://github.com/${REPO_USERNAME}/${REPO}.git" || {
                echo "Failed to clone repository $REPO for user $REPO_USERNAME"
                continue
            }
        fi
        
        # Navigate to the repository directory
        cd "$REPO_DIR" || { 
            echo "Failed to navigate to repository directory: $REPO_DIR"
            continue
        }
        
        # Verify this is actually a git repository
        if [ ! -d ".git" ]; then
            echo "Error: $REPO_DIR is not a git repository"
            continue
        fi
        
        # Double-check that this repository is actually a fork by checking remotes
        ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ ! "$ORIGIN_URL" =~ github\.com[/:]${REPO_USERNAME}/${REPO}(\.git)?$ ]]; then
            echo "Warning: Origin URL doesn't match expected fork URL for $REPO"
            echo "Expected pattern: github.com/${REPO_USERNAME}/${REPO}"
            echo "Actual origin: $ORIGIN_URL"
            continue
        fi

        # Add upstream remote if not already present
        echo "Checking upstream remote..."
        if git remote get-url upstream &> /dev/null; then
            EXISTING_UPSTREAM=$(git remote get-url upstream)
            echo "Upstream remote already exists: $EXISTING_UPSTREAM"
            EXPECTED_UPSTREAM="https://github.com/$UPSTREAM"
            if [ "$EXISTING_UPSTREAM" != "$EXPECTED_UPSTREAM" ]; then
                echo "Updating upstream remote from $EXISTING_UPSTREAM to $EXPECTED_UPSTREAM"
                git remote set-url upstream "$EXPECTED_UPSTREAM"
            fi
        else
            echo "Adding upstream remote: https://github.com/$UPSTREAM"
            git remote add upstream "https://github.com/$UPSTREAM" || {
                echo "Failed to add upstream remote"
                continue
            }
        fi

        # Fetch upstream changes
        echo "Fetching from upstream..."
        git fetch upstream || {
            echo "Failed to fetch from upstream"
            continue
        }

        # Checkout the default branch
        echo "Switching to branch: $DEFAULT_BRANCH"
        git checkout "$DEFAULT_BRANCH" || {
            echo "Failed to checkout branch $DEFAULT_BRANCH"
            continue
        }

        # Merge the upstream changes
        echo "Merging upstream/$DEFAULT_BRANCH..."
        git merge "upstream/$DEFAULT_BRANCH" || {
            echo "Failed to merge upstream changes"
            continue
        }

        # Push the changes to your fork
        echo "Pushing changes to origin..."
        PUSH_OUTPUT=$(git push origin "$DEFAULT_BRANCH" 2>&1)
        PUSH_EXIT_CODE=$?
        
        if [ $PUSH_EXIT_CODE -eq 0 ]; then
            echo "✓ Successfully synced $REPO (user: $REPO_USERNAME)"
        else
            # Check if it's a workflow permission issue
            if echo "$PUSH_OUTPUT" | grep -q "workflow.*scope"; then
                echo "⚠️ Synced $REPO but couldn't push due to workflow permissions (user: $REPO_USERNAME)"
                echo "   (Your token needs 'workflow' scope to update .github/workflows/ files)"
                echo "   Repository is still synced locally"
            else
                echo "❌ Failed to push changes to $REPO (user: $REPO_USERNAME)"
                echo "   Error: $PUSH_OUTPUT"
            fi
        fi
        echo ""
    done
    
    echo "Completed processing forks for user: $username"
}

# Main script execution
echo "GitHub Fork Syncer - Multi-User Support"
echo "======================================="

# Get list of usernames to process
USERNAMES=$(get_usernames "$@")

if [ -z "$USERNAMES" ]; then
    echo "No usernames to process"
    exit 1
fi

echo ""
echo "Will process forks for users: $USERNAMES"
echo ""

# Process each username
for USERNAME in $USERNAMES; do
    process_user_forks "$USERNAME"
done

echo ""
echo "========================================="
echo "Fork synchronization completed for all users"
echo "========================================="