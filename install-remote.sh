#!/bin/bash
# Usage: install-remote.sh [claude|antigravity]   (defaults to claude)
set -e

REPO="HuskyDevClub/kde-ai-usage-trackers"
BRANCH="main"
WIDGET="${1:-claude}"

case "$WIDGET" in
    claude) NAME="Claude Usage Tracker" ;;
    antigravity) NAME="Antigravity Usage Tracker" ;;
    *)
        echo "Error: unknown widget '$WIDGET' (choose 'claude' or 'antigravity')" >&2
        exit 1
        ;;
esac

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading $NAME..."

if command -v curl &>/dev/null; then
    curl -sL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMPDIR" --strip-components=1
elif command -v wget &>/dev/null; then
    wget -qO- "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMPDIR" --strip-components=1
else
    echo "Error: curl or wget is required" >&2
    exit 1
fi

cd "$TMPDIR/$WIDGET"
./install.sh
