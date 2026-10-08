"""Code every tracker shares. A tracker's fetch_usage.py defines fetch() and calls run(fetch).

fetch() returns the tracker's usage in the app's common shape, or raises TrackerError:

    {
        "plan": "Pro",              # badge next to the popup title; "" for none
        "panelPercent": 42.0,       # what the panel icon shows
        "historyPercent": 42.0,     # optional: recorded as today's peak for the daily chart
        "groups": [                 # usage limits, drawn as bars in the popup
            {
                "name": "Gemini Models",    # "" for no heading
                "description": "",          # optional
                "buckets": [
                    {
                        "title": "5-Hour Limit",
                        "used": 42.0,                       # percent of the limit
                        "resetsAt": "2026-01-01T00:00:00Z", # optional
                        "description": "",                  # optional
                        "disabled": False,                  # optional: limit reached
                    },
                ],
            },
        ],
        "extra": {"used": 12.5, "limit": 50.0, "utilization": 25.0},  # optional: paid usage beyond the plan
    }

run() adds lastUpdated, history, error, notLoggedIn and rateLimited, caches the result,
and prints it as JSON for the widget.
"""

import json
import os
import re
import sys
import tempfile
from datetime import datetime
from typing import Any, Callable

try:
    import requests
except ImportError:
    print(
        json.dumps(
            {
                "error": "Python 'requests' module not installed. Run: python3 -m pip install requests"
            }
        )
    )
    sys.exit(0)

# The installed package this script runs from, and the app's data folder in the user's home
PACKAGE_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
APP_DATA_DIR = os.path.join(
    os.path.expanduser("~"), ".local", "share", "kde-ai-usage-trackers"
)

HISTORY_DAYS = 7

__all__ = [
    "APP_DATA_DIR",
    "TrackerError",
    "atomic_write_json",
    "num",
    "read_metadata",
    "requests",
    "run",
]


class TrackerError(Exception):
    """A fetch failure the widget should report, with the message shown to the user."""

    def __init__(
        self, message: str, not_logged_in: bool = False, rate_limited: bool = False
    ):
        super().__init__(message)
        self.not_logged_in = not_logged_in
        self.rate_limited = rate_limited


def num(value: Any, default: float = 0) -> float:
    """Coerce an API value to a number, treating null/non-numeric as the default.

    APIs send null (not a missing key) for unset fields, so dict.get(key, 0) is not enough on its own.
    """
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return float(default)


def atomic_write_json(filepath: str, data: Any, mode: int = 0o600) -> bool:
    """Write JSON to a file atomically using write-to-temp-then-rename.

    Prevents data corruption if the process is interrupted mid-write.

    Returns:
        True on success, False on failure.
    """
    dir_path = os.path.dirname(filepath)
    os.makedirs(dir_path, mode=0o700, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=dir_path, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.chmod(tmp_path, mode)
        os.rename(tmp_path, filepath)
        return True
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False


def read_metadata() -> dict[str, Any]:
    """The installed package's metadata.json, or an empty dict if it can't be read."""
    try:
        with open(os.path.join(PACKAGE_DIR, "metadata.json"), "r") as f:
            metadata = json.load(f)
        return metadata if isinstance(metadata, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def tracker_data_dir() -> str:
    """This tracker's folder inside the app's data folder, named after X-Tracker-Name."""
    name = str(read_metadata().get("X-Tracker-Name", ""))
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "tracker"
    return os.path.join(APP_DATA_DIR, slug)


def record_history(data_dir: str, percent: float) -> list[dict[str, Any]]:
    """Record today's peak usage and return the last HISTORY_DAYS days for the daily chart."""
    history_file = os.path.join(data_dir, "history.json")
    history: dict[str, float] = {}
    try:
        with open(history_file, "r") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            history = {date: num(peak) for date, peak in loaded.items()}
    except (json.JSONDecodeError, OSError):
        pass

    today = datetime.now().strftime("%Y-%m-%d")
    history[today] = max(percent, history.get(today, 0.0))

    # Prune entries older than HISTORY_DAYS
    cutoff = datetime.now().timestamp() - HISTORY_DAYS * 86400
    pruned: dict[str, float] = {}
    for date, peak in history.items():
        try:
            if datetime.strptime(date, "%Y-%m-%d").timestamp() >= cutoff:
                pruned[date] = peak
        except ValueError:
            pass  # Skip corrupted date entries

    atomic_write_json(history_file, pruned)

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    return [
        {
            "day": day_names[datetime.strptime(date, "%Y-%m-%d").weekday()],
            "date": date,
            "percent": pruned[date],
        }
        for date in sorted(pruned)
    ]


def run(fetch: Callable[[], dict[str, Any]]) -> None:
    """Fetch usage, cache it, and print it as JSON for the widget.

    With --cached, print the last cached result instead (nothing if there is none), so the
    widget can show data immediately at startup.
    """
    data_dir = tracker_data_dir()
    cache_file = os.path.join(data_dir, "usage.json")

    if "--cached" in sys.argv:
        try:
            with open(cache_file, "r") as f:
                print(json.dumps(json.load(f)))
        except (json.JSONDecodeError, OSError):
            pass
        return

    result: dict[str, Any] = {
        "lastUpdated": datetime.now().strftime("%H:%M:%S"),
        "error": None,
    }
    try:
        result.update(fetch())
    except TrackerError as e:
        result["error"] = str(e)
        if e.not_logged_in:
            result["notLoggedIn"] = True
        if e.rate_limited:
            result["rateLimited"] = True
    except requests.exceptions.Timeout:
        result["error"] = "Request timeout"
    except requests.exceptions.ConnectionError:
        result["error"] = "Connection error"
    except requests.exceptions.RequestException as e:
        result["error"] = f"Request failed: {e}"

    # On rate limit, serve the cached result flagged so the widget backs off
    if result.get("rateLimited"):
        try:
            with open(cache_file, "r") as f:
                cached = json.load(f)
            cached["rateLimited"] = True
            cached["error"] = None
            print(json.dumps(cached))
            return
        except (json.JSONDecodeError, OSError):
            pass  # No usable cache — output the error result
    elif not result["error"]:
        if "historyPercent" in result:
            result["history"] = record_history(
                data_dir, num(result.pop("historyPercent"))
            )
        if not atomic_write_json(cache_file, result):
            print("Warning: failed to write cache file", file=sys.stderr)

    print(json.dumps(result))
