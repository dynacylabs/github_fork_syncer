#!/bin/bash

# Ensure required environment variables are set
if [ -z "${GITHUB_TOKEN}" ]; then
    echo "Error: GITHUB_TOKEN is not set."
    exit 1
fi

# Set the base directory for repositories (can be overridden by environment variable)
BASE_REPO_DIR="${REPO_BASE_DIR:-/app/repos}"

# Set branch sync mode (can be overridden by environment variable)
# Options: "default" (only default branch), "all" (all branches), "selective" (pattern-based)
SYNC_MODE="${SYNC_MODE:-all}"

# Branch patterns for selective sync (comma-separated patterns)
SYNC_BRANCHES="${SYNC_BRANCHES:-main,master,develop,dev,feature/*,release/*}"

# Whether to create new branches from upstream that don't exist in fork
CREATE_NEW_BRANCHES="${CREATE_NEW_BRANCHES:-true}"

# Create the base directory if it doesn't exist
mkdir -p "$BASE_REPO_DIR"

# Function to check if a branch matches sync patterns
should_sync_branch() {
    local branch="$1"
    local patterns="$2"
    
    # Convert comma-separated patterns to array
    IFS=',' read -ra PATTERN_ARRAY <<< "$patterns"
    
    for pattern in "${PATTERN_ARRAY[@]}"; do
        # Trim whitespace
        pattern=$(echo "$pattern" | xargs)
        
        # Handle wildcard patterns
        if [[ "$pattern" == *"*"* ]]; then
            # Convert shell glob to regex
            regex_pattern=$(echo "$pattern" | sed 's/\*/.*/')
            if [[ "$branch" =~ ^${regex_pattern}$ ]]; then
                return 0
            fi
        else
            # Exact match
            if [[ "$branch" == "$pattern" ]]; then
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to sync all branches for a repository
sync_all_branches() {
    local repo="$1"
    local upstream="$2" 
    local default_branch="$3"
    local repo_username="$4"
    
    echo "🔄 Starting multi-branch sync for $repo..."
    
    # Get list of upstream branches
    echo "Fetching upstream branches..."
    UPSTREAM_BRANCHES=$(git ls-remote --heads upstream | sed 's/.*refs\/heads\///' | sort)
    
    if [ -z "$UPSTREAM_BRANCHES" ]; then
        echo "⚠️ No upstream branches found"
        return 1
    fi
    
    echo "Found upstream branches: $(echo "$UPSTREAM_BRANCHES" | tr '\n' ' ')"
    
    # Get list of origin branches  
    echo "Fetching origin branches..."
    ORIGIN_BRANCHES=$(git ls-remote --heads origin | sed 's/.*refs\/heads\///' | sort)
    
    echo "Found origin branches: $(echo "$ORIGIN_BRANCHES" | tr '\n' ' ')"
    
    local synced_count=0
    local created_count=0
    local skipped_count=0
    
    # Process each upstream branch
    while IFS= read -r branch; do
        if [ -z "$branch" ]; then
            continue
        fi
        
        echo ""
        echo "--- Processing branch: $branch ---"
        
        # Check if branch should be synced based on mode
        local should_sync=false
        
        case "$SYNC_MODE" in
            "default")
                if [ "$branch" = "$default_branch" ]; then
                    should_sync=true
                fi
                ;;
            "all")
                should_sync=true
                ;;
            "selective")
                if should_sync_branch "$branch" "$SYNC_BRANCHES"; then
                    should_sync=true
                fi
                ;;
        esac
        
        if [ "$should_sync" = false ]; then
            echo "⏭️ Skipping branch $branch (doesn't match sync criteria)"
            ((skipped_count++))
            continue
        fi
        
        # Check if branch exists in origin
        local branch_exists_in_origin=false
        if echo "$ORIGIN_BRANCHES" | grep -q "^${branch}$"; then
            branch_exists_in_origin=true
        fi
        
        if [ "$branch_exists_in_origin" = true ]; then
            # Sync existing branch
            echo "🔄 Syncing existing branch: $branch"
            
            # Checkout the branch
            if git checkout "$branch" 2>/dev/null; then
                echo "✓ Switched to branch $branch"
            else
                echo "📥 Creating local tracking branch for $branch"
                git checkout -b "$branch" "origin/$branch" || {
                    echo "❌ Failed to create local branch $branch"
                    ((skipped_count++))
                    continue
                }
            fi
            
            # Reset to origin state
            echo "🔄 Resetting to origin/$branch..."
            git reset --hard "origin/$branch" || {
                echo "⚠️ Failed to reset to origin state"
            }
            
            # Merge upstream changes
            echo "🔄 Merging upstream/$branch..."
            if git merge "upstream/$branch" --no-edit; then
                echo "✅ Successfully merged upstream/$branch"
                
                # Push changes
                echo "📤 Pushing $branch to origin..."
                PUSH_OUTPUT=$(git push origin "$branch" 2>&1)
                PUSH_EXIT_CODE=$?
                
                # Handle push conflicts
                if [ $PUSH_EXIT_CODE -ne 0 ] && echo "$PUSH_OUTPUT" | grep -q "cannot lock ref"; then
                    echo "🔄 Detected reference lock, attempting force push..."
                    PUSH_OUTPUT=$(git push --force-with-lease origin "$branch" 2>&1)
                    PUSH_EXIT_CODE=$?
                fi
                
                if [ $PUSH_EXIT_CODE -eq 0 ]; then
                    echo "✅ Successfully synced branch $branch"
                    ((synced_count++))
                else
                    echo "❌ Failed to push branch $branch: $PUSH_OUTPUT"
                fi
            else
                echo "❌ Failed to merge upstream/$branch (conflicts may need manual resolution)"
                git merge --abort 2>/dev/null
                ((skipped_count++))
            fi
            
        else
            # Create new branch from upstream
            if [ "$CREATE_NEW_BRANCHES" = "true" ]; then
                echo "📥 Creating new branch from upstream: $branch"
                
                if git checkout -b "$branch" "upstream/$branch"; then
                    echo "✓ Created local branch $branch from upstream"
                    
                    # Push new branch to origin
                    echo "📤 Pushing new branch $branch to origin..."
                    if git push -u origin "$branch"; then
                        echo "✅ Successfully created and pushed new branch $branch"
                        ((created_count++))
                    else
                        echo "❌ Failed to push new branch $branch"
                        # Clean up failed branch
                        git checkout "$default_branch" 2>/dev/null
                        git branch -D "$branch" 2>/dev/null
                    fi
                else
                    echo "❌ Failed to create branch $branch from upstream"
                    ((skipped_count++))
                fi
            else
                echo "⏭️ Skipping creation of new branch $branch (CREATE_NEW_BRANCHES=false)"
                ((skipped_count++))
            fi
        fi
        
    done <<< "$UPSTREAM_BRANCHES"
    
    # Return to default branch
    echo ""
    echo "🔄 Returning to default branch: $default_branch"
    git checkout "$default_branch" 2>/dev/null
    
    # Summary
    echo ""
    echo "📊 Branch sync summary for $repo:"
    echo "   ✅ Synced: $synced_count branches"
    echo "   📥 Created: $created_count branches"  
    echo "   ⏭️ Skipped: $skipped_count branches"
    echo "   🎯 Total processed: $((synced_count + created_count + skipped_count)) branches"
    
    return 0
}

# Function to get usernames to process
get_usernames() {
    local usernames=""
    
    # Priority 1: Command line arguments
    if [ $# -gt 0 ]; then
        usernames="$*"
        echo "Using usernames from command line: $usernames" >&2
    # Priority 2: GITHUB_USERNAMES environment variable (comma or space separated)
    elif [ -n "${GITHUB_USERNAMES}" ]; then
        usernames=$(echo "${GITHUB_USERNAMES}" | tr ',' ' ')
        echo "Using usernames from GITHUB_USERNAMES: $usernames" >&2
    # Priority 3: GITHUB_USERNAME environment variable (single user)
    elif [ -n "${GITHUB_USERNAME}" ]; then
        usernames="${GITHUB_USERNAME}"
        echo "Using username from GITHUB_USERNAME: $usernames" >&2
    # Priority 4: usernames.txt file
    elif [ -f "usernames.txt" ]; then
        usernames=$(grep -v '^#' usernames.txt | grep -v '^[[:space:]]*$' | tr '\n' ' ')
        echo "Using usernames from usernames.txt: $usernames" >&2
    else
        echo "Error: No usernames specified!" >&2
        echo "" >&2
        echo "Please specify usernames using one of these methods:" >&2
        echo "1. Command line: $0 username1 username2 username3" >&2
        echo "2. Environment variable: GITHUB_USERNAMES=\"user1,user2,user3\"" >&2
        echo "3. Environment variable: GITHUB_USERNAME=\"single_user\"" >&2
        echo "4. Create usernames.txt file with one username per line" >&2
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
            # Use token authentication for cloning
            git clone "https://${GITHUB_TOKEN}@github.com/${REPO_USERNAME}/${REPO}.git" || {
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
        
        # Configure git to use token authentication for this repository
        echo "Configuring git authentication..."
        git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${REPO_USERNAME}/${REPO}.git"

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

        # Also fetch from origin to get latest state
        echo "Fetching latest state from origin..."
        git fetch origin || {
            echo "Warning: Failed to fetch from origin, continuing anyway..."
        }

        # Sync branches based on configured mode
        echo ""
        echo "🌟 Starting branch synchronization (mode: $SYNC_MODE)..."
        case "$SYNC_MODE" in
            "default")
                echo "📌 Syncing only default branch: $DEFAULT_BRANCH"
                # Use original single-branch sync logic for default mode
                git checkout "$DEFAULT_BRANCH" || {
                    echo "Failed to checkout branch $DEFAULT_BRANCH"
                    continue
                }
                
                git reset --hard "origin/$DEFAULT_BRANCH" || {
                    echo "Warning: Failed to reset to origin state, continuing anyway..."
                }
                
                git merge "upstream/$DEFAULT_BRANCH" || {
                    echo "Failed to merge upstream changes"
                    continue
                }
                
                PUSH_OUTPUT=$(git push origin "$DEFAULT_BRANCH" 2>&1)
                PUSH_EXIT_CODE=$?
                
                if [ $PUSH_EXIT_CODE -ne 0 ] && echo "$PUSH_OUTPUT" | grep -q "cannot lock ref"; then
                    echo "Detected reference lock issue, attempting force push..."
                    PUSH_OUTPUT=$(git push --force-with-lease origin "$DEFAULT_BRANCH" 2>&1)
                    PUSH_EXIT_CODE=$?
                fi
                ;;
            "all"|"selective")
                echo "🔄 Syncing multiple branches..."
                sync_all_branches "$REPO" "$UPSTREAM" "$DEFAULT_BRANCH" "$REPO_USERNAME"
                PUSH_EXIT_CODE=$?
                ;;
        esac
        
        # Report results
        if [ $PUSH_EXIT_CODE -eq 0 ]; then
            case "$SYNC_MODE" in
                "default")
                    echo "✓ Successfully synced $REPO (user: $REPO_USERNAME)"
                    ;;
                "all"|"selective")
                    echo "✅ Successfully completed multi-branch sync for $REPO (user: $REPO_USERNAME)"
                    ;;
            esac
        else
            case "$SYNC_MODE" in
                "default")
                    # Check if it's a workflow permission issue
                    if echo "$PUSH_OUTPUT" | grep -q "workflow.*scope"; then
                        echo "⚠️ Synced $REPO but couldn't push due to workflow permissions (user: $REPO_USERNAME)"
                        echo "   (Your token needs 'workflow' scope to update .github/workflows/ files)"
                        echo "   Repository is still synced locally"
                    elif echo "$PUSH_OUTPUT" | grep -q "cannot lock ref"; then
                        echo "⚠️ Synced $REPO but couldn't push due to concurrent modifications (user: $REPO_USERNAME)"
                        echo "   This can happen when the repository is being modified during sync"
                        echo "   Repository is synced locally, will retry on next run"
                    else
                        echo "❌ Failed to push changes to $REPO (user: $REPO_USERNAME)"
                        echo "   Error: $PUSH_OUTPUT"
                    fi
                    ;;
                "all"|"selective")
                    echo "⚠️ Multi-branch sync completed with some issues for $REPO (user: $REPO_USERNAME)"
                    echo "   Check the detailed output above for specific branch results"
                    ;;
            esac
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