# Antigravity Usage Tracker

A KDE Plasma 6 widget that displays your Google Antigravity (`agy`) AI usage limits and quotas directly in your panel.

## Features

- **Panel donut chart** showing current peak utilization at a glance
- **Multi-group quota tracking** for Gemini Models and 3rd-party (Claude, GPT) model pools
- **5-Hour and weekly limit bars** with dynamic reset countdown timers
- **Configurable auto-refresh** interval
- **Auto-login** via Antigravity CLI (`agy`) credentials (from Secret Service keyring or local credentials)
- **Pin popup** to keep the detail view open
- **Colorblind-friendly presets** and custom color schemes

## Requirements

- KDE Plasma 6
- Python 3 with the `requests` module (`pip install requests`)
- [Antigravity CLI (`agy`)](https://antigravity.google) (logged in via `agy`)

## Installation

Just copy and paste this single line into your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash -s antigravity
```

Or from a clone:

```bash
git clone https://github.com/HuskyDevClub/kde-ai-usage-trackers.git
cd kde-ai-usage-trackers/antigravity
bash install.sh
```

Then right-click your panel, select **Add Widgets**, and search for **Antigravity**.

## Uninstallation

```bash
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/antigravity/uninstall.sh | bash
```

## Configuration

Right-click the widget and select **Configure** to adjust:

| Setting | Default | Description |
|---|---|---|
| Refresh interval | 5 min | How often to fetch fresh data from the API (1-60 min) |
| Custom colors | Off | Override theme colors, with colorblind-friendly presets |

## How it works

The widget calls Google Cloud Code internal quota endpoints (`/v1internal:retrieveUserQuotaSummary`) using credentials from Antigravity CLI. A Python script ([fetch_usage.py](contents/code/fetch_usage.py)) reads credentials from the desktop Secret Service keyring (or `~/.gemini/oauth_creds.json`), auto-refreshes OAuth tokens as needed, and returns quota pool data.

Usage data is cached locally at `~/.local/share/antigravity-usage-tracker/usage.json` so the widget displays data instantly on login or startup while fresh data loads in the background.

## License

GPL-3.0
