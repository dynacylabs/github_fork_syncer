#!/bin/bash

# Ensure required environment variables are set
if [ -z "${GITHUB_TOKEN}" ]; then
    echo "Error: GITHUB_TOKEN is not set."
    exit 1
fi

# Configure Git identity (required for merge operations)
GIT_USER_NAME="${GIT_USER_NAME:-GitHub Fork Syncer}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-github-fork-syncer@users.noreply.github.com}"

git config --global user.name "$GIT_USER_NAME" >/dev/null 2>&1
git config --global user.email "$GIT_USER_EMAIL" >/dev/null 2>&1

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

# Global statistics
TOTAL_REPOS=0
TOTAL_BRANCHES_SYNCED=0
TOTAL_BRANCHES_CREATED=0
TOTAL_ERRORS=0
declare -a ERRORS
declare -a REPO_SUMMARIES

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
    
    local synced_count=0
    local created_count=0
    local error_count=0
    local skipped_count=0
    
    # Get list of upstream branches
    UPSTREAM_BRANCHES=$(git ls-remote --heads upstream 2>/dev/null | sed 's/.*refs\/heads\///' | sort)
    
    if [ -z "$UPSTREAM_BRANCHES" ]; then
        ERRORS+=("$repo: No upstream branches found")
        return 1
    fi
    
    # Get list of origin branches  
    ORIGIN_BRANCHES=$(git ls-remote --heads origin 2>/dev/null | sed 's/.*refs\/heads\///' | sort)
    
    # Process each upstream branch
    while IFS= read -r branch; do
        if [ -z "$branch" ]; then
            continue
        fi
        
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
            if git checkout "$branch" >/dev/null 2>&1 || git checkout -b "$branch" "origin/$branch" >/dev/null 2>&1; then
                git reset --hard "origin/$branch" >/dev/null 2>&1
                
                if git merge "upstream/$branch" --no-edit >/dev/null 2>&1; then
                    if git push origin "$branch" >/dev/null 2>&1 || git push --force-with-lease origin "$branch" >/dev/null 2>&1; then
                        ((synced_count++))
                    else
                        ERRORS+=("$repo/$branch: Push failed")
                        ((error_count++))
                    fi
                else
                    ERRORS+=("$repo/$branch: Merge conflict")
                    git merge --abort 2>/dev/null
                    ((error_count++))
                fi
            else
                ERRORS+=("$repo/$branch: Checkout failed")
                ((error_count++))
            fi
        else
            # Create new branch from upstream
            if [ "$CREATE_NEW_BRANCHES" = "true" ]; then
                if git checkout -b "$branch" "upstream/$branch" >/dev/null 2>&1; then
                    if git push -u origin "$branch" >/dev/null 2>&1; then
                        ((created_count++))
                    else
                        ERRORS+=("$repo/$branch: Push new branch failed")
                        git checkout "$default_branch" 2>/dev/null
                        git branch -D "$branch" 2>/dev/null
                        ((error_count++))
                    fi
                else
                    ERRORS+=("$repo/$branch: Create branch failed")
                    ((error_count++))
                fi
            else
                ((skipped_count++))
            fi
        fi
        
    done <<< "$UPSTREAM_BRANCHES"
    
    # Return to default branch
    git checkout "$default_branch" >/dev/null 2>&1
    
    # Update global counters
    TOTAL_BRANCHES_SYNCED=$((TOTAL_BRANCHES_SYNCED + synced_count))
    TOTAL_BRANCHES_CREATED=$((TOTAL_BRANCHES_CREATED + created_count))
    TOTAL_ERRORS=$((TOTAL_ERRORS + error_count))
    
    # Create summary for this repo
    local summary="$repo: "
    if [ $synced_count -gt 0 ]; then
        summary+="✅ $synced_count synced"
    fi
    if [ $created_count -gt 0 ]; then
        [ $synced_count -gt 0 ] && summary+=", "
        summary+="📥 $created_count created"
    fi
    if [ $error_count -gt 0 ]; then
        [ $synced_count -gt 0 ] || [ $created_count -gt 0 ] && summary+=", "
        summary+="❌ $error_count errors"
    fi
    if [ $synced_count -eq 0 ] && [ $created_count -eq 0 ] && [ $error_count -eq 0 ]; then
        summary+="⏭️  no changes"
    fi
    
    REPO_SUMMARIES+=("$summary")
    
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
    else
        echo "Error: No usernames specified!" >&2
        echo "" >&2
        echo "Please specify usernames using one of these methods:" >&2
        echo "1. Command line: $0 username1 username2 username3" >&2
        echo "2. Environment variable: GITHUB_USERNAMES=\"user1,user2,user3\"" >&2
        echo "3. Environment variable: GITHUB_USERNAME=\"single_user\"" >&2
        exit 1
    fi
    
    echo "$usernames"
}

# Function to process forks for a single user
process_user_forks() {
    local username="$1"
    echo ""
    echo "🔍 Processing forks for user: $username"

    # Get all repositories with more complete information
    API_RESPONSE=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/users/${username}/repos?per_page=100")

    if [ -z "$API_RESPONSE" ]; then
        ERRORS+=("$username: Empty API response")
        return 1
    fi

    # Check if we got an error response
    ERROR_MESSAGE=$(echo "$API_RESPONSE" | jq -r '.message // empty' 2>/dev/null)
    if [ -n "$ERROR_MESSAGE" ]; then
        ERRORS+=("$username: GitHub API Error - $ERROR_MESSAGE")
        return 1
    fi

    # Get list of fork repository names
    FORK_NAMES=$(echo "$API_RESPONSE" | jq -r '.[] | select(.fork == true) | .name' 2>/dev/null)

    if [ -z "$FORK_NAMES" ]; then
        echo "  ℹ️  No forks found for $username"
        return 0
    fi

    local fork_count=$(echo "$FORK_NAMES" | wc -l | tr -d ' ')
    echo "  📦 Found $fork_count fork(s)"

    # For each fork, get detailed information including parent data
    REPOS=""
    while IFS= read -r REPO_NAME; do
        if [ -z "$REPO_NAME" ]; then
            continue
        fi
        
        REPO_DETAIL=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${username}/${REPO_NAME}")
        
        # Check if this call was successful
        DETAIL_ERROR=$(echo "$REPO_DETAIL" | jq -r '.message // empty' 2>/dev/null)
        if [ -n "$DETAIL_ERROR" ]; then
            ERRORS+=("$username/$REPO_NAME: Failed to fetch details - $DETAIL_ERROR")
            continue
        fi
        
        # Extract parent information
        PARENT_FULL_NAME=$(echo "$REPO_DETAIL" | jq -r '.parent.full_name // empty')
        PARENT_DEFAULT_BRANCH=$(echo "$REPO_DETAIL" | jq -r '.parent.default_branch // empty')
        
        if [ -n "$PARENT_FULL_NAME" ] && [ "$PARENT_FULL_NAME" != "null" ]; then
            if [ -z "$PARENT_DEFAULT_BRANCH" ] || [ "$PARENT_DEFAULT_BRANCH" = "null" ]; then
                PARENT_DEFAULT_BRANCH="main"
            fi
            
            REPOS="${REPOS}${REPO_NAME} ${PARENT_FULL_NAME} ${PARENT_DEFAULT_BRANCH} ${username}\n"
        fi
    done <<< "$FORK_NAMES"

    # Check if we found any valid forks with upstream
    if [ -z "$REPOS" ]; then
        echo "  ⚠️  No valid forks with upstream found"
        return 0
    fi

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
            continue
        fi
        
        echo "  🔄 Syncing $REPO..."
        TOTAL_REPOS=$((TOTAL_REPOS + 1))
        
        # Set the repository directory path (include username to avoid conflicts)
        REPO_DIR="$BASE_REPO_DIR/$REPO_USERNAME/$REPO"
        
        # Create user-specific directory
        mkdir -p "$BASE_REPO_DIR/$REPO_USERNAME"
        
        # Check if repository directory exists, if not, clone it
        if [ ! -d "$REPO_DIR" ]; then
            cd "$BASE_REPO_DIR/$REPO_USERNAME"
            if ! git clone "https://${GITHUB_TOKEN}@github.com/${REPO_USERNAME}/${REPO}.git" >/dev/null 2>&1; then
                ERRORS+=("$REPO: Clone failed")
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                continue
            fi
        fi
        
        # Navigate to the repository directory
        cd "$REPO_DIR" || { 
            ERRORS+=("$REPO: Cannot access directory")
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        }
        
        # Verify this is actually a git repository
        if [ ! -d ".git" ]; then
            ERRORS+=("$REPO: Not a git repository")
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi
        
        # Configure git to use token authentication for this repository
        git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${REPO_USERNAME}/${REPO}.git" 2>/dev/null

        # Add upstream remote if not already present
        if git remote get-url upstream &> /dev/null; then
            EXISTING_UPSTREAM=$(git remote get-url upstream)
            EXPECTED_UPSTREAM="https://github.com/$UPSTREAM"
            if [ "$EXISTING_UPSTREAM" != "$EXPECTED_UPSTREAM" ]; then
                git remote set-url upstream "$EXPECTED_UPSTREAM" 2>/dev/null
            fi
        else
            if ! git remote add upstream "https://github.com/$UPSTREAM" 2>/dev/null; then
                ERRORS+=("$REPO: Failed to add upstream remote")
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                continue
            fi
        fi

        # Fetch upstream changes
        if ! git fetch upstream >/dev/null 2>&1; then
            ERRORS+=("$REPO: Failed to fetch upstream")
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

        # Also fetch from origin to get latest state
        git fetch origin >/dev/null 2>&1

        # Sync branches based on configured mode
        case "$SYNC_MODE" in
            "default")
                # Use original single-branch sync logic for default mode
                if git checkout "$DEFAULT_BRANCH" >/dev/null 2>&1; then
                    git reset --hard "origin/$DEFAULT_BRANCH" >/dev/null 2>&1
                    
                    if git merge "upstream/$DEFAULT_BRANCH" --no-edit >/dev/null 2>&1; then
                        if git push origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || git push --force-with-lease origin "$DEFAULT_BRANCH" >/dev/null 2>&1; then
                            TOTAL_BRANCHES_SYNCED=$((TOTAL_BRANCHES_SYNCED + 1))
                            REPO_SUMMARIES+=("$REPO: ✅ 1 synced")
                        else
                            ERRORS+=("$REPO/$DEFAULT_BRANCH: Push failed")
                            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                        fi
                    else
                        ERRORS+=("$REPO/$DEFAULT_BRANCH: Merge conflict")
                        git merge --abort 2>/dev/null
                        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                    fi
                else
                    ERRORS+=("$REPO/$DEFAULT_BRANCH: Checkout failed")
                    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                fi
                ;;
            "all"|"selective")
                sync_all_branches "$REPO" "$UPSTREAM" "$DEFAULT_BRANCH" "$REPO_USERNAME"
                ;;
        esac
        
    done
}

# Main script execution
echo "=========================================="
echo "🔄 GitHub Fork Syncer"
echo "=========================================="

# Get list of usernames to process
USERNAMES=$(get_usernames "$@")

if [ -z "$USERNAMES" ]; then
    echo "❌ No usernames to process"
    exit 1
fi

echo "👥 Users: $USERNAMES"
echo "📋 Mode: $SYNC_MODE"
echo "=========================================="

# Process each username
for USERNAME in $USERNAMES; do
    process_user_forks "$USERNAME"
done

echo ""
echo "=========================================="
echo "📊 SYNC SUMMARY"
echo "=========================================="

# Display repo summaries
if [ ${#REPO_SUMMARIES[@]} -gt 0 ]; then
    echo ""
    echo "Repository Updates:"
    for summary in "${REPO_SUMMARIES[@]}"; do
        echo "  $summary"
    done
fi

# Display statistics
echo ""
echo "Statistics:"
echo "  📦 Repositories processed: $TOTAL_REPOS"
echo "  ✅ Branches synced: $TOTAL_BRANCHES_SYNCED"
echo "  📥 Branches created: $TOTAL_BRANCHES_CREATED"
echo "  ❌ Errors: $TOTAL_ERRORS"

# Display errors if any
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Errors:"
    for error in "${ERRORS[@]}"; do
        echo "  ❌ $error"
    done
    echo ""
    echo "=========================================="
    exit 1
else
    echo ""
    echo "✅ All operations completed successfully!"
    echo "=========================================="
fi