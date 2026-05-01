#!/bin/bash

##############################################################################
# SYNC.sh - Synchronize PnyxAI branch with upstream EleutherAI repository
#
# This script maintains the PnyxAI branch structure:
# 1. Base synced with EleutherAI/lm-evaluation-harness main
# 2. Single "sync scipts and tools" commit with SYNC.sh and .gitignore updates
# 3. All active branches from pnyxai/lm-evaluation-harness merged on top
#
# Usage: ./SYNC.sh [OPTIONS]
##############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DRY_RUN=false
UNDO_BRANCH_MERGES=false
SYNC_BRANCH="PnyxAI"
UPSTREAM_REMOTE="upstream"
ORIGIN_REMOTE="origin"
SYNC_COMMIT_MSG="sync scipts and tools"
IGNORE_BRANCHES=""  # Comma-separated list of branches to ignore

# Rollback state
ORIGINAL_BRANCH=""
ORIGINAL_HEAD=""
ROLLBACK_EXECUTED=false

##############################################################################
# Utility Functions
##############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

print_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}========================================${NC}"
}

dry_run_prefix() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] "
    fi
}

git_cmd() {
    local cmd=("$@")
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)git ${cmd[*]}"
    else
        git "${cmd[@]}"
    fi
}

##############################################################################
# Validation and Setup
##############################################################################

validate_prerequisites() {
    print_section "Validating Prerequisites"
    
    # Check if we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi
    
    # Check if we're on PnyxAI branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$CURRENT_BRANCH" != "$SYNC_BRANCH" ]; then
        log_error "Must be on $SYNC_BRANCH branch (currently on $CURRENT_BRANCH)"
        exit 1
    fi
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        log_error "Working directory has uncommitted changes. Please commit or stash them."
        exit 1
    fi
    
    # Check if remotes exist
    if ! git remote | grep -q "^$UPSTREAM_REMOTE$"; then
        log_error "Upstream remote '$UPSTREAM_REMOTE' not found"
        exit 1
    fi
    
    if ! git remote | grep -q "^$ORIGIN_REMOTE$"; then
        log_error "Origin remote '$ORIGIN_REMOTE' not found"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

setup_rollback() {
    ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    ORIGINAL_HEAD=$(git rev-parse HEAD)
    log_info "Rollback checkpoint: $ORIGINAL_BRANCH @ $ORIGINAL_HEAD"
}

cleanup_on_error() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
        if [ "$DRY_RUN" = false ] && [ "$ROLLBACK_EXECUTED" = false ]; then
            rollback
        fi
    fi
    
    exit $exit_code
}

rollback() {
    print_section "Rolling Back Changes"
    
    if [ -z "$ORIGINAL_HEAD" ]; then
        log_error "No rollback checkpoint available"
        exit 1
    fi
    
    ROLLBACK_EXECUTED=true
    
    log_warning "Reverting to original state: $ORIGINAL_BRANCH @ $ORIGINAL_HEAD"
    
    # Reset to original HEAD
    git reset --hard "$ORIGINAL_HEAD"
    
    # Return to original branch if different
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "$ORIGINAL_BRANCH" ]; then
        git checkout "$ORIGINAL_BRANCH"
    fi
    
    log_success "Rollback completed"
}

trap cleanup_on_error EXIT

##############################################################################
# Step 1: Fetch from Upstream
##############################################################################

fetch_and_fastforward() {
    print_section "Step 1: Fetch from Upstream"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)Fetching from $UPSTREAM_REMOTE"
        git fetch "$UPSTREAM_REMOTE" 2>&1 | head -20 || true
        return
    fi
    
    log_info "Fetching from $UPSTREAM_REMOTE"
    git fetch "$UPSTREAM_REMOTE"
    
    log_success "Fetch completed"
}

##############################################################################
# Step 2: Get Active Branches from Origin
##############################################################################

get_active_branches() {
    print_section "Step 2: Identifying Active Branches"
    
    # Get all branches from origin using ls-remote (most accurate)
    local branches=()
    while IFS=$'\t' read -r sha ref; do
        # Extract branch name from "refs/heads/branch-name"
        local branch="${ref#refs/heads/}"
        
        # Skip main and PnyxAI (only add if not these special branches)
        if [ "$branch" != "main" ] && [ "$branch" != "$SYNC_BRANCH" ]; then
            branches+=("$branch")
        fi
    done < <(git ls-remote --heads "$ORIGIN_REMOTE")
    
    # Print active branches
    if [ ${#branches[@]} -eq 0 ]; then
        log_warning "No active branches found to merge"
    else
        log_info "Found ${#branches[@]} active branch(es):"
        for branch in "${branches[@]}"; do
            log_info "  - $branch"
        done
    fi
    
    # Return branches as array via global variable
    ACTIVE_BRANCHES=("${branches[@]}")
}

##############################################################################
# Step 3: Undo Previous Merges
##############################################################################

undo_branch_merges() {
    print_section "Step 3: Undoing Previous Branch Merges"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)Would undo all non-sync commits"
        return
    fi
    
    log_info "Finding merge commits and non-sync commits to undo..."
    
    # Find the "sync scipts and tools" commit
    SYNC_COMMIT=$(git log --oneline --all | grep "sync scipts and tools" | head -1 | awk '{print $1}')
    
    if [ -z "$SYNC_COMMIT" ]; then
        log_warning "No 'sync scipts and tools' commit found"
        return
    fi
    
    log_info "Found sync commit: $SYNC_COMMIT"
    
    # Get parent of sync commit (should be upstream/main equivalent)
    SYNC_COMMIT_PARENT=$(git rev-parse "$SYNC_COMMIT^")
    
    log_info "Resetting to parent of sync commit: $SYNC_COMMIT_PARENT"
    git reset --hard "$SYNC_COMMIT_PARENT"
    
    log_success "Previous merges undone"
}

##############################################################################
# Step 4: Preserve Sync Files
##############################################################################

preserve_sync_files() {
    print_section "Step 4: Preserving Sync Files"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)Would preserve SYNC.sh, .gitignore, and SYNC_README.md"
        return
    fi
    
    log_info "Saving sync files to temporary storage..."
    
    # Create a temporary directory to store files
    SYNC_TEMP_DIR=$(mktemp -d)
    export SYNC_TEMP_DIR
    
    # Save each sync file
    for file in "SYNC.sh" ".gitignore" "SYNC_README.md"; do
        if [ -f "$file" ]; then
            cp "$file" "$SYNC_TEMP_DIR/$file"
            log_info "Saved $file"
        fi
    done
    
    log_success "Sync files preserved in temporary storage"
}

##############################################################################
# Step 5: Rebase onto Updated Main
##############################################################################

rebase_onto_main() {
    print_section "Step 5: Rebasing PnyxAI onto Updated Main"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)Would rebase $SYNC_BRANCH onto $UPSTREAM_REMOTE/main"
        return
    fi
    
    log_info "Fetching latest main from upstream..."
    git fetch "$UPSTREAM_REMOTE" main
    
    log_info "Rebasing $SYNC_BRANCH onto $UPSTREAM_REMOTE/main..."
    
    if ! git rebase "$UPSTREAM_REMOTE/main"; then
        log_error "Rebase failed - conflicts detected"
        log_error "Manual resolution required or SYNC aborted"
        git rebase --abort
        return 1
    fi
    
    log_success "Rebase completed"
}

##############################################################################
# Step 6: Re-apply Stashed Changes and Commit
##############################################################################

reapply_sync_changes() {
    print_section "Step 6: Restoring Sync Files and Creating Sync Commit"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "$(dry_run_prefix)Would restore sync files and create sync commit"
        return
    fi
    
    # Restore from temporary storage
    if [ -n "${SYNC_TEMP_DIR:-}" ] && [ -d "$SYNC_TEMP_DIR" ]; then
        log_info "Restoring sync files from temporary storage..."
        
        for file in "SYNC.sh" ".gitignore" "SYNC_README.md"; do
            if [ -f "$SYNC_TEMP_DIR/$file" ]; then
                cp "$SYNC_TEMP_DIR/$file" "$file"
                log_info "Restored $file"
            fi
        done
        
        # Clean up temporary directory
        rm -rf "$SYNC_TEMP_DIR"
        unset SYNC_TEMP_DIR
    else
        log_error "Sync files temporary storage not found"
        return 1
    fi
    
    # Stage the sync files
    log_info "Staging sync files..."
    git add SYNC.sh .gitignore SYNC_README.md
    
    # Create the sync commit
    if ! git diff --cached --quiet; then
        log_info "Creating sync commit..."
        git commit -m "$SYNC_COMMIT_MSG"
        log_success "Sync commit created with all sync files"
    else
        log_error "No changes to commit in sync files"
        return 1
    fi
}

##############################################################################
# Utility: Check if branch should be ignored
##############################################################################

should_ignore_branch() {
    local branch="$1"
    
    # If no ignore list, don't ignore anything
    if [ -z "$IGNORE_BRANCHES" ]; then
        return 1  # false (don't ignore)
    fi
    
    # Check if branch is in the ignore list
    # Convert comma-separated list to space-separated for easy iteration
    local ignore_list="${IGNORE_BRANCHES//,/ }"
    
    for ignored_branch in $ignore_list; do
        # Trim whitespace from ignored_branch
        ignored_branch=$(echo "$ignored_branch" | xargs)
        
        if [ "$branch" = "$ignored_branch" ]; then
            return 0  # true (should ignore)
        fi
    done
    
    return 1  # false (don't ignore)
}

##############################################################################
# Step 7: Merge Active Branches
##############################################################################

merge_active_branches() {
    print_section "Step 7: Merging Active Branches"
    
    if [ ${#ACTIVE_BRANCHES[@]} -eq 0 ]; then
        log_warning "No active branches to merge"
        return
    fi
    
    local ignored_count=0
    
    # Log ignored branches if any
    if [ -n "$IGNORE_BRANCHES" ]; then
        log_info "Ignoring branches: $IGNORE_BRANCHES"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        for branch in "${ACTIVE_BRANCHES[@]}"; do
            if should_ignore_branch "$branch"; then
                log_info "$(dry_run_prefix)[IGNORED] $branch"
                ((ignored_count++))
            else
                log_info "$(dry_run_prefix)Would merge $ORIGIN_REMOTE/$branch into $SYNC_BRANCH"
            fi
        done
        return
    fi
    
    local merge_count=0
    
    for branch in "${ACTIVE_BRANCHES[@]}"; do
        if should_ignore_branch "$branch"; then
            log_warning "Skipping ignored branch: $branch"
            ((ignored_count++))
            continue
        fi
        
        log_info "Merging $ORIGIN_REMOTE/$branch..."
        
        # Attempt merge
        if git merge "$ORIGIN_REMOTE/$branch" --no-edit; then
            ((merge_count++))
            log_success "Merged $branch"
        else
            log_error "Merge conflict detected in $branch"
            log_error "Aborting merge and rolling back"
            git merge --abort
            return 1
        fi
    done
    
    log_success "Successfully merged $merge_count branch(es)"
    if [ $ignored_count -gt 0 ]; then
        log_info "Ignored $ignored_count branch(es)"
    fi
}

##############################################################################
# Help Text
##############################################################################

show_help() {
    cat << 'EOF'
SYNC.sh - Synchronize PnyxAI branch with upstream repository

USAGE:
    ./SYNC.sh [OPTIONS]

OPTIONS:
    --dry-run                       Run in dry-run mode (report changes without applying them)
    --undo-branch-merges            Undo all branch merges only (skip sync with upstream)
    --ignore-branches BRANCHES      Comma-separated list of branches to skip during merge
    --help, -h                      Show this help message

DESCRIPTION:
    This script maintains the PnyxAI branch structure:
    1. Syncs base with EleutherAI/lm-evaluation-harness main branch
    2. Preserves a "sync scipts and tools" commit with SYNC.sh and .gitignore
    3. Merges all active branches from pnyxai/lm-evaluation-harness

    If any conflicts occur during the process, all changes are rolled back
    and the repository is left in its original state.

    The --undo-branch-merges option removes previously merged branch commits,
    leaving only the sync commit on top of the upstream main branch.

    The --ignore-branches option allows you to skip specific branches during the
    merge process. Provide a comma-separated list of branch names (with or without spaces).

EXAMPLES:
    ./SYNC.sh --dry-run                   # Preview what would happen
    ./SYNC.sh                             # Execute the full sync
    ./SYNC.sh --undo-branch-merges        # Undo all branch merges
    ./SYNC.sh --undo-branch-merges --dry-run  # Preview undo operation
    ./SYNC.sh --ignore-branches "feature-a,feature-b"  # Skip specific branches
    ./SYNC.sh --ignore-branches "wip-feature,old-branch" --dry-run  # Preview with ignored branches
EOF
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                log_info "Running in DRY-RUN mode (no changes will be made)"
                shift
                ;;
            --undo-branch-merges)
                UNDO_BRANCH_MERGES=true
                shift
                ;;
            --ignore-branches)
                if [ -z "${2:-}" ]; then
                    log_error "--ignore-branches requires a value (comma-separated branch names)"
                    show_help
                    exit 1
                fi
                IGNORE_BRANCHES="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo ""
    log_info "Starting SYNC.sh script"
    log_info "Branch: $SYNC_BRANCH"
    log_info "Upstream: $UPSTREAM_REMOTE"
    log_info "Origin: $ORIGIN_REMOTE"
    if [ -n "$IGNORE_BRANCHES" ]; then
        log_info "Ignored branches: $IGNORE_BRANCHES"
    fi
    
    # Validate and setup
    validate_prerequisites
    setup_rollback
    
    # Execute undo-branch-merges if requested
    if [ "$UNDO_BRANCH_MERGES" = true ]; then
        print_section "Undo Branch Merges Mode"
        undo_branch_merges || exit 1
        
        if [ "$DRY_RUN" = false ]; then
            print_section "Undo Complete"
            log_success "Branch merges have been undone"
            log_info "Current HEAD: $(git rev-parse --short HEAD)"
        else
            print_section "Undo Complete (DRY-RUN)"
            log_info "DRY-RUN mode: no changes were actually made"
        fi
        return
    fi
    
    # Execute full sync steps
    fetch_and_fastforward || exit 1
    get_active_branches
    preserve_sync_files || exit 1
    undo_branch_merges || exit 1
    rebase_onto_main || exit 1
    reapply_sync_changes || exit 1
    merge_active_branches || exit 1
    
    # Success
    print_section "SYNC Complete"
    log_success "PnyxAI branch is now synced!"
    log_info "Current HEAD: $(git rev-parse --short HEAD)"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN mode: no changes were actually made"
        log_info "Run without --dry-run to apply changes"
    fi
}

main "$@"
