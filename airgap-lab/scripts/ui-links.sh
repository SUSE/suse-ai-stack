#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
generated_dir="${lab_dir}/generated"
inventory="${AIF_AIRGAP_INVENTORY:-${generated_dir}/inventory.yml}"
lab_vars="${AIF_AIRGAP_VARS:-${generated_dir}/vars.yml}"
links_dir="${AIF_AIRGAP_UI_LINKS_DIR:-${generated_dir}/ui-links}"
caddyfile="${links_dir}/Caddyfile"
links_file="${links_dir}/links.txt"
ssh_destination_file="${links_dir}/ssh-destination"
tunnel_backend_file="${links_dir}/tunnel-backend"
control_socket_file="${links_dir}/control-socket"
ca_file="${generated_dir}/pki/ca.crt"

harbor_port="${AIF_AIRGAP_HARBOR_UI_PORT:-18080}"
gitea_port="${AIF_AIRGAP_GITEA_UI_PORT:-18081}"
tunnel_port="${AIF_AIRGAP_UI_TUNNEL_PORT:-18443}"
gitea_tunnel_port="${AIF_AIRGAP_GITEA_UI_TUNNEL_PORT:-18444}"
proxy_image="${AIF_AIRGAP_UI_PROXY_IMAGE:-caddy@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648}"
container_name="${AIF_AIRGAP_UI_PROXY_CONTAINER:-suse-aif-airgap-ui-proxy}"
systemd_unit="${AIF_AIRGAP_UI_TUNNEL_UNIT:-suse-aif-airgap-ui-tunnel.service}"
use_systemd="${AIF_AIRGAP_UI_USE_SYSTEMD:-auto}"
control_socket="${XDG_RUNTIME_DIR:-/tmp}/suse-aif-airgap-ui-${UID}-${tunnel_port}.sock"
owner_label="com.suse.ai-factory.airgap-ui-links"

usage() {
  printf 'Usage: %s {start|stop|status}\n' "$0"
}

require_command() {
  command -v "$1" >/dev/null || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 2
  }
}

validate_port() {
  local name=$1 value=$2
  if ! [[ "${value}" =~ ^[0-9]+$ ]] ||
    ((value < 1024 || value > 65535)); then
    printf '%s must be an unprivileged TCP port between 1024 and 65535; got %s.\n' \
      "${name}" "${value}" >&2
    exit 2
  fi
}

validate_generated_path() {
  case "${links_dir}" in
    "${generated_dir}"/*) ;;
    *)
      printf 'Refusing to manage a UI links directory outside %s: %s\n' \
        "${generated_dir}" "${links_dir}" >&2
      exit 2
      ;;
  esac
}

container_is_owned() {
  [[ "$(docker inspect --format "{{ index .Config.Labels \"${owner_label}\" }}" \
    "${container_name}" 2>/dev/null || true)" == true ]]
}

managed_control_socket() {
  local candidate="${control_socket}"
  if [[ -f "${control_socket_file}" ]]; then
    candidate="$(<"${control_socket_file}")"
  fi
  case "${candidate}" in
    "${XDG_RUNTIME_DIR:-/tmp}/suse-aif-airgap-ui-${UID}-"*.sock)
      printf '%s\n' "${candidate}"
      ;;
    *)
      printf 'Refusing to manage an unexpected SSH control socket: %s\n' \
        "${candidate}" >&2
      return 1
      ;;
  esac
}

stop_proxy() {
  local rc=0
  if ! command -v docker >/dev/null; then
    if [[ -d "${links_dir}" ]]; then
      printf 'Docker is unavailable; could not remove the UI proxy container.\n' >&2
      return 1
    fi
    return 0
  fi
  if ! docker inspect "${container_name}" >/dev/null 2>&1; then
    return 0
  fi
  if container_is_owned; then
    docker rm --force "${container_name}" >/dev/null
  else
    printf 'Refusing to remove container %s because it is not labeled as lab-owned.\n' \
      "${container_name}" >&2
    rc=1
  fi
  return "${rc}"
}

stop_tunnel() {
  local backend="" destination=airgap-services managed_socket="" rc=0
  if [[ -f "${tunnel_backend_file}" ]]; then
    backend="$(<"${tunnel_backend_file}")"
  fi

  if [[ "${backend}" == systemd ]] &&
    { ! command -v systemctl >/dev/null ||
      ! systemctl --user show-environment >/dev/null 2>&1; }; then
    printf 'The user service manager is unavailable; could not stop %s.\n' \
      "${systemd_unit}" >&2
    rc=1
  fi

  if command -v systemctl >/dev/null &&
    systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user stop "${systemd_unit}" >/dev/null 2>&1 || true
    systemctl --user reset-failed "${systemd_unit}" >/dev/null 2>&1 || true
    if systemctl --user is-active --quiet "${systemd_unit}" 2>/dev/null; then
      printf 'Failed to stop SSH tunnel unit %s.\n' "${systemd_unit}" >&2
      rc=1
    fi
  fi

  if ! managed_socket="$(managed_control_socket)"; then
    rc=1
  elif [[ -S "${managed_socket}" ]]; then
    if ! command -v ssh >/dev/null; then
      printf 'SSH is unavailable; could not stop control master at %s.\n' \
        "${managed_socket}" >&2
      rc=1
    else
      if [[ -f "${ssh_destination_file}" ]]; then
        destination="$(<"${ssh_destination_file}")"
      fi
      if ssh -S "${managed_socket}" -O exit "${destination}" >/dev/null 2>&1; then
        rm -f -- "${managed_socket}"
      else
        printf 'Failed to stop SSH control master at %s.\n' "${managed_socket}" >&2
        rc=1
      fi
    fi
  fi
  return "${rc}"
}

remove_generated_links() {
  if [[ -d "${links_dir}" ]]; then
    find "${links_dir}" -depth -delete
  fi
}

stop_links() {
  local rc=0
  stop_proxy || rc=$?
  stop_tunnel || rc=$?
  if ((rc == 0)); then
    remove_generated_links
  fi
  return "${rc}"
}

read_configuration() {
  [[ -f "${inventory}" && -f "${lab_vars}" && -f "${ca_file}" ]] || {
    printf 'Inventory, lab variables, or the generated lab CA are missing; run setup first.\n' >&2
    exit 2
  }

  services_host="$(yq -r '.all.children.airgap_services.hosts."airgap-services".ansible_host // ""' "${inventory}")"
  management_host="$(yq -r '.all.children.aif_management.hosts."mgmt-rancher".ansible_host // ""' "${inventory}")"
  ssh_user="$(yq -r '.all.children.airgap_services.hosts."airgap-services".ansible_user // .all.vars.ansible_user // "ec2-user"' "${inventory}")"
  ssh_key="$(yq -r '.all.children.airgap_services.hosts."airgap-services".ansible_ssh_private_key_file // .all.vars.ansible_ssh_private_key_file // ""' "${inventory}")"
  harbor_hostname="$(yq -r '.harbor_hostname // ""' "${lab_vars}")"
  gitea_hostname="$(yq -r '.gitea_hostname // ""' "${lab_vars}")"
  gitea_tls_enabled="$(yq -r '.gitea_tls_enabled | select(. != null)' "${lab_vars}")"
  gitea_tls_enabled="${gitea_tls_enabled:-true}"
  gitea_http_node_port="$(yq -r '.gitea_http_node_port // ""' "${lab_vars}")"
  services_private_ip="$(yq -r '.airgap_services_address // ""' "${lab_vars}")"
  rancher_url="$(yq -r '.rancher_url // ""' "${lab_vars}")"
  rancher_hostname="${rancher_url#*://}"
  rancher_hostname="${rancher_hostname%%/*}"
  rancher_hostname="${rancher_hostname%%:*}"

  [[ "${services_host}" =~ ^[A-Za-z0-9._:-]+$ &&
    "${management_host}" =~ ^[A-Za-z0-9._:-]+$ &&
    "${ssh_user}" =~ ^[A-Za-z0-9._-]+$ &&
    "${harbor_hostname}" =~ ^[A-Za-z0-9.-]+$ &&
    "${gitea_hostname}" =~ ^[A-Za-z0-9.-]+$ &&
    "${rancher_hostname}" =~ ^[A-Za-z0-9.-]+$ ]] || {
    printf 'Inventory or service hostnames contain unsupported characters.\n' >&2
    exit 2
  }
  [[ -f "${ssh_key}" ]] || {
    printf 'SSH private key not found: %s\n' "${ssh_key}" >&2
    exit 2
  }
  [[ "${harbor_port}" != "${gitea_port}" &&
    "${harbor_port}" != "${tunnel_port}" &&
    "${gitea_port}" != "${tunnel_port}" ]] || {
    printf 'Harbor, Gitea, and tunnel ports must be distinct.\n' >&2
    exit 2
  }
  if [[ "${gitea_tls_enabled}" != true && "${gitea_tls_enabled}" != false ]]; then
    printf 'gitea_tls_enabled must be true or false.\n' >&2
    exit 2
  fi
  if [[ "${gitea_tls_enabled}" == false ]]; then
    validate_port AIF_AIRGAP_GITEA_UI_TUNNEL_PORT "${gitea_tunnel_port}"
    validate_port gitea_http_node_port "${gitea_http_node_port}"
    [[ "${services_private_ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || {
      printf 'airgap_services_address must be an IPv4 address for HTTP Gitea tunneling.\n' >&2
      exit 2
    }
    [[ "${gitea_tunnel_port}" != "${harbor_port}" &&
      "${gitea_tunnel_port}" != "${gitea_port}" &&
      "${gitea_tunnel_port}" != "${tunnel_port}" ]] || {
      printf 'The HTTP Gitea backend tunnel port must be distinct.\n' >&2
      exit 2
    }
  fi
  case "${use_systemd}" in
    auto | true | false) ;;
    *)
      printf 'AIF_AIRGAP_UI_USE_SYSTEMD must be auto, true, or false.\n' >&2
      exit 2
      ;;
  esac
}

write_proxy_configuration() {
  mkdir -p "${links_dir}"
  chmod 700 "${links_dir}"
  umask 077
  cat >"${caddyfile}" <<EOF
{
	admin off
	auto_https off
}

http://127.0.0.1:${harbor_port} {
	bind 127.0.0.1
	reverse_proxy https://127.0.0.1:${tunnel_port} {
		header_up Host ${harbor_hostname}
		transport http {
			tls_server_name ${harbor_hostname}
			tls_trust_pool file /etc/aif-airgap-ca/ca.crt
		}
		header_down Location "^https://${harbor_hostname//./\\.}(?::[0-9]+)?(.*)$" "http://127.0.0.1:${harbor_port}\${1}"
		header_down Set-Cookie "(?i);[ ]*Secure" ""
		header_down -Strict-Transport-Security
	}
}

EOF

  if [[ "${gitea_tls_enabled}" == true ]]; then
    cat >>"${caddyfile}" <<EOF
http://127.0.0.1:${gitea_port} {
	bind 127.0.0.1
	reverse_proxy https://127.0.0.1:${tunnel_port} {
		header_up Host ${gitea_hostname}
		transport http {
			tls_server_name ${gitea_hostname}
			tls_trust_pool file /etc/aif-airgap-ca/ca.crt
		}
		header_down Location "^https://${gitea_hostname//./\\.}(?::[0-9]+)?(.*)$" "http://127.0.0.1:${gitea_port}\${1}"
		header_down Set-Cookie "(?i);[ ]*Secure" ""
		header_down -Strict-Transport-Security
	}
}
EOF
  else
    cat >>"${caddyfile}" <<EOF
http://127.0.0.1:${gitea_port} {
	bind 127.0.0.1
	reverse_proxy http://127.0.0.1:${gitea_tunnel_port} {
		header_up Host ${gitea_hostname}:${gitea_http_node_port}
		header_down Location "^https?://${gitea_hostname//./\\.}(?::[0-9]+)?(.*)$" "http://127.0.0.1:${gitea_port}\${1}"
		header_down Set-Cookie "(?i);[ ]*Secure" ""
		header_down -Strict-Transport-Security
	}
}
EOF
  fi
  chmod 600 "${caddyfile}"
}

start_tunnel() {
  local ssh_binary systemd_available=false
  local -a forward_args
  ssh_binary="$(command -v ssh)"
  forward_args=(-L "127.0.0.1:${tunnel_port}:127.0.0.1:443")
  if [[ "${gitea_tls_enabled}" == false ]]; then
    forward_args+=(-L "127.0.0.1:${gitea_tunnel_port}:${services_private_ip}:${gitea_http_node_port}")
  fi
  printf '%s@%s\n' "${ssh_user}" "${services_host}" >"${ssh_destination_file}"
  printf '%s\n' "${control_socket}" >"${control_socket_file}"
  chmod 600 "${ssh_destination_file}" "${control_socket_file}"
  if command -v systemd-run >/dev/null &&
    command -v systemctl >/dev/null &&
    systemctl --user show-environment >/dev/null 2>&1; then
    systemd_available=true
  fi
  if [[ "${use_systemd}" == true && "${systemd_available}" != true ]]; then
    printf 'A user systemd manager was requested but is unavailable.\n' >&2
    return 1
  fi
  if [[ "${use_systemd}" != false && "${systemd_available}" == true ]]; then
    systemd-run --user --quiet --collect --unit="${systemd_unit%.service}" \
      --description='SUSE AI Factory air-gap UI SSH tunnel' \
      --property=Restart=on-failure --property=RestartSec=5s \
      "${ssh_binary}" -NT \
      -i "${ssh_key}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      "${forward_args[@]}" \
      "${ssh_user}@${services_host}"
    printf 'systemd\n' >"${tunnel_backend_file}"
  else
    ssh -fNT -M -S "${control_socket}" \
      -i "${ssh_key}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      "${forward_args[@]}" \
      "${ssh_user}@${services_host}"
    printf 'control-master\n' >"${tunnel_backend_file}"
  fi
  chmod 600 "${tunnel_backend_file}"
}

wait_for_url() {
  local description=$1
  shift
  for _ in $(seq 1 30); do
    if curl --silent --show-error --fail --noproxy '*' \
      --connect-timeout 2 --max-time 5 "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s.\n' "${description}" >&2
  return 1
}

start_proxy() {
  docker run --detach \
    --name "${container_name}" \
    --label "${owner_label}=true" \
    --restart unless-stopped \
    --network host \
    --volume "${caddyfile}:/etc/caddy/Caddyfile:ro" \
    --volume "${ca_file}:/etc/aif-airgap-ca/ca.crt:ro" \
    "${proxy_image}" \
    caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
}

write_links() {
  cat >"${links_file}" <<EOF
Harbor UI: http://127.0.0.1:${harbor_port}/
Gitea UI: http://127.0.0.1:${gitea_port}/
Rancher UI: ${rancher_url}
Rancher /etc/hosts entry: ${management_host} ${rancher_hostname}
EOF
  chmod 600 "${links_file}"
}

print_links() {
  printf '\nLocal demo links (loopback only; upstream traffic uses SSH):\n'
  sed 's/^/  /' "${links_file}"
  print_credentials
  printf 'Remove local links: %s stop\n' "$0"
}

print_credentials() {
  if [[ ! -f "${lab_vars}" ]]; then
    printf '\nLab UI credentials: not generated.\n'
    return 0
  fi
  require_command yq
  printf '\nLab UI credentials:\n'
  printf '  Rancher username: %s\n' "$(yq -r '.rancher_admin_username // "admin"' "${lab_vars}")"
  printf '  Rancher password: %s\n' "$(yq -r '.rancher_bootstrap_password // "<not configured>"' "${lab_vars}")"
  printf '  Harbor username: admin\n'
  printf '  Harbor password: %s\n' "$(yq -r '.harbor_admin_password // "<not configured>"' "${lab_vars}")"
  printf '  Gitea username: %s\n' "$(yq -r '.gitea_admin_username // "<not configured>"' "${lab_vars}")"
  printf '  Gitea password: %s\n' "$(yq -r '.gitea_admin_password // "<not configured>"' "${lab_vars}")"
}

cleanup_start_failure() {
  local exit_status=$1
  trap - ERR
  stop_links || true
  exit "${exit_status}"
}

start_links() {
  for command_name in curl docker ssh yq; do
    require_command "${command_name}"
  done
  validate_port AIF_AIRGAP_HARBOR_UI_PORT "${harbor_port}"
  validate_port AIF_AIRGAP_GITEA_UI_PORT "${gitea_port}"
  validate_port AIF_AIRGAP_UI_TUNNEL_PORT "${tunnel_port}"
  read_configuration
  stop_links

  trap 'cleanup_start_failure $?' ERR
  write_proxy_configuration
  start_tunnel
  wait_for_url 'the Harbor ingress through SSH' \
    --cacert "${ca_file}" \
    --resolve "${harbor_hostname}:${tunnel_port}:127.0.0.1" \
    "https://${harbor_hostname}:${tunnel_port}/api/v2.0/health"
  start_proxy
  wait_for_url 'the local Harbor UI link' \
    "http://127.0.0.1:${harbor_port}/api/v2.0/health"
  wait_for_url 'the local Gitea UI link' \
    "http://127.0.0.1:${gitea_port}/api/healthz"
  write_links
  trap - ERR
  print_links
}

show_status() {
  local backend="" managed_socket=""
  if [[ -f "${tunnel_backend_file}" ]]; then
    backend="$(<"${tunnel_backend_file}")"
  fi
  if [[ -f "${links_file}" ]]; then
    cat "${links_file}"
  else
    printf 'Local UI links are not generated.\n'
  fi
  print_credentials

  if command -v docker >/dev/null && container_is_owned &&
    [[ "$(docker inspect --format '{{.State.Running}}' "${container_name}")" == true ]]; then
    printf 'UI proxy: running\n'
  else
    printf 'UI proxy: stopped\n'
  fi

  if command -v systemctl >/dev/null &&
    systemctl --user is-active --quiet "${systemd_unit}" 2>/dev/null; then
    printf 'SSH tunnel: running (systemd)\n'
  elif managed_socket="$(managed_control_socket)" &&
    [[ "${backend}" == control-master && -S "${managed_socket}" ]]; then
    printf 'SSH tunnel: running (SSH control master)\n'
  else
    printf 'SSH tunnel: stopped\n'
  fi
}

validate_generated_path
case "${1:-}" in
  start) start_links ;;
  stop)
    stop_links
    printf 'Removed the local Harbor and Gitea UI links.\n'
    ;;
  status) show_status ;;
  -h | --help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
