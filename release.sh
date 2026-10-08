#!/bin/bash
# Usage: release.sh [extra gh release create flags, e.g. --notes "..."]
#
# Tags and publishes a release of the whole project as v<Version>. Every
# widget's metadata.json must carry the same Version, so bump them together.
# Installed widgets update by downloading the tag's source tarball and running
# its install.sh, which upgrades every widget.
set -euo pipefail

WIDGETS=(claude antigravity)

cd "$(dirname "$0")"

# Shared files are committed copies, so never publish a widget whose copies drifted
./sync-shared.sh --check

read_version() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' \
        "$1/metadata.json"
}

VERSION=$(read_version "${WIDGETS[0]}")
for widget in "${WIDGETS[@]}"; do
    widget_version=$(read_version "$widget")
    if [ "$widget_version" != "$VERSION" ]; then
        echo "Error: $widget/metadata.json is at $widget_version but ${WIDGETS[0]} is at $VERSION — bump them together" >&2
        exit 1
    fi
done
TAG="v$VERSION"

if ! git diff --quiet HEAD; then
    echo "Error: there are uncommitted changes" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists — bump Version in every metadata.json first" >&2
    exit 1
fi

# Claude widgets from v26.3 install the tarball root as the Claude package, so the
# tagged tree also carries claude/metadata.json and claude/contents at its root.
# Newer updaters run install.sh and ignore them. Drop this once v26.3 installs
# have had time to update.
TREE=$(
    {
        git ls-tree HEAD
        git ls-tree HEAD claude/metadata.json claude/contents | sed 's|\tclaude/|\t|'
    } | git mktree
)
COMMIT=$(git commit-tree "$TREE" -p HEAD -m "KDE AI Usage Trackers $VERSION")
git tag "$TAG" "$COMMIT"
git push origin "refs/tags/$TAG"
gh release create "$TAG" --title "KDE AI Usage Trackers $VERSION" --latest "$@"
