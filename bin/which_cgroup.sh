#!/usr/bin/env bash
#
# Print cgroup name, sysfs path, and the file to write PIDs into for a process.
# Uses /proc/<PID>/cgroup (same view as the process). Default PID is the current shell.
#
# Usage: ./which_cgroup.sh [PID]

set -euo pipefail

print_usage() {
  echo "Usage: $0 [PID]" >&2
  echo "Print cgroup name, path under /sys/fs/cgroup, and tasks file for PID (default: \$\$)." >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

PID="${1:-$$}"
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
  print_usage
  exit 1
fi

if [ ! -r "/proc/${PID}/cgroup" ]; then
  echo "Error: cannot read /proc/${PID}/cgroup" >&2
  exit 1
fi

CGROUP_FS="/sys/fs/cgroup"
CPUSET_V1_ROOT="${CGROUP_FS}/cpuset"

# cgroup v2 unified hierarchy (line starts with 0::)
line="$(grep '^0::' "/proc/${PID}/cgroup" 2>/dev/null | head -1 || true)"
if [ -n "$line" ]; then
  rel="${line#0::}"
  if [ -z "$rel" ] || [ "$rel" = "/" ]; then
    dir="$CGROUP_FS"
    name="(root)"
  else
    dir="${CGROUP_FS}${rel}"
    name="$(basename "$rel")"
  fi
  echo "Cgroup name: ${name}"
  echo "Cgroup path: ${dir}"
  echo "Tasks file: ${dir}/cgroup.procs"
  echo
  echo "Cross-cgroup migration: you must be allowed to remove the task from its current"
  echo "cgroup (often root-owned). If plain 'echo PID > ...' fails with Permission denied,"
  echo "use: sudo sh -c 'echo PID > ${dir}/cgroup.procs'"
  echo "Use > not >> (append is not supported)."
  printf '  echo $$ > %s\n' "${dir}/cgroup.procs"
  exit 0
fi

# cgroup v1: cpuset controller if present
line="$(grep ':cpuset:' "/proc/${PID}/cgroup" 2>/dev/null | head -1 || true)"
if [ -n "$line" ]; then
  rel="${line##*:}"
  if [ -z "$rel" ] || [ "$rel" = "/" ]; then
    dir="$CPUSET_V1_ROOT"
    name="(cpuset root)"
  else
    dir="${CPUSET_V1_ROOT}${rel}"
    name="$(basename "$rel")"
  fi
  echo "Cgroup name: ${name}"
  echo "Cgroup path: ${dir}"
  echo "Tasks file: ${dir}/tasks"
  echo "If write fails, try: sudo sh -c 'echo PID > ${dir}/tasks'"
  printf '  echo $$ > %s\n' "${dir}/tasks"
  exit 0
fi

echo "Error: no cgroup v2 line (0::) and no :cpuset: line in /proc/${PID}/cgroup" >&2
echo "Raw /proc/${PID}/cgroup:" >&2
cat "/proc/${PID}/cgroup" >&2
exit 1
