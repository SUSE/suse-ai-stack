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
  mkdir -p "charts"
  for chart in "${charts[@]}"
  do
    # Strip potential artifacts like "" if copied directly from documentation/chat
    chart=$(echo "$chart" | sed -e 's/^\*//')
    
    # Check if the chart is an OCI registry that contains a version tag (:)
    if [[ "$chart" == oci://*:* ]]; then
      # Extract URL and version
      url="${chart%:*}"
      version="${chart##*:}"
      echo -e "${GREEN}Pulling OCI chart: $url --version $version${NO_COLOR}"
      helm pull -d charts "$url" --version "$version"
    else
      echo -e "${GREEN}Pulling chart: $chart${NO_COLOR}"
      helm pull -d charts "$chart"
    fi
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

# Read the chart array while ignoring empty lines
readarray -t charts < <(awk 'NF' "$CHARTS_FILE")
echo -e "${GREEN}Read in '${CHARTS_FILE}'. Number of entries: ${#charts[@]}${NO_COLOR}"

if [[ -z "$helm_chart_archive" ]]; then
  echo -e "${GREEN}Using default charts.${NO_COLOR}"
  getCharts
fi

images=()
function listImages() {
  cd "charts" || exit 1
  
  # Use a global associative array to prevent duplicates across ALL charts
  local -A unique_images_map

  for chart in *; do
    # Prevent '*' from expanding literally if the directory is empty
    [ -f "$chart" ] || continue

    echo -e "${GREEN}Evaluating ${chart} via helm template...${NO_COLOR}"

    # helm template works directly on .tgz files (no need to unpack)
    # 2>/dev/null suppresses warnings from missing values/custom resources
    image_list=$(helm template dummy "$chart" --set global.demoMode=true 2>/dev/null | awk '
      # Match standard Kubernetes image declarations
      /^[[:space:]]*-?[[:space:]]*image:[[:space:]]*/ {
          img = $0
          sub(/^[[:space:]]*-?[[:space:]]*image:[[:space:]]*/, "", img) # Strip the "image:" key
          sub(/[[:space:]]*#.*$/, "", img)                               # Strip inline comments
          sub(/[[:space:]]+$/, "", img)                                  # Strip trailing spaces
          gsub(/["\x27]/, "", img)                                       # Strip quotes
          
          # STRICT FILTER: Ignore empty strings, env vars ($), or raw templates ({, <)
          if (img != "" && img !~ /^[$<{]/) {
              print img
          }
      }')

    while read -r clean_img; do
      if [[ -n "$clean_img" ]]; then
        unique_images_map["$clean_img"]=1
      fi
    done <<< "$image_list"
  done

  # Append to images array safely
  for img in "${!unique_images_map[@]}"; do
      images+=("$img")
  done

  # Add MLflow to the list which does not come with a helm-chart
  images+=("dp.apps.rancher.io/containers/mlflow:2.22.0")
  # Add OpenTelemetry collector
  images+=("otel/opentelemetry-collector-k8s")
}

function pullImages() {
  pulled=""
  MAX_RETRIES=3
  RETRY_DELAY=5

  # Pull the images from the list
  for image in "${images[@]}"
  do
    local attempt=1
    local success=false

    while [[ $attempt -le $MAX_RETRIES ]]; do
      if docker pull "${image}" > /dev/null 2>&1; then
        echo -e "${GREEN}Image pull success${NO_COLOR}: ${image}"
        pulled="${pulled} ${image}"
        success=true
        break # Exit the retry loop on success
      else
        echo -e "${RED}Image pull failed (Attempt ${attempt}/${MAX_RETRIES})${NO_COLOR}: ${image}"
        attempt=$((attempt + 1))
        
        # Only sleep if we have more retries left
        if [[ $attempt -le $MAX_RETRIES ]]; then
          echo "Retrying in ${RETRY_DELAY} seconds..."
          sleep $RETRY_DELAY
        fi
      fi
    done

    # Final check if all retries were exhausted
    if [[ "$success" == false ]]; then
      echo -e "${RED}Final failure. Could not pull ${image} after ${MAX_RETRIES} attempts. Skipping.${NO_COLOR}"
    fi
  done

  # Check if anything was actually pulled to avoid docker save errors
  if [[ -z "$(echo "${pulled}" | tr -d '[:space:]')" ]]; then
      echo -e "${RED}No images were successfully pulled. Skipping archive creation.${NO_COLOR}"
      return
  fi

  image_archive=suse-ai-containers.tgz
  echo -e "Creating ${image_archive} with $(echo "${pulled}" | wc -w | tr -d '[:space:]') images"

  # shellcheck disable=SC2086
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