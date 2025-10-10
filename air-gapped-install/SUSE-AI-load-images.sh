#!/usr/bin/env bash
set -o pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NO_COLOR='\033[0m'

image_list_file="suse-ai-containers.txt"
image_archive="suse-ai-containers.tgz"

function usage() {
  cat <<EOF
Load Docker images needed for the SUSE AI charts to another Docker image registry

Usage:
  $0 -d custom-registry.example.com:5000 -i suse-ai-containers.txt -f suse-ai-containers.tgz

Environment Variables:
    DST_REGISTRY_USERNAME : Destination Docker image registry username. If both DST_REGISTRY_USERNAME and DST_REGISTRY_PASSWORD are set, the script will attempt to login to the registry.
    DST_REGISTRY_PASSWORD : Destination Docker image registry password

Arguments:
    -d : Destination Docker image registry (required)
    -f : TGZ Archive with images (default: ${image_archive})
    -i : File with the list of images (default: ${image_list_file})
    -h : Show this help text
EOF
}

# Parse options
while getopts ":d:f:i:h" opt; do
  case ${opt} in
    d)
      destination_registry=${OPTARG}
      ;;
    f)
      image_archive=${OPTARG}
      ;;
    i)
      image_list_file=${OPTARG}
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

# Check if all required options are provided
if [[ -z "${destination_registry}" ]]; then
  echo -e "${RED}Error: -d option is required.${NO_COLOR}"
  usage
  exit 1
fi

# Check if the archive exists
if [ ! -f "${image_archive}" ]; then
  echo -e "${RED}The archive with images is not found${NO_COLOR}: ${image_archive}"
  exit 1
fi

# Check if the file with image list exists
if [ ! -f "${image_list_file}" ]; then
  echo -e "${RED}The file with the list of images is not found${NO_COLOR}: ${image_list_file}"
  exit 1
fi

# Login to the destination registry
if [ -n "${DST_REGISTRY_USERNAME}" ] && [ -n "${DST_REGISTRY_PASSWORD}" ]; then
  docker login -u "${DST_REGISTRY_USERNAME}" -p "${DST_REGISTRY_PASSWORD}" "${destination_registry}"
fi

docker load < "${image_archive}" > /dev/null
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to load images from ${image_archive}${NO_COLOR}"
  exit 1
fi

# Process each line in the file
while IFS= read -r image; do
  # Simple check if the image is in the format <registry>/<repository>:<tag>
  if [[ $image =~ ^([^/]+)/(.*):([^:]+)$ ]]; then
    repository_and_tag=$(echo "${image}" | cut -d'/' -f2-)
    dest_image="${destination_registry}/${repository_and_tag}"
    docker tag "${image}" "${dest_image}"
    docker push "${dest_image}"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Successfully pushed ${dest_image}${NO_COLOR}"
    else
      echo -e "${RED}Failed to push ${dest_image}${NO_COLOR}"
    fi
  else
      echo -e "${RED}Image url ${image} is not valid. Skipping...${NO_COLOR}"
  fi
done < "${image_list_file}"
