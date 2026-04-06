#!/usr/bin/env bash
# ============================================================================
# rollout-snyk-cleanup.sh
# Distributes the snyk-cleanup.yml caller workflow to repositories.
#
# Modes:
#   Default    — Only deploys to repos that DON'T have the workflow yet
#   --update   — Also updates repos that ALREADY have the workflow
#                (creates a PR with the new content if it differs)
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - repos.txt in the same directory
#
# Usage:
#   chmod +x rollout-snyk-cleanup.sh
#   ./rollout-snyk-cleanup.sh              # First-time deploy only
#   ./rollout-snyk-cleanup.sh --update     # Deploy + update existing
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="${SCRIPT_DIR}/repos.txt"

# ---- Parse flags ----
UPDATE_MODE=false
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE=true ;;
    *) echo "Unknown flag: $arg"; echo "Usage: $0 [--update]"; exit 1 ;;
  esac
done

BRANCH_NAME="chore/add-snyk-cleanup-workflow"
# Use a different branch name for updates to avoid collision with previous PRs
if [ "$UPDATE_MODE" = true ]; then
  BRANCH_NAME="chore/update-snyk-cleanup-workflow"
fi

WORKFLOW_FILE=".github/workflows/snyk-cleanup.yml"

# ---- Workflow content (single source of truth) ----
# Any changes to this block will be rolled out with --update
read -r -d '' WORKFLOW_CONTENT << 'WORKFLOW_EOF' || true
# Snyk Branch Cleanup — Caller Workflow
# Triggers when a branch is deleted and calls the centralized cleanup workflow.

name: "Snyk Cleanup on Branch Delete"

on:
  delete:

permissions:
  contents: read

jobs:
  snyk-cleanup:
    # Only trigger for branch deletions, not tag deletions
    if: github.event.ref_type == 'branch'
    uses: dhivagar29/.github/.github/workflows/snyk-cleanup-reusable.yml@main
    with:
      deleted_branch: ${{ github.event.ref }}
      repo_name: ${{ github.repository }}
    secrets:
      SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      SNYK_ORG_ID: ${{ secrets.SNYK_ORG_ID }}
WORKFLOW_EOF

# ---- Commit messages and PR content ----
if [ "$UPDATE_MODE" = true ]; then
  COMMIT_MSG="ci: update Snyk branch cleanup workflow"
  PR_TITLE="ci: update Snyk branch cleanup workflow"
  PR_BODY="## What

Updates the Snyk branch cleanup caller workflow with latest changes.

## Why

The workflow content has been modified in the central rollout script and needs
to be propagated to all repositories.

## Testing

1. Create a test branch → push → let Snyk CI scan run
2. Delete the test branch
3. Verify the Snyk dashboard no longer shows projects for that branch
"
else
  COMMIT_MSG="ci: add automated Snyk branch cleanup workflow"
  PR_TITLE="ci: auto-cleanup stale Snyk projects on branch delete"
  PR_BODY="## What

Adds a GitHub Actions workflow that automatically deletes Snyk project data
when a feature branch is deleted. This prevents stale branch scan results
from cluttering the Snyk dashboard.

## How it works

1. Triggers on the \`delete\` event (branch deletion only)
2. Calls a centralized reusable workflow in \`dhivagar29/.github\`
3. Queries Snyk REST API for projects matching the deleted branch
4. Deletes all matching projects with retry logic and error handling
5. Protected branches (main, master, develop, release/*, hotfix/*) are never affected

## Testing

1. Create a test branch → push → let Snyk CI scan run
2. Delete the test branch
3. Verify the Snyk dashboard no longer shows projects for that branch
"
fi

# ---- Preflight checks ----
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) is not installed."
  echo "Install it from: https://cli.github.com/"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "ERROR: GitHub CLI is not authenticated."
  echo ""
  echo "  Authenticate: export GH_TOKEN=ghp_your_token_here"
  echo "  OR run:       gh auth login"
  exit 1
fi

if [ ! -f "$REPOS_FILE" ]; then
  echo "ERROR: repos.txt not found at $REPOS_FILE"
  exit 1
fi

MODE_LABEL="DEPLOY (new repos only)"
if [ "$UPDATE_MODE" = true ]; then
  MODE_LABEL="DEPLOY + UPDATE (all repos)"
fi

echo "============================================="
echo "  Snyk Cleanup Workflow Rollout"
echo "============================================="
echo "  Mode: $MODE_LABEL"
echo "  Auth: $(gh auth status 2>&1 | head -3 | tail -1 | xargs)"
echo "  Repos file: $REPOS_FILE"
echo "============================================="
echo ""

# ---- Counters ----
SUCCESS=0
FAILED=0
SKIPPED=0
UNCHANGED=0

# ---- Process each repo ----
while IFS= read -r REPO || [ -n "$REPO" ]; do
  # Skip empty lines and comments
  [[ -z "$REPO" || "$REPO" =~ ^# ]] && continue
  REPO=$(echo "$REPO" | xargs)  # trim whitespace

  echo "→ Processing: $REPO"

  # Check if workflow already exists on default branch
  WORKFLOW_EXISTS=false
  if gh api "repos/${REPO}/contents/${WORKFLOW_FILE}" --silent 2>/dev/null; then
    WORKFLOW_EXISTS=true
  fi

  # Decide whether to proceed based on mode
  if [ "$WORKFLOW_EXISTS" = true ] && [ "$UPDATE_MODE" = false ]; then
    echo "  ⚠ Workflow already exists. Skipping. (use --update to push changes)"
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi

  # Check if the update branch already exists (from a previous run)
  if gh api "repos/${REPO}/git/ref/heads/${BRANCH_NAME}" --silent 2>/dev/null; then
    echo "  ⚠ Branch '${BRANCH_NAME}' already exists. Skipping (delete branch first if you want to retry)."
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi

  # Create a fresh temp directory for this repo
  WORK_DIR=$(mktemp -d -t 'snyk-rollout-XXXXXX')

  # Clone into a subdirectory to keep temp dir structure clean
  if gh repo clone "$REPO" "$WORK_DIR/repo" -- --depth 1 2>/dev/null; then
    cd "$WORK_DIR/repo"

    # If updating, check if content actually differs
    if [ "$WORKFLOW_EXISTS" = true ]; then
      EXISTING_CONTENT=""
      if [ -f "$WORKFLOW_FILE" ]; then
        EXISTING_CONTENT=$(cat "$WORKFLOW_FILE")
      fi

      if [ "$EXISTING_CONTENT" = "$WORKFLOW_CONTENT" ]; then
        echo "  ✓ Workflow content is already up to date. No changes needed."
        UNCHANGED=$((UNCHANGED + 1))
        cd "$SCRIPT_DIR"
        rm -rf "$WORK_DIR"
        echo ""
        continue
      fi

      echo "  ℹ Workflow exists but content differs. Creating update PR..."
    fi

    # Create branch
    git checkout -b "$BRANCH_NAME" 2>/dev/null

    # Write the caller workflow
    mkdir -p .github/workflows
    echo "$WORKFLOW_CONTENT" > "$WORKFLOW_FILE"

    git add "$WORKFLOW_FILE"

    # Check if there are actually changes to commit
    if git diff --cached --quiet 2>/dev/null; then
      echo "  ✓ No changes detected after write. Already up to date."
      UNCHANGED=$((UNCHANGED + 1))
      cd "$SCRIPT_DIR"
      rm -rf "$WORK_DIR"
      echo ""
      continue
    fi

    git commit -m "$COMMIT_MSG" --quiet

    # Push branch
    if git push origin "$BRANCH_NAME" --quiet 2>/dev/null; then
      echo "  ✓ Branch pushed"

      # Create PR
      if gh pr create \
        --repo "$REPO" \
        --head "$BRANCH_NAME" \
        --title "$PR_TITLE" \
        --body "$PR_BODY" \
        2>/dev/null; then
        echo "  ✓ PR created"
      else
        echo "  ✓ Branch pushed (PR may need manual creation)"
      fi
      SUCCESS=$((SUCCESS + 1))
    else
      echo "  ✗ Failed to push branch"
      FAILED=$((FAILED + 1))
    fi

    # Return to the script directory BEFORE cleaning up temp dir
    cd "$SCRIPT_DIR"
  else
    echo "  ✗ Failed to clone repo (check permissions)"
    FAILED=$((FAILED + 1))
  fi

  # Clean up temp directory
  rm -rf "$WORK_DIR"
  echo ""

done < "$REPOS_FILE"

echo "============================================="
echo "  Rollout Summary"
echo "============================================="
echo "  PRs created:  $SUCCESS"
echo "  Up to date:   $UNCHANGED"
echo "  Skipped:      $SKIPPED"
echo "  Failed:       $FAILED"
echo "  Total repos:  $((SUCCESS + UNCHANGED + SKIPPED + FAILED))"
echo "============================================="

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Some repos failed. Check the logs above and verify:"
  echo "  1. Your PAT has 'Contents: Read+Write' and 'Pull requests: Read+Write'"
  echo "  2. The repos exist and are accessible"
  exit 1
fi
