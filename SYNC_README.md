# SYNC.sh - Branch Synchronization Guide

## Overview

`SYNC.sh` maintains the `PnyxAI` branch as a synchronized pivot between the upstream `EleutherAI/lm-evaluation-harness` repository and the `pnyxai/lm-evaluation-harness` fork.

The script ensures the following branch structure:
1. Base synced with `EleutherAI/lm-evaluation-harness` main branch
2. Single "sync scipts and tools" commit containing `SYNC.sh`, `.gitignore` updates and this `SYNC_README.md`
3. All active branches from `pnyxai/lm-evaluation-harness` merged on top

## Basic Usage

### Full Synchronization
```bash
./SYNC.sh
```

Performs a complete sync:
1. Fetches latest changes from upstream
2. Undoes all previous branch merges
3. Rebases PnyxAI onto updated upstream main
4. Re-applies the sync commit
5. Re-merges all active branches from origin

### Preview Changes (Dry-Run)
```bash
./SYNC.sh --dry-run
```

Reports what would happen without making any changes. Useful for:
- Verifying before running the full sync
- Understanding what branches would be merged
- Checking for potential issues

## Advanced Options

### Undo Branch Merges Only
```bash
./SYNC.sh --undo-branch-merges
```

Removes all previously merged branch commits while keeping the "sync scipts and tools" commit. Use when:
- You want to clean up merged branches before a fresh sync
- You need to reset the merge state without affecting the base
- Troubleshooting merge conflicts

### Combine Options
```bash
./SYNC.sh --undo-branch-merges --dry-run
```

Flags can be combined in any order to preview undo operations.

## Prerequisites

- Must be on the `PnyxAI` branch
- Working directory must be clean (no uncommitted changes)
- Both `upstream` and `origin` remotes must be configured
- No existing rebase or merge in progress

## How It Works

### Step 1: Fetch from Upstream
Downloads latest changes from `EleutherAI/lm-evaluation-harness`.

### Step 2: Identify Active Branches
Detects all branches in `pnyxai/lm-evaluation-harness` (except `main` and `PnyxAI`).

### Step 3: Undo Previous Merges
Resets to the parent of the "sync scipts and tools" commit, removing all merged branches from the working state.

### Step 4: Stash Sync Changes
Preserves any modifications from the sync commit (`SYNC.sh`, `.gitignore` and `SYNC_README.md`).

### Step 5: Rebase onto Updated Main
Rebases PnyxAI onto the freshly fetched upstream main branch.

### Step 6: Re-apply Sync Changes
Restores the stashed sync commit with its original message.

### Step 7: Merge Active Branches
Re-merges all detected active branches in sequence.

## Error Handling

If any conflicts occur during the sync process:
- The script aborts immediately
- All changes are rolled back
- The repository returns to its original state
- An error message explains what failed

This ensures the repository is never left in an inconsistent state.

## Common Scenarios

### Scenario 1: Regular Sync
Keep PnyxAI in sync with upstream while maintaining custom branches.
```bash
./SYNC.sh
```

### Scenario 2: Check Before Syncing
Preview what will happen before committing to changes.
```bash
./SYNC.sh --dry-run
```

### Scenario 3: Clean Merge State
Reset branch merges without affecting the sync commit.
```bash
./SYNC.sh --undo-branch-merges
```

### Scenario 4: Troubleshoot Merge Issues
See what would happen if you reset the merge state (without actually doing it).
```bash
./SYNC.sh --undo-branch-merges --dry-run
```

## Git State After Sync

After a successful `./SYNC.sh`, the branch structure looks like:
```
HEAD -> PnyxAI
  └─ Merge: add-ifbench
     └─ Merge: add-evaluation-process-workers-and-tqdm
        └─ sync scipts and tools
           └─ ... (upstream main commits)
```

## Troubleshooting

### "Working directory has uncommitted changes"
Commit or stash all changes before running SYNC.sh:
```bash
git add .
git commit -m "your message"
```

### "Rebase failed - conflicts detected"
Manual merge conflict resolution was required. The script has rolled back automatically. You may need to:
1. Review conflicting changes
2. Fix manually if needed
3. Run SYNC.sh again

### "No active branches found to merge"
This is normal when all custom branches have been deleted from the origin. The script continues without merging any additional branches.

## Help

View detailed usage information:
```bash
./SYNC.sh --help
```
