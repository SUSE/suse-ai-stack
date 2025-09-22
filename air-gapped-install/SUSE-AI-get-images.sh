#!/usr/bin/env bash
set -o pipefail

# shellcheck disable=SC2034
GREEN='\033[0;32m'
RED='\033[0;31m'
NO_COLOR='\033[0m'

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function usage() {
  cat <<EOF >&2
Get the list of Docker images used by the SUSE AI stack

Usage:
  $0 [-f suse-ai-stack-X.Y.Z.tgz]

Arguments:
    -f : TGZ archive with the SUSE AI-Stack (optional)
    -h : Show this help text
EOF
}

charts=()
charts+=("milvus")
charts+=("ollama")
charts+=("open-webui")
charts+=("open-webui-pipelines")
charts+=("pytorch")
charts+=("suse-ai-observability-extension")
charts+=("cert-manager")
default=0

helm_chart_archive=$(realpath "$dir/..")

function getCharts() {
  mkdir "charts"
  for chart in "${charts[@]}"
  do
    helm fetch -d charts 'oci://dp.apps.rancher.io/charts/'"$chart"
  done
}

# Parse options
while getopts ":f:h" opt; do
  case ${opt} in
    f)
      helm_chart_archive=${OPTARG}

      # Check if the archive exists
      if [ ! -f "${helm_chart_archive}" ]; then
        echo -e "${RED}Helm chart archive not found${NO_COLOR}: ${helm_chart_archive}" >&2
        exit 1
      fi
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo -e "${RED}Option -${OPTARG} requires an argument.${NO_COLOR}" >&2
      usage
      exit 1
      ;;
    *)
      echo -e "${RED}Unimplemented option: -${OPTARG}${NO_COLOR}" >&2
      usage
      exit 1
      ;;
  esac
done

if [ $OPTIND -eq 1 ]
then
  echo -e "${GREEN}Using default charts.${NO_COLOR}"
  getCharts
fi

helm_release=release

images=()
function listImages() {
  tmp_file=/tmp/suse-ai-tenant-get-images
  cd "charts"
  helm_values="serverUrl=http://dummy.stackstate.io,clusterName=dummy,apiKey=dummy,apiToken=dummy"
  for chart in *; do
    echo -e "${GREEN}Evaluating ${chart}${NO_COLOR}"
    helm template "$helm_release" "$chart" --set "$helm_values" | grep image: | sed -E 's/^.*image: ['\''"]?([^'\''"]*)['\''"]?.*$/\1/' > "$tmp_file"
    while IFS='' read -r line; do images+=("$line"); done < "$tmp_file"

    # Remove duplicates
    IFS=" " read -r -a images <<< "$(echo "${images[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    rm -f "$tmp_file"
  done

  # Add MLflow to the list which does not come with a helm-chart
  images+=("dp.apps.rancher.io/containers/mlflow:2.22.0")
  # Add OpenTelemetry collector
  images+=("otel/opentelemetry-collector-k8s")
}

function pullImages() {
  # Pull the images from the list
  for image in "${images[@]}"
  do
    if docker pull "${image}" > /dev/null 2>&1; then
      echo -e "${GREEN}Image pull success${NO_COLOR}: ${image}"
      pulled="${pulled} ${image}"
    else
      echo -e "${RED}Image pull failed${NO_COLOR}: ${image}"
    fi
  done

  image_archive=suse-ai-containers.tgz
  echo -e "Creating ${image_archive} with $(echo "${pulled}" | wc -w | tr -d '[:space:]') images"

  docker save ${pulled} | gzip --stdout > "${image_archive}"
  if [ $? -eq 0 ]; then
      echo -e "${GREEN}Images saved to ${image_archive}${NO_COLOR}"
  else
      echo -e "${RED}Failed to save images to ${image_archive}${NO_COLOR}"
  fi
}

function saveImageFile() {
  echo -e "${GREEN}Image list saved to suse-ai-containers.txt${NO_COLOR}"
  printf "%s\n" "${images[@]}" > suse-ai-containers.txt
}

listImages
pullImages
saveImageFile
