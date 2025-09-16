#!/bin/bash
# A script to download all RPMs from a direct repository URL using command-line arguments.

# --- Default Configuration ---
# These values will be used if not overridden by command-line switches.
REPO_URL=""
DOWNLOAD_PATH="/var/www/html/repos"
LATEST_ONLY=false

# --- Usage Function ---
# Displays help information.
usage() {
  echo "Downloads all RPMs from one or more repository URLs."
  echo ""
  echo "Usage: $0 [-p <download_path>] [-l] <url1> [url2] ..."
  echo "  -p  The base path where repository subdirectories will be created."
  echo "      (Default: '$DOWNLOAD_PATH')"
  echo "  -l  Download the latest packages only."
  echo "  -h  Display this help message."
  exit 1
}

# --- Parse Command-Line Options ---
while getopts ":p:lh" opt; do
  case ${opt} in
    p ) DOWNLOAD_PATH=$OPTARG ;;
    l ) LATEST_ONLY=true ;;
    h ) usage ;;
    \? ) echo "Invalid option: -$OPTARG" >&2; usage ;;
    : ) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
# Remove parsed options from the argument list
shift $((OPTIND -1))

# --- Validate Arguments ---
if [ "$#" -eq 0 ]; then
  echo "Error: At least one repository URL must be provided." >&2
  usage
fi

# --- Main Execution ---

# 1. Check for prerequisites
if ! command -v reposync &> /dev/null; then
    echo "Error: 'reposync' command not found."
    echo "Please install it first (e.g., 'sudo zypper install yum-utils')."
    exit 1
fi

if ! command -v createrepo_c &> /dev/null; then
    echo "Error: 'createrepo_c' command not found."
    echo "Please install it first (e.g., 'sudo zypper install createrepo_c')."
    exit 1
fi

# 2. Loop through all provided URLs
for REPO_URL in "$@"; do
  echo "-----------------------------------------------------"
  echo "Processing URL: $REPO_URL"

  # 2a. Derive a unique, filesystem-safe name from the URL
  # Example: https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/
  # Becomes: developer.download.nvidia.com-compute-cuda/repos-sles15-x86_64
  REPO_NAME=$(echo "$REPO_URL" | sed -e 's|^https\?://||' -e 's|/$||' -e 's|/|-|g')
  
  # 2b. Set up paths and create the directory
  FULL_DEST_PATH="$DOWNLOAD_PATH/$REPO_NAME"
  echo "Destination: $FULL_DEST_PATH"
  mkdir -p "$FULL_DEST_PATH"

  # 2c. Run the reposync command for the current URL
  if [ "$LATEST_ONLY" = true ]; then
    reposync --repofrompath="$REPO_NAME,$REPO_URL" --repoid="$REPO_NAME" --download-path="$DOWNLOAD_PATH" --newest-only
  else
    reposync --repofrompath="$REPO_NAME,$REPO_URL" --repoid="$REPO_NAME" --download-path="$DOWNLOAD_PATH"
  fi

  # 2d. Completion message for the current repository
  echo "Download complete for $REPO_NAME."
done

# 3. Create the repository metadata
echo "Creating repository metadata in '$FULL_DEST_PATH'..."
createrepo_c "$FULL_DEST_PATH"

if [ $? -ne 0 ]; then
    echo "Error creating repository metadata. Aborting."
    exit 1
fi
echo "Repository metadata created successfully."
echo "---"

echo "-----------------------------------------------------"
echo "All steps completed successfully!"
echo "A local repository has been created in '$FULL_DEST_PATH'."
echo ""
echo "You can now add it to zypper manually with a command like:"
echo "sudo zypper addrepo --no-gpgcheck file://$FULL_DEST_PATH my-custom-repo"
echo "-----------------------------------------------------"

exit 0