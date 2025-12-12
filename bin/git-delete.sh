#!/bin/bash
set -euo pipefail

# --- Input Validation ---
if [ $# -eq 0 ]; then
  echo "Usage: $0 <branch> [<branch> ...]"
  exit 1
fi

# Process each branch argument
for branch in "$@"; do
  echo "Processing branch: ${branch}"

  # Check if the branch exists locally
  if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
    echo "Warning: local branch '${branch}' does not exist."
  else
    # Make sure we're not deleting the checked-out branch
    current_branch=$(git symbolic-ref --short HEAD || echo "")
    if [ "$current_branch" = "$branch" ]; then
      git checkout main 2>/dev/null || git checkout master
    fi

    # Delete the local branch
    git branch -D "$branch"
    echo "Deleted local branch '${branch}'"
  fi

  # Delete the remote branch
  if git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
    git push origin --delete "$branch"
    echo "Deleted remote branch '${branch}'"
  else
    echo "Remote branch '${branch}' does not exist on origin."
  fi

  echo ""
done

