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
CGROUP_MODE=""
TASKS_FILE="tasks"

if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
  CGROUP_MODE="v2"
  CPUSET_ROOT="/sys/fs/cgroup"
  TASKS_FILE="cgroup.procs"
elif [ -d "$CPUSET_ROOT" ] && [ -f "${CPUSET_ROOT}/cpuset.cpus" ]; then
  CGROUP_MODE="v1"
else
  echo "Error: cpuset cgroup filesystem not found." >&2
  echo "Expected either cgroup v2 at /sys/fs/cgroup or v1 cpuset at /sys/fs/cgroup/cpuset." >&2
  exit 1
fi

ISO_DIR="${CPUSET_ROOT}/${ISO_NAME}"
OTHER_DIR="${CPUSET_ROOT}/${OTHER_NAME}"

if [ "$CGROUP_MODE" = "v1" ]; then
  if ! command -v cgdelete >/dev/null 2>&1; then
    echo "Error: cgdelete not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
    exit 1
  fi
fi

move_tasks_to_root() {
  local src_dir="$1"
  if [ -d "$src_dir" ] && [ -f "${src_dir}/${TASKS_FILE}" ]; then
    sudo sh -c "while read -r pid; do \
      [ -z \"\$pid\" ] && continue; \
      echo \"\$pid\" > \"${CPUSET_ROOT}/${TASKS_FILE}\" 2>/dev/null || true; \
    done < \"${src_dir}/${TASKS_FILE}\""
  fi
}

echo "Moving tasks from '${ISO_NAME}' and '${OTHER_NAME}' back to root"
move_tasks_to_root "$ISO_DIR"
move_tasks_to_root "$OTHER_DIR"

if [ -d "$ISO_DIR" ]; then
  echo "Deleting cgroup '${ISO_NAME}' from cpuset controller (${CGROUP_MODE})"
  if [ "$CGROUP_MODE" = "v1" ]; then
    sudo cgdelete -g "cpuset:${ISO_NAME}"
  else
    sudo rmdir "$ISO_DIR"
  fi
fi

if [ -d "$OTHER_DIR" ]; then
  echo "Deleting cgroup '${OTHER_NAME}' from cpuset controller (${CGROUP_MODE})"
  if [ "$CGROUP_MODE" = "v1" ]; then
    sudo cgdelete -g "cpuset:${OTHER_NAME}"
  else
    sudo rmdir "$OTHER_DIR"
  fi
fi

