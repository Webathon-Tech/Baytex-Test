#!/usr/bin/env bash
# ----------------------------------------------------------------------------------------------------------------------
# baytex-haproxy-reconcile
# Installed by cloud-init from the haproxy-tier Terraform module.
#
# Converges this VM on the state Terraform publishes in the VM's user data: the HAProxy configuration and the load
# balancer frontend IPs.
#
#   baytex-haproxy-reconcile        Full run. Started by baytex-haproxy-reconcile.timer shortly after boot and every two
#                                   minutes after that.
#   baytex-haproxy-reconcile boot   Adds the saved frontend IPs only. Started by baytex-haproxy-frontend-ips.service at
#                                   boot, before HAProxy.
#
# Every step is idempotent. A step that cannot complete yet, such as the package installation before the package mirrors
# are reachable, is completed by a later run, including after a restart. A configuration is applied only after haproxy -c
# accepts it, and the previous configuration is restored if HAProxy does not run with the new one.
# ----------------------------------------------------------------------------------------------------------------------

set -uo pipefail
export LC_ALL=C

readonly state_dir=/var/lib/baytex-haproxy
readonly desired_state="${state_dir}/desired-state.json"
readonly rejected_config="${state_dir}/rejected-haproxy.cfg"
readonly previous_config="${state_dir}/previous-haproxy.cfg"
readonly live_config=/etc/haproxy/haproxy.cfg
readonly lock_file=/run/baytex-haproxy-reconcile.lock
readonly user_data_url='http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text'
readonly packages=(haproxy rsyslog netcat-openbsd)

log() {
  printf '%s\n' "$*"
}

# ----------------------------------------------------------------------------------------------------------------------
# Desired state
# ----------------------------------------------------------------------------------------------------------------------

# Succeeds when the file holds a desired state: a non-empty HAProxy configuration and a list of IPv4 frontend addresses.
is_desired_state() {
  python3 -c '
import ipaddress, json, sys
state = json.load(open(sys.argv[1]))
assert isinstance(state["haproxy_cfg"], str) and state["haproxy_cfg"].strip()
assert isinstance(state["frontend_ips"], list)
for address in state["frontend_ips"]:
    ipaddress.IPv4Address(address)
' "$1" >/dev/null 2>&1
}

# Prints one field of the saved desired state, with a list printed one item per line.
desired_field() {
  python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))[sys.argv[2]]
sys.stdout.write("".join(item + "\n" for item in value) if isinstance(value, list) else value)
' "$desired_state" "$1"
}

# Saves the VM user data as the desired state. When the user data cannot be read or is not a desired state, the saved
# desired state stays in effect.
refresh_desired_state() {
  local encoded incoming
  incoming=$(mktemp "${state_dir}/incoming.XXXXXX") || return 1

  if encoded=$(curl --silent --fail --noproxy '*' --max-time 10 --header 'Metadata: true' "$user_data_url") &&
    [[ -n $encoded ]] &&
    base64 --decode <<<"$encoded" >"$incoming" 2>/dev/null &&
    is_desired_state "$incoming"; then
    if ! cmp --silent "$incoming" "$desired_state"; then
      mv -f "$incoming" "$desired_state"
      log "Saved a new desired state from the VM user data."
      return 0
    fi
  else
    log "The VM user data could not be read as a desired state; the saved desired state stays in effect."
  fi

  rm -f "$incoming"
}

# ----------------------------------------------------------------------------------------------------------------------
# Frontend IPs
# ----------------------------------------------------------------------------------------------------------------------

# The load balancer uses floating IP, so each frontend IP must be local to the VM for the VM to accept its traffic.

desired_frontend_ips() {
  desired_field frontend_ips | sort -u
}

current_frontend_ips() {
  ip -4 -o address show dev dummy0 2>/dev/null | awk '{ split($4, address, "/"); print address[1] }' | sort -u
}

add_frontend_ips() {
  local address
  ip link show dummy0 >/dev/null 2>&1 || ip link add dummy0 type dummy
  ip link set dummy0 up

  while read -r address; do
    [[ -n $address ]] || continue
    ip address add "${address}/32" dev dummy0 && log "Added frontend IP ${address}."
  done < <(comm -13 <(current_frontend_ips) <(desired_frontend_ips))
}

# Runs only once HAProxy has the desired configuration, so no running frontend loses its address.
remove_stale_frontend_ips() {
  local address
  while read -r address; do
    [[ -n $address ]] || continue
    ip address del "${address}/32" dev dummy0 && log "Removed frontend IP ${address}."
  done < <(comm -23 <(current_frontend_ips) <(desired_frontend_ips))
}

# ----------------------------------------------------------------------------------------------------------------------
# Packages
# ----------------------------------------------------------------------------------------------------------------------

packages_installed() {
  local package
  for package in "${packages[@]}"; do
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) == installed ]] || return 1
  done
}

# The package mirrors are reached through the firewall. apt waits for the lock that platform patch assessment holds, and
# the apt settings cloud-init installs keep a single attempt short, so an unreachable mirror only delays the next run.
install_packages() {
  packages_installed && return 0

  log "Installing ${packages[*]}."
  export DEBIAN_FRONTEND=noninteractive
  # Completes any package configuration that a restart interrupted.
  dpkg --configure --pending >/dev/null 2>&1 || true

  apt-get -qq -o DPkg::Lock::Timeout=300 update &&
    apt-get -qq -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      install --yes "${packages[@]}" &&
    log "Installed ${packages[*]}."
}

# ----------------------------------------------------------------------------------------------------------------------
# HAProxy
# ----------------------------------------------------------------------------------------------------------------------

# Starts or restarts HAProxy and succeeds when it is active afterwards.
run_haproxy() {
  systemctl reset-failed haproxy >/dev/null 2>&1 || true
  timeout 120 systemctl "$1" haproxy && systemctl is-active --quiet haproxy
}

# Applies the desired HAProxy configuration once haproxy -c accepts it: a graceful reload when HAProxy is running, and a
# start when it is not. A configuration that fails validation is kept for inspection and never applied, and one that
# HAProxy does not run with is replaced by the previous configuration.
apply_haproxy_config() {
  local candidate
  candidate=$(mktemp "${state_dir}/candidate.XXXXXX") || return 1
  desired_field haproxy_cfg >"$candidate"

  # Already applied, or already rejected and reported.
  if cmp --silent "$candidate" "$live_config"; then
    rm -f "$candidate"
    return 0
  fi
  if cmp --silent "$candidate" "$rejected_config"; then
    rm -f "$candidate"
    return 1
  fi

  if ! haproxy -c -q -f "$candidate" >/dev/null 2>&1; then
    log "The desired HAProxy configuration failed validation and was not applied; HAProxy keeps its current configuration."
    haproxy -c -f "$candidate" 2>&1 | tail -n 20
    mv -f "$candidate" "$rejected_config"
    return 1
  fi

  cp -f "$live_config" "$previous_config" 2>/dev/null || true
  install -m 0644 "$candidate" "$live_config"
  rm -f "$candidate" "$rejected_config"

  if systemctl is-active --quiet haproxy; then
    if systemctl reload haproxy; then
      log "Applied a new HAProxy configuration with a graceful reload."
      return 0
    fi
  elif run_haproxy start; then
    log "Applied a new HAProxy configuration and started HAProxy."
    return 0
  fi

  log "HAProxy did not run with the new configuration; restoring the previous configuration."
  cp -f "$live_config" "$rejected_config"
  if [[ -s $previous_config ]]; then
    install -m 0644 "$previous_config" "$live_config"
  fi
  run_haproxy restart
  return 1
}

# Keeps HAProxy enabled and running with the configuration in place.
ensure_haproxy_running() {
  systemctl is-enabled --quiet haproxy || systemctl enable --quiet haproxy
  systemctl is-active --quiet haproxy && return 0

  if run_haproxy start; then
    log "Started HAProxy."
    return 0
  fi
  log "HAProxy did not start:"
  journalctl -u haproxy -n 10 --no-pager 2>&1
  return 1
}

# ----------------------------------------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------------------------------------

main() {
  local config_status=0

  mkdir -p "$state_dir"
  exec 9>"$lock_file"

  if [[ ${1:-} == boot ]]; then
    # HAProxy waits for this at boot, so it never waits long; a full run in progress handles the frontend IPs itself.
    flock --wait 20 9 || return 0
    [[ -s $desired_state ]] || refresh_desired_state
    if [[ -s $desired_state ]]; then
      add_frontend_ips
    fi
    return 0
  fi

  # A full run still in progress, such as a long package installation, is left to finish.
  flock --nonblock 9 || return 0

  systemctl is-enabled --quiet baytex-haproxy-reconcile.timer ||
    systemctl enable --quiet baytex-haproxy-reconcile.timer
  systemctl is-enabled --quiet baytex-haproxy-frontend-ips.service ||
    systemctl enable --quiet baytex-haproxy-frontend-ips.service

  refresh_desired_state
  if [[ ! -s $desired_state ]]; then
    log "No desired state has been received from the VM user data yet."
    return 1
  fi

  sysctl --quiet --write net.ipv4.ip_nonlocal_bind=1 >/dev/null
  add_frontend_ips

  if ! install_packages; then
    log "The package installation did not complete; the next run retries it."
    return 1
  fi

  apply_haproxy_config || config_status=1
  ensure_haproxy_running || return 1
  [[ $config_status -eq 0 ]] || return 1

  remove_stale_frontend_ips
}

main "$@"
