#!/bin/bash
# Removes the whole app: every tracker's widget, the app's data folder, and its
# icons. Needs nothing else from the repo, so it also works piped from curl.
set -e

# Every tracker's widget ID starts with this
APP_NAMESPACE="com.github.huskydevclub.kde-ai-usage-trackers"
ICON_DIR="$HOME/.local/share/icons/hicolor"

INSTALLED=$(kpackagetool6 --type Plasma/Applet --list 2>/dev/null || true)
REMOVED=false

while read -r id; do
    case "$id" in
        # The app's trackers, and the separate widgets they were before becoming one app
        "$APP_NAMESPACE".* | com.github.huskydevclub.claude-usage-kde-tracker | com.github.huskydevclub.antigravity-usage-kde-tracker)
            kpackagetool6 --type Plasma/Applet --remove "$id"
            REMOVED=true
            ;;
    esac
done <<< "$INSTALLED"

# Clean up even if the widgets themselves were already gone
rm -rf "$HOME/.local/share/kde-ai-usage-trackers" \
    "$HOME/.local/share/claude-usage-tracker" \
    "$HOME/.local/share/antigravity-usage-tracker"
rm -f "$ICON_DIR"/256x256/apps/kde-ai-usage-trackers-*.png "$ICON_DIR/256x256/apps/claude.png"
gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true

if [ "$REMOVED" = true ]; then
    echo "AI Usage Tracker uninstalled. Restart plasmashell or log out/in to apply changes."
    echo "  To restart manually: plasmashell --replace &disown"
else
    echo "AI Usage Tracker was not installed. Cleaned up any leftover data."
fi
