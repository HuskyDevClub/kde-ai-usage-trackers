import json
import os
import sys
import tempfile
import time
from typing import Any

try:
    import requests
except ImportError:
    print(json.dumps({"error": "Python 'requests' module not installed"}))
    sys.exit(0)

REPO = "HuskyDevClub/claude-usage-kde-tracker"
LATEST_RELEASE_URL = f"https://api.github.com/repos/{REPO}/releases/latest"
RELEASES_PAGE_URL = f"https://github.com/{REPO}/releases/latest"
METADATA_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "metadata.json"
)
CACHE_DIR = os.path.join(
    os.path.expanduser("~"), ".local", "share", "claude-usage-tracker"
)
CACHE_FILE = os.path.join(CACHE_DIR, "update.json")

# GitHub allows 60 unauthenticated requests per hour per IP — one check a day is plenty
CHECK_INTERVAL_SECONDS = 24 * 60 * 60


def _atomic_write_json(filepath: str, data: Any) -> bool:
    """Write JSON to a file atomically using write-to-temp-then-rename."""
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(filepath), suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, filepath)
        return True
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False


def parse_version(version: str) -> tuple[int, ...]:
    """Parse a version string like 'v26.2' or '26.2.1' into a comparable tuple.

    Non-numeric suffixes are dropped, so '26.3-beta' parses as (26, 3).
    """
    cleaned = version.strip().lstrip("vV")
    parts: list[int] = []
    for part in cleaned.split("."):
        digits = ""
        for char in part:
            if not char.isdigit():
                break
            digits += char
        if not digits:
            break
        parts.append(int(digits))
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
    """Read the installed widget version from metadata.json."""
    try:
        with open(METADATA_PATH, "r") as f:
            metadata = json.load(f)
        return metadata.get("KPlugin", {}).get("Version", "")
    except (json.JSONDecodeError, OSError):
        return ""


def read_cache() -> dict[str, Any]:
    """Read the cached update check result, or an empty dict if unavailable."""
    try:
        with open(CACHE_FILE, "r") as f:
            cached = json.load(f)
        return cached if isinstance(cached, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


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


def check_for_update(force: bool) -> dict[str, Any]:
    """Check GitHub Releases for a newer version, using a cached result when fresh."""
    current = local_version()
    if not current:
        return {"error": "Could not read installed version"}

    cached = read_cache()
    cache_age = time.time() - cached.get("checkedAt", 0)

    # Serve the cached result, but re-compare against the version installed right now
    if not force and cached.get("latestTag") and cache_age < CHECK_INTERVAL_SECONDS:
        result = build_result(
            cached["latestTag"], cached.get("releaseUrl", ""), current
        )
        result["checkedAt"] = cached.get("checkedAt", 0)
        result["cached"] = True
        return result

    try:
        response = requests.get(
            LATEST_RELEASE_URL,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "claude-usage-kde-tracker",
            },
            timeout=10,
        )

        # No releases published yet — nothing to update to
        if response.status_code == 404:
            return build_result("", "", current)

        # Rate limited — fall back to whatever was cached
        if response.status_code in (403, 429):
            if cached.get("latestTag"):
                result = build_result(
                    cached["latestTag"], cached.get("releaseUrl", ""), current
                )
                result["checkedAt"] = cached.get("checkedAt", 0)
                result["cached"] = True
                return result
            return {"error": "GitHub rate limit reached"}

        if response.status_code != 200:
            return {"error": f"Update check failed: {response.status_code}"}

        data = response.json()
        tag = data.get("tag_name") or ""
        if not tag:
            return build_result("", "", current)

        result = build_result(tag, data.get("html_url", ""), current)
        os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
        _atomic_write_json(CACHE_FILE, result)
        return result

    except requests.exceptions.Timeout:
        return {"error": "Update check timed out"}
    except requests.exceptions.ConnectionError:
        return {"error": "Could not reach GitHub"}
    except requests.exceptions.RequestException as e:
        return {"error": f"Update check failed: {e}"}
    except json.JSONDecodeError:
        return {"error": "Invalid response from GitHub"}


def main() -> None:
    print(json.dumps(check_for_update("--force" in sys.argv)))


if __name__ == "__main__":
    main()
