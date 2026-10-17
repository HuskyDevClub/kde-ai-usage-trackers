# Antigravity tracker

The Antigravity tracker in [AI Usage Tracker](../../README.md) shows how much of your Google Antigravity (`agy`) quotas you've used.

## What it shows

- **One section per quota pool** — Gemini models, 3rd-party models such as Claude and GPT, and on paid Pro plans Gemini 4 Argon, which has its own quota
- **5-hour and weekly limits** in each pool (Gemini 4 Argon has a weekly limit only), with countdowns to when they reset, and a notice when a limit has been reached (none once the weekly limit is used up, since its full bar says so)
- Your plan (tier) next to the title
- The panel and the daily chart both follow your busiest limit across every pool

## Requirements

[Antigravity CLI (`agy`)](https://antigravity.google), signed in by running `agy`. The tracker reads its credentials from the desktop Secret Service keyring, or from `~/.gemini/oauth_creds.json`.

## How it works

[fetch_usage.py](contents/code/fetch_usage.py) calls Google Cloud Code's internal quota endpoint (`/v1internal:retrieveUserQuotaSummary`) with Antigravity's credentials, refreshing the OAuth token as needed, and returns the quota pools in the app's common shape.

Installing, settings, updates, and everything else the trackers share are covered in the [main README](../../README.md).
