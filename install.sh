#!/bin/bash
# Installs or upgrades every widget in this project. The in-widget updater
# (claude/contents/code/apply_update.sh) runs this same script from the new
# release, so installing and upgrading always do the same thing.
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WIDGETS=(claude antigravity)
ICON_DIR="$HOME/.local/share/icons/hicolor"

# Check dependencies
python3 -c "import requests" 2>/dev/null || {
    echo "ERROR: Python 'requests' module is required. Install with:"
    echo "  python3 -m pip install requests"
    exit 1
}

# Print a value from a widget's metadata.json by dotted key, e.g. "KPlugin.Id"; empty if missing
metadata() {
    python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    value = json.load(f)
for key in sys.argv[2].split("."):
    value = value.get(key, "") if isinstance(value, dict) else ""
print(value)
' "$REPO_DIR/$1/metadata.json" "$2"
}

INSTALLED=$(kpackagetool6 --type Plasma/Applet --list 2>/dev/null || true)

for widget in "${WIDGETS[@]}"; do
    id=$(metadata "$widget" KPlugin.Id)
    name=$(metadata "$widget" KPlugin.Name)

    if grep -qx "$id" <<< "$INSTALLED"; then
        echo "Upgrading $name..."
        kpackagetool6 --type Plasma/Applet --upgrade "$REPO_DIR/$widget"
    else
        echo "Installing $name..."
        kpackagetool6 --type Plasma/Applet --install "$REPO_DIR/$widget"
    fi

    # A widget that ships its own icon (X-Tracker-IconFile) gets it installed into the
    # user icon theme under its KPlugin.Icon name so the widget explorer can find it
    icon_file=$(metadata "$widget" X-Tracker-IconFile)
    if [ -n "$icon_file" ]; then
        mkdir -p "$ICON_DIR/256x256/apps"
        cp "$REPO_DIR/$widget/$icon_file" "$ICON_DIR/256x256/apps/$(metadata "$widget" KPlugin.Icon).png"
    fi
done

gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true

echo "Done. Restart plasmashell or log out/in to apply changes."
echo "  To restart manually: plasmashell --replace &disown"
echo "Add the widgets via: right-click panel → Add Widgets → search 'Usage Tracker'"
