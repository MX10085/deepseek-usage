# DeepSeek Usage Monitor v1.0.1

## Fixed

- **Usage history no longer resets after a top-up.** Previously, when your
  DeepSeek balance increased noticeably (top-up or gift credit), the widget
  cleared all snapshot history and restarted from the new balance — zeroing
  out today/week/total usage and the 7-day chart. Now the top-up amount is
  shifted onto the existing history, so the consumption curve stays
  continuous and previously spent amounts are preserved.

## Full Changelog

- `recordSnapshot()`: on top-up detection, add the top-up delta to all
  existing snapshots instead of clearing the array (a712c81)
