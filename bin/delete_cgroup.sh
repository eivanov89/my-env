#!/bin/bash

# Delete cpuset cgroups: isolated + other.
# Usage: ./delete_cgroup.sh
#
# Example:
#   ./delete_cgroup.sh

set -euo pipefail

if [ $# -ne 0 ]; then
  echo "Usage: $0" >&2
  echo "Example: $0" >&2
  exit 1
fi

ISO_NAME="isolated"
OTHER_NAME="other"
CPUSET_ROOT="/sys/fs/cgroup/cpuset"
ISO_DIR="${CPUSET_ROOT}/${ISO_NAME}"
OTHER_DIR="${CPUSET_ROOT}/${OTHER_NAME}"

if ! command -v cgdelete >/dev/null 2>&1; then
  echo "Error: cgdelete not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
  exit 1
fi

if [ ! -d "$CPUSET_ROOT" ] || [ ! -f "${CPUSET_ROOT}/cpuset.cpus" ]; then
  echo "Error: cpuset cgroup filesystem not found at ${CPUSET_ROOT}" >&2
  echo "Make sure cgroup v1 cpuset is mounted (and you have permissions)." >&2
  exit 1
fi

move_tasks_to_root() {
  local src_dir="$1"
  if [ -d "$src_dir" ]; then
    sudo sh -c "while read -r pid; do echo \"\$pid\" > \"${CPUSET_ROOT}/tasks\"; done < \"${src_dir}/tasks\""
  fi
}

echo "Moving tasks from '${ISO_NAME}' and '${OTHER_NAME}' back to root"
move_tasks_to_root "$ISO_DIR"
move_tasks_to_root "$OTHER_DIR"

if [ -d "$ISO_DIR" ]; then
  echo "Deleting cgroup '${ISO_NAME}' from cpuset controller"
  sudo cgdelete -g "cpuset:${ISO_NAME}"
fi

if [ -d "$OTHER_DIR" ]; then
  echo "Deleting cgroup '${OTHER_NAME}' from cpuset controller"
  sudo cgdelete -g "cpuset:${OTHER_NAME}"
fi

