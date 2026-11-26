#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
operation="${1:-}"
shift || true

manifest="${lab_dir}/artifacts.yml"
bundle="${lab_dir}/bundles/current"
profile="suse"
profile_was_set=false

usage() {
  printf '%s\n' \
    "Usage: $0 <export|import|mirror> [--manifest FILE] [--bundle DIR] [--profile core|suse|chatbot|vendor|all]" \
    "" \
    "Destination variables: HARBOR_REGISTRY, HARBOR_USERNAME, HARBOR_PASSWORD" \
    "Optional: HARBOR_CA_FILE (defaults to generated/pki/ca.crt)" \
    "Source variables: APPCO_USERNAME/PASSWORD, SUSE_REGISTRY_USERNAME/PASSWORD," \
    "                  NGC_USERNAME/PASSWORD, DOCKERHUB_USERNAME/PASSWORD"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest=$2; shift 2 ;;
    --bundle) bundle=$2; shift 2 ;;
    --profile) profile=$2; profile_was_set=true; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${operation}" != "export" && "${operation}" != "import" && "${operation}" != "mirror" ]]; then
  usage >&2
  exit 2
fi

if [[ "${profile}" != "core" && "${profile}" != "suse" && "${profile}" != "chatbot" && \
      "${profile}" != "vendor" && "${profile}" != "all" ]]; then
  printf 'Unsupported profile: %s\n' "${profile}" >&2
  exit 2
fi

for command_name in helm skopeo yq sha256sum; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done

if [[ "${operation}" == "import" ]]; then
  manifest="${bundle}/ARTIFACTS.yaml"
  [[ -f "${manifest}" ]] || {
    printf 'Bundled artifact manifest not found: %s\n' "${manifest}" >&2
    exit 2
  }
else
  [[ -f "${manifest}" ]] || { printf 'Manifest not found: %s\n' "${manifest}" >&2; exit 2; }
fi
manifest_dir="$(cd "$(dirname "${manifest}")" && pwd)"
harbor_ca_file="${HARBOR_CA_FILE:-${lab_dir}/generated/pki/ca.crt}"

source_auth_file="$(mktemp)"
destination_auth_file="$(mktemp)"
helm_state_dir="$(mktemp -d)"
cleanup_auth_files() {
  rm -f -- "${source_auth_file}" "${destination_auth_file}"
  rm -rf -- "${helm_state_dir}"
}
trap cleanup_auth_files EXIT
chmod 600 "${source_auth_file}" "${destination_auth_file}"
printf '{}\n' > "${source_auth_file}"
printf '{}\n' > "${destination_auth_file}"
export HELM_REGISTRY_CONFIG="${helm_state_dir}/registry.json"
export HELM_REPOSITORY_CONFIG="${helm_state_dir}/repositories.yaml"
export HELM_REPOSITORY_CACHE="${helm_state_dir}/repository-cache"
skopeo_cert_dir="${helm_state_dir}/certs"
mkdir -p "${skopeo_cert_dir}"

selected() {
  local profiles=$1
  if [[ "${profile}" == "all" ]]; then
    return 0
  fi
  if [[ ",${profiles}," == *",core,"* ]]; then
    return 0
  fi
  [[ ",${profiles}," == *",${profile},"* ]]
}

require_bundle_basename() {
  local value=$1 field=$2
  if [[ -z "${value}" || "${value}" == "null" || "${value}" == */* || "${value}" == "." || "${value}" == ".." ]]; then
    printf '%s must be a non-empty basename, got: %s\n' "${field}" "${value}" >&2
    exit 2
  fi
}

login_skopeo_source() {
  local registry=$1 username=$2 password=$3
  if [[ -n "${username}" && -n "${password}" ]]; then
    printf '%s' "${password}" | skopeo login --authfile "${source_auth_file}" \
      --username "${username}" --password-stdin "${registry}" >/dev/null
  fi
}

login_helm_source() {
  local registry=$1 username=$2 password=$3
  if [[ -n "${username}" && -n "${password}" ]]; then
    printf '%s' "${password}" | helm registry login "${registry}" \
      --username "${username}" --password-stdin >/dev/null
  fi
}

source_logins() {
  login_skopeo_source "dp.apps.rancher.io" "${APPCO_USERNAME:-}" "${APPCO_PASSWORD:-}"
  login_skopeo_source "registry.suse.com" "${SUSE_REGISTRY_USERNAME:-}" "${SUSE_REGISTRY_PASSWORD:-}"
  login_skopeo_source "nvcr.io" "${NGC_USERNAME:-}" "${NGC_PASSWORD:-}"
  login_skopeo_source "docker.io" "${DOCKERHUB_USERNAME:-}" "${DOCKERHUB_PASSWORD:-}"
  login_helm_source "dp.apps.rancher.io" "${APPCO_USERNAME:-}" "${APPCO_PASSWORD:-}"
  login_helm_source "registry.suse.com" "${SUSE_REGISTRY_USERNAME:-}" "${SUSE_REGISTRY_PASSWORD:-}"
}

destination_login() {
  : "${HARBOR_REGISTRY:?Set HARBOR_REGISTRY to the Harbor host[:port]}"
  : "${HARBOR_USERNAME:?Set HARBOR_USERNAME}"
  : "${HARBOR_PASSWORD:?Set HARBOR_PASSWORD}"
  [[ -f "${harbor_ca_file}" ]] || {
    printf 'Harbor CA not found: %s\n' "${harbor_ca_file}" >&2
    exit 2
  }
  cp -- "${harbor_ca_file}" "${skopeo_cert_dir}/ca.crt"
  printf '%s' "${HARBOR_PASSWORD}" | skopeo login \
    --authfile "${destination_auth_file}" \
    --cert-dir "${skopeo_cert_dir}" \
    --username "${HARBOR_USERNAME}" --password-stdin "${HARBOR_REGISTRY}" >/dev/null
  printf '%s' "${HARBOR_PASSWORD}" | helm registry login "${HARBOR_REGISTRY}" \
    --ca-file "${harbor_ca_file}" \
    --username "${HARBOR_USERNAME}" --password-stdin >/dev/null
}

validate_chart_dependencies() {
  local archive=$1 chart_name dep
  chart_name="$(helm show chart "${archive}" | yq -r '.name')"
  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if ! tar -tzf "${archive}" \
        | LC_ALL=C grep -E "^${chart_name}/charts/${dep}(-[^/]+)?\.(tgz|yaml)$|^${chart_name}/charts/${dep}/Chart\.yaml$" >/dev/null; then
      printf 'Chart %s declares dependency %s but does not vendor it; air-gap install would fetch upstream.\n' \
        "${archive}" "${dep}" >&2
      return 1
    fi
  done < <(helm show chart "${archive}" | yq -r '.dependencies[]?.name')
}

export_bundle() {
  local current_manifest_digest cached_manifest_digest cached_profile
  current_manifest_digest="$(sha256sum "${manifest}" | awk '{print $1}')"
  if [[ -f "${bundle}/METADATA" ]]; then
    cached_manifest_digest="$(awk -F= '$1 == "manifest_sha256" {print $2}' "${bundle}/METADATA")"
    cached_profile="$(awk -F= '$1 == "profile" {print $2}' "${bundle}/METADATA")"
    if [[ "${cached_manifest_digest}" != "${current_manifest_digest}" || "${cached_profile}" != "${profile}" ]]; then
      printf 'Bundle %s was created for a different manifest/profile; use a new bundle directory.\n' \
        "${bundle}" >&2
      exit 1
    fi
  fi

  mkdir -p "${bundle}/charts" "${bundle}/images"
  source_logins
  : > "${bundle}/SOURCE-DIGESTS.txt"
  cp -- "${manifest}" "${bundle}/ARTIFACTS.yaml"

  local chart_count chart_index profiles source_type source version archive chart path chart_version
  chart_count="$(yq -r '.spec.charts | length' "${manifest}")"
  for ((chart_index=0; chart_index<chart_count; chart_index++)); do
    profiles="$(yq -r ".spec.charts[${chart_index}].profiles | join(\",\")" "${manifest}")"
    selected "${profiles}" || continue
    source_type="$(yq -r ".spec.charts[${chart_index}].sourceType" "${manifest}")"
    source="$(yq -r ".spec.charts[${chart_index}].source" "${manifest}")"
    version="$(yq -r ".spec.charts[${chart_index}].version" "${manifest}")"
    archive="$(yq -r ".spec.charts[${chart_index}].archive" "${manifest}")"
    require_bundle_basename "${archive}" "spec.charts[${chart_index}].archive"
    path="${bundle}/charts/${archive}"
    if [[ -f "${path}" ]]; then
      printf 'Using existing chart archive %s\n' "${path}"
    else
      case "${source_type}" in
        oci)
          helm pull "${source}" --version "${version}" --destination "${bundle}/charts"
          ;;
        helm-repo)
          chart="$(yq -r ".spec.charts[${chart_index}].chart" "${manifest}")"
          helm pull "${chart}" --repo "${source}" --version "${version}" --destination "${bundle}/charts"
          ;;
        local)
          helm package "${manifest_dir}/${source}" --destination "${bundle}/charts" >/dev/null
          ;;
        *)
          printf 'Unsupported chart sourceType %s\n' "${source_type}" >&2
          exit 2
          ;;
      esac
    fi
    [[ -f "${path}" ]] || { printf 'Expected chart archive was not produced: %s\n' "${path}" >&2; exit 1; }
    chart_version="$(helm show chart "${path}" | yq -r '.version')"
    if [[ "${chart_version}" != "${version}" ]]; then
      printf 'Chart %s has version %s, but the manifest requires %s; use a new bundle directory.\n' \
        "${path}" "${chart_version}" "${version}" >&2
      exit 1
    fi
    validate_chart_dependencies "${path}"
    printf 'chart\t%s\t%s\t%s\n' "${source}" "${version}" "$(sha256sum "${path}" | awk '{print $1}')" \
      >> "${bundle}/SOURCE-DIGESTS.txt"
  done

  local image_count image_index image_source image_transport image_ref image_bundle image_digest bundle_digest
  image_count="$(yq -r '.spec.images | length' "${manifest}")"
  for ((image_index=0; image_index<image_count; image_index++)); do
    profiles="$(yq -r ".spec.images[${image_index}].profiles | join(\",\")" "${manifest}")"
    selected "${profiles}" || continue
    image_source="$(yq -r ".spec.images[${image_index}].source" "${manifest}")"
    image_transport="$(yq -r ".spec.images[${image_index}].sourceTransport // \"docker\"" "${manifest}")"
    case "${image_transport}" in
      docker) image_ref="docker://${image_source}" ;;
      docker-daemon) image_ref="docker-daemon:${image_source}" ;;
      *)
        printf 'Unsupported image sourceTransport %s for %s\n' "${image_transport}" "${image_source}" >&2
        exit 2
        ;;
    esac
    image_bundle="$(yq -r ".spec.images[${image_index}].bundlePath" "${manifest}")"
    require_bundle_basename "${image_bundle}" "spec.images[${image_index}].bundlePath"
    path="${bundle}/images/${image_bundle}"
    if [[ "${image_transport}" == "docker" ]]; then
      image_digest="$(skopeo inspect --no-tags --retry-times 3 \
        --authfile "${source_auth_file}" --format '{{.Digest}}' "${image_ref}")"
    else
      image_digest="$(skopeo inspect --format '{{.Digest}}' "${image_ref}")"
    fi
    if [[ -d "${path}" ]]; then
      [[ -f "${path}/manifest.json" ]] || {
        printf 'Cached image bundle is incomplete: %s; use a new bundle directory.\n' "${path}" >&2
        exit 1
      }
      bundle_digest="$(skopeo inspect --format '{{.Digest}}' "dir:${path}")"
      if [[ "${bundle_digest}" != "${image_digest}" ]]; then
        printf 'Cached image %s has digest %s, but source is now %s; use a new bundle directory.\n' \
          "${path}" "${bundle_digest}" "${image_digest}" >&2
        exit 1
      fi
    elif [[ -e "${path}" ]]; then
      printf 'Image bundle path exists but is not a directory: %s\n' "${path}" >&2
      exit 1
    else
      # The dir transport preserves Docker/OCI manifest media types, multi-arch
      # indexes, source digests, and containers/image transport signatures.
      if [[ "${image_transport}" == "docker" ]]; then
        skopeo copy --all --preserve-digests --retry-times 3 \
          --src-authfile "${source_auth_file}" \
          "${image_ref}" "dir:${path}"
      else
        # A locally built PR image is intentionally single-platform. The
        # Docker daemon transport cannot expose a manifest list, so --all does
        # not apply; digest preservation still makes the transfer verifiable.
        skopeo copy --preserve-digests --retry-times 3 \
          "${image_ref}" "dir:${path}"
      fi
    fi
    printf 'image\t%s\t%s\t%s\n' "${image_source}" "${image_digest}" "${image_transport}" \
      >> "${bundle}/SOURCE-DIGESTS.txt"
  done

  {
    printf 'manifest_sha256=%s\n' "${current_manifest_digest}"
    printf 'profile=%s\n' "${profile}"
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'helm=%s\n' "$(helm version --short)"
    printf 'skopeo=%s\n' "$(skopeo --version)"
  } > "${bundle}/METADATA"
  (
    cd "${bundle}"
    find charts images -type f -print0 | sort -z | xargs -0 sha256sum
    sha256sum ARTIFACTS.yaml SOURCE-DIGESTS.txt METADATA
  ) > "${bundle}/SHA256SUMS"
  printf 'Export complete: %s\n' "${bundle}"
}

import_bundle() {
  [[ -f "${bundle}/SHA256SUMS" ]] || { printf 'Missing bundle checksums: %s\n' "${bundle}" >&2; exit 2; }
  (cd "${bundle}" && sha256sum --check SHA256SUMS)
  [[ -f "${bundle}/ARTIFACTS.yaml" ]] || { printf 'Missing bundled artifact manifest.\n' >&2; exit 2; }
  manifest="${bundle}/ARTIFACTS.yaml"

  local bundled_profile
  bundled_profile="$(awk -F= '$1 == "profile" {print $2}' "${bundle}/METADATA")"
  if [[ "${bundled_profile}" != "core" && "${bundled_profile}" != "suse" && "${bundled_profile}" != "chatbot" && \
        "${bundled_profile}" != "vendor" && "${bundled_profile}" != "all" ]]; then
    printf 'Bundle contains an invalid or missing profile: %s\n' "${bundled_profile}" >&2
    exit 1
  fi
  if [[ "${profile_was_set}" == true && "${profile}" != "${bundled_profile}" ]]; then
    printf 'Requested profile %s does not match bundled profile %s.\n' \
      "${profile}" "${bundled_profile}" >&2
    exit 1
  fi
  profile="${bundled_profile}"
  destination_login

  local chart_count chart_index profiles archive target_count target_index target chart_name version
  chart_count="$(yq -r '.spec.charts | length' "${manifest}")"
  for ((chart_index=0; chart_index<chart_count; chart_index++)); do
    profiles="$(yq -r ".spec.charts[${chart_index}].profiles | join(\",\")" "${manifest}")"
    selected "${profiles}" || continue
    archive="$(yq -r ".spec.charts[${chart_index}].archive" "${manifest}")"
    require_bundle_basename "${archive}" "spec.charts[${chart_index}].archive"
    version="$(yq -r ".spec.charts[${chart_index}].version" "${manifest}")"
    chart_name="$(helm show chart "${bundle}/charts/${archive}" | yq -r '.name')"
    target_count="$(yq -r ".spec.charts[${chart_index}].targets | length" "${manifest}")"
    for ((target_index=0; target_index<target_count; target_index++)); do
      target="$(yq -r ".spec.charts[${chart_index}].targets[${target_index}]" "${manifest}")"
      helm push "${bundle}/charts/${archive}" "oci://${HARBOR_REGISTRY}/${target}" \
        --ca-file "${harbor_ca_file}"
      helm show chart "oci://${HARBOR_REGISTRY}/${target}/${chart_name}" \
        --version "${version}" --ca-file "${harbor_ca_file}" >/dev/null
    done
  done

  local image_count image_index image_bundle image_target image_source expected_digest destination_digest
  image_count="$(yq -r '.spec.images | length' "${manifest}")"
  for ((image_index=0; image_index<image_count; image_index++)); do
    profiles="$(yq -r ".spec.images[${image_index}].profiles | join(\",\")" "${manifest}")"
    selected "${profiles}" || continue
    image_bundle="$(yq -r ".spec.images[${image_index}].bundlePath" "${manifest}")"
    require_bundle_basename "${image_bundle}" "spec.images[${image_index}].bundlePath"
    image_target="$(yq -r ".spec.images[${image_index}].target" "${manifest}")"
    image_source="$(yq -r ".spec.images[${image_index}].source" "${manifest}")"
    expected_digest="$(awk -F '\t' -v source="${image_source}" '$1 == "image" && $2 == source {print $3}' "${bundle}/SOURCE-DIGESTS.txt")"
    [[ -n "${expected_digest}" ]] || { printf 'No source digest recorded for %s\n' "${image_source}" >&2; exit 1; }
    [[ -f "${bundle}/images/${image_bundle}/manifest.json" ]] || {
      printf 'Missing image bundle: %s\n' "${bundle}/images/${image_bundle}" >&2
      exit 1
    }
    # Registry transports cannot store containers/image simple-signature files.
    # They remain checksummed in the media bundle for separate verification.
    skopeo copy --all --preserve-digests --remove-signatures --retry-times 3 \
      --dest-authfile "${destination_auth_file}" \
      --dest-cert-dir "${skopeo_cert_dir}" \
      "dir:${bundle}/images/${image_bundle}" \
      "docker://${HARBOR_REGISTRY}/${image_target}"
    destination_digest="$(skopeo inspect --no-tags --retry-times 3 \
      --authfile "${destination_auth_file}" \
      --cert-dir "${skopeo_cert_dir}" \
      --format '{{.Digest}}' "docker://${HARBOR_REGISTRY}/${image_target}")"
    if [[ "${destination_digest}" != "${expected_digest}" ]]; then
      printf 'Digest mismatch for %s: expected %s, imported %s\n' \
        "${image_target}" "${expected_digest}" "${destination_digest}" >&2
      exit 1
    fi
    printf 'Imported %s at %s\n' "${image_target}" "${destination_digest}"
  done
  printf 'Import complete: %s\n' "${HARBOR_REGISTRY}"
}

case "${operation}" in
  export) export_bundle ;;
  import) import_bundle ;;
  mirror) export_bundle; import_bundle ;;
esac
