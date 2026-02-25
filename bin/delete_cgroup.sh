#!/bin/bash

# Remove CPU isolation created by create_cpu_cgroup.sh.
# Usage: ./delete_cgroup.sh
#
# Example:
#   ./delete_cgroup.sh
#
# Behavior:
# - cgroup v1: moves tasks back and deletes cpuset cgroups "isolated" + "other".
# - cgroup v2: resets runtime systemd AllowedCPUs properties.

set -euo pipefail

if [ $# -ne 0 ]; then
  echo "Usage: $0" >&2
  echo "Example: $0" >&2
  exit 1
fi

ISO_NAME="isolated"
OTHER_NAME="other"
STATE_FILE="/tmp/create_cpu_cgroup_state_${UID}.env"
CPUSET_ROOT="/sys/fs/cgroup/cpuset"
CGROUP_MODE=""
TASKS_FILE="tasks"
ROOT_CPU_FILE="cpuset.cpus"

if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
  CGROUP_MODE="v2"
  CPUSET_ROOT="/sys/fs/cgroup"
  TASKS_FILE="cgroup.procs"
  ROOT_CPU_FILE="cpuset.cpus.effective"
elif [ -d "$CPUSET_ROOT" ] && [ -f "${CPUSET_ROOT}/cpuset.cpus" ]; then
  CGROUP_MODE="v1"
else
  echo "Error: cpuset cgroup filesystem not found." >&2
  echo "Expected either cgroup v2 at /sys/fs/cgroup or v1 cpuset at /sys/fs/cgroup/cpuset." >&2
  exit 1
fi

ISO_DIR="${CPUSET_ROOT}/${ISO_NAME}"
OTHER_DIR="${CPUSET_ROOT}/${OTHER_NAME}"

if [ "$CGROUP_MODE" = "v2" ]; then
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl not found; required for cgroup v2 cleanup." >&2
    exit 1
  fi

  ROOT_CPU_LIST="$(cat "${CPUSET_ROOT}/${ROOT_CPU_FILE}")"
  echo "Resetting user.slice AllowedCPUs=${ROOT_CPU_LIST}"
  sudo systemctl set-property --runtime user.slice AllowedCPUs="${ROOT_CPU_LIST}"

  current_scope=""
  fallback_other_unit=""
  fallback_taskset_pid=""
  if [ -f "${STATE_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${STATE_FILE}"
    current_scope="${CURRENT_UNIT:-}"
    fallback_other_unit="${FALLBACK_OTHER_UNIT:-}"
    fallback_taskset_pid="${FALLBACK_TASKSET_PID:-}"
  fi

  if [[ "$current_scope" == *.scope || "$current_scope" == *.service || "$current_scope" == *.slice ]]; then
    echo "Resetting unit '${current_scope}' AllowedCPUs=${ROOT_CPU_LIST}"
    sudo systemctl set-property --runtime "${current_scope}" AllowedCPUs="${ROOT_CPU_LIST}" || \
      echo "Warning: failed to reset unit '${current_scope}' (it may already be gone)." >&2
  fi
  if [[ "$fallback_other_unit" == *.scope || "$fallback_other_unit" == *.service || "$fallback_other_unit" == *.slice ]]; then
    echo "Resetting fallback unit '${fallback_other_unit}' AllowedCPUs=${ROOT_CPU_LIST}"
    sudo systemctl set-property --runtime "${fallback_other_unit}" AllowedCPUs="${ROOT_CPU_LIST}" || \
      echo "Warning: failed to reset unit '${fallback_other_unit}' (it may already be gone)." >&2
  fi
  if [ -n "$fallback_taskset_pid" ] && [ -d "/proc/${fallback_taskset_pid}" ] && command -v taskset >/dev/null 2>&1; then
    echo "Resetting PID ${fallback_taskset_pid} affinity to ${ROOT_CPU_LIST}"
    taskset -pc "${ROOT_CPU_LIST}" "${fallback_taskset_pid}" >/dev/null || \
      echo "Warning: failed to reset PID ${fallback_taskset_pid} affinity." >&2
  fi

  rm -f "${STATE_FILE}"

  # Best-effort cleanup if old v2 directories are still present from prior script versions.
  if [ -d "$ISO_DIR" ]; then
    sudo rmdir "$ISO_DIR" 2>/dev/null || true
  fi
  if [ -d "$OTHER_DIR" ]; then
    sudo rmdir "$OTHER_DIR" 2>/dev/null || true
  fi
  exit 0
fi

if ! command -v cgdelete >/dev/null 2>&1; then
  echo "Error: cgdelete not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
  exit 1
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
  sudo cgdelete -g "cpuset:${ISO_NAME}"
fi

if [ -d "$OTHER_DIR" ]; then
  echo "Deleting cgroup '${OTHER_NAME}' from cpuset controller (${CGROUP_MODE})"
  sudo cgdelete -g "cpuset:${OTHER_NAME}"
fi

