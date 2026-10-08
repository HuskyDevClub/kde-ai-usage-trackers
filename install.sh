#!/bin/bash
set -e

WIDGET_ID="com.github.huskydevclub.antigravity-usage-kde-tracker"
WIDGET_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check dependencies
python3 -c "import requests" 2>/dev/null || {
    echo "ERROR: Python 'requests' module is required. Install with:"
    echo "  python3 -m pip install requests"
    exit 1
}

# Check if already installed — upgrade instead
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q "^${WIDGET_ID}$"; then
    echo "Upgrading existing installation..."
    kpackagetool6 --type Plasma/Applet --upgrade "$WIDGET_DIR"
else
    echo "Installing widget..."
    kpackagetool6 --type Plasma/Applet --install "$WIDGET_DIR"
fi

echo "Done. Restart plasmashell or log out/in to apply changes."
echo "  To restart manually: plasmashell --replace &disown"
echo "Add the widget via: right-click panel → Add Widgets → search 'Antigravity'"
