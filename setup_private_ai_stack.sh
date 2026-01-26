#!/bin/bash -eu

PROJECT_DIR=$(dirname -- $(readlink -e -- ${BASH_SOURCE[0]}))
PATH=${PROJECT_DIR}/bin:${PATH}
EXTRA_VARS_FILE=$PROJECT_DIR/extra_vars.yml
export ANSIBLE_ROLES_PATH=${PROJECT_DIR}/roles:${PROJECT_DIR}/external_playbooks/roles:${LIBVIRT_IMAGES_DIR:=/var/lib/libvirt/images}

if [ ! -d ${LIBVIRT_IMAGES_DIR} ] ; then
  echo "WARNING: ${LIBVIRT_IMAGES_DIR} either not exist or not accessible by  user ${USER}."
  echo "Will use ${PROJECT_DIR}/libvirt_images instead."
  LIBVIRT_IMAGES_DIR=${PROJECT_DIR}/libvirt_images
fi

setup_name=$(basename ${BASH_SOURCE[0]} .sh)
setup_type=${setup_name#setup_}
playbook=${setup_name}
case "${setup_type}" in
#(special_case)
#	inv_name=some_value
#	;;
(*)
	inv_name=localhost
	;;
esac

# Base argument
base_playbook_args=(
  -e current_project_dir="${PROJECT_DIR}"
  -e libvirt_images_dir="${LIBVIRT_IMAGES_DIR}"
)

if [ ! -f "${EXTRA_VARS_FILE}" ] ; then
	echo "ERROR: ${EXTRA_VARS_FILE} not found. Did you remember to copy extra_vars.yml.example to extra_vars.yml and configure it appropriately?"
	exit 1
fi

if ! command -v ansible-playbook &> /dev/null; then
    echo "ERROR: ansible-playbook command not found. Please install ansible."
    exit 1
fi

# clean up dynamically created inventories/extra_vars.yml
clusters=("mgmt" "suse-ai" "suse-observability")

CLEANUP_INI_FILES=${CLEANUP_INI_FILES:-true} #always cleanup for every run since the logic later depends on existence of these files.

# clean up ini files
for cluster in "${clusters[@]}"; do
  if [[ ${cluster} != "mgmt" ]]; then
    if [[ "$CLEANUP_INI_FILES" == true ]]; then
      rm -f "${PROJECT_DIR}/inventories/${cluster}_inventory.ini"
      rm -f "${PROJECT_DIR}/${cluster}_extra_vars.yml"
    fi
  fi
done

### SET UP NODES
playbook_args=(
  "${base_playbook_args[@]}"
  -e "@extra_vars.yml"
)
inv_file=${PROJECT_DIR}/inventories/${inv_name}_inventory.yml
if [ -f "${inv_file}" ]; then
	playbook_args+=( -i ${inv_file} )
fi

playbook="setup_nodes" # playbook that creates resources and defines nodes in the cluster

# Playbook and passthrough args
playbook_args+=(
  "${PROJECT_DIR}/playbooks/${playbook}.yml"
  "$@"
)

${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"

### CLONE suse-ai-node-ansible repo as external_playbooks
EXT_REPO_URL="https://github.com/SUSE/suse-ai-node-ansible.git"
EXT_REPO_BRANCH="main"
DEST_DIR="${PROJECT_DIR}/external_playbooks"
if [ -d "$DEST_DIR/.git" ]; then
    # Updating existing repo at $DEST_DIR
    git -C "$DEST_DIR" fetch --depth 1 origin \
        "+refs/heads/$EXT_REPO_BRANCH:refs/remotes/origin/$EXT_REPO_BRANCH" \
        > /dev/null 2>&1

    git -C "$DEST_DIR" checkout -B "$EXT_REPO_BRANCH" \
        "origin/$EXT_REPO_BRANCH" \
        > /dev/null 2>&1
else
    #Cloning repo into $DEST_DIR
    git clone --depth 1 --branch "$EXT_REPO_BRANCH" "$EXT_REPO_URL" "$DEST_DIR" > /dev/null 2>&1
fi

# Copy cluster specific extra_vars.yaml to external-playbooks
# Copy cluster specific inventory.ini to external-playbooks
for cluster in "${clusters[@]}"; do
  if [ -e "${PROJECT_DIR}/${cluster}_extra_vars.yml" ]; then
    cp "${cluster}_extra_vars.yml" ${DEST_DIR}
  fi
  if [ -e "${PROJECT_DIR}/inventories/${cluster}_inventory.ini" ]; then
    cp "${PROJECT_DIR}/inventories/${cluster}_inventory.ini" ${DEST_DIR}
  fi

done


### DEPLOY RKE2 on all clusters and Rancher on mgmt cluster
playbook="deploy_rke2_rancher"

for cluster in "${clusters[@]}"; do
  playbook_args=(
    "${base_playbook_args[@]}"
    -i "${PROJECT_DIR}/inventories/${cluster}_inventory.ini"
    -e "@${DEST_DIR}/${cluster}_extra_vars.yml"
    -e cluster="${cluster}"
    "$PROJECT_DIR/playbooks/${playbook}.yml"
  )

  # Run through each cluster - mgmt, suse-ai, suse-observability with own ini files
  if [ -e "${PROJECT_DIR}/inventories/${cluster}_inventory.ini" ]; then
    ${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"
  fi

done

### DEPLOY nvidia-driver-installer optionally (https://github.com/SUSE/nvidia-driver-installer/)
playbook="deploy_nvidia_driver_installer"   # playbook that uses nvidia driver installer to install nvidia driver

cluster_inv_name='mgmt_inventory.ini'
if [ -e "${PROJECT_DIR}/inventories/suse-ai_inventory.ini" ]; then
  cluster_inv_name='suse-ai_inventory.ini'
fi

playbook_args=(
  "${base_playbook_args[@]}"
  -i "${PROJECT_DIR}/inventories/${inv_name}_inventory.yml"
  -i "${PROJECT_DIR}/inventories/${cluster_inv_name}"
  -e "@${PROJECT_DIR}/extra_vars.yml"
  "$PROJECT_DIR/playbooks/${playbook}.yml"
)

${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"


# DEPLOY external-dns, storage on all clusters
playbook="setup_dns_storage"

for cluster in "${clusters[@]}"; do
  playbook_args=(
    "${base_playbook_args[@]}"
    -i "${PROJECT_DIR}/inventories/${inv_name}_inventory.yml"
    -i "${PROJECT_DIR}/inventories/${cluster}_inventory.ini"
    -e "@${PROJECT_DIR}/extra_vars.yml"
    -e cluster="${cluster}"
    "$PROJECT_DIR/playbooks/${playbook}.yml"
  )

  # Run through each cluster - mgmt, suse-ai, suse-observability with own ini files
  if [ -e "${PROJECT_DIR}/inventories/${cluster}_inventory.ini" ]; then
    ${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"
  fi

done

### DEPLOY SUSE Observability
playbook="deploy_suse_observability" # playbook that deploys suse observability
cluster_inv_name='mgmt_inventory.ini'
if [ -e "${PROJECT_DIR}/inventories/suse-observability_inventory.ini" ]; then
  cluster_inv_name='suse-observability_inventory.ini'
fi


playbook_args=(
  "${base_playbook_args[@]}"
  -i "${PROJECT_DIR}/inventories/${inv_name}_inventory.yml"
  -i "${PROJECT_DIR}/inventories/${cluster_inv_name}"
  -e "@${PROJECT_DIR}/extra_vars.yml"
  "$PROJECT_DIR/playbooks/${playbook}.yml"
)

${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"

### Deploy SUSE AI
playbook="deploy_suse_ai" # playbook that deploys suse ai
cluster_inv_name='mgmt_inventory.ini'
if [ -e "${PROJECT_DIR}/inventories/suse-ai_inventory.ini" ]; then
  cluster_inv_name='suse-ai_inventory.ini'
fi

playbook_args=(
  "${base_playbook_args[@]}"
  -i "${PROJECT_DIR}/inventories/${inv_name}_inventory.yml"
  -i "${PROJECT_DIR}/inventories/${cluster_inv_name}"
  -e "@${PROJECT_DIR}/extra_vars.yml"
  "$PROJECT_DIR/playbooks/${playbook}.yml"
)

${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"

### Display access info
playbook="display" # playbook that displays access info

playbook_args=(
  "${base_playbook_args[@]}"
  -i "${PROJECT_DIR}/inventories/${inv_name}_inventory.yml"
  -e "@${PROJECT_DIR}/extra_vars.yml"
  "$PROJECT_DIR/playbooks/${playbook}.yml"
)

${DEBUG:+echo} ansible-playbook "${playbook_args[@]}"
