#!/usr/bin/env python3
"""Claude tracker: usage from the Anthropic OAuth usage API, signed in with Claude Code's credentials."""

import json
import os
from datetime import datetime
from typing import Any

from tracker_common import TrackerError, atomic_write_json, num, requests, run

OAUTH_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CREDENTIALS_PATH = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")


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
        atomic_write_json(CREDENTIALS_PATH, credentials_data)

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


def _make_usage_request(token: str) -> requests.Response:
    """Make a GET request to the usage API."""
    headers = {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
    }
    return requests.get(OAUTH_USAGE_URL, headers=headers, timeout=15)


def _bucket(data: dict, api_key: str, title: str) -> dict[str, Any]:
    """One usage limit from the API response, as a bucket in the app's common shape."""
    item = data.get(api_key)
    bucket: dict[str, Any] = {"title": title, "used": 0.0}
    if isinstance(item, dict):
        bucket["used"] = num(item.get("utilization"))
        if item.get("resets_at"):
            bucket["resetsAt"] = item["resets_at"]
    return bucket


def fetch() -> dict[str, Any]:
    """Fetch current usage from the Claude OAuth API."""
    token, subscription_type = load_credentials_from_file()
    if not token:
        raise TrackerError(
            "No credentials found. Run: claude login", not_logged_in=True
        )

    response = _make_usage_request(token)

    # On 401, try refreshing the token once
    if response.status_code == 401:
        try:
            with open(CREDENTIALS_PATH, "r") as f:
                cred_data = json.load(f)
            new_token, new_sub = _refresh_token(cred_data)
            if new_token:
                token = new_token
                subscription_type = new_sub
                response = _make_usage_request(token)
        except (json.JSONDecodeError, IOError, OSError):
            pass

    if response.status_code == 401:
        raise TrackerError("Session expired. Run: claude login", not_logged_in=True)
    if response.status_code == 403:
        raise TrackerError("Access denied. Check your subscription.")
    if response.status_code == 429:
        raise TrackerError("Rate limited — using cached data", rate_limited=True)
    if response.status_code != 200:
        raise TrackerError(f"API error: {response.status_code}")

    try:
        data = response.json()
    except json.JSONDecodeError:
        raise TrackerError("Invalid API response")
    if not isinstance(data, dict):
        raise TrackerError("Invalid API response")

    session = _bucket(data, "five_hour", "Current Session")
    weekly = _bucket(data, "seven_day", "Weekly Limits")
    models = [
        bucket
        for bucket in (
            _bucket(data, "seven_day_sonnet", "Sonnet"),
            _bucket(data, "seven_day_opus", "Opus"),
        )
        if bucket["used"] > 0
    ]

    groups: list[dict[str, Any]] = [{"name": "", "buckets": [session, weekly]}]
    if models:
        groups.append({"name": "Per-Model Usage", "buckets": models})

    plan = (
        subscription_type
        if subscription_type and subscription_type != "unknown"
        else ""
    )
    usage: dict[str, Any] = {
        "plan": plan[:1].upper() + plan[1:],
        "groups": groups,
        # The panel shows the session, falling back to the weekly limit when no session is active
        "panelPercent": session["used"] if session["used"] > 0 else weekly["used"],
        # The daily chart records each day's peak session usage
        "historyPercent": session["used"],
    }

    # Extra usage (paid overage) — API returns credits in cents
    extra = data.get("extra_usage")
    if isinstance(extra, dict) and extra.get("is_enabled"):
        usage["extra"] = {
            "used": num(extra.get("used_credits")) / 100,
            "limit": num(extra.get("monthly_limit")) / 100,
            "utilization": num(extra.get("utilization")),
        }

    return usage


if __name__ == "__main__":
    run(fetch)
