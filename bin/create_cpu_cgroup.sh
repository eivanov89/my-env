#!/bin/bash

# Create and configure cpuset cgroups: isolated + other.
# Usage: ./create_cpu_cgroup.sh <isolated-cpu-list>
#
# Example:
#   ./create_cpu_cgroup.sh 0-16
#
# This script:
# - creates cpuset cgroups: isolated + other (cgroup v1 or v2)
# - sets cpuset.cpus for isolated to <isolated-cpu-list>
# - sets cpuset.cpus for other to the remaining CPUs
# - copies cpuset.mems from the root cpuset
# - moves all tasks from the root cpuset to "other"
# - prints the command to attach current shell to "isolated"

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <isolated-cpu-list>" >&2
  echo "Example: $0 0-16" >&2
  exit 1
fi

ISO_NAME="isolated"
OTHER_NAME="other"
ISO_CPU_LIST="$1"

CPUSET_ROOT="/sys/fs/cgroup/cpuset"
CGROUP_MODE=""
TASKS_FILE="tasks"
ROOT_CPU_FILE="cpuset.cpus"
ROOT_MEMS_FILE="cpuset.mems"

if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
  CGROUP_MODE="v2"
  CPUSET_ROOT="/sys/fs/cgroup"
  TASKS_FILE="cgroup.procs"
  ROOT_CPU_FILE="cpuset.cpus.effective"
  ROOT_MEMS_FILE="cpuset.mems.effective"
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
  if ! command -v cgcreate >/dev/null 2>&1; then
    echo "Error: cgcreate not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
    exit 1
  fi
else
  root_controllers="$(cat "${CPUSET_ROOT}/cgroup.controllers")"
  case " ${root_controllers} " in
    *" cpuset "*) ;;
    *)
      echo "Error: cpuset controller is not available in cgroup v2 root." >&2
      exit 1
      ;;
  esac
  root_subtree="$(cat "${CPUSET_ROOT}/cgroup.subtree_control")"
  case " ${root_subtree} " in
    *" cpuset "*) ;;
    *)
      echo "Enabling cpuset controller in cgroup v2 root subtree_control"
      echo "+cpuset" | sudo tee "${CPUSET_ROOT}/cgroup.subtree_control" >/dev/null
      ;;
  esac
fi

normalize_cpu_list() {
  python3 - "$1" <<'PY'
import sys
from typing import Set

def parse(s: str) -> Set[int]:
    cpus: Set[int] = set()
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            a = int(a)
            b = int(b)
            if b < a:
                a, b = b, a
            cpus.update(range(a, b + 1))
        else:
            cpus.add(int(part))
    return cpus

def fmt(cpus: Set[int]) -> str:
    xs = sorted(cpus)
    if not xs:
        return ""
    out = []
    start = prev = xs[0]
    for x in xs[1:]:
        if x == prev + 1:
            prev = x
            continue
        out.append(f"{start}-{prev}" if start != prev else f"{start}")
        start = prev = x
    out.append(f"{start}-{prev}" if start != prev else f"{start}")
    return ",".join(out)

cpus = parse(sys.argv[1])
print(fmt(cpus))
PY
}

calc_other_cpu_list() {
  python3 - "$1" "$2" <<'PY'
import sys
from typing import Set

def parse(s: str) -> Set[int]:
    cpus: Set[int] = set()
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            a = int(a)
            b = int(b)
            if b < a:
                a, b = b, a
            cpus.update(range(a, b + 1))
        else:
            cpus.add(int(part))
    return cpus

def fmt(cpus: Set[int]) -> str:
    xs = sorted(cpus)
    if not xs:
        return ""
    out = []
    start = prev = xs[0]
    for x in xs[1:]:
        if x == prev + 1:
            prev = x
            continue
        out.append(f"{start}-{prev}" if start != prev else f"{start}")
        start = prev = x
    out.append(f"{start}-{prev}" if start != prev else f"{start}")
    return ",".join(out)

root = parse(sys.argv[1])
iso = parse(sys.argv[2])
if not iso:
    sys.stderr.write("Error: isolated CPU list is empty\n")
    sys.exit(2)
if not iso.issubset(root):
    sys.stderr.write("Error: isolated CPUs must be a subset of root cpuset\n")
    sys.exit(3)
other = root - iso
if not other:
    sys.stderr.write("Error: other CPU list is empty\n")
    sys.exit(4)
print(fmt(other))
PY
}

ISO_CPU_LIST="$(normalize_cpu_list "$ISO_CPU_LIST")"
if [ -z "$ISO_CPU_LIST" ]; then
  echo "Error: isolated CPU list is empty after normalization" >&2
  exit 1
fi

ROOT_CPU_LIST="$(cat "${CPUSET_ROOT}/${ROOT_CPU_FILE}")"
OTHER_CPU_LIST="$(calc_other_cpu_list "$ROOT_CPU_LIST" "$ISO_CPU_LIST")"

# cpuset requires mems + cpus to be set on the new cgroup before moving tasks.
# Use the root cpuset mems as a default.
if [ -d "$ISO_DIR" ]; then
  if [ "$(sudo wc -l < "${ISO_DIR}/${TASKS_FILE}")" -gt 0 ]; then
    echo "Error: '${ISO_NAME}' cgroup already has tasks; refusing to modify it." >&2
    exit 1
  fi
else
  echo "Creating cgroup '${ISO_NAME}' in cpuset controller (${CGROUP_MODE})"
  if [ "$CGROUP_MODE" = "v1" ]; then
    sudo cgcreate -g "cpuset:${ISO_NAME}"
  else
    sudo mkdir -p "$ISO_DIR"
  fi
fi

current_iso="$(sudo cat "${ISO_DIR}/cpuset.cpus")"
current_iso_norm="$(normalize_cpu_list "$current_iso")"
if [ "$current_iso_norm" != "$ISO_CPU_LIST" ]; then
  echo "Warning: '${ISO_NAME}' cpuset.cpus differs; updating to ${ISO_CPU_LIST}" >&2
fi
echo "Configuring ${ISO_NAME} cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/${ROOT_MEMS_FILE}" | sudo tee "${ISO_DIR}/cpuset.mems" >/dev/null
echo "Configuring ${ISO_NAME} cpuset.cpus=${ISO_CPU_LIST}"
echo "$ISO_CPU_LIST" | sudo tee "${ISO_DIR}/cpuset.cpus" >/dev/null
if [ "$CGROUP_MODE" = "v1" ]; then
  echo "Configuring ${ISO_NAME} cpuset.cpu_exclusive=1"
  echo 1 | sudo tee "${ISO_DIR}/cpuset.cpu_exclusive" >/dev/null
fi

if [ ! -d "$OTHER_DIR" ]; then
  echo "Creating cgroup '${OTHER_NAME}' in cpuset controller (${CGROUP_MODE})"
  if [ "$CGROUP_MODE" = "v1" ]; then
    sudo cgcreate -g "cpuset:${OTHER_NAME}"
  else
    sudo mkdir -p "$OTHER_DIR"
  fi
fi
echo "Configuring ${OTHER_NAME} cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/${ROOT_MEMS_FILE}" | sudo tee "${OTHER_DIR}/cpuset.mems" >/dev/null
echo "Configuring ${OTHER_NAME} cpuset.cpus=${OTHER_CPU_LIST}"
echo "$OTHER_CPU_LIST" | sudo tee "${OTHER_DIR}/cpuset.cpus" >/dev/null
if [ "$CGROUP_MODE" = "v1" ]; then
  echo "Configuring ${OTHER_NAME} cpuset.cpu_exclusive=0"
  echo 0 | sudo tee "${OTHER_DIR}/cpuset.cpu_exclusive" >/dev/null
fi

echo "Moving tasks from root cpuset to '${OTHER_NAME}'"
sudo sh -c "while read -r pid; do \
  [ -z \"\$pid\" ] && continue; \
  if [ ! -r \"/proc/\$pid/cmdline\" ] || [ ! -s \"/proc/\$pid/cmdline\" ]; then \
    continue; \
  fi; \
  if ! echo \"\$pid\" > \"${OTHER_DIR}/${TASKS_FILE}\" 2>/dev/null; then \
    echo \"Warning: failed to move pid \$pid\" >&2; \
  fi; \
done < \"${CPUSET_ROOT}/${TASKS_FILE}\""

echo
echo "Moving parent shell into '${ISO_NAME}'"
echo "$PPID" | sudo tee "${ISO_DIR}/${TASKS_FILE}" >/dev/null

