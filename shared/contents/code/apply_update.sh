#!/bin/bash
# Shared file: edit shared/contents/code/apply_update.sh, then run `./sync-shared.sh`.
#
# Download a tagged release from GitHub and run its install.sh, which upgrades
# every widget in the project — the same thing a fresh install does.
# Prints a JSON result on stdout so the QML frontend can parse it.
set -uo pipefail

REPO="HuskyDevClub/kde-ai-usage-trackers"
# Any widget's ID would do — this one just confirms the tarball is this project
WIDGET_ID="com.github.huskydevclub.claude-usage-kde-tracker"
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

# Verify we downloaded this project before running its installer
[ -f "$TMPDIR/install.sh" ] || fail "Downloaded release is missing install.sh"

DOWNLOADED_ID=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("KPlugin", {}).get("Id", ""))
except Exception:
    print("")
' "$TMPDIR/claude/metadata.json")

[ "$DOWNLOADED_ID" = "$WIDGET_ID" ] || fail "Downloaded release has an unexpected widget ID"

OUTPUT=$(bash "$TMPDIR/install.sh" 2>&1) || fail "$OUTPUT"

printf '{"success": true, "version": %s}\n' "$(printf '%s' "${TAG#v}" | json_string)"
