#!/usr/bin/env bash
set -euo pipefail

# Kept separate so the same HTTP assertions can also exercise offline containers.
probe_suse_apis() (
  qdrant_url=$1
  ollama_url=$2
  request() { curl --silent --show-error --fail-with-body --noproxy '*' --connect-timeout 5 --max-time 30 "$@"; }

  request "${qdrant_url}/readyz" >/dev/null
  request "${qdrant_url}/" | jq -e '.version == "1.19.0"' >/dev/null
  collection="airgap_probe_$(date -u +%Y%m%dT%H%M%S)_${RANDOM}"
  probe_status=0
  trap 'probe_status=$?; request --request DELETE "${qdrant_url}/collections/${collection}" >/dev/null || probe_status=1; exit "${probe_status}"' EXIT
  request --request PUT --header 'Content-Type: application/json' \
    --data '{"vectors":{"size":4,"distance":"Dot"}}' \
    "${qdrant_url}/collections/${collection}" | jq -e '.status == "ok" and .result == true' >/dev/null
  request --request PUT --header 'Content-Type: application/json' \
    --data '{"points":[{"id":1,"vector":[1,0,0,0],"payload":{"source":"suse-airgap"}},{"id":2,"vector":[0,1,0,0]}]}' \
    "${qdrant_url}/collections/${collection}/points?wait=true" |
    jq -e '.status == "ok" and .result.status == "completed"' >/dev/null
  request --request POST --header 'Content-Type: application/json' \
    --data '{"query":[1,0,0,0],"limit":1,"with_payload":true}' \
    "${qdrant_url}/collections/${collection}/points/query" |
    jq -e '.status == "ok" and .result.points[0].id == 1 and .result.points[0].payload.source == "suse-airgap"' >/dev/null
  printf 'qdrant_vector_write_and_search=PASS\n'
  request "${ollama_url}/api/version" | jq -e '.version == "0.21.2"' >/dev/null
  request "${ollama_url}/api/tags" | jq -e '.models | type == "array"' >/dev/null
  printf 'ollama_api=PASS\n'
)

main() {
  # Run on a target RKE2 server: its ClusterIP routes and kubeconfig are local.
  namespace="${1:-aif-suse-apps}"
  timeout_seconds="${2:-900}"
  [[ "${namespace}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#namespace} -le 63 ]] || exit 2
  [[ "${timeout_seconds}" =~ ^[0-9]+$ ]] || exit 2
  for command_name in kubectl curl jq; do
    command -v "${command_name}" >/dev/null || { printf 'Required command not found: %s\n' "${command_name}" >&2; exit 2; }
  done

  kubectl -n "${namespace}" rollout status statefulset/suse-qdrant --timeout="${timeout_seconds}s"
  kubectl -n "${namespace}" rollout status deployment/appco-ollama --timeout="${timeout_seconds}s"
  qdrant_ip="$(kubectl -n "${namespace}" get service suse-qdrant -o jsonpath='{.spec.clusterIP}')"
  ollama_ip="$(kubectl -n "${namespace}" get service appco-ollama -o jsonpath='{.spec.clusterIP}')"
  [[ -n "${qdrant_ip}" && "${qdrant_ip}" != None && -n "${ollama_ip}" && "${ollama_ip}" != None ]]
  probe_suse_apis "http://${qdrant_ip}:6333" "http://${ollama_ip}:11434"
  printf 'captured_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kubectl -n "${namespace}" get pods -l 'app.kubernetes.io/instance in (suse-qdrant,appco-ollama)' -o json |
    jq '[.items[] | {name: .metadata.name, node: .spec.nodeName,
        containers: [.status.containerStatuses[]? | {name, image, imageID, ready}],
        initContainers: [.status.initContainerStatuses[]? | {name, image, imageID}]}]'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
