# 2.0.2

- Define DeepSeek 100% as the highest balance observed by the widget. The first balance after upgrading becomes the initial baseline, and a later higher balance raises it automatically.
- Preserve DeepSeek usage history when the percentage baseline changes.
- Select Codex quota data by event time across recent sessions instead of relying on the newest file alone.
- Cache the last valid Codex window length and reset time, so exhausted quotas no longer lose their reset time.
- Roll an expired Codex window forward immediately while waiting for a new session event, and label inferred reset times as estimated.
