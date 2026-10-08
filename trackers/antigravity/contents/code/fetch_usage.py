#!/usr/bin/env python3
"""Antigravity tracker: quota pools from the Cloud Code internal API, signed in with agy's credentials.

agy keeps its Google OAuth credentials in the Secret Service keyring (service "gemini",
username "antigravity"), or else in ~/.gemini/oauth_creds.json.
"""

import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from typing import Any

from tracker_common import (
    TrackerError,
    atomic_write_json,
    num,
    read_json,
    requests,
    run,
)

API_BASE = "https://cloudcode-pa.googleapis.com/v1internal"
OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
OAUTH_CLIENT_ID = (
    "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
)
OAUTH_CLIENT_SECRET = "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"
KEYRING_SERVICE = "gemini"
KEYRING_USER = "antigravity"
USER_AGENT = "antigravity"
# Queried when the account has no project of its own and agy hasn't cached one
DEFAULT_PROJECT = "aicode-consumers"
SESSION_EXPIRED = "Antigravity session expired. Run agy to log in again"

OAUTH_CREDS_PATH = os.path.join(os.path.expanduser("~"), ".gemini", "oauth_creds.json")
DEFAULT_PROJECT_CACHE = os.path.join(
    os.path.expanduser("~"),
    ".gemini",
    "antigravity-cli",
    "cache",
    "default_project_id.txt",
)

WINDOW_TITLES = {"5h": "5-Hour Limit", "weekly": "Weekly Limit"}
# Each pool lists these windows first, in this order, then any other limits
WINDOW_ORDER = {title: i for i, title in enumerate(WINDOW_TITLES.values())}


def _read_keyring_secret() -> str | None:
    """agy's credentials JSON from the keyring, via secret-tool or else the secretstorage module."""
    try:
        proc = subprocess.run(
            [
                "secret-tool",
                "lookup",
                "service",
                KEYRING_SERVICE,
                "username",
                KEYRING_USER,
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
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
    except Exception:  # noqa: BLE001, S110
        pass  # Any keyring failure just means no stored credentials

    return None


def _parse_expiry(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    # Trim fractional seconds to the microseconds fromisoformat() accepts
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
        raise TrackerError("Connection error")

    if response.status_code != 200:
        raise TrackerError(SESSION_EXPIRED, not_logged_in=True)
    try:
        token = response.json().get("access_token")
    except json.JSONDecodeError:
        token = None
    if not token:
        raise TrackerError(SESSION_EXPIRED, not_logged_in=True)
    return token


def _load_from_oauth_creds_file() -> tuple[str | None, str | None]:
    """Tokens from ~/.gemini/oauth_creds.json, refreshed and saved back if expired."""
    data = read_json(OAUTH_CREDS_PATH)
    access_token = data.get("access_token")
    refresh_token = data.get("refresh_token")
    expiry_date = data.get("expiry_date")

    now = time.time()
    if isinstance(expiry_date, (int, float)):
        if expiry_date > 1e12:  # milliseconds
            expiry_date /= 1000
        expired = expiry_date - 60 < now
    else:
        expired = not access_token

    if expired and refresh_token:
        access_token = _refresh_access_token(refresh_token)
        data["access_token"] = access_token
        data["expiry_date"] = int((now + 3600) * 1000)
        atomic_write_json(OAUTH_CREDS_PATH, data)
    return access_token, refresh_token


def _load_from_file_or_raise(error: TrackerError) -> tuple[str, str | None]:
    """Fall back to the credentials file, raising error if it has no token either."""
    token, refresh_token = _load_from_oauth_creds_file()
    if not token:
        raise error
    return token, refresh_token


def load_credentials() -> tuple[str, str | None]:
    """agy's access and refresh tokens, from the keyring or else the credentials file."""
    raw = _read_keyring_secret()
    if not raw:
        return _load_from_file_or_raise(
            TrackerError("Not logged into Antigravity. Run: agy", not_logged_in=True)
        )

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = None
    token_obj = data.get("token") if isinstance(data, dict) else None
    if not isinstance(token_obj, dict):
        return _load_from_file_or_raise(
            TrackerError("Unreadable Antigravity credentials")
        )

    access_token = token_obj.get("access_token")
    refresh_token = token_obj.get("refresh_token")
    expiry = _parse_expiry(token_obj.get("expiry"))
    expired = expiry is None or expiry.timestamp() - 60 < time.time()
    if access_token and not expired:
        return access_token, refresh_token
    if not refresh_token:
        return _load_from_file_or_raise(
            TrackerError(SESSION_EXPIRED, not_logged_in=True)
        )
    return _refresh_access_token(refresh_token), refresh_token


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


def _call(
    method: str, token: str, refresh_token: str | None, body: dict
) -> tuple[dict, str]:
    """Call a Cloud Code API method, refreshing the token once if it's rejected.

    Returns the response and the token that worked, for the next call.
    """
    response = _post(method, token, body)
    if response.status_code == 401 and refresh_token:
        token = _refresh_access_token(refresh_token)
        response = _post(method, token, body)

    if response.status_code == 401:
        raise TrackerError(SESSION_EXPIRED, not_logged_in=True)
    if response.status_code == 403:
        raise TrackerError("Antigravity access denied. Check your plan")
    if response.status_code == 429:
        raise TrackerError("Rate limited — using cached data", rate_limited=True)
    if response.status_code != 200:
        raise TrackerError(f"Antigravity API error: {response.status_code}")

    try:
        data = response.json()
    except json.JSONDecodeError:
        raise TrackerError("Invalid Antigravity API response")
    return (data if isinstance(data, dict) else {}), token


def _project_id(load_response: dict) -> str:
    """The project to query quotas for: the account's own, else agy's cached one, else DEFAULT_PROJECT."""
    project = load_response.get("cloudaicompanionProject")
    if isinstance(project, dict):
        project = project.get("id")
    if isinstance(project, str) and project:
        return project

    try:
        with open(DEFAULT_PROJECT_CACHE, "r") as f:
            cached = f.read().strip()
        if cached:
            return cached
    except OSError:
        pass

    return DEFAULT_PROJECT


def _tier_name(load_response: dict) -> str:
    """The account's plan, for the badge next to the popup title."""
    for key in ("paidTier", "currentTier"):
        tier = load_response.get(key)
        if (
            isinstance(tier, dict)
            and isinstance(tier.get("name"), str)
            and tier["name"]
        ):
            return tier["name"]
    return "Antigravity"


def parse_bucket(bucket: dict) -> dict[str, Any]:
    """One quota limit from the API, as a bucket in the app's common shape."""
    window = bucket.get("window")
    title = WINDOW_TITLES.get(window) if isinstance(window, str) else None
    if not title:
        title = str(bucket.get("displayName") or bucket.get("bucketId") or "Limit")
        title = title.replace(" Remaining", "")

    remaining = max(0.0, min(1.0, num(bucket.get("remainingFraction"))))
    result: dict[str, Any] = {"title": title, "used": round((1 - remaining) * 100, 1)}
    if bucket.get("description"):
        result["description"] = bucket["description"]
    if bucket.get("disabled"):
        result["disabled"] = True
    # An untouched limit has no countdown to show
    if remaining < 1 and isinstance(bucket.get("resetTime"), str):
        result["resetsAt"] = bucket["resetTime"]
    return result


def parse_summary(summary: dict) -> list[dict[str, Any]]:
    """The quota pools from the API, as groups in the app's common shape."""
    groups = []
    for group in summary.get("groups") or []:
        if not isinstance(group, dict):
            continue
        buckets = [
            parse_bucket(b) for b in group.get("buckets") or [] if isinstance(b, dict)
        ]
        buckets.sort(key=lambda b: WINDOW_ORDER.get(b["title"], len(WINDOW_ORDER)))
        groups.append(
            {
                "name": str(group.get("displayName") or "Models"),
                "description": str(group.get("description") or ""),
                "buckets": buckets,
            }
        )
    return groups


def fetch() -> dict[str, Any]:
    """Fetch the quota pools for Gemini and 3rd-party models."""
    token, refresh_token = load_credentials()

    load_response, token = _call(
        "loadCodeAssist", token, refresh_token, {"metadata": {"ideType": "ANTIGRAVITY"}}
    )
    summary, _ = _call(
        "retrieveUserQuotaSummary",
        token,
        refresh_token,
        {"project": _project_id(load_response)},
    )
    groups = parse_summary(summary)

    # The panel and the daily chart both follow the busiest limit across every pool
    peak = max((b["used"] for g in groups for b in g["buckets"]), default=0.0)
    return {
        "plan": _tier_name(load_response),
        "groups": groups,
        "panelPercent": peak,
        "historyPercent": peak,
    }


if __name__ == "__main__":
    run(fetch)
