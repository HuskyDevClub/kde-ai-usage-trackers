# Ollama Cloud tracker

The Ollama Cloud tracker in [AI Usage Tracker](../../README.md) shows how much of your Ollama Cloud plan you've used.

## What it shows

- **Included credits** on credit-based plans: how much of the month's allowance is spent, the dollar amounts left, and a countdown to when it renews
- **Session and weekly limits** on legacy plans, with countdowns to when they reset, and a notice when a limit has been reached
- **Purchased credits** left, if you have any
- Your plan next to the title
- The panel and the daily chart both follow your busiest limit

## Requirements

[Ollama](https://ollama.com/download) 0.40.1 or later, running, and signed in with `ollama signin`. The tracker asks the local Ollama server for your usage, so it follows whichever account Ollama is signed into and needs no credentials of its own. It finds the server the same way the `ollama` CLI does: at `127.0.0.1:11434`, or wherever `OLLAMA_HOST` points if that's set in Plasma's environment.

## How it works

[fetch_usage.py](contents/code/fetch_usage.py) calls the Ollama server's `/api/balance`, which relays Ollama's [balance API](https://docs.ollama.com/api/balance) signed as your account, and `/api/me` for your plan. It returns your limits and credits in the app's common shape.

Installing, settings, updates, and everything else the trackers share are covered in the [main README](../../README.md).
