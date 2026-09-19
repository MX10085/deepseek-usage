# AI Usage Monitor

A Plasma 6 taskbar widget for DeepSeek balance, Codex subscription limits, and OpenAI API usage.

## Features

- Two top-level pages: **DeepSeek** and **Codex**; the Codex page combines subscription and OpenAI API data
- DeepSeek balance, local usage estimates, history, low-balance notifications, and an automatic 100% baseline based on the highest observed balance
- Codex `/status`-style information from local session records: 5-hour and weekly limits, reset times, model, plan, context usage, and session tokens
- Cached Codex limit windows keep reset times visible and roll expired windows forward while waiting for the next Codex event
- OpenAI organization API statistics: daily/monthly token counts, requests, and costs
- Compact taskbar display; middle-click switches services
- Automatic, subscription-only, API-only, and combined Codex data modes

## Requirements

- KDE Plasma 6
- `plasma5support`
- Python 3
- A DeepSeek API key for the DeepSeek page
- An OpenAI Admin API Key for organization Usage and Costs data

A normal project API key cannot read organization-wide usage. Without an Admin API Key, the widget still shows local Codex session data.

## Install

```bash
kpackagetool6 --type Plasma/Applet --upgrade .
```

The plugin keeps the existing `org.kde.deepseek.usage` ID so upgrades preserve existing panel instances and settings.

## Configuration

Open the widget settings to select the default page and Codex data source.

For OpenAI API statistics, place the Admin API Key in a user-readable file and set its path in the widget settings:

```bash
install -m 600 /dev/null ~/.config/openai/admin-key
printf '%s\n' 'sk-admin-...' > ~/.config/openai/admin-key
chmod 600 ~/.config/openai/admin-key
```

The key is read only by the helper and is never returned to QML. `OPENAI_ADMIN_KEY` is also supported when available in the Plasma session environment.

## Data access

The bundled helper reads `~/.codex/sessions/**/*.jsonl` and returns only aggregate status fields. It does not read `~/.codex/auth.json`. In API mode it connects only to `https://api.openai.com/v1`.

## License

GPL-2.0-or-later
