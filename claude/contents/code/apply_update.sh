#!/bin/bash
# Download a tagged release from GitHub and install it over the current version.
# Prints a JSON result on stdout so the QML frontend can parse it.
set -uo pipefail

REPO="HuskyDevClub/claude-usage-kde-tracker"
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

# Verify we downloaded the widget we think we did before handing it to kpackagetool
[ -f "$TMPDIR/metadata.json" ] || fail "Downloaded release is missing metadata.json"

DOWNLOADED_ID=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("KPlugin", {}).get("Id", ""))
except Exception:
    print("")
' "$TMPDIR/metadata.json")

[ "$DOWNLOADED_ID" = "$WIDGET_ID" ] || fail "Downloaded release has an unexpected widget ID"

OUTPUT=$(kpackagetool6 --type Plasma/Applet --upgrade "$TMPDIR" 2>&1) || fail "$OUTPUT"

# Refresh the icon in the user icon theme, matching install.sh
if [ -f "$TMPDIR/screenshots/preview.png" ]; then
    ICON_DIR="$HOME/.local/share/icons/hicolor"
    mkdir -p "$ICON_DIR/256x256/apps" \
        && cp "$TMPDIR/screenshots/preview.png" "$ICON_DIR/256x256/apps/claude.png"
    gtk-update-icon-cache "$ICON_DIR" &>/dev/null || true
fi

printf '{"success": true, "version": %s}\n' "$(printf '%s' "${TAG#v}" | json_string)"
