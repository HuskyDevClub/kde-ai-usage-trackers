#!/bin/bash
set -e

WIDGET_ID="com.github.huskydevclub.antigravity-usage-kde-tracker"

echo "Uninstalling widget..."
kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" 2>/dev/null || true

# Remove cache directory
rm -rf "$HOME/.local/share/antigravity-usage-tracker"

echo "Done. Restart plasmashell or log out/in to apply changes."
echo "  To restart manually: plasmashell --replace &disown"
