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
                        "disabled": False,                  # optional: limit reached
                        "description": "",                  # optional: replaces "Limit reached"
                    },
                ],
            },
        ],
        # optional: paid usage beyond the plan, in dollars; a limit of 0 means no cap
        "extra": {"used": 12.5, "limit": 50.0, "utilization": 25.0},
    }

run() adds history, error, notLoggedIn and rateLimited, caches the result, and prints it
as JSON for the widget.
"""

import json
import os
import re
import sys
import tempfile
from collections.abc import Callable
from datetime import date, datetime, timedelta
from typing import Any

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
    "read_json",
    "read_metadata",
    "requests",
    "response_json",
    "run",
]


class TrackerError(Exception):
    """A fetch failure the widget should report, with the message shown to the user.

    not_logged_in shows it as a sign-in reminder rather than an error. rate_limited makes
    run() serve the last cached result instead, if there is one, and the widget back off.
    """

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


def atomic_write_json(filepath: str, data: Any) -> bool:
    """Write JSON to a temp file and rename it into place, so the file is never left
    half-written. Returns whether it succeeded.

    mkstemp() creates the file readable only by the user, as credentials files need.
    """
    tmp_path = None
    try:
        dir_path = os.path.dirname(filepath)
        os.makedirs(dir_path, mode=0o700, exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(dir=dir_path, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, filepath)
        return True
    except OSError:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return False


def read_json(filepath: str) -> dict[str, Any]:
    """The JSON object in a file, or an empty dict if it's missing, unreadable, or not an object."""
    try:
        with open(filepath, "r") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def response_json(response: requests.Response) -> dict[str, Any] | None:
    """The JSON object in a response's body, or None if the body isn't one."""
    try:
        data = response.json()
    # requests' own error, a json.JSONDecodeError only when simplejson isn't installed
    except requests.exceptions.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def read_metadata() -> dict[str, Any]:
    """The installed package's metadata.json, or an empty dict if it can't be read."""
    return read_json(os.path.join(PACKAGE_DIR, "metadata.json"))


def tracker_data_dir() -> str:
    """This tracker's folder inside the app's data folder, named after X-Tracker-Name."""
    name = str(read_metadata().get("X-Tracker-Name", ""))
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "tracker"
    return os.path.join(APP_DATA_DIR, slug)


def record_history(data_dir: str, percent: float) -> list[dict[str, Any]]:
    """Record today's peak usage and return the last HISTORY_DAYS days for the daily chart."""
    history_file = os.path.join(data_dir, "history.json")
    today = datetime.now().astimezone().date()
    # Compared as dates, not timestamps, since a day that starts or ends daylight saving
    # time isn't 24 hours long
    oldest = today - timedelta(days=HISTORY_DAYS - 1)

    history: dict[date, float] = {}
    for key, peak in read_json(history_file).items():
        try:
            day = date.fromisoformat(key)
        except ValueError:
            continue  # Skip corrupted date entries
        if day >= oldest:
            history[day] = num(peak)
    history[today] = max(percent, history.get(today, 0.0))

    atomic_write_json(
        history_file, {day.isoformat(): peak for day, peak in history.items()}
    )

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    return [
        {
            "day": day_names[day.weekday()],
            "date": day.isoformat(),
            "percent": history[day],
        }
        for day in sorted(history)
    ]


def run(fetch: Callable[[], dict[str, Any]]) -> None:
    """Fetch usage, cache it, and print it as JSON for the widget.

    With --cached, print the last cached result instead (nothing if there is none), so the
    widget can show data immediately at startup.
    """
    data_dir = tracker_data_dir()
    cache_file = os.path.join(data_dir, "usage.json")

    if "--cached" in sys.argv:
        cached = read_json(cache_file)
        if cached:
            print(json.dumps(cached))
        return

    result: dict[str, Any] = {"error": None}
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

    # On rate limit, serve the cached result flagged so the widget backs off; with no
    # usable cache, fall through and output the error
    if result.get("rateLimited"):
        cached = read_json(cache_file)
        if cached:
            print(json.dumps({**cached, "rateLimited": True, "error": None}))
            return
    elif not result["error"]:
        if "historyPercent" in result:
            result["history"] = record_history(
                data_dir, num(result.pop("historyPercent"))
            )
        if not atomic_write_json(cache_file, result):
            print("Warning: failed to write cache file", file=sys.stderr)

    print(json.dumps(result))
