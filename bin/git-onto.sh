#!/bin/bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [<last-wip-commit>]" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  git rebase main
else
  git rebase --onto main "$1"
fi
