#!/usr/bin/env python3
"""Ollama Cloud tracker: limits and credits from the local Ollama server, signed in with ollama signin.

The server (0.40.1 or later) relays /api/balance and /api/me to ollama.com, signed as the
account it's signed into, so the tracker needs no credentials of its own.
"""

import json
import os
import re
from typing import Any

from tracker_common import TrackerError, requests, run

# Where the ollama CLI finds the server unless OLLAMA_HOST says otherwise
DEFAULT_HOST = "127.0.0.1:11434"
# The first release whose server relays /api/balance
MIN_VERSION = "0.40.1"

# The limit windows a legacy plan can report, in the order they're shown
WINDOW_TITLES = {
    "session": "Session Limit",
    "weekly": "Weekly Limit",
    "monthly": "Monthly Limit",
}


def server_url() -> str:
    """The local Ollama server's address, from OLLAMA_HOST like the ollama CLI."""
    host = os.environ.get("OLLAMA_HOST", "").strip().rstrip("/") or DEFAULT_HOST
    if "://" not in host:
        host = "http://" + host
        if not re.search(r":\d+$", host):
            host += ":11434"
    return host


def _request(method: str, path: str) -> requests.Response:
    try:
        return requests.request(
            method,
            server_url() + path,
            headers={"Accept": "application/json"},
            timeout=15,
        )
    except requests.exceptions.ConnectionError:
        raise TrackerError("Can't reach Ollama. Make sure it's running")


def _error_text(response: requests.Response) -> str:
    """The error message in an API error response, or "" if there is none."""
    try:
        data = response.json()
    except json.JSONDecodeError:
        return ""
    error = data.get("error") if isinstance(data, dict) else None
    return error if isinstance(error, str) else ""


def _number(value: Any) -> float | None:
    """An API number, or None when it's missing or null — which here differs from zero."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def _used(percent: float) -> float:
    return round(max(0.0, min(100.0, percent)), 1)


def _usd(amount: float) -> str:
    return f"${amount:,.2f}"


def parse_balance(data: dict) -> list[dict[str, Any]]:
    """The balance from the API, as groups in the app's common shape.

    Legacy plans report limit windows as a percentage remaining; credit-based plans report
    included credits in USD for the billing period. Either can also have purchased credits.
    """
    included = data.get("included")
    if not isinstance(included, dict):
        included = {}
    purchased = data.get("purchased")
    purchased_usd = (
        _number(purchased.get("balance_usd")) if isinstance(purchased, dict) else None
    )
    if not included and purchased_usd is None:
        raise TrackerError("Invalid Ollama API response")

    buckets: list[dict[str, Any]] = []
    for key, title in WINDOW_TITLES.items():
        window = included.get(key)
        remaining = (
            _number(window.get("remaining_percent"))
            if isinstance(window, dict)
            else None
        )
        if remaining is None:
            continue
        bucket: dict[str, Any] = {"title": title, "used": _used(100 - remaining)}
        if isinstance(window.get("resets_at"), str):
            bucket["resetsAt"] = window["resets_at"]
        if remaining <= 0:
            bucket["disabled"] = True
        buckets.append(bucket)

    notes = []
    balance = _number(included.get("balance_usd"))
    allowance = _number(included.get("allowance_usd"))
    if balance is not None and allowance:
        bucket = {
            "title": "Included Credits",
            "used": _used((1 - balance / allowance) * 100),
        }
        period = included.get("period")
        if isinstance(period, dict) and isinstance(period.get("until"), str):
            bucket["resetsAt"] = period["until"]
        if balance <= 0:
            bucket["disabled"] = True
            # Requests keep going while purchased credits last
            if purchased_usd:
                bucket["description"] = "Now using purchased credits"
        buckets.append(bucket)
        notes.append(f"{_usd(balance)} of {_usd(allowance)} included credits left")
    if purchased_usd:
        notes.append(f"{_usd(purchased_usd)} in purchased credits")

    if not buckets and not notes:
        return []
    return [{"name": "", "description": " · ".join(notes), "buckets": buckets}]


def _plan() -> str:
    """The account's plan, for the badge next to the popup title; "" if it's unavailable."""
    try:
        response = _request("POST", "/api/me")
        data = response.json() if response.status_code == 200 else None
    except (TrackerError, requests.exceptions.RequestException, json.JSONDecodeError):
        return ""
    plan = data.get("plan") if isinstance(data, dict) else None
    return plan[:1].upper() + plan[1:] if isinstance(plan, str) else ""


def fetch() -> dict[str, Any]:
    """Fetch the account's limits and credits through the local Ollama server."""
    response = _request("GET", "/api/balance")

    if response.status_code == 401:
        raise TrackerError(
            "Not signed in to Ollama. Run: ollama signin", not_logged_in=True
        )
    if response.status_code == 404:
        raise TrackerError(f"Update Ollama to {MIN_VERSION} or later")
    if response.status_code == 429:
        raise TrackerError("Rate limited — using cached data", rate_limited=True)
    if response.status_code == 502:
        raise TrackerError("Ollama can't reach ollama.com")
    if response.status_code != 200:
        error = _error_text(response)
        raise TrackerError(
            f"Ollama error: {error}"
            if error
            else f"Ollama API error: {response.status_code}"
        )

    try:
        data = response.json()
    except json.JSONDecodeError:
        raise TrackerError("Invalid Ollama API response")
    if not isinstance(data, dict):
        raise TrackerError("Invalid Ollama API response")

    groups = parse_balance(data)
    # The panel and the daily chart both follow the busiest limit
    peak = max((b["used"] for g in groups for b in g["buckets"]), default=0.0)
    return {
        "plan": _plan(),
        "groups": groups,
        "panelPercent": peak,
        "historyPercent": peak,
    }


if __name__ == "__main__":
    run(fetch)
