#!/bin/bash
debug=""

set -euo pipefail

# --- Input Validation / Argument Parsing ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <branch> [<branch> ...] [--prefix <prefix>]"
  echo "Legacy usage is still supported for a single branch: $0 <branch> [prefix]"
  exit 1
fi

prefix=""
branches=()

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix|-p)
      if [ $# -lt 2 ]; then
        echo "Error: --prefix requires a value."
        exit 1
      fi
      prefix="$2"
      shift 2
      ;;
    *)
      branches+=("$1")
      shift
      ;;
  esac
done

# Backward compatibility for old form: <branch> <prefix>
if [ ${#branches[@]} -eq 2 ] && [[ -z "$prefix" ]] && ! git show-ref --verify --quiet "refs/heads/${branches[1]}"; then
  prefix="${branches[1]}"
  branches=("${branches[0]}")
fi

if [ ${#branches[@]} -eq 0 ]; then
  echo "Error: at least one branch is required."
  exit 1
fi

# Validate prefix if provided
if [[ -n "$prefix" && "$prefix" =~ [^a-zA-Z0-9._-] ]]; then
  echo "Error: prefix contains invalid characters. Allowed: a–z, A–Z, 0–9, ., _, -"
  exit 1
fi

# Validate all branch names before any mutation
for branch in "${branches[@]}"; do
  if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
    echo "Error: branch '${branch}' does not exist locally."
    exit 1
  fi
done

for branch in "${branches[@]}"; do
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
done
