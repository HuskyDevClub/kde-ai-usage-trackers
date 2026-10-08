#!/usr/bin/env python3
"""Claude tracker: usage from the Anthropic OAuth usage API, signed in with Claude Code's credentials."""

import json
import os
import time
from typing import Any

from tracker_common import (
    TrackerError,
    atomic_write_json,
    num,
    read_json,
    requests,
    run,
)

OAUTH_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CREDENTIALS_PATH = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")


def _is_token_expired(oauth: dict) -> bool:
    expires_at = oauth.get("expiresAt")
    if not expires_at or not isinstance(expires_at, (int, float)):
        return True
    if expires_at > 1e12:  # milliseconds
        expires_at /= 1000
    return expires_at < time.time()


def _refresh_token(credentials: dict) -> str | None:
    """Get a new access token with the refresh token, and save it to the credentials file.

    Returns the new access token, or None if it can't be refreshed.
    """
    oauth = credentials.get("claudeAiOauth")
    refresh_token = oauth.get("refreshToken") if isinstance(oauth, dict) else None
    if not refresh_token:
        return None

    try:
        response = requests.post(
            OAUTH_TOKEN_URL,
            json={
                "grant_type": "refresh_token",
                "client_id": OAUTH_CLIENT_ID,
                "refresh_token": refresh_token,
            },
            timeout=15,
        )
        if response.status_code != 200:
            return None
        token_data = response.json()
    except (requests.exceptions.RequestException, json.JSONDecodeError):
        return None

    access_token = (
        token_data.get("access_token") if isinstance(token_data, dict) else None
    )
    if not access_token:
        return None

    oauth["accessToken"] = access_token
    if token_data.get("refresh_token"):
        oauth["refreshToken"] = token_data["refresh_token"]
    if token_data.get("expires_in"):
        oauth["expiresAt"] = int((time.time() + token_data["expires_in"]) * 1000)
    atomic_write_json(CREDENTIALS_PATH, credentials)
    return access_token


def _make_usage_request(token: str) -> requests.Response:
    return requests.get(
        OAUTH_USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
        timeout=15,
    )


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
    credentials = read_json(CREDENTIALS_PATH)
    oauth = credentials.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        oauth = {}
    token = oauth.get("accessToken")
    if token and _is_token_expired(oauth):
        token = _refresh_token(credentials)
    if not token:
        raise TrackerError(
            "No credentials found. Run: claude login", not_logged_in=True
        )

    response = _make_usage_request(token)

    # A token can be revoked before it expires: refresh it once and retry, re-reading the
    # credentials in case Claude Code has replaced them since
    if response.status_code == 401:
        token = _refresh_token(read_json(CREDENTIALS_PATH))
        if token:
            response = _make_usage_request(token)

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

    plan = str(oauth.get("subscriptionType") or "")
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
