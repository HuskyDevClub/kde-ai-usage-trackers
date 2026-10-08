#!/bin/bash
# Usage: release.sh [extra gh release create flags, e.g. --notes "..."]
#
# Tags and publishes a release of the app as v<Version>, where Version is the one
# in core/metadata.json — the app's only version number. Installed widgets update
# by downloading the tag's source tarball and running its install.sh.
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(python3 -c 'import json; print(json.load(open("core/metadata.json"))["KPlugin"]["Version"])')
TAG="v$VERSION"

if ! git diff --quiet HEAD; then
    echo "Error: there are uncommitted changes" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists — bump Version in core/metadata.json first" >&2
    exit 1
fi

# Claude widgets from v26.3 update by installing the tarball root as their own
# package, and only accept one with their old widget ID. So the tagged tree also
# carries the Claude tracker's package, built from this commit, at its root under
# that old ID. The next update then runs install.sh, which moves it to the app.
# Drop this once v26.3 installs have had time to update.
BRIDGE=$(mktemp -d)
trap 'rm -rf "$BRIDGE"' EXIT
mkdir "$BRIDGE/src"
git archive HEAD | tar x -C "$BRIDGE/src"
bash "$BRIDGE/src/build.sh" "$BRIDGE/packages"
PACKAGE="$BRIDGE/packages/claude"
python3 - "$PACKAGE/metadata.json" <<'EOF'
import json
import sys

with open(sys.argv[1]) as f:
    metadata = json.load(f)
metadata["KPlugin"]["Id"] = "com.github.huskydevclub.claude-usage-kde-tracker"
with open(sys.argv[1], "w") as f:
    json.dump(metadata, f, indent=4, ensure_ascii=False)
EOF
BRIDGE_TREE=$(
    export GIT_INDEX_FILE="$BRIDGE/index"
    git --work-tree="$PACKAGE" add -f -- "$PACKAGE/metadata.json" "$PACKAGE/contents"
    git write-tree
)
TREE=$( { git ls-tree HEAD; git ls-tree "$BRIDGE_TREE"; } | git mktree )

COMMIT=$(git commit-tree "$TREE" -p HEAD -m "AI Usage Tracker $VERSION")
git tag "$TAG" "$COMMIT"
git push origin "refs/tags/$TAG"
gh release create "$TAG" --title "AI Usage Tracker $VERSION" --latest "$@"
