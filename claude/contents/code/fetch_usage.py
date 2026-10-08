import json
import os
import sys
import tempfile
from datetime import datetime
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

OAUTH_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CREDENTIALS_PATH = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
CACHE_DIR = os.path.join(
    os.path.expanduser("~"), ".local", "share", "claude-usage-tracker"
)


def _num(value: Any, default: float = 0) -> float:
    """Coerce an API value to a number, treating null/non-numeric as the default.

    The API sends null (not a missing key) for unset fields such as
    monthly_limit, so dict.get(key, 0) is not enough on its own.
    """
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    return default


def _atomic_write_json(filepath: str, data: Any, mode: int = 0o600) -> bool:
    """Write JSON to a file atomically using write-to-temp-then-rename.

    Prevents data corruption if the process is interrupted mid-write.

    Returns:
        True on success, False on failure.
    """
    dir_path = os.path.dirname(filepath)
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


def _is_token_expired(oauth_data: dict) -> bool:
    """Check if the access token is expired."""
    expires_at = oauth_data.get("expiresAt")
    if not expires_at or not isinstance(expires_at, (int, float)):
        return True
    if expires_at > 1e12:  # milliseconds
        expires_at = expires_at / 1000
    return datetime.fromtimestamp(expires_at) < datetime.now()


def _refresh_token(credentials_data: dict) -> tuple[str | None, str | None]:
    """Refresh the OAuth access token using the refresh token.

    Updates the credentials file on success.

    Returns:
        Tuple of (access_token, subscription_type) or (None, None) on failure.
    """
    oauth_data = credentials_data.get("claudeAiOauth", {})
    refresh_token = oauth_data.get("refreshToken")
    if not refresh_token:
        return None, None

    try:
        response = requests.post(
            OAUTH_TOKEN_URL,
            json={
                "grant_type": "refresh_token",
                "client_id": OAUTH_CLIENT_ID,
                "refresh_token": refresh_token,
            },
            headers={"Content-Type": "application/json"},
            timeout=15,
        )

        if response.status_code != 200:
            return None, None

        token_data = response.json()
        new_access_token = token_data.get("access_token")
        if not new_access_token:
            return None, None

        # Update credentials in memory and on disk
        oauth_data["accessToken"] = new_access_token
        if token_data.get("refresh_token"):
            oauth_data["refreshToken"] = token_data["refresh_token"]
        if token_data.get("expires_in"):
            oauth_data["expiresAt"] = int(
                (datetime.now().timestamp() + token_data["expires_in"]) * 1000
            )

        credentials_data["claudeAiOauth"] = oauth_data
        _atomic_write_json(CREDENTIALS_PATH, credentials_data)

        subscription_type = oauth_data.get("subscriptionType", "unknown")
        return new_access_token, subscription_type

    except (requests.exceptions.RequestException, json.JSONDecodeError):
        return None, None


def load_credentials_from_file() -> tuple[str | None, str | None]:
    """Load OAuth credentials from the Claude Code CLI credentials file.

    Automatically refreshes expired tokens using the refresh token.

    Returns:
        Tuple of (access_token, subscription_type) or (None, None) on failure.
    """
    if not os.path.exists(CREDENTIALS_PATH):
        return None, None

    try:
        with open(CREDENTIALS_PATH, "r") as f:
            data = json.load(f)

        oauth_data = data.get("claudeAiOauth", {})
        token = oauth_data.get("accessToken")
        subscription_type = oauth_data.get("subscriptionType", "unknown")

        if not token:
            return None, None

        # If token is expired, try to refresh it
        if _is_token_expired(oauth_data):
            return _refresh_token(data)

        return token, subscription_type
    except (json.JSONDecodeError, IOError, OSError):
        return None, None


def create_empty_result() -> dict[str, Any]:
    """Create an empty result structure."""
    return {
        "session": {"used": 0, "limit": 100},
        "weekly": {"used": 0, "limit": 100},
        "sonnet": {"used": 0, "limit": 100},
        "opus": {"used": 0, "limit": 100},
        "subscriptionType": "unknown",
        "lastUpdated": datetime.now().strftime("%H:%M:%S"),
        "error": None,
    }


def parse_usage_item(data: dict, api_key: str) -> dict[str, Any]:
    """Parse a single usage item from the API response."""
    item = data.get(api_key)
    if not item or not isinstance(item, dict):
        return {"used": 0, "limit": 100}

    result: dict[str, Any] = {
        "used": _num(item.get("utilization")),
        "limit": 100,
    }
    if item.get("resets_at"):
        result["resetsAt"] = item["resets_at"]
    return result


def _make_usage_request(token: str) -> requests.Response:
    """Make a GET request to the usage API."""
    headers = {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
    }
    return requests.get(OAUTH_USAGE_URL, headers=headers, timeout=15)


def fetch_usage() -> dict[str, Any]:
    """Fetch current usage data from Claude OAuth API."""
    result = create_empty_result()

    # Load credentials
    token, subscription_type = load_credentials_from_file()
    if not token:
        result["error"] = "No credentials found. Run: claude login"
        return result

    result["subscriptionType"] = subscription_type or "unknown"

    try:
        response = _make_usage_request(token)

        # On 401, try refreshing the token once
        if response.status_code == 401:
            try:
                with open(CREDENTIALS_PATH, "r") as f:
                    cred_data = json.load(f)
                new_token, new_sub = _refresh_token(cred_data)
                if new_token:
                    token = new_token
                    result["subscriptionType"] = new_sub or "unknown"
                    response = _make_usage_request(token)
            except (json.JSONDecodeError, IOError, OSError):
                pass

        if response.status_code == 401:
            result["error"] = "Session expired. Run: claude login"
            return result
        if response.status_code == 403:
            result["error"] = "Access denied. Check your subscription."
            return result
        if response.status_code == 429:
            result["rateLimited"] = True
            result["error"] = "Rate limited — using cached data"
            return result
        if response.status_code != 200:
            result["error"] = f"API error: {response.status_code}"
            return result

        data = response.json()

        result["session"] = parse_usage_item(data, "five_hour")
        result["weekly"] = parse_usage_item(data, "seven_day")
        result["sonnet"] = parse_usage_item(data, "seven_day_sonnet")
        result["opus"] = parse_usage_item(data, "seven_day_opus")

        # Extra usage (paid overage) — API returns credits in cents
        extra = data.get("extra_usage")
        if extra and isinstance(extra, dict) and extra.get("is_enabled"):
            result["extra"] = {
                "used": _num(extra.get("used_credits")) / 100,
                "limit": _num(extra.get("monthly_limit")) / 100,
                "utilization": _num(extra.get("utilization")),
            }

    except requests.exceptions.Timeout:
        result["error"] = "Request timeout"
    except requests.exceptions.ConnectionError:
        result["error"] = "Connection error"
    except requests.exceptions.RequestException as e:
        result["error"] = f"Request failed: {e}"
    except json.JSONDecodeError:
        result["error"] = "Invalid API response"

    return result


def update_daily_history(usage: dict[str, Any]) -> list[dict[str, Any]]:
    """Update daily usage history and return the last 7 days as an array.

    Each entry records the peak session usage observed for that date.
    """
    history_file = os.path.join(CACHE_DIR, "history.json")
    history: dict[str, dict[str, Any]] = {}

    try:
        if os.path.exists(history_file):
            with open(history_file, "r") as f:
                history = json.load(f)
    except (json.JSONDecodeError, OSError):
        history = {}

    today = datetime.now().strftime("%Y-%m-%d")
    session_pct = usage.get("session", {}).get("used", 0)
    weekly_pct = usage.get("weekly", {}).get("used", 0)

    # Keep the peak session usage for each day
    existing = history.get(today, {})
    prev_session = existing.get("session", 0)
    history[today] = {
        "session": max(session_pct, prev_session),
        "weekly": weekly_pct,
    }

    # Prune entries older than 7 days
    cutoff = datetime.now().timestamp() - 7 * 86400
    pruned: dict[str, dict[str, Any]] = {}
    for date, data in history.items():
        try:
            if datetime.strptime(date, "%Y-%m-%d").timestamp() >= cutoff:
                pruned[date] = data
        except ValueError:
            pass  # Skip corrupted date entries
    history = pruned

    _atomic_write_json(history_file, history)

    # Convert to sorted array for QML consumption
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    result = []
    for date_str in sorted(history.keys()):
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        day_name = day_names[dt.weekday()]
        entry = history[date_str]
        result.append(
            {
                "day": day_name,
                "date": date_str,
                "percent": entry.get("session", 0),
            }
        )

    return result


def main() -> None:
    usage = fetch_usage()

    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
    cache_file = os.path.join(CACHE_DIR, "usage.json")

    # On rate limit, serve cached data with rateLimited flag
    if usage.get("rateLimited"):
        try:
            if os.path.exists(cache_file):
                with open(cache_file, "r") as f:
                    cached = json.load(f)
                cached["rateLimited"] = True
                cached["error"] = None
                print(json.dumps(cached))
                return
        except (json.JSONDecodeError, OSError):
            pass
        # No usable cache — fall through and output the error result
        print(json.dumps(usage))
        return

    # Update daily history (only if no error)
    if not usage.get("error"):
        usage["dailyHistory"] = update_daily_history(usage)

        # Cache result (after history is added so cached loads include it)
        if not _atomic_write_json(cache_file, usage):
            print("Warning: failed to write cache file", file=sys.stderr)

    # Output to stdout for DataSource
    print(json.dumps(usage))


if __name__ == "__main__":
    main()
