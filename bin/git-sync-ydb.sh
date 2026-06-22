#!/bin/bash

set -e

pushd "$HOME/repos/ydb_main"

RED='\033[0;31m'
NC='\033[0m'
BELL='\a'

STEP=""

die() {
    local message="$1"
    local exit_code="${2:-1}"
    echo ""
    printf "${RED}✗ Error: %s (exit status: %d)${NC}\n" "$message" "$exit_code"
    printf "${BELL}"
    popd > /dev/null 2>&1 || true
    exit "$exit_code"
}

fail() {
    die "${1:-Unknown error}" "$?"
}

trap 'fail "$STEP"' ERR

echo "1. Checking git status..."
STEP="Checking git status"
status_content=$(git status --porcelain --untracked-files=no)
if [ -z "$status_content" ]; then
    echo "✓ Working directory is clean"
else
    echo "Please commit or stash your changes before running this script"
    die "Working directory has uncommitted changes"
fi

echo "2. Fetching latest main from ydb..."
STEP="Fetching latest main from ydb"
git fetch ydb main
echo "✓ Fetch completed successfully"

echo "3. Checking out main branch..."
STEP="Checking out main branch"
git checkout main
echo "✓ Checkout completed successfully"

echo "4. Resetting local main to ydb/main..."
STEP="Resetting local main to ydb/main"
git reset --hard ydb/main
echo "✓ Reset completed successfully"

echo "5. Force pushing to origin/main..."
STEP="Force pushing to origin/main"
git push origin main --force
echo "✓ Push completed successfully"

echo "=== YDB hard sync completed successfully ==="

popd
