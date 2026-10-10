#!/bin/bash
# Installs or upgrades the app: one Plasma widget per tracker in trackers/, each
# built by build.sh. The in-widget updater (core/contents/code/apply_update.sh)
# runs this same script from the new release, so installing and upgrading always
# do the same thing.
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR="$HOME/.local/share/icons/hicolor"

# Before the trackers became one app they were separate widgets with their own
# IDs, data folders, and icon. Remove them so Add Widgets doesn't list both
# generations; their panel widgets have to be re-added once.
LEGACY_IDS=(
    com.github.huskydevclub.claude-usage-kde-tracker
    com.github.huskydevclub.antigravity-usage-kde-tracker
)
LEGACY_DATA_DIRS=(claude-usage-tracker antigravity-usage-tracker)
LEGACY_ICON="$ICON_DIR/256x256/apps/claude.png"

# Check dependencies
python3 -c "import requests" 2>/dev/null || {
    echo "ERROR: Python 'requests' module is required. Install with:"
    echo "  python3 -m pip install requests"
    exit 1
}

# Print a value from a package's metadata.json by dotted key, e.g. "KPlugin.Id"; empty if missing
metadata() {
    python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    value = json.load(f)
for key in sys.argv[2].split("."):
    value = value.get(key, "") if isinstance(value, dict) else ""
print(value)
' "$1/metadata.json" "$2"
}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
bash "$REPO_DIR/build.sh" "$STAGE"

INSTALLED=$(kpackagetool6 --type Plasma/Applet --list 2>/dev/null || true)

REPLACED_LEGACY=false
for id in "${LEGACY_IDS[@]}"; do
    if grep -qx "$id" <<< "$INSTALLED"; then
        kpackagetool6 --type Plasma/Applet --remove "$id"
        REPLACED_LEGACY=true
    fi
done

# The old Claude widget kept the daily chart's history as {date: {"session": peak, ...}}.
# Carry its session peaks into the Claude tracker's history.json ({date: peak}) before
# its data folder goes, so upgrading doesn't wipe the chart.
LEGACY_HISTORY="$HOME/.local/share/claude-usage-tracker/history.json"
if [ -f "$LEGACY_HISTORY" ]; then
    python3 - "$REPO_DIR/core/contents/code" "$LEGACY_HISTORY" <<'EOF' || echo "Warning: couldn't carry over the Claude usage history"
import os
import sys

sys.path.insert(0, sys.argv[1])
from tracker_common import APP_DATA_DIR, atomic_write_json, num, read_json

history_file = os.path.join(APP_DATA_DIR, "claude", "history.json")
history = {date: num(peak) for date, peak in read_json(history_file).items()}
for date, entry in read_json(sys.argv[2]).items():
    if isinstance(entry, dict):
        history[date] = max(num(entry.get("session")), history.get(date, 0.0))
if not atomic_write_json(history_file, history):
    sys.exit(1)
EOF
fi
for dir in "${LEGACY_DATA_DIRS[@]}"; do
    rm -rf "$HOME/.local/share/$dir"
done
rm -f "$LEGACY_ICON"

for package in "$STAGE"/*/; do
    package="${package%/}"
    id=$(metadata "$package" KPlugin.Id)
    name="$(metadata "$package" KPlugin.Name) — $(metadata "$package" X-Tracker-Name)"

    if grep -qx "$id" <<< "$INSTALLED"; then
        echo "Upgrading $name..."
        kpackagetool6 --type Plasma/Applet --upgrade "$package"
    else
        echo "Installing $name..."
        kpackagetool6 --type Plasma/Applet --install "$package"
    fi

    # A tracker that ships its own icon (X-Tracker-IconFile) gets it installed into the
    # user icon theme under its KPlugin.Icon name so the widget explorer can find it
    icon_file=$(metadata "$package" X-Tracker-IconFile)
    if [ -n "$icon_file" ]; then
        mkdir -p "$ICON_DIR/256x256/apps"
        cp "$package/$icon_file" "$ICON_DIR/256x256/apps/$(metadata "$package" KPlugin.Icon).png"
    fi
done

gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true

echo "Done. Restart plasmashell or log out/in to apply changes."
echo "  To restart manually: plasmashell --replace &disown"
echo "Add the widgets via: right-click panel → Add Widgets → search 'AI Usage Tracker'"
if [ "$REPLACED_LEGACY" = true ]; then
    echo "The old Claude/Antigravity Usage Tracker widgets were replaced: re-add them from Add Widgets."
fi
