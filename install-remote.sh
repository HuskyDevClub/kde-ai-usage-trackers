#!/bin/bash
# Usage: curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash
#
# Downloads the project and installs (or upgrades) all of its widgets. Any
# argument is ignored, so older instructions like `bash -s antigravity` still work.
set -e

REPO="HuskyDevClub/kde-ai-usage-trackers"
BRANCH="main"
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading KDE AI Usage Trackers..."

if command -v curl &>/dev/null; then
    curl -fsSL "$URL" | tar xz -C "$TMPDIR" --strip-components=1
elif command -v wget &>/dev/null; then
    wget -qO- "$URL" | tar xz -C "$TMPDIR" --strip-components=1
else
    echo "Error: curl or wget is required" >&2
    exit 1
fi

bash "$TMPDIR/install.sh"
