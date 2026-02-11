#!/bin/bash
set -euo pipefail

# Rename a branch locally and on remote (if remote branch exists).
# Usage:
#   git-rename.sh <new-branch>                # rename current branch
#   git-rename.sh <old-branch> <new-branch>   # rename specific branch

print_usage() {
  cat <<EOF
Usage:
  $0 <new-branch>
  $0 <old-branch> <new-branch>
  $0 -h|--help

Rename a branch locally and on remote (if old remote branch exists).
EOF
}

if [ $# -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
  print_usage
  exit 0
fi

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  print_usage >&2
  exit 1
fi

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"

if [ $# -eq 1 ]; then
  if [ -z "$current_branch" ]; then
    echo "Error: cannot infer current branch (detached HEAD)." >&2
    exit 1
  fi
  old_branch="$current_branch"
  new_branch="$1"
else
  old_branch="$1"
  new_branch="$2"
fi

if [ "$old_branch" = "$new_branch" ]; then
  echo "Error: old and new branch names are the same." >&2
  exit 1
fi

# Validate old local branch exists.
if ! git show-ref --verify --quiet "refs/heads/${old_branch}"; then
  echo "Error: local branch '${old_branch}' does not exist." >&2
  exit 1
fi

# Prevent clobbering an existing local branch.
if git show-ref --verify --quiet "refs/heads/${new_branch}"; then
  echo "Error: local branch '${new_branch}' already exists." >&2
  exit 1
fi

# Prevent clobbering an existing remote branch.
if git ls-remote --exit-code --heads origin "$new_branch" >/dev/null 2>&1; then
  echo "Error: remote branch 'origin/${new_branch}' already exists." >&2
  exit 1
fi

# Rename local branch (works whether it's checked out or not).
if [ "$current_branch" = "$old_branch" ]; then
  git branch -m "$new_branch"
else
  git branch -m "$old_branch" "$new_branch"
fi
echo "Renamed local branch: '${old_branch}' -> '${new_branch}'"

# Rename remote branch only if the old remote branch exists.
if git ls-remote --exit-code --heads origin "$old_branch" >/dev/null 2>&1; then
  git push origin "refs/heads/${new_branch}:refs/heads/${new_branch}"
  git push origin --delete "$old_branch"
  echo "Renamed remote branch on origin: '${old_branch}' -> '${new_branch}'"
else
  echo "Remote branch 'origin/${old_branch}' not found; skipped remote rename."
fi

# Ensure local branch tracks the new remote name.
git push -u origin "$new_branch" >/dev/null
echo "Set upstream: '${new_branch}' tracks 'origin/${new_branch}'"
