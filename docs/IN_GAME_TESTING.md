# Live-client verification

Target: Forever **1.60.1.70959**, interface **16001**. Every checkbox below is **pending**. Automated checks are not live-game results. Record date, character/locale, build, other UI addons, steps, actual result, and any Lua/blocked-action warnings when testing.

## Native XP bar

- [ ] Current/required XP, completed-quest rewards, percentage, partial data, and tooltip values agree with the quest log.
- [ ] Complete/remove/turn in quests; uncached rewards resolve asynchronously without changing the selected quest or map.
- [ ] Resize native bar; narrow text fits; gold projection covers only current-to-projected progress and clips correctly.
- [ ] Cross a level with ready rewards; level-ready overflow refers to the current requirement only.
- [ ] Rested region, native animations, mouse behavior, and native tooltip content remain functional.
- [ ] Switch to reputation, hide/replace XP bar, and test level cap; strip remains functional and explains unavailable enhancement.
- [ ] Toggle XP text and projection; native text restores; reload retains settings.

## Acquisition and time

- [ ] First solo and group credited kill starts armed session; include full first-kill XP, including rested/bonus XP.
- [ ] Verify localized kill/loot/money messages in the installed locale.
- [ ] First confirmed grey-mob corpse item or coin starts at receipt; empty corpse does not. Test manual and auto loot, delayed looting, multiple corpses, full bags, and failed acquisition.
- [ ] Running session counts exploration and quest XP separately from combat. Cross a level; check actual delta.
- [ ] Gather herb/ore, loot container, receive stack quantities; source and total quantities match receipts.
- [ ] Confirm fixed and selected quest rewards only; test single/multiple choices, currency choices, and quest automation. No duplicate pushed-item reward, coin, or XP accounting.
- [ ] Buy, trade, receive mail, craft, sell, bank, discard, and loot again: only new eligible acquisitions increase the ledger.
- [ ] Pause around loot/XP events; no late callbacks enter a fresh session. Resume includes new gains only.
- [ ] Logout and reload while running/armed/paused/stopped; unfinished sessions remain paused and inactive observations are rebaselined.
- [ ] Travel, wait, die, pause, and return after offline time; active rates exclude only armed/paused/offline intervals.

## Valuation and journal

- [ ] Auctionator absent, disabled, no quote, old quote, unknown age, and database update cases explain vendor fallback without errors.
- [ ] Available quotes use correct link/variant, quantity, 5% cut, age, and upside; never recommend bound items. Test mixed bound/unbound copies and bag update timing.
- [ ] Request uncached item information; pending quantities resolve against the original session even after stop/new session.
- [ ] Stop/save, then update AH database/change cut/age; history retains quotes/settings, including originally missing quotes. Unfinished session revalues.
- [ ] Manually verify vendor baseline, vendor route, AH proceeds, projected total, and both hourly comparisons against a small known ledger.
- [ ] Save vs Stop, name/notes edits, sorting, filters, temporary promotion, deletion confirmation, and 21st-entry eviction across reloads.
- [ ] Compare two characters/realms: shared history, independent unfinished sessions, persistent strip settings.
- [ ] Verify start/end map, zone, subzone, coordinates, visited-zone times; unavailable map coordinates say unavailable.
- [ ] Move/lock/scale/reset strip, test UI scale/small screens, native Settings scrolling, tooltips, journal navigation, and ESC.
- [ ] Inspect Lua errors and blocked-action/taint warnings during combat and out of combat with normal UI addons.

No game-client results have been recorded for this preview.
