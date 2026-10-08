# Claude Usage Tracker

A KDE Plasma 6 widget that displays your Claude AI usage limits and quotas directly in your panel.

## Preview

![Preview](screenshots/preview.png)

## Features

- **Panel donut chart** showing current session utilization at a glance
- **Session (5-hour) and weekly (7-day) usage bars** with reset time countdowns
- **Per-model breakdown** for Sonnet and Opus utilization
- **Extra usage tracking** for paid overage credits
- **Daily usage bar chart** for recent usage history
- **Configurable auto-refresh** interval
- **Auto-login** via Claude Code CLI credentials
- **Pin popup** to keep the detail view open
- **Update notifications** with one-click install when a new release is published

## Requirements

- KDE Plasma 6
- Python 3 with the `requests` module (`pip install requests`)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (run `claude login` to set up credentials)

## Installation

See the [main README](../README.md#installation) — one command installs every widget in this project.

## Updating

See the [main README](../README.md#updating) — updating from any widget upgrades every widget in this project.

## Uninstallation

See the [main README](../README.md#uninstallation) — one command removes every widget in this project.

## Configuration

Right-click the widget and select **Configure** to adjust:

| Setting | Default | Description |
|---|---|---|
| Refresh interval | 5 min | How often to fetch fresh data from the API (1-60 min) |
| Show extra usage | On | Show paid overage section |
| Show recent usage | Off | Show daily usage bar chart |
| Check for updates | On | Check GitHub daily for new releases (manual checks always available) |
| Custom colors | Off | Override theme colors, with colorblind-friendly presets |

## How it works

The widget calls the Anthropic OAuth usage API (`/api/oauth/usage`) using credentials from Claude Code CLI. A Python script ([fetch_usage.py](contents/code/fetch_usage.py)) handles authentication and API communication, while the QML frontend renders the data as interactive progress bars and charts.

Usage data is cached locally at `~/.local/share/claude-usage-tracker/usage.json` so the widget can display stale data instantly while a fresh fetch runs in the background.

## Contributing

Bug reports, feature ideas, and pull requests are welcome — see [Contributing](../README.md#contributing) in the main README, which also covers [how to cut a release](../README.md#releasing).

## License

GPL-3.0
