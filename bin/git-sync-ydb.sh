#!/bin/bash

set -e

pushd $HOME/repos/ydb_main

check_status() {
    if [ $? -eq 0 ]; then
        echo "✓ $1 completed successfully"
    else
        echo "✗ Error: $1 failed"
        exit 1
    fi
}

echo "1. Checking git status..."
status_content=`git status --porcelain --untracked-files=no`
if [ $? -eq 0 ] && [ -z "$status_content" ]; then
    echo "✓ Working directory is clean"
else
    echo "✗ Error: Working directory has uncommitted changes"
    echo "Please commit or stash your changes before running this script"
    exit 1
fi

echo "2. Fetching latest main from ydb..."
git fetch ydb main

echo "3. Checking out main branch..."
git checkout main

echo "4. Resetting local main to ydb/main..."
git reset --hard ydb/main

echo "5. Force pushing to origin/main..."
git push origin main --force

echo "=== YDB hard sync completed successfully ==="

popd