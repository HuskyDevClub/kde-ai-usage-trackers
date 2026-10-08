# KDE AI Usage Trackers

KDE Plasma 6 panel widgets that show your AI coding assistant usage limits and quotas at a glance.

| Widget | Tracks | Docs |
|---|---|---|
| **Claude Usage Tracker** | Claude session, weekly, per-model, and extra usage via Claude Code CLI credentials | [claude/](claude/README.md) |
| **Antigravity Usage Tracker** | Google Antigravity (`agy`) Gemini and 3rd-party model quota pools | [antigravity/](antigravity/README.md) |

![Claude Usage Tracker preview](claude/screenshots/preview.png)

## Installation

The widgets need KDE Plasma 6 and Python 3 with the `requests` module (`pip install requests`). One command installs all of them:

```bash
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash
```

Then right-click your panel, select **Add Widgets**, search for **Usage Tracker**, and add the ones you use.

To install from a clone instead, run `./install.sh` at the top of the repo.

## Updating

Every widget checks GitHub once a day for a new release. When one is available, a notice appears at the top of the widget's popup with an **Update now** button, which downloads the release and upgrades every widget in the project — followed by a **Restart Plasma** button to apply it. With several widgets on your panel, updating from any one of them is enough.

**Skip** hides the notice until a version newer than the one you skipped is released. Automatic checks can be turned off in each widget's settings.

### Checking manually

Manual checks work whether or not automatic checking is enabled, and always ask GitHub directly rather than reusing the cached daily answer:

- **Check now** in a widget's settings, under **Updates** — the result appears right there, and the widget picks it up too, or
- **Check for Updates** in a widget's right-click menu, which opens the popup with the result

Either way you get an answer: an update notice, *"You're up to date"*, or the reason the check failed. A manual check also un-skips a version you previously skipped.

From a terminal:

```bash
python3 ~/.local/share/plasma/plasmoids/com.github.huskydevclub.claude-usage-kde-tracker/contents/code/check_update.py --force
```

To update manually instead, re-run the install command:

```bash
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/install-remote.sh | bash
```

### How updates work

Update checks ([check_update.py](shared/contents/code/check_update.py)) compare the `Version` field in `metadata.json` against the latest GitHub release tag, caching the answer for 24 hours in `~/.local/share/kde-ai-usage-trackers/update.json` — shared by every widget, so they make one request a day between them and stay well inside GitHub's unauthenticated rate limit. Installing an update ([apply_update.sh](shared/contents/code/apply_update.sh)) downloads that release's tarball and runs its `install.sh`, the same script a fresh install uses.

## Uninstallation

```bash
curl -fsSL https://raw.githubusercontent.com/HuskyDevClub/kde-ai-usage-trackers/main/uninstall.sh | bash
```

This removes every widget, along with their cached data in `~/.local/share/` — including the Claude widget's daily usage history — and the Claude icon.

## Repository layout

The project installs, upgrades, and uninstalls as one unit: `install.sh` and `uninstall.sh` at the top handle every widget, and all widgets share one version number. Each widget folder (`claude/`, `antigravity/`) is a self-contained Plasma applet package — `metadata.json` and `contents/` — that `install.sh` hands to `kpackagetool6` as-is.

Files the widgets have in common live once in [`shared/`](shared/), laid out like a widget folder, and `./sync-shared.sh` copies them into each widget. Always edit the copy in `shared/`: `./sync-shared.sh --check`, CI, and `release.sh` all fail if a widget's copy drifts from it.

## Development

| Command | What it does |
|---|---|
| `./sync-shared.sh` | Copy `shared/` (and `LICENSE`) into every widget folder |
| `./sync-shared.sh --check` | Verify every widget's shared copies match `shared/` |
| `ruff check .` | Lint the Python code |
| `plasmoidviewer -a claude` | Preview a widget straight from its folder — needs `plasma-sdk` |
| `./install.sh` | Install or upgrade every widget from this clone |
| `./release.sh` | Tag and publish a release — bump `Version` in every `metadata.json` first |

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
