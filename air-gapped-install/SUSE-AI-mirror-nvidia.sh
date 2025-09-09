#!/bin/bash

# =================================================================================
#  Script to download all .rpm files from a specific web URL.
#
#  This script is ideal for web directories that list their files ("Index of...").
#
#  Usage: ./SUSE-AI-mirror-nvidia.sh <source_url> <target_directory> [--latest]
#
#  Example:
#  ./SUSE-AI-mirror-nvidia.sh https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ /mnt/nvidia-rpms
# =================================================================================

# --- Argument Parsing ---
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <source_url> <target_directory> [--latest]"
    exit 1
fi

# --- Define Variables ---
SOURCE_URL="$1"
TARGET_DIR="$2"
LATEST_ONLY=false

if [ "$3" == "--latest" ]; then
    LATEST_ONLY=true
fi

# --- Dependency Check ---
for cmd in wget createrepo_c sort grep sed; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: Command '$cmd' not found. Please ensure core utilities are installed."
    exit 1
  fi
done

# --- Check if wget is installed ---
if ! command -v wget &> /dev/null; then
    echo "Error: 'wget' command not found. Please install it to use this script."
    exit 1
fi

# --- Check if the target directory exists, create if not ---
if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory '$TARGET_DIR' does not exist. Creating it..."
    mkdir -p "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Could not create directory '$TARGET_DIR'."
        exit 1
    fi
fi

# --- Main Logic: Download the RPMs ---
if [ "$LATEST_ONLY" = true ]; then
    ### --- LATEST-ONLY LOGIC --- ###
    echo "Fetching file list to determine latest packages..."

    ALL_FILES=$(wget -q -O- "$SOURCE_URL" | grep -oE '[a-zA-Z0-9._-]+.rpm' | sort -u)

    if [ -z "$ALL_FILES" ]; then
        echo "Could not retrieve any .rpm files from the URL. Please check the link."
        exit 1
    fi

    # Use an associative array to track the latest file for each package.
    declare -A latest_packages

    echo "Processing files to find the latest versions..."

    # Read the file list, sorted by version, line by line.
    while IFS= read -r filename; do
        # Generate a "base name" key by stripping version info. This is just for grouping.
        basename=$(echo "$filename" | sed -E 's/-[0-9]+.*\.rpm$//')

        # Because the input is version-sorted, the LAST file seen for a given
        # base name will be the one with the highest version. We simply overwrite
        # the array entry for that key on each encounter.
        latest_packages["$basename"]="$filename"
    done < <(echo "$ALL_FILES" | sort -V)

    # The values of the array are now the list of latest files.
    FILES_TO_DOWNLOAD=("${latest_packages[@]}")

    echo "Found ${#FILES_TO_DOWNLOAD[@]} unique packages to download."
    echo "Starting download..."
    for file in "${FILES_TO_DOWNLOAD[@]}"; do
        wget --no-clobber --quiet --show-progress -P "$TARGET_DIR" "${SOURCE_URL}${file}"
    done
else
    ### --- STANDARD LOGIC (DOWNLOAD ALL) --- ###
    echo "Downloading all RPM files from '$SOURCE_URL'..."
    wget \
        --recursive \
        --no-parent \
        --no-clobber \
        --no-directories \
        --accept "*.rpm" \
        --directory-prefix="$TARGET_DIR" \
        "$SOURCE_URL"
fi

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Error during RPM download. Aborting."
    exit 1
fi
echo "RPM Download successful."
echo "---"

echo "Creating repository metadata in '$TARGET_DIR'..."
createrepo_c "$TARGET_DIR"

if [ $? -ne 0 ]; then
    echo "Error creating repository metadata. Aborting."
    exit 1
fi
echo "Repository metadata created successfully."
echo "---"

echo "-----------------------------------------------------"
echo "All steps completed successfully!"
echo "A local repository has been created in '$TARGET_DIR'."
echo ""
echo "You can now add it to zypper manually with a command like:"
echo "sudo zypper addrepo --no-gpgcheck file://$TARGET_DIR my-custom-repo"
echo "-----------------------------------------------------"

exit 0