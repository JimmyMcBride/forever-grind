# Changelog

## 0.1.2 — 2026-11-20

- Replace the narrow journal details panel with full-width Overview, Loot, and Session details reports, keeping XP/hour, estimated gold/hour, active time, and total XP visible.
- Align earnings and XP breakdowns; separate the vendor-only comparison and data notices. Add selectable loot rows, recommendation details, wrapped notes, and zones sorted by active time.
- Preserve list navigation, report scrolling, selected items, and unfinished edits during updates. Keep promotion/deletion and frozen pricing behavior without changing saved data.

## 0.1.1 — 2026-11-20

- Replace completed-quest/projection bar text with a running-session time-to-level estimate based on XP remaining and active XP rate.
- Keep quest totals/projection details in the tooltip and retain the gold overlay. Hide ETA while inactive or before an XP rate is available; shorten text on narrow bars.

## 0.1.0 — 2026-11-20

- Add native XP-bar text, completed-quest projection, partial-data status, and level-boundary overflow.
- Add compact movable session strip, armed/paused states, account-wide saved/temporary journal, filters, and location details.
- Track XP sources, eligible loot and confirmed quest rewards, pending item data, and optional cached Auctionator estimates.
- Freeze closed-session pricing; retain 20 unsaved records with permanent promotion.
- Add Lua 5.1 unit/mocked integration tests, CI, reproducible install ZIP, and a pending live-client checklist.
