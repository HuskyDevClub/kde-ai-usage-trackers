# Claude tracker

The Claude tracker in [AI Usage Tracker](../../README.md) shows how much of your Claude plan's usage limits you've used.

![Preview](screenshots/preview.png)

## What it shows

- **Current session** (5-hour) and **weekly** (7-day) limits, with countdowns to when they reset
- **Per-model limits** for Sonnet and Opus, once you've used them
- **Extra usage** — paid overage credits, against your monthly cap if you've set one
- The panel shows your session usage, or your weekly usage when no session is active; the daily chart records each day's peak session usage

## Requirements

[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), signed in with `claude login`. The tracker reads Claude Code's credentials from `~/.claude/.credentials.json` and refreshes the access token there when it expires.

## How it works

[fetch_usage.py](contents/code/fetch_usage.py) calls the Anthropic OAuth usage API (`/api/oauth/usage`) with Claude Code's credentials and returns the limits above in the app's common shape.

Installing, settings, updates, and everything else the trackers share are covered in the [main README](../../README.md).
