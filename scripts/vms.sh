#!/usr/bin/env bash
# Manage the Lima VMs that make up the homelab cluster.
#
# Usage: scripts/vms.sh {up|start|stop|down|status|ssh-config}
#
# Optional environment overrides (only used when an instance is created):
#   CPUS=4 MEMORY=4 DISK=30     (MEMORY and DISK are in GiB)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/lima/node.yaml"
SSH_CONFIG="${ROOT}/ansible/.ssh_config"
NETWORK="lima:user-v2"

# The first node runs the control plane, the others are workers.
# Keep in sync with ansible/inventory/hosts.yml (Lima instance name == inventory name).
NODES=(homelab-cp homelab-w1 homelab-w2)

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

require_limactl() {
  command -v limactl >/dev/null 2>&1 || die "limactl not found (install it with: brew install lima)"
}

instance_exists() {
  limactl list -q | grep -qx "$1"
}

# Optional resource overrides as limactl flags.
resource_flags() {
  [ -z "${CPUS:-}" ] || printf '%s\n' --cpus "$CPUS"
  [ -z "${MEMORY:-}" ] || printf '%s\n' --memory "$MEMORY"
  [ -z "${DISK:-}" ] || printf '%s\n' --disk "$DISK"
}

cmd_up() {
  require_limactl
  local node flag
  local flags=()
  while IFS= read -r flag; do flags+=("$flag"); done < <(resource_flags)

  for node in "${NODES[@]}"; do
    if instance_exists "$node"; then
      log "starting existing instance $node"
      limactl start --tty=false "$node"
    else
      log "creating instance $node"
      limactl start --tty=false --name "$node" --network "$NETWORK" \
        ${flags[@]+"${flags[@]}"} "$TEMPLATE"
    fi
  done
  cmd_ssh_config
}

# Ansible reaches the VMs over SSH. Lima keeps an ssh.config per instance (its
# forwarded port changes whenever a VM restarts), so the file generated here only
# *includes* those, which means it never goes stale.
cmd_ssh_config() {
  require_limactl
  local node path
  : >"$SSH_CONFIG"
  for node in "${NODES[@]}"; do
    instance_exists "$node" || die "instance $node does not exist, run 'up' first"
    path="$(limactl list --format '{{.SSHConfigFile}}' "$node")"
    echo "Include \"${path}\"" >>"$SSH_CONFIG"
  done
  chmod 600 "$SSH_CONFIG"
  log "wrote ${SSH_CONFIG#"$ROOT"/}"
}

cmd_start() {
  require_limactl
  local node
  for node in "${NODES[@]}"; do
    instance_exists "$node" || die "instance $node does not exist, run 'up' first"
    limactl start --tty=false "$node"
  done
  cmd_ssh_config
}

cmd_stop() {
  require_limactl
  local i
  for ((i = ${#NODES[@]} - 1; i >= 0; i--)); do
    if instance_exists "${NODES[$i]}"; then
      limactl stop "${NODES[$i]}"
    fi
  done
}

cmd_down() {
  require_limactl
  local i
  for ((i = ${#NODES[@]} - 1; i >= 0; i--)); do
    if instance_exists "${NODES[$i]}"; then
      log "deleting instance ${NODES[$i]}"
      limactl delete --force "${NODES[$i]}"
    fi
  done
  rm -f "$SSH_CONFIG"
}

cmd_status() {
  require_limactl
  limactl list
}

case "${1:-}" in
  up) cmd_up ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  down) cmd_down ;;
  status) cmd_status ;;
  ssh-config) cmd_ssh_config ;;
  *) die "usage: $0 {up|start|stop|down|status|ssh-config}" ;;
esac
