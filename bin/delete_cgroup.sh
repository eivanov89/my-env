#!/bin/bash

# Delete a cpuset cgroup.
# Usage: ./delete_cgroup.sh <cgroup_name>
#
# Example:
#   ./delete_cgroup.sh stress_tool_group

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cgroup_name>" >&2
  echo "Example: $0 stress_tool_group" >&2
  exit 1
fi

CGROUP_NAME="$1"

if ! command -v cgdelete >/dev/null 2>&1; then
  echo "Error: cgdelete not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
  exit 1
fi

echo "Deleting cgroup '${CGROUP_NAME}' from cpuset controller"
sudo cgdelete -g "cpuset:${CGROUP_NAME}"

