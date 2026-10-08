#!/bin/bash
# Removes every widget in this project, along with the cached data and icon
# they leave in your home folder. Needs nothing else from the repo, so it also
# works piped from curl.
set -e

WIDGET_IDS=(
    com.github.huskydevclub.claude-usage-kde-tracker
    com.github.huskydevclub.antigravity-usage-kde-tracker
)
CACHE_DIRS=(kde-ai-usage-trackers claude-usage-tracker antigravity-usage-tracker)
ICON_DIR="$HOME/.local/share/icons/hicolor"

INSTALLED=$(kpackagetool6 --type Plasma/Applet --list 2>/dev/null || true)
REMOVED=false

for id in "${WIDGET_IDS[@]}"; do
    if grep -qx "$id" <<< "$INSTALLED"; then
        kpackagetool6 --type Plasma/Applet --remove "$id"
        REMOVED=true
    fi
done

# Clean up even if the widgets themselves were already gone
for dir in "${CACHE_DIRS[@]}"; do
    rm -rf "$HOME/.local/share/$dir"
done
rm -f "$ICON_DIR/256x256/apps/claude.png"
gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true

if [ "$REMOVED" = true ]; then
    echo "Widgets uninstalled. Restart plasmashell or log out/in to apply changes."
    echo "  To restart manually: plasmashell --replace &disown"
else
    echo "No widgets from this project were installed. Cleaned up any leftover data."
fi
