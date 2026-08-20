#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
default_source_dir="$(cd "${lab_dir}/../.." && pwd)/aif"

source_dir="${AIF_SOURCE_DIR:-${default_source_dir}}"
output_manifest="${AIF_SOURCE_MANIFEST:-${lab_dir}/generated/artifacts-aif-source.yml}"
image_prefix="${AIF_SOURCE_IMAGE_PREFIX:-localhost/aif-airgap-source}"
rebuild="${AIF_SOURCE_REBUILD:-false}"

usage() {
  printf '%s\n' \
    "Usage: $0 [--source-dir DIR] [--output-manifest FILE] [--image-prefix PREFIX]" \
    "" \
    "Builds AIF operator/UI images and stages charts from an exact local Git" \
    "checkout. The generated manifest can then be supplied to run.sh mirror." \
    "" \
    "Environment: AIF_SOURCE_REBUILD=true forces container rebuilds."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir) source_dir=$2; shift 2 ;;
    --output-manifest) output_manifest=$2; shift 2 ;;
    --image-prefix) image_prefix=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for command_name in docker git helm jq node realpath tar yq yarn; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done

source_dir="$(cd "${source_dir}" && pwd)"
for required in \
  "${source_dir}/.git" \
  "${source_dir}/build/Dockerfile.operator" \
  "${source_dir}/build/Dockerfile.ui" \
  "${source_dir}/charts/aif-operator/Chart.yaml" \
  "${source_dir}/charts/aif-ui/Chart.yaml" \
  "${source_dir}/operator/go.mod" \
  "${source_dir}/ui/package.json"; do
  [[ -e "${required}" ]] || {
    printf 'AIF source checkout is incomplete: %s is missing\n' "${required}" >&2
    exit 2
  }
done

if [[ -n "$(git -C "${source_dir}" status --porcelain --untracked-files=no)" ]]; then
  printf 'AIF source checkout has tracked changes; commit or stash them before building evidence.\n' >&2
  exit 1
fi

version="$(yq -r '.version' "${source_dir}/charts/aif-operator/Chart.yaml")"
ui_chart_version="$(yq -r '.version' "${source_dir}/charts/aif-ui/Chart.yaml")"
ui_package_version="$(jq -r '.version' "${source_dir}/ui/package.json")"
ui_extension_version="$(jq -r '.version' "${source_dir}/ui/pkg/aif-ui/package.json")"
if [[ -z "${version}" || "${version}" == "null" ||
      "${ui_chart_version}" != "${version}" ||
      "${ui_package_version}" != "${version}" ||
      "${ui_extension_version}" != "${version}" ]]; then
  printf 'AIF operator chart, UI chart, UI workspace and extension versions must match.\n' >&2
  printf 'operator=%s ui-chart=%s ui-workspace=%s ui-extension=%s\n' \
    "${version}" "${ui_chart_version}" "${ui_package_version}" "${ui_extension_version}" >&2
  exit 1
fi

if [[ "${image_prefix}" != */* ]]; then
  printf 'Image prefix must contain a registry and organization, got: %s\n' "${image_prefix}" >&2
  exit 2
fi
image_registry="${image_prefix%%/*}"
image_org="${image_prefix#*/}"

commit="$(git -C "${source_dir}" rev-parse HEAD)"
short_commit="${commit:0:12}"
branch="$(git -C "${source_dir}" branch --show-current)"
source_url="https://github.com/SUSE/aif"
build_root="${lab_dir}/generated/aif-source/${commit}"
operator_image="${image_prefix}/aif-operator:${version}"
ui_image="${image_prefix}/aif-ui:${version}"
build_checkout="$(mktemp -d /tmp/aif-source-build.XXXXXX)"
cleanup_build_checkout() {
  rm -rf -- "${build_checkout}"
}
trap cleanup_build_checkout EXIT

image_revision() {
  docker image inspect "$1" \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    2>/dev/null || true
}

# Build from Git's exact commit rather than the developer's working directory.
# This excludes untracked files and lets the UI publisher freely create and
# clean its output without mutating the source checkout used as evidence.
git -C "${source_dir}" archive --format=tar "${commit}" | tar -xf - -C "${build_checkout}"

mkdir -p "${build_root}/charts" "$(dirname "${output_manifest}")"
if [[ ! -d "${build_root}/charts/aif-operator" ]]; then
  cp -a "${build_checkout}/charts/aif-operator" "${build_root}/charts/aif-operator"
fi
if [[ ! -d "${build_root}/charts/aif-ui" ]]; then
  cp -a "${build_checkout}/charts/aif-ui" "${build_root}/charts/aif-ui"
fi

operator_revision="$(image_revision "${operator_image}")"
if [[ "${rebuild}" == "true" || "${operator_revision}" != "${commit}" ]]; then
  if [[ -n "${operator_revision}" && "${operator_revision}" != "${commit}" ]]; then
    printf 'Rebuilding stale operator image %s (cached revision %s).\n' \
      "${operator_image}" "${operator_revision}"
  fi
  docker build \
    -f "${build_checkout}/build/Dockerfile.operator" \
    --build-arg "VERSION=${version}" \
    --build-arg "COMMIT=${commit}" \
    --label "org.opencontainers.image.revision=${commit}" \
    --label "org.opencontainers.image.source=${source_url}" \
    -t "${operator_image}" \
    "${build_checkout}/operator"
else
  printf 'Using existing operator image %s\n' "${operator_image}"
fi

ui_revision="$(image_revision "${ui_image}")"
if [[ "${rebuild}" == "true" || "${ui_revision}" != "${commit}" ]]; then
  if [[ -n "${ui_revision}" && "${ui_revision}" != "${commit}" ]]; then
    printf 'Rebuilding stale UI image %s (cached revision %s).\n' \
      "${ui_image}" "${ui_revision}"
  fi
  (
    cd "${build_checkout}/ui"
    yarn install --frozen-lockfile --ignore-engines --non-interactive
  )
  # webpack-virtual-modules creates @rancher/auto-import under the package's
  # nearest node_modules directory. Keep the package-local directory inside
  # the disposable checkout as well.
  mkdir -p "${build_checkout}/ui/pkg/aif-ui/node_modules"
  (
    cd "${build_checkout}/ui"
    yarn publish-pkgs -n -f -c -i '' \
      -r "${image_registry}" -o "${image_org}" \
      -t "aif-ui-${version}" aif-ui
  )
  docker build \
    -f "${build_checkout}/build/Dockerfile.ui" \
    --build-arg "BASE=${ui_image}" \
    --label "org.opencontainers.image.revision=${commit}" \
    --label "org.opencontainers.image.source=${source_url}" \
    -t "${ui_image}" \
    "${build_checkout}"
else
  printf 'Using existing UI image %s\n' "${ui_image}"
fi

# The Rancher publisher historically logged some packaging errors without
# returning non-zero. Assert the catalog contract from inside the final image
# so a malformed PR artifact cannot become test evidence.
docker run --rm --entrypoint /bin/bash "${ui_image}" -euc '
  version=$1
  root=/home/plugin-server/plugin-contents
  test -s "${root}/index.yaml"
  test -s "${root}/plugin/index.yaml"
  test -s "${root}/plugin/aif-ui/aif-ui-${version}.tgz"
  test -s "${root}/plugin/aif-ui-${version}.tgz"
  test -s "${root}/plugin/aif-ui-${version}/files.txt"
  test -s "${root}/plugin/aif-ui-${version}/plugin/aif-ui-${version}.umd.min.js"
  test ! -e "${root}/plugin/aif-ui-${version}.tar.gz"
  tar -tzf "${root}/plugin/aif-ui/aif-ui-${version}.tgz" >/dev/null
' -- "${version}"

for image in "${operator_image}" "${ui_image}"; do
  revision="$(docker image inspect "${image}" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"
  if [[ "${revision}" != "${commit}" ]]; then
    printf 'Image %s revision is %s, expected %s\n' "${image}" "${revision}" "${commit}" >&2
    exit 1
  fi
done

cp "${lab_dir}/artifacts.yml" "${output_manifest}"
manifest_dir="$(cd "$(dirname "${output_manifest}")" && pwd)"
operator_chart_source="$(realpath --relative-to="${manifest_dir}" "${build_root}/charts/aif-operator")"
ui_chart_source="$(realpath --relative-to="${manifest_dir}" "${build_root}/charts/aif-ui")"
smoke_chart_source="$(realpath --relative-to="${manifest_dir}" "${lab_dir}/fixtures/charts/airgap-smoke")"

AIF_SOURCE_COMMIT="${commit}" \
AIF_SOURCE_BRANCH="${branch}" \
AIF_SOURCE_SHORT_COMMIT="${short_commit}" \
AIF_SOURCE_VERSION="${version}" \
AIF_OPERATOR_CHART_SOURCE="${operator_chart_source}" \
AIF_UI_CHART_SOURCE="${ui_chart_source}" \
AIF_SMOKE_CHART_SOURCE="${smoke_chart_source}" \
AIF_OPERATOR_IMAGE="${operator_image}" \
AIF_UI_IMAGE="${ui_image}" \
yq -i '
  .metadata.name = "aif-source-" + strenv(AIF_SOURCE_SHORT_COMMIT) |
  .metadata.annotations."airgap.ai-factory.suse.com/source-commit" = strenv(AIF_SOURCE_COMMIT) |
  .metadata.annotations."airgap.ai-factory.suse.com/source-branch" = strenv(AIF_SOURCE_BRANCH) |
  .metadata.annotations."airgap.ai-factory.suse.com/source-version" = strenv(AIF_SOURCE_VERSION) |
  (.spec.charts[] | select(.id == "aif-operator") | .sourceType) = "local" |
  (.spec.charts[] | select(.id == "aif-operator") | .source) = strenv(AIF_OPERATOR_CHART_SOURCE) |
  (.spec.charts[] | select(.id == "aif-operator") | .version) = strenv(AIF_SOURCE_VERSION) |
  (.spec.charts[] | select(.id == "aif-operator") | .archive) = "aif-operator-" + strenv(AIF_SOURCE_VERSION) + ".tgz" |
  (.spec.charts[] | select(.id == "aif-ui") | .sourceType) = "local" |
  (.spec.charts[] | select(.id == "aif-ui") | .source) = strenv(AIF_UI_CHART_SOURCE) |
  (.spec.charts[] | select(.id == "aif-ui") | .version) = strenv(AIF_SOURCE_VERSION) |
  (.spec.charts[] | select(.id == "aif-ui") | .archive) = "aif-ui-" + strenv(AIF_SOURCE_VERSION) + ".tgz" |
  (.spec.charts[] | select(.sourceType == "local" and .id != "aif-operator" and .id != "aif-ui") | .source) = strenv(AIF_SMOKE_CHART_SOURCE) |
  (.spec.images[] | select(.id == "aif-operator") | .source) = strenv(AIF_OPERATOR_IMAGE) |
  (.spec.images[] | select(.id == "aif-operator") | .sourceTransport) = "docker-daemon" |
  (.spec.images[] | select(.id == "aif-operator") | .bundlePath) = "ghcr.io_suse_aif-operator_" + strenv(AIF_SOURCE_VERSION) + ".dir" |
  (.spec.images[] | select(.id == "aif-operator") | .target) = "aif-images/ghcr.io/suse/aif-operator:" + strenv(AIF_SOURCE_VERSION) |
  (.spec.images[] | select(.id == "aif-ui") | .source) = strenv(AIF_UI_IMAGE) |
  (.spec.images[] | select(.id == "aif-ui") | .sourceTransport) = "docker-daemon" |
  (.spec.images[] | select(.id == "aif-ui") | .bundlePath) = "ghcr.io_suse_aif-ui_" + strenv(AIF_SOURCE_VERSION) + ".dir" |
  (.spec.images[] | select(.id == "aif-ui") | .target) = "aif-images/ghcr.io/suse/aif-ui:" + strenv(AIF_SOURCE_VERSION)
' "${output_manifest}"

helm lint "${build_root}/charts/aif-operator"
helm lint "${build_root}/charts/aif-ui"

printf 'Built AIF source artifacts for %s (%s)\n' "${commit}" "${branch:-detached}"
printf 'Set aif_version: %s in the lab vars used for installation.\n' "${version}"
printf 'Generated manifest: %s\n' "${output_manifest}"
printf 'Use a unique bundle, for example:\n'
printf '  AIF_AIRGAP_MANIFEST=%q AIF_AIRGAP_BUNDLE=%q %q mirror\n' \
  "${output_manifest}" "${lab_dir}/bundles/aif-${short_commit}" "${lab_dir}/run.sh"
