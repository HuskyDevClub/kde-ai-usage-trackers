#!/bin/bash
# Download a tagged release from GitHub and run its install.sh, which upgrades
# the whole app, every tracker included — the same thing a fresh install does.
# Prints a JSON result on stdout so the QML frontend can parse it.
set -uo pipefail

REPO="HuskyDevClub/kde-ai-usage-trackers"
# Every tracker's widget ID starts with this
APP_NAMESPACE="com.github.huskydevclub.kde-ai-usage-trackers"
TAG="${1:-}"

json_string() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

fail() {
    printf '{"success": false, "error": %s}\n' "$(printf '%s' "$1" | json_string)"
    exit 0
}

# Reject anything that isn't a plain tag name — it goes straight into a URL
if [[ ! "$TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "Invalid release tag"
fi

command -v kpackagetool6 &>/dev/null || fail "kpackagetool6 not found"

TMPDIR=$(mktemp -d) || fail "Could not create temp directory"
trap 'rm -rf "$TMPDIR"' EXIT

URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"

if command -v curl &>/dev/null; then
    curl -fsSL "$URL" | tar xz -C "$TMPDIR" --strip-components=1 || fail "Download failed"
elif command -v wget &>/dev/null; then
    wget -qO- "$URL" | tar xz -C "$TMPDIR" --strip-components=1 || fail "Download failed"
else
    fail "curl or wget is required"
fi

# Verify we downloaded this app before running its installer: it must have
# trackers, and every one of them must be in the app's namespace
[ -f "$TMPDIR/install.sh" ] || fail "Downloaded release is missing install.sh"

python3 -c '
import glob, json, sys
root, namespace = sys.argv[1:]
paths = glob.glob(root + "/trackers/*/metadata.json")
try:
    ids = [json.load(open(path))["KPlugin"]["Id"] for path in paths]
except Exception:
    sys.exit(1)
sys.exit(0 if ids and all(i.startswith(namespace + ".") for i in ids) else 1)
' "$TMPDIR" "$APP_NAMESPACE" || fail "Downloaded release is not AI Usage Tracker"

OUTPUT=$(bash "$TMPDIR/install.sh" 2>&1) || fail "$OUTPUT"

printf '{"success": true, "version": %s}\n' "$(printf '%s' "${TAG#v}" | json_string)"
