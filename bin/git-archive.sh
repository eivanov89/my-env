#!/bin/bash
debug=""

set -euo pipefail

# --- Input Validation ---
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <branch> [prefix]"
  exit 1
fi

branch="$1"
prefix="${2:-}"  # Optional; defaults to empty string

# Validate branch name
if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
  echo "Error: branch '${branch}' does not exist locally."
  exit 1
fi

# Validate prefix if provided
if [[ -n "$prefix" && "$prefix" =~ [^a-zA-Z0-9._-] ]]; then
  echo "Error: prefix contains invalid characters. Allowed: a–z, A–Z, 0–9, ., _, -"
  exit 1
fi

# --- Construct archive branch name ---
if [[ -n "$prefix" ]]; then
  archived_branch="archive/${prefix}/${branch}"
else
  archived_branch="archive/${branch}"
fi

# --- Push the branch to the new remote name ---
$debug git push origin "refs/heads/${branch}:refs/heads/${archived_branch}"

# --- Delete the old remote branch ---
$debug git push origin --delete "${branch}" || true

# --- Checkout another branch to avoid deleting checked-out one ---
current_branch=$(git symbolic-ref --short HEAD || echo "")
if [ "$current_branch" = "$branch" ]; then
  $debug git checkout main 2>/dev/null || git checkout master
fi

# --- Delete the local branch ---
$debug git branch -D "${branch}"

echo "Archived '${branch}' as '${archived_branch}'"
