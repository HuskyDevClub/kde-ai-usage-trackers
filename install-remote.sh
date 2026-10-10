#!/bin/bash
# Usage: curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash
#
# Downloads the app and installs (or upgrades) it, every tracker included. Any
# argument is ignored, so older instructions like `bash -s antigravity` still work.
set -e

REPO="HuskyDevClub/kde-ai-usage-trackers"
BRANCH="main"
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

echo "Downloading AI Usage Tracker..."

if command -v curl &>/dev/null; then
    curl -fsSL "$URL" | tar xz -C "$DOWNLOAD_DIR" --strip-components=1
elif command -v wget &>/dev/null; then
    wget -qO- "$URL" | tar xz -C "$DOWNLOAD_DIR" --strip-components=1
else
    echo "Error: curl or wget is required" >&2
    exit 1
fi

bash "$DOWNLOAD_DIR/install.sh"
