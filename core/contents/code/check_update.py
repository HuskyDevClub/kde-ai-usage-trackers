"""Check GitHub for a newer release of the app, for the widget's update notice."""

import json
import os
import re
import sys
import time
from typing import Any

from tracker_common import (
    APP_DATA_DIR,
    atomic_write_json,
    read_json,
    read_metadata,
    requests,
)

REPO = "HuskyDevClub/kde-ai-usage-trackers"
LATEST_RELEASE_URL = f"https://api.github.com/repos/{REPO}/releases/latest"
RELEASES_PAGE_URL = f"https://github.com/{REPO}/releases/latest"
# One cache for the whole app, so every tracker's widget shares a single daily check
CACHE_FILE = os.path.join(APP_DATA_DIR, "update.json")

# GitHub allows 60 unauthenticated requests per hour per IP — one check a day is plenty
CHECK_INTERVAL_SECONDS = 24 * 60 * 60


def parse_version(version: str) -> tuple[int, ...]:
    """Parse a version string like 'v26.2' or '26.2.1' into a comparable tuple.

    Non-numeric suffixes are dropped, so '26.3-beta' parses as (26, 3).
    """
    parts: list[int] = []
    for part in version.strip().lstrip("vV").split("."):
        digits = re.match(r"\d+", part)
        if not digits:
            break
        parts.append(int(digits.group()))
    return tuple(parts)


def is_newer(latest: str, current: str) -> bool:
    """Return True if the latest version is strictly newer than the current one."""
    latest_parts = parse_version(latest)
    current_parts = parse_version(current)
    if not latest_parts or not current_parts:
        return False

    # Pad the shorter version with zeros so 26.3 > 26.2.1 compares correctly
    length = max(len(latest_parts), len(current_parts))
    latest_padded = latest_parts + (0,) * (length - len(latest_parts))
    current_padded = current_parts + (0,) * (length - len(current_parts))
    return latest_padded > current_padded


def local_version() -> str:
    """The installed app version, from metadata.json."""
    return str(read_metadata().get("KPlugin", {}).get("Version", ""))


def build_result(latest_tag: str, release_url: str, current: str) -> dict[str, Any]:
    """Build the result payload consumed by the QML frontend."""
    latest = latest_tag.lstrip("vV")
    return {
        "currentVersion": current,
        "latestVersion": latest,
        "latestTag": latest_tag,
        "releaseUrl": release_url or RELEASES_PAGE_URL,
        "updateAvailable": bool(latest_tag) and is_newer(latest_tag, current),
        "checkedAt": int(time.time()),
    }


def cached_result(cached: dict[str, Any], current: str) -> dict[str, Any]:
    """The result of the cached check, re-compared against the version installed now."""
    result = build_result(cached["latestTag"], cached.get("releaseUrl", ""), current)
    result["checkedAt"] = cached.get("checkedAt", 0)
    result["cached"] = True
    return result


def check_for_update(force: bool) -> dict[str, Any]:
    """Check GitHub Releases for a newer version, using a cached result when fresh."""
    current = local_version()
    if not current:
        return {"error": "Could not read installed version"}

    cached = read_json(CACHE_FILE)
    cache_age = time.time() - cached.get("checkedAt", 0)
    if not force and cached.get("latestTag") and cache_age < CHECK_INTERVAL_SECONDS:
        return cached_result(cached, current)

    try:
        response = requests.get(
            LATEST_RELEASE_URL,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "kde-ai-usage-trackers",
            },
            timeout=10,
        )

        # No releases published yet — nothing to update to
        if response.status_code == 404:
            return build_result("", "", current)

        # Rate limited — fall back to whatever was cached
        if response.status_code in (403, 429):
            if cached.get("latestTag"):
                return cached_result(cached, current)
            return {"error": "GitHub rate limit reached"}

        if response.status_code != 200:
            return {"error": f"Update check failed: {response.status_code}"}

        data = response.json()
        tag = data.get("tag_name") or ""
        if not tag:
            return build_result("", "", current)

        result = build_result(tag, data.get("html_url", ""), current)
        atomic_write_json(CACHE_FILE, result)
        return result

    # Before RequestException, which requests' own JSONDecodeError also subclasses
    except json.JSONDecodeError:
        return {"error": "Invalid response from GitHub"}
    except requests.exceptions.Timeout:
        return {"error": "Update check timed out"}
    except requests.exceptions.ConnectionError:
        return {"error": "Could not reach GitHub"}
    except requests.exceptions.RequestException as e:
        return {"error": f"Update check failed: {e}"}


def main() -> None:
    print(json.dumps(check_for_update("--force" in sys.argv)))


if __name__ == "__main__":
    main()
