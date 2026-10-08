#!/bin/bash
# Usage: sync-shared.sh [--check]
#
# Copies everything in shared/, plus the root LICENSE, into each widget folder.
# The copies are committed on purpose: install.sh hands each widget folder to
# kpackagetool6 as-is, and plasmoidviewer previews one straight from the repo,
# so every widget folder has to be a complete plasmoid on its own.
#
# --check changes nothing and exits 1 if any copy differs from its source.
set -euo pipefail

WIDGETS=(claude antigravity)

CHECK=false
case "${1:-}" in
    "") ;;
    --check) CHECK=true ;;
    *)
        echo "Usage: $0 [--check]" >&2
        exit 1
        ;;
esac

cd "$(dirname "$0")"

# Each source file, and the path it lands at inside a widget folder
SOURCES=(LICENSE)
TARGETS=(LICENSE)
while IFS= read -r -d '' path; do
    SOURCES+=("shared/$path")
    TARGETS+=("$path")
done < <(cd shared && find . -type f -not -path '*/__pycache__/*' -printf '%P\0' | sort -z)

same_exec_bit() {
    { [ -x "$1" ] && [ -x "$2" ]; } || { [ ! -x "$1" ] && [ ! -x "$2" ]; }
}

STATUS=0
for widget in "${WIDGETS[@]}"; do
    for i in "${!SOURCES[@]}"; do
        src="${SOURCES[$i]}"
        dest="$widget/${TARGETS[$i]}"
        if [ "$CHECK" = true ]; then
            if ! cmp -s "$src" "$dest" || ! same_exec_bit "$src" "$dest"; then
                echo "$dest differs from $src" >&2
                STATUS=1
            fi
        else
            mkdir -p "$(dirname "$dest")"
            cp --preserve=mode "$src" "$dest"
        fi
    done
done

if [ "$STATUS" -ne 0 ]; then
    echo "Edit the file in shared/ (not the widget copy), then run: ./sync-shared.sh" >&2
fi
exit "$STATUS"
