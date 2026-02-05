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
  $0 [-f suse-ai-stack-X.Y.Z.tgz] [-i charts.txt]

Arguments:
    -f : TGZ archive with the SUSE AI-Stack (optional)
    -i : File which lists all needed charts (optional)	
    -h : Show this help text
EOF
}

CHARTS_FILE="charts.txt"

helm_chart_archive=""

function getCharts() {
  mkdir "charts"
  for chart in "${charts[@]}"
  do
    helm fetch -d charts "$chart"
  done
}

# Parse options
while getopts "f:i:h" opt; do
  case ${opt} in
    f)
      helm_chart_archive=${OPTARG}

      # Check if the archive exists
      if [ ! -f "${helm_chart_archive}" ]; then
        echo -e "${RED}Helm chart archive not found${NO_COLOR}: ${helm_chart_archive}" >&2
        exit 1
      fi
      ;;
    i)
      CHARTS_FILE=${OPTARG}
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

if [[ ! -f "$CHARTS_FILE" ]]; then
  echo -e "${RED}File '$CHARTS_FILE' is not valid.${NO_COLOR}"
  exit 1
fi

readarray -t charts < "$CHARTS_FILE"
echo -e "${GREEN} Read in '${CHARTS_FILE}'. Number of entries: ${#charts[@]}"

if [[ -z "$helm_chart_archive" ]]; then
  echo -e "${GREEN}Using default charts.${NO_COLOR}"
  getCharts
fi

images=()
function listImages() {
  cd "charts"
  for chart in *; do
    echo -e "${GREEN}Evaluating ${chart}${NO_COLOR}"
    TMP_DIR=$(mktemp -d)
    echo "Unpack chart ${chart} to: $TMP_DIR"
    tar -xzf "$chart" -C $TMP_DIR

    image_list=$(find "$TMP_DIR" -name "Chart.yaml" -exec awk '
    # look for the line "helm.sh/images:" and flag it
    /helm.sh\/images:/ { in_images_block = 1; next }

    in_images_block && /^[[:space:]]*- image:/ {
        img = $0
        sub(/^[[:space:]]*- image:[[:space:]]*/, "", img) # Remove "- image: "
        sub(/[[:space:]]*$/, "", img)                    # Remove spaces
        print img
    }

    in_images_block && /^[a-zA-Z]/ && !/helm.sh\/images:/ { in_images_block = 0 }
' {} +)

    local -A unique_images_map
    while read -r line; do
      if [[ -n "$line" ]]; then
        clean_img=$(echo "$line" | tr -d '"' | tr -d "'")
        unique_images_map["$clean_img"]=1
      fi
    done <<< "$image_list"

    images=("${!unique_images_map[@]}")

    rm -rf "$TMP_DIR"
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
