# Changelog

## 0.1.1 — 2026-11-20

- Replace completed-quest/projection bar text with a running-session time-to-level estimate based on XP remaining and active XP rate.
- Keep quest totals/projection details in the tooltip and retain the gold overlay. Hide ETA while inactive or before an XP rate is available; shorten text on narrow bars.

## 0.1.0 — 2026-11-20

- Add native XP-bar text, completed-quest projection, partial-data status, and level-boundary overflow.
- Add compact movable session strip, armed/paused states, account-wide saved/temporary journal, filters, and location details.
- Track XP sources, eligible loot and confirmed quest rewards, pending item data, and optional cached Auctionator estimates.
- Freeze closed-session pricing; retain 20 unsaved records with permanent promotion.
- Add Lua 5.1 unit/mocked integration tests, CI, reproducible install ZIP, and a pending live-client checklist.
