#!/bin/bash

# Create and configure CPU isolation for cpuset controller.
# Usage: ./create_cpu_cgroup.sh [--numa-node N] <isolated-cpu-list>
#
# Example:
#   ./create_cpu_cgroup.sh 0-16
#   ./create_cpu_cgroup.sh --numa-node 1 0-16
#
# Options:
#   --numa-node N   Bind isolated group to NUMA node N (default: 0).
#                   Sets cpuset.mems (v1) or AllowedMemoryNodes (v2).
#
# Behavior:
# - cgroup v1: creates cpuset cgroups "isolated" + "other", then moves tasks.
# - cgroup v2: uses systemd AllowedCPUs/AllowedMemoryNodes at runtime:
#   - user.slice -> remaining CPUs ("other")
#   - current session scope -> isolated CPUs + specified NUMA node

set -euo pipefail

NUMA_NODE=0
ISO_CPU_LIST=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --numa-node)
      NUMA_NODE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--numa-node N] <isolated-cpu-list>"
      echo "Example: $0 0-16"
      echo "         $0 --numa-node 1 0-16"
      echo
      echo "Options:"
      echo "  --numa-node N   Bind isolated group to NUMA node N (default: 0)"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--numa-node N] <isolated-cpu-list>" >&2
      exit 1
      ;;
    *)
      if [ -n "$ISO_CPU_LIST" ]; then
        echo "Error: unexpected argument: $1" >&2
        exit 1
      fi
      ISO_CPU_LIST="$1"
      shift
      ;;
  esac
done

if [ -z "$ISO_CPU_LIST" ]; then
  echo "Error: <isolated-cpu-list> is required" >&2
  echo "Usage: $0 [--numa-node N] <isolated-cpu-list>" >&2
  exit 1
fi

if ! [[ "$NUMA_NODE" =~ ^[0-9]+$ ]]; then
  echo "Error: --numa-node must be a non-negative integer, got: ${NUMA_NODE}" >&2
  exit 1
fi

ISO_NAME="isolated"
OTHER_NAME="other"
STATE_FILE="/tmp/create_cpu_cgroup_state_${UID}.env"

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

NUMA_SYSFS="/sys/devices/system/node/node${NUMA_NODE}"
if [ ! -d "$NUMA_SYSFS" ]; then
  echo "Error: NUMA node ${NUMA_NODE} not found (${NUMA_SYSFS} does not exist)." >&2
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
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl not found; required for cgroup v2 runtime CPU partitioning." >&2
    exit 1
  fi
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

detect_systemd_unit_for_pid() {
  local pid="$1"
  local unit=""
  local cgroup_path=""
  local segment=""

  if command -v ps >/dev/null 2>&1; then
    unit="$(ps -o unit= -p "$pid" 2>/dev/null | awk '{print $1}')"
    case "$unit" in
      ""|"-"|"?"|"N/A"|"n/a") unit="" ;;
    esac
    if [ -n "$unit" ]; then
      echo "$unit"
      return 0
    fi
  fi

  cgroup_path="$(awk -F: '$1=="0"{print $3}' "/proc/${pid}/cgroup" 2>/dev/null || true)"
  for segment in ${cgroup_path//\// }; do
    case "$segment" in
      *.scope|*.service|*.slice) unit="$segment" ;;
    esac
  done
  if [ -n "$unit" ]; then
    echo "$unit"
    return 0
  fi

  if command -v loginctl >/dev/null 2>&1 && [ -n "${XDG_SESSION_ID:-}" ]; then
    unit="$(loginctl show-session "${XDG_SESSION_ID}" -p Scope --value 2>/dev/null || true)"
    if [[ "$unit" == *.scope ]]; then
      echo "$unit"
      return 0
    fi
  fi

  return 1
}

detect_ancestor_systemd_unit() {
  local pid="$1"
  local unit=""
  local next_ppid=""
  local guard=0

  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    unit="$(detect_systemd_unit_for_pid "$pid" || true)"
    if [ -n "$unit" ]; then
      echo "$unit"
      return 0
    fi
    next_ppid="$(awk '{print $4}' "/proc/${pid}/stat" 2>/dev/null || true)"
    if [ -z "$next_ppid" ] || [ "$next_ppid" -eq "$pid" ] 2>/dev/null; then
      break
    fi
    pid="$next_ppid"
    guard=$((guard + 1))
    if [ "$guard" -gt 64 ]; then
      break
    fi
  done

  return 1
}

# cgroup v2: relative path under CPUSET_ROOT (/sys/fs/cgroup), e.g. /system.slice/foo.scope
cgroup_v2_rel_path_for_pid() {
  local pid="$1"
  local line=""
  line="$(grep '^0::' "/proc/${pid}/cgroup" 2>/dev/null | head -1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  echo "${line#0::}"
}

cgroup_abs_path_v2_for_pid() {
  local pid="$1"
  local rel=""
  rel="$(cgroup_v2_rel_path_for_pid "$pid" || true)"
  if [ -z "$rel" ]; then
    return 1
  fi
  echo "${CPUSET_ROOT}${rel}"
}

# Delegate a leaf cgroup to the invoking user so they can write PIDs to cgroup.procs (or tasks) without sudo.
delegate_cgroup_to_invoking_user() {
  local dir="$1"
  local uid="${SUDO_UID:-$(id -u)}"
  local gid="${SUDO_GID:-$(id -g)}"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  sudo chown -R "${uid}:${gid}" "$dir"
  # Ensure tasks interface is writable (some setups leave mode tight after chown).
  if [ -e "${dir}/cgroup.procs" ]; then
    sudo chmod u+w "${dir}/cgroup.procs" 2>/dev/null || true
  fi
  if [ -e "${dir}/tasks" ]; then
    sudo chmod u+w "${dir}/tasks" 2>/dev/null || true
  fi
}

# Print human-readable cgroup location (name, dir, how to move a PID).
print_cgroup_paths_for_dir() {
  local dir="$1"
  local tasks_basename="${2:-cgroup.procs}"
  local name=""
  local procs="${dir}/${tasks_basename}"
  name="$(basename "$dir")"
  echo "Cgroup name: ${name}"
  echo "Cgroup path: ${dir}"
  echo "Tasks file: ${procs}"
  echo
  echo "Moving a process from another cgroup (e.g. ssh.service) requires permission to"
  echo "detach it from the *source* cgroup, not just write access here. Typical fixes:"
  echo "  sudo sh -c 'echo PID > ${procs}'"
  echo "  # or: echo PID | sudo tee ${procs} >/dev/null"
  echo "If your shell was already moved into this cgroup by this script, children inherit it;"
  echo "use > not >> (append is not supported on cgroup.procs)."
  printf '  echo $$ > %s\n' "${procs}"
}

print_cgroup_paths_for_pid_v2() {
  local pid="${1:-$$}"
  local dir=""
  dir="$(cgroup_abs_path_v2_for_pid "$pid" || true)"
  if [ -z "$dir" ]; then
    echo "Warning: could not resolve cgroup v2 path for PID ${pid} (/proc/${pid}/cgroup has no 0:: line)." >&2
    return 1
  fi
  print_cgroup_paths_for_dir "$dir" "cgroup.procs"
}

ISO_CPU_LIST="$(normalize_cpu_list "$ISO_CPU_LIST")"
if [ -z "$ISO_CPU_LIST" ]; then
  echo "Error: isolated CPU list is empty after normalization" >&2
  exit 1
fi

ROOT_CPU_LIST="$(cat "${CPUSET_ROOT}/${ROOT_CPU_FILE}")"
OTHER_CPU_LIST="$(calc_other_cpu_list "$ROOT_CPU_LIST" "$ISO_CPU_LIST")"

if [ "$CGROUP_MODE" = "v2" ]; then
  fallback_taskset_pid=""
  fallback_other_unit=""
  echo "Applying runtime CPU partition via systemd (cgroup v2)"
  echo "Setting user.slice AllowedCPUs=${OTHER_CPU_LIST}"
  sudo systemctl set-property --runtime user.slice AllowedCPUs="${OTHER_CPU_LIST}"

  current_unit="$(detect_systemd_unit_for_pid "${PPID}" || true)"
  service_unit=""
  isolated_cgroup_dir=""
  service_cgroup_dir=""

  echo
  if [[ "$current_unit" == *.scope ]]; then
    echo "Setting current unit '${current_unit}' AllowedCPUs=${ISO_CPU_LIST} AllowedMemoryNodes=${NUMA_NODE}"
    sudo systemctl set-property --runtime "${current_unit}" AllowedCPUs="${ISO_CPU_LIST}" AllowedMemoryNodes="${NUMA_NODE}"
    echo "Current shell session is now constrained to CPUs ${ISO_CPU_LIST}, NUMA node ${NUMA_NODE}"
    echo
    echo "Shell cgroup (session scope):"
    print_cgroup_paths_for_pid_v2 "${PPID}" || true
  elif [[ "$current_unit" == *.service ]]; then
    # System-wide services (e.g. ssh.service) contain unrelated processes.
    # Move PPID into a new peer cgroup, then constrain the service to OTHER CPUs.
    service_unit="$current_unit"
    current_unit=""

    service_cgroup="$(systemctl show -p ControlGroup --value "$service_unit" 2>/dev/null || true)"
    if [ -n "$service_cgroup" ]; then
      service_cgroup_dir="${CPUSET_ROOT}${service_cgroup}"
      parent_cgroup_dir="$(dirname "$service_cgroup_dir")"
      isolated_cgroup_dir="${parent_cgroup_dir}/bench-isolated-${PPID}"

      parent_subtree="$(cat "${parent_cgroup_dir}/cgroup.subtree_control" 2>/dev/null || true)"
      case " ${parent_subtree} " in
        *" cpuset "*) ;;
        *)
          echo "Enabling cpuset in $(basename "$parent_cgroup_dir") subtree_control"
          echo "+cpuset" | sudo tee "${parent_cgroup_dir}/cgroup.subtree_control" >/dev/null
          ;;
      esac

      echo "Creating isolated cgroup ${isolated_cgroup_dir}"
      sudo mkdir -p "$isolated_cgroup_dir"
      echo "$ISO_CPU_LIST" | sudo tee "${isolated_cgroup_dir}/cpuset.cpus" >/dev/null
      echo "$NUMA_NODE" | sudo tee "${isolated_cgroup_dir}/cpuset.mems" >/dev/null

      echo "Moving shell PID ${PPID} into isolated cgroup"
      echo "$PPID" | sudo tee "${isolated_cgroup_dir}/cgroup.procs" >/dev/null

      echo "Setting ${service_unit} AllowedCPUs=${OTHER_CPU_LIST}"
      sudo systemctl set-property --runtime "$service_unit" AllowedCPUs="${OTHER_CPU_LIST}"

      echo "Delegating isolated cgroup to invoking user (chown for cgroup.procs)"
      delegate_cgroup_to_invoking_user "$isolated_cgroup_dir"

      echo "Current shell session is now constrained to CPUs ${ISO_CPU_LIST}, NUMA node ${NUMA_NODE}"
      echo
      print_cgroup_paths_for_dir "$isolated_cgroup_dir" "cgroup.procs"
    else
      echo "Warning: could not determine ControlGroup for ${service_unit}; falling back to taskset." >&2
      service_unit=""
      if command -v taskset >/dev/null 2>&1; then
        echo "Pinning current shell PID ${PPID} to ${ISO_CPU_LIST} via taskset"
        taskset -pc "${ISO_CPU_LIST}" "${PPID}" >/dev/null
        fallback_taskset_pid="${PPID}"
        echo "Current shell session is now constrained to ${ISO_CPU_LIST}"
      else
        echo "Warning: taskset not found. Run an isolated shell with:" >&2
        echo "  systemd-run --scope -p AllowedCPUs=${ISO_CPU_LIST} --same-dir bash"
      fi
    fi
  else
    fallback_other_unit="$(detect_ancestor_systemd_unit "${PPID}" || true)"
    case "$fallback_other_unit" in
      *.service) fallback_other_unit="" ;;
    esac
    if [ -n "$fallback_other_unit" ]; then
      echo "Current shell has no direct unit; setting ancestor unit '${fallback_other_unit}' AllowedCPUs=${OTHER_CPU_LIST}"
      sudo systemctl set-property --runtime "${fallback_other_unit}" AllowedCPUs="${OTHER_CPU_LIST}"
    else
      echo "Warning: unable to detect any ancestor systemd unit for current shell tree." >&2
    fi

    if command -v taskset >/dev/null 2>&1; then
      echo "Pinning current shell PID ${PPID} to ${ISO_CPU_LIST} via taskset fallback"
      taskset -pc "${ISO_CPU_LIST}" "${PPID}" >/dev/null
      fallback_taskset_pid="${PPID}"
      echo "Current shell session is now constrained to ${ISO_CPU_LIST}"
      echo
      echo "Shell cgroup (taskset only; use cgroup below to attach other processes if writable):"
      print_cgroup_paths_for_pid_v2 "${PPID}" || true
    else
      echo "Warning: taskset not found. Run an isolated shell with:" >&2
      echo "  systemd-run --scope -p AllowedCPUs=${ISO_CPU_LIST} --same-dir bash"
    fi
  fi

  {
    echo "CGROUP_MODE=${CGROUP_MODE}"
    echo "NUMA_NODE=${NUMA_NODE}"
    echo "ISO_CPU_LIST=${ISO_CPU_LIST}"
    echo "OTHER_CPU_LIST=${OTHER_CPU_LIST}"
    echo "ROOT_CPU_LIST=${ROOT_CPU_LIST}"
    echo "CURRENT_UNIT=${current_unit}"
    echo "SERVICE_UNIT=${service_unit}"
    echo "ISOLATED_CGROUP_DIR=${isolated_cgroup_dir}"
    if [ -n "${isolated_cgroup_dir}" ]; then
      echo "ISOLATED_CGROUP_TASKS_FILE=${isolated_cgroup_dir}/cgroup.procs"
    else
      echo "ISOLATED_CGROUP_TASKS_FILE="
    fi
    echo "SERVICE_CGROUP_DIR=${service_cgroup_dir}"
    echo "FALLBACK_OTHER_UNIT=${fallback_other_unit}"
    echo "FALLBACK_TASKSET_PID=${fallback_taskset_pid}"
  } > "${STATE_FILE}"
  echo
  echo "Saved runtime state to ${STATE_FILE}"
  exit 0
fi

# cgroup v1 path: cpuset requires mems + cpus to be set before moving tasks.
if [ -d "$ISO_DIR" ]; then
  if [ "$(sudo wc -l < "${ISO_DIR}/${TASKS_FILE}")" -gt 0 ]; then
    echo "Error: '${ISO_NAME}' cgroup already has tasks; refusing to modify it." >&2
    exit 1
  fi
else
  echo "Creating cgroup '${ISO_NAME}' in cpuset controller (${CGROUP_MODE})"
  sudo cgcreate -g "cpuset:${ISO_NAME}"
fi

current_iso="$(sudo cat "${ISO_DIR}/cpuset.cpus")"
current_iso_norm="$(normalize_cpu_list "$current_iso")"
if [ "$current_iso_norm" != "$ISO_CPU_LIST" ]; then
  echo "Warning: '${ISO_NAME}' cpuset.cpus differs; updating to ${ISO_CPU_LIST}" >&2
fi
echo "Configuring ${ISO_NAME} cpuset.mems=${NUMA_NODE}"
echo "$NUMA_NODE" | sudo tee "${ISO_DIR}/cpuset.mems" >/dev/null
echo "Configuring ${ISO_NAME} cpuset.cpus=${ISO_CPU_LIST}"
echo "$ISO_CPU_LIST" | sudo tee "${ISO_DIR}/cpuset.cpus" >/dev/null
echo "Configuring ${ISO_NAME} cpuset.cpu_exclusive=1"
echo 1 | sudo tee "${ISO_DIR}/cpuset.cpu_exclusive" >/dev/null

if [ ! -d "$OTHER_DIR" ]; then
  echo "Creating cgroup '${OTHER_NAME}' in cpuset controller (${CGROUP_MODE})"
  sudo cgcreate -g "cpuset:${OTHER_NAME}"
fi
echo "Configuring ${OTHER_NAME} cpuset.mems (copied from root cpuset)"
cat "${CPUSET_ROOT}/${ROOT_MEMS_FILE}" | sudo tee "${OTHER_DIR}/cpuset.mems" >/dev/null
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
  if ! echo \"\$pid\" > \"${OTHER_DIR}/${TASKS_FILE}\" 2>/dev/null; then \
    echo \"Warning: failed to move pid \$pid\" >&2; \
  fi; \
done < \"${CPUSET_ROOT}/${TASKS_FILE}\""

echo
echo "Moving parent shell into '${ISO_NAME}'"
echo "$PPID" | sudo tee "${ISO_DIR}/${TASKS_FILE}" >/dev/null

echo "Delegating '${ISO_NAME}' cgroup to invoking user (chown for ${TASKS_FILE})"
delegate_cgroup_to_invoking_user "$ISO_DIR"
echo
print_cgroup_paths_for_dir "$ISO_DIR" "${TASKS_FILE}"
