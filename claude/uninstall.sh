#!/bin/bash
set -e

WIDGET_ID="com.github.huskydevclub.claude-usage-kde-tracker"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q "^${WIDGET_ID}$"; then
    kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID"
    rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/claude.png"
    gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    echo "Widget uninstalled."
else
    echo "Widget is not installed."
fi
