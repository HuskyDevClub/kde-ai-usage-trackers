#!/bin/bash
# Usage: build.sh <output dir>
#
# Builds the Plasma applet package for every tracker into <output dir>/<tracker>/.
# A package is core/ with trackers/<tracker>/ laid on top, so a tracker file
# replaces the core file at the same path. The two metadata.json files are
# merged instead: app-wide fields come from core/, the tracker's own fields
# (ID, description, icon, X-Tracker-*) from the tracker.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?Usage: $0 <output dir>}"

for tracker_dir in "$REPO_DIR"/trackers/*/; do
    package="$OUT/$(basename "$tracker_dir")"
    rm -rf "$package"
    mkdir -p "$package"

    cp -r "$REPO_DIR/core/." "$tracker_dir." "$package/"
    cp "$REPO_DIR/LICENSE" "$package/"

    python3 - "$REPO_DIR/core/metadata.json" "$tracker_dir/metadata.json" "$package/metadata.json" <<'EOF'
import json
import sys

core_path, tracker_path, out_path = sys.argv[1:]
with open(core_path) as f:
    metadata = json.load(f)
with open(tracker_path) as f:
    tracker = json.load(f)

metadata["KPlugin"].update(tracker.pop("KPlugin", {}))
metadata.update(tracker)

with open(out_path, "w") as f:
    json.dump(metadata, f, indent=4, ensure_ascii=False)
    f.write("\n")
EOF
done
