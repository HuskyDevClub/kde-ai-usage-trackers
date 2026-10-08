# KDE AI Usage Trackers

KDE Plasma 6 panel widgets that show your AI coding assistant usage limits and quotas at a glance.

| Widget | Tracks | Docs |
|---|---|---|
| **Claude Usage Tracker** | Claude session, weekly, per-model, and extra usage via Claude Code CLI credentials | [claude/](claude/README.md) |
| **Antigravity Usage Tracker** | Google Antigravity (`agy`) Gemini and 3rd-party model quota pools | [antigravity/](antigravity/README.md) |

![Claude Usage Tracker preview](claude/screenshots/preview.png)

## Installation

Both widgets need KDE Plasma 6 and Python 3 with the `requests` module (`pip install requests`). Install either or both:

```bash
# Claude Usage Tracker
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash

# Antigravity Usage Tracker
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash -s antigravity
```

Then right-click your panel, select **Add Widgets**, and search for **Claude** or **Antigravity**.

To install from a clone instead, run `install.sh` inside the widget's folder. See each widget's README for configuration, updating, and uninstalling.

## Repository layout

Each top-level widget folder (`claude/`, `antigravity/`) is a self-contained Plasma applet package — `metadata.json`, `contents/`, and its own `install.sh` / `uninstall.sh`.

Files the widgets have in common live once in [`shared/`](shared/), laid out like a widget folder, and `./sync-shared.sh` copies them into each widget. Always edit the copy in `shared/`: `./sync-shared.sh --check` and CI fail if a widget's copy drifts from it.

## Development

| Command | What it does |
|---|---|
| `./sync-shared.sh` | Copy `shared/` (and `LICENSE`) into every widget folder |
| `./sync-shared.sh --check` | Verify every widget's shared copies match `shared/` |
| `ruff check .` | Lint the Python code |
| `plasmoidviewer -a claude` | Preview a widget straight from its folder — needs `plasma-sdk` |

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, or pull requests — every bit helps.

- **Report bugs** — Open an [issue](https://github.com/HuskyDevClub/kde-ai-usage-trackers/issues) and mention which widget it's about
- **Suggest features** — Have an idea for a useful addition? Let us know
- **Submit pull requests** — Code improvements, UI tweaks, and documentation fixes are all appreciated
- **Share feedback** — Let us know how you use the widgets and what could be better

If you'd like to contribute code, fork the repo, create a branch, and open a PR. There are no strict contribution guidelines — just keep changes focused and test before submitting.

### Releasing

Bump `KPlugin.Version` in the widget's `metadata.json`, commit, then run:

```bash
./release.sh claude --notes "What changed"        # tags v<version>, marked Latest
./release.sh antigravity --notes "What changed"   # tags antigravity-v<version>, never Latest
```

The script tags a standalone commit containing only that widget's folder, so each release's source tarball is an installable plasmoid with `metadata.json` at its root. Don't tag `main` by hand: the Claude widget's in-app updater downloads the tag's tarball and expects that layout.

The Claude updater also reads GitHub's **Latest** release and only understands `v`-prefixed tags. That's why Claude releases keep plain `vX.Y` tags and other widgets' releases must never be marked Latest. `release.sh` handles both.

## License

GPL-3.0
