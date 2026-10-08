#!/usr/bin/env python3
"""Fetch Antigravity CLI (agy) quota usage.

agy stores its Google OAuth credentials in the Secret Service keyring
(service: "gemini", username: "antigravity") with a file fallback to
~/.gemini/oauth_creds.json.

This script loads the credentials, refreshes the access token if needed,
and requests the quota summary pools for Gemini and 3rd-party models from
the Cloud Code internal API.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
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

API_BASE = "https://cloudcode-pa.googleapis.com/v1internal"
OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
OAUTH_CLIENT_ID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
OAUTH_CLIENT_SECRET = "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"
KEYRING_SERVICE = "gemini"
KEYRING_USER = "antigravity"
USER_AGENT = "antigravity"

CACHE_DIR = os.path.join(
    os.path.expanduser("~"), ".local", "share", "antigravity-usage-tracker"
)
CACHE_FILE = os.path.join(CACHE_DIR, "usage.json")
OAUTH_CREDS_PATH = os.path.join(os.path.expanduser("~"), ".gemini", "oauth_creds.json")
DEFAULT_PROJECT_CACHE = os.path.join(
    os.path.expanduser("~"), ".gemini", "antigravity-cli", "cache", "default_project_id.txt"
)

WINDOW_TITLES = {"5h": "5-Hour Limit", "weekly": "Weekly Limit"}


class AgyError(Exception):
    def __init__(self, message: str, not_logged_in: bool = False, rate_limited: bool = False):
        super().__init__(message)
        self.not_logged_in = not_logged_in
        self.rate_limited = rate_limited


def _num(value: Any, default: float = 0) -> float:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return float(default)


def _atomic_write_json(filepath: str, data: Any, mode: int = 0o600) -> bool:
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


def _read_keyring_secret() -> str | None:
    try:
        proc = subprocess.run(
            ["secret-tool", "lookup", "service", KEYRING_SERVICE, "username", KEYRING_USER],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout
    except (OSError, subprocess.TimeoutExpired):
        pass

    try:
        import secretstorage  # type: ignore[import-not-found]

        conn = secretstorage.dbus_init()
        try:
            collection = secretstorage.get_default_collection(conn)
            if collection.is_locked():
                collection.unlock()
            for item in collection.search_items(
                {"service": KEYRING_SERVICE, "username": KEYRING_USER}
            ):
                return item.get_secret().decode("utf-8")
        finally:
            conn.close()
    except Exception:
        pass

    return None


def _parse_expiry(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    value = re.sub(r"(\.\d{6})\d+", r"\1", value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _refresh_access_token(refresh_token: str) -> str:
    try:
        response = requests.post(
            OAUTH_TOKEN_URL,
            data={
                "client_id": OAUTH_CLIENT_ID,
                "client_secret": OAUTH_CLIENT_SECRET,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            },
            timeout=15,
        )
    except requests.exceptions.RequestException:
        raise AgyError("Connection error")

    if response.status_code != 200:
        raise AgyError("Antigravity session expired. Run agy to log in again")
    try:
        token = response.json().get("access_token")
    except json.JSONDecodeError:
        token = None
    if not token:
        raise AgyError("Antigravity session expired. Run agy to log in again")
    return token


def _load_from_oauth_creds_file() -> tuple[str | None, str | None]:
    if not os.path.exists(OAUTH_CREDS_PATH):
        return None, None
    try:
        with open(OAUTH_CREDS_PATH, "r") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return None, None
        access_token = data.get("access_token")
        refresh_token = data.get("refresh_token")
        expiry_date = data.get("expiry_date")

        now_sec = datetime.now(timezone.utc).timestamp()
        expired = False
        if isinstance(expiry_date, (int, float)):
            exp_sec = expiry_date / 1000.0 if expiry_date > 1e12 else float(expiry_date)
            expired = (exp_sec - 60) < now_sec
        elif not access_token:
            expired = True

        if expired and refresh_token:
            new_token = _refresh_access_token(refresh_token)
            data["access_token"] = new_token
            data["expiry_date"] = int((now_sec + 3600) * 1000)
            _atomic_write_json(OAUTH_CREDS_PATH, data)
            return new_token, refresh_token

        return access_token, refresh_token
    except (json.JSONDecodeError, OSError):
        return None, None


def load_credentials() -> tuple[str, str | None]:
    raw = _read_keyring_secret()
    if not raw:
        token, refresh = _load_from_oauth_creds_file()
        if token:
            return token, refresh
        raise AgyError("Not logged into Antigravity. Run: agy", not_logged_in=True)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        token, refresh = _load_from_oauth_creds_file()
        if token:
            return token, refresh
        raise AgyError("Unreadable Antigravity credentials")

    token_obj = data.get("token") if isinstance(data, dict) else None
    if not isinstance(token_obj, dict):
        token, refresh = _load_from_oauth_creds_file()
        if token:
            return token, refresh
        raise AgyError("Unreadable Antigravity credentials")

    access_token = token_obj.get("access_token")
    refresh_token = token_obj.get("refresh_token")
    expiry = _parse_expiry(token_obj.get("expiry"))

    expired = expiry is None or (expiry.timestamp() - 60) < datetime.now(timezone.utc).timestamp()
    if not access_token or expired:
        if not refresh_token:
            token, refresh = _load_from_oauth_creds_file()
            if token:
                return token, refresh
            raise AgyError("Antigravity session expired. Run agy to log in again")
        access_token = _refresh_access_token(refresh_token)

    return access_token, refresh_token


def _post(method: str, token: str, body: dict) -> requests.Response:
    return requests.post(
        f"{API_BASE}:{method}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
        json=body,
        timeout=15,
    )


def _check_status(response: requests.Response) -> None:
    if response.status_code == 200:
        return
    if response.status_code == 403:
        raise AgyError("Antigravity access denied. Check your plan")
    if response.status_code == 429:
        raise AgyError("Rate limited — using cached data", rate_limited=True)
    raise AgyError(f"Antigravity API error: {response.status_code}")


def _call(method: str, token: str, refresh_token: str | None, body: dict) -> tuple[dict, str]:
    response = _post(method, token, body)
    if response.status_code == 401 and refresh_token:
        token = _refresh_access_token(refresh_token)
        response = _post(method, token, body)
    if response.status_code == 401:
        raise AgyError("Antigravity session expired. Run agy to log in again")
    _check_status(response)
    try:
        data = response.json()
    except json.JSONDecodeError:
        raise AgyError("Invalid Antigravity API response")
    return (data if isinstance(data, dict) else {}), token


def _project_id(load_response: dict) -> str | None:
    project = load_response.get("cloudaicompanionProject")
    if isinstance(project, dict):
        project = project.get("id")
    if isinstance(project, str) and project:
        return project

    if os.path.exists(DEFAULT_PROJECT_CACHE):
        try:
            with open(DEFAULT_PROJECT_CACHE, "r") as f:
                cached_proj = f.read().strip()
            if cached_proj:
                return cached_proj
        except OSError:
            pass

    return "aicode-consumers"


def _tier_name(load_response: dict) -> str:
    for key in ("paidTier", "currentTier"):
        tier = load_response.get(key)
        if isinstance(tier, dict) and isinstance(tier.get("name"), str) and tier["name"]:
            return tier["name"]
    return "Antigravity"


def parse_bucket(bucket: dict) -> dict[str, Any]:
    window = bucket.get("window") if isinstance(bucket.get("window"), str) else ""
    title = WINDOW_TITLES.get(window)
    if not title:
        title = str(bucket.get("displayName") or bucket.get("bucketId") or "Limit")
        title = title.replace(" Remaining", "")

    remaining = max(0.0, min(1.0, _num(bucket.get("remainingFraction"), 0)))
    result: dict[str, Any] = {
        "id": str(bucket.get("bucketId") or window or title),
        "title": title,
        "used": round((1 - remaining) * 100, 1),
    }
    if bucket.get("description"):
        result["description"] = bucket["description"]
    if bucket.get("disabled"):
        result["disabled"] = True

    if remaining < 1 and isinstance(bucket.get("resetTime"), str):
        result["resetsAt"] = bucket["resetTime"]
    return result


def parse_summary(summary: dict) -> list[dict[str, Any]]:
    groups = []
    for group in summary.get("groups") or []:
        if not isinstance(group, dict):
            continue
        buckets = [parse_bucket(b) for b in group.get("buckets") or [] if isinstance(b, dict)]
        order = {"5-Hour Limit": 0, "Weekly Limit": 1}
        buckets.sort(key=lambda b: order.get(b["title"], 2))
        groups.append(
            {
                "name": str(group.get("displayName") or "Models"),
                "description": str(group.get("description") or ""),
                "buckets": buckets,
            }
        )
    return groups


def fetch_usage() -> dict[str, Any]:
    result: dict[str, Any] = {
        "tier": "",
        "groups": [],
        "maxPercent": 0.0,
        "lastUpdated": datetime.now().strftime("%H:%M:%S"),
        "error": None,
    }

    try:
        token, refresh_token = load_credentials()

        load_response, token = _call(
            "loadCodeAssist", token, refresh_token, {"metadata": {"ideType": "ANTIGRAVITY"}}
        )
        result["tier"] = _tier_name(load_response)
        project = _project_id(load_response)
        if not project:
            raise AgyError("No Antigravity project found. Run agy once to finish setup")

        summary, token = _call("retrieveUserQuotaSummary", token, refresh_token, {"project": project})
        groups = parse_summary(summary)
        result["groups"] = groups

        all_pcts = [b["used"] for g in groups for b in g.get("buckets", [])]
        result["maxPercent"] = max(all_pcts) if all_pcts else 0.0
    except AgyError as e:
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

    return result


def main() -> None:
    usage = fetch_usage()
    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)

    if usage.get("rateLimited"):
        try:
            with open(CACHE_FILE, "r") as f:
                cached = json.load(f)
            cached["rateLimited"] = True
            cached["error"] = None
            print(json.dumps(cached))
            return
        except (json.JSONDecodeError, OSError):
            pass
    elif not usage.get("error"):
        if not _atomic_write_json(CACHE_FILE, usage):
            print("Warning: failed to write agy cache file", file=sys.stderr)

    print(json.dumps(usage))


if __name__ == "__main__":
    main()
