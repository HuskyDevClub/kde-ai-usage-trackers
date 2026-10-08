#!/bin/bash
# Usage: release.sh <claude|antigravity> [extra gh release create flags, e.g. --notes "..."]
#
# Tags and publishes a release of one widget. The tag points at a standalone
# commit holding just that widget's folder at its root, so the tag's source
# tarball is an installable plasmoid — the in-widget updater downloads it and
# expects metadata.json at the top level.
set -euo pipefail

WIDGET="${1:-}"
case "$WIDGET" in
    # Claude keeps plain vX.Y tags and the "Latest" flag: installed widgets
    # read /releases/latest and only understand v-prefixed tags
    claude) TAG_PREFIX="v"; LATEST=true ;;
    antigravity) TAG_PREFIX="antigravity-v"; LATEST=false ;;
    *)
        echo "Usage: $0 <claude|antigravity> [gh release create flags]" >&2
        exit 1
        ;;
esac
shift

cd "$(dirname "$0")"

read_metadata() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"][sys.argv[2]])' \
        "$WIDGET/metadata.json" "$1"
}

NAME=$(read_metadata Name)
VERSION=$(read_metadata Version)
TAG="$TAG_PREFIX$VERSION"

if ! git diff --quiet HEAD -- "$WIDGET"; then
    echo "Error: $WIDGET/ has uncommitted changes" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists — bump Version in $WIDGET/metadata.json first" >&2
    exit 1
fi

COMMIT=$(git commit-tree "HEAD:$WIDGET" -m "$NAME $VERSION")
git tag "$TAG" "$COMMIT"
git push origin "refs/tags/$TAG"
gh release create "$TAG" --title "$NAME $VERSION" --latest="$LATEST" "$@"
