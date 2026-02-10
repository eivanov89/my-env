#!/bin/bash

# Create and configure cpuset cgroups: isolated + other.
# Usage: ./create_cpu_cgroup.sh <isolated-cpu-list>
#
# Example:
#   ./create_cpu_cgroup.sh 0-16
#
# This script:
# - creates /sys/fs/cgroup/cpuset/isolated and /sys/fs/cgroup/cpuset/other
# - sets cpuset.cpus for isolated to <isolated-cpu-list> (cpu_exclusive=1)
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
ISO_DIR="${CPUSET_ROOT}/${ISO_NAME}"
OTHER_DIR="${CPUSET_ROOT}/${OTHER_NAME}"

if [ ! -d "$CPUSET_ROOT" ] || [ ! -f "${CPUSET_ROOT}/cpuset.cpus" ]; then
  echo "Error: cpuset cgroup filesystem not found at ${CPUSET_ROOT}" >&2
  echo "Make sure cgroup v1 cpuset is mounted (and you have permissions)." >&2
  exit 1
fi

if ! command -v cgcreate >/dev/null 2>&1; then
  echo "Error: cgcreate not found. Install libcgroup tools (e.g. 'cgroup-tools' / 'libcgroup')." >&2
  exit 1
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

ROOT_CPU_LIST="$(cat "${CPUSET_ROOT}/cpuset.cpus")"
OTHER_CPU_LIST="$(calc_other_cpu_list "$ROOT_CPU_LIST" "$ISO_CPU_LIST")"

# cpuset requires mems + cpus to be set on the new cgroup before moving tasks.
# Use the root cpuset mems as a default.
if [ -d "$ISO_DIR" ]; then
  if [ "$(sudo wc -l < "${ISO_DIR}/tasks")" -gt 0 ]; then
    echo "Error: '${ISO_NAME}' cgroup already has tasks; refusing to modify it." >&2
    exit 1
  fi
else
  echo "Creating cgroup '${ISO_NAME}' in cpuset controller"
  sudo cgcreate -g "cpuset:${ISO_NAME}"
fi

current_iso="$(sudo cat "${ISO_DIR}/cpuset.cpus")"
current_iso_norm="$(normalize_cpu_list "$current_iso")"
if [ "$current_iso_norm" != "$ISO_CPU_LIST" ]; then
  echo "Warning: '${ISO_NAME}' cpuset.cpus differs; updating to ${ISO_CPU_LIST}" >&2
fi
echo "Configuring ${ISO_NAME} cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/cpuset.mems" | sudo tee "${ISO_DIR}/cpuset.mems" >/dev/null
echo "Configuring ${ISO_NAME} cpuset.cpus=${ISO_CPU_LIST}"
echo "$ISO_CPU_LIST" | sudo tee "${ISO_DIR}/cpuset.cpus" >/dev/null
echo "Configuring ${ISO_NAME} cpuset.cpu_exclusive=1"
echo 1 | sudo tee "${ISO_DIR}/cpuset.cpu_exclusive" >/dev/null

if [ ! -d "$OTHER_DIR" ]; then
  echo "Creating cgroup '${OTHER_NAME}' in cpuset controller"
  sudo cgcreate -g "cpuset:${OTHER_NAME}"
fi
echo "Configuring ${OTHER_NAME} cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/cpuset.mems" | sudo tee "${OTHER_DIR}/cpuset.mems" >/dev/null
echo "Configuring ${OTHER_NAME} cpuset.cpus=${OTHER_CPU_LIST}"
echo "$OTHER_CPU_LIST" | sudo tee "${OTHER_DIR}/cpuset.cpus" >/dev/null
echo "Configuring ${OTHER_NAME} cpuset.cpu_exclusive=0"
echo 0 | sudo tee "${OTHER_DIR}/cpuset.cpu_exclusive" >/dev/null

echo "Moving tasks from root cpuset to '${OTHER_NAME}'"
sudo sh -c "while read -r pid; do \
  [ -z \"\$pid\" ] && continue; \
  if [ ! -r \"/proc/\$pid/cmdline\" ] || [ ! -s \"/proc/\$pid/cmdline\" ]; then \
    continue; \
  fi; \
  if ! echo \"\$pid\" > \"${OTHER_DIR}/tasks\" 2>/dev/null; then \
    echo \"Warning: failed to move pid \$pid\" >&2; \
  fi; \
done < \"${CPUSET_ROOT}/tasks\""

echo
echo "Moving parent shell into '${ISO_NAME}'"
echo "$PPID" | sudo tee "${ISO_DIR}/tasks" >/dev/null

