#!/bin/bash

# Create and configure a cpuset cgroup.
# Usage: ./create_cpu_cgroup.sh <cgroup_name> <cpu-list>
#
# Example:
#   ./create_cpu_cgroup.sh stress_tool_group 0-16
#
# This script:
# - creates /sys/fs/cgroup/cpuset/<cgroup_name>
# - sets cpuset.cpus to <cpu-list>
# - sets cpuset.cpu_exclusive to 1
# - copies cpuset.mems from the root cpuset
# - prints the command to attach current shell to the cgroup

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cgroup_name> <cpu-list>" >&2
  echo "Example: $0 stress_tool_group 0-16" >&2
  exit 1
fi

CGROUP_NAME="$1"
CPU_LIST="$2"

CPUSET_ROOT="/sys/fs/cgroup/cpuset"
CGROUP_DIR="${CPUSET_ROOT}/${CGROUP_NAME}"

if [ ! -d "$CPUSET_ROOT" ] || [ ! -f "${CPUSET_ROOT}/cpuset.cpus" ]; then
  echo "Error: cpuset cgroup filesystem not found at ${CPUSET_ROOT}" >&2
  echo "Make sure cgroup v1 cpuset is mounted (and you have permissions)." >&2
  exit 1
fi

if ! command -v cgcreate >/dev/null 2>&1; then
  echo "Error: cgcreate not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
  exit 1
fi

echo "Creating cgroup '${CGROUP_NAME}' in cpuset controller"
sudo cgcreate -g "cpuset:${CGROUP_NAME}"

# cpuset requires mems + cpus to be set on the new cgroup before moving tasks.
# Use the root cpuset mems as a default.
echo "Configuring cpuset.cpus=${CPU_LIST}"
echo "$CPU_LIST" | sudo tee "${CGROUP_DIR}/cpuset.cpus" >/dev/null

echo "Configuring cpuset.cpu_exclusive=1"
echo 1 | sudo tee "${CGROUP_DIR}/cpuset.cpu_exclusive" >/dev/null

echo "Configuring cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/cpuset.mems" | sudo tee "${CGROUP_DIR}/cpuset.mems" >/dev/null

echo
echo "To move your CURRENT shell into the cgroup, run:"
echo "  echo \$\$ | sudo tee ${CGROUP_DIR}/tasks"

