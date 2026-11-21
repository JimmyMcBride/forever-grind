# Forever Grind

Native XP-bar projections, recorded farming routes, mob history, and a compact session tracker for **WoW Forever 1.60.1.70959, interface 16001**. Original, dependency-free Lua 5.1 addon. Auctionator and TomTom are optional. No dependency on Grinding Made Simple or Questie.

Version **0.2.0 is a preview**. Automated and mocked integration checks pass; actual game behavior still needs the [in-game checklist](docs/IN_GAME_TESTING.md).

## Install

Extract the generated ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. The resulting path must be `AddOns/ForeverGrind/ForeverGrind.toc`. Restart the game when installing a new addon, then enable **Forever Grind** in AddOns. An existing installation can use `/reload` after updating its files.

Disable Grinding Made Simple's duplicate display if you use it. Enable Blizzard's native XP bar in any UI addon that hides it. Forever Grind keeps tracking when the bar is unavailable or you are level capped; it does not create a replacement XP bar.

Run `/fg` for the journal and `/fg settings` for Blizzard's AddOns settings. The compact strip starts at the top center. Drag its background to move it; position, scale, and lock are saved account-wide. Settings also offer a position reset.

## XP bar

Blizzard's status-tracking manager supplies the existing XP bar. Forever Grind adds current/required XP and percentage. During a running session it also shows **Level in n hours and x minutes**, using XP remaining divided by the session's XP earned per active second. Completed but unturned-in quests are not subtracted from XP remaining. The estimate rounds up to the next minute and appears once the session has both earned XP and active time; paused/stopped/armed sessions show no ETA.

Text shortens to fit. Completed-quest totals, projected percentage, partial-data status, and level-ready overflow appear in the tooltip rather than cluttering the bar text. The gold overlay begins at current progress and clips at the level boundary; it does not estimate a next-level percentage.

Projection updates even while sessions are armed, stopped, or paused. Uncached quest rewards are requested asynchronously and marked partial until available. Native position, rested-XP region, animations, and tooltip handlers remain in place. Hidden/replaced bars and reputation-only displays leave session tracking available.

## Sessions

The strip has fixed columns for **XP/hour · estimated gold/hour · active time**, plus Play/Pause, Stop, Save, Log, and settings controls. Hover shows totals, estimates, pending items, and the best AH candidates. The journal's Current tab shows the full live item ledger.

- First launch is **armed**. Your first confirmed credited kill starts tracking and includes that kill's XP, or starts with zero XP for a confirmed grey-mob kill. If no usable kill event arrives, receiving an item or coin from a confirmed corpse starts tracking at receipt. Empty corpses do not start it.
- Running time includes travel, downtime, and deaths. XP includes combat, quests, and exploration/other gains. Gathering and confirmed quest rewards count while running.
- Pause excludes time and gains. Play resumes a paused session immediately. Logout/reload preserves an unfinished session **paused**; it never silently resumes.
- Stop puts a closed session in **Unsaved**, retaining the latest 20 account-wide across logouts. The 21st evicts the oldest permanently. Play then arms a fresh session.
- Save closes directly into Saved. Keep promotes an Unsaved record without changing its timestamps, coordinates, duration, or estimates. Saved records remain until deleted with confirmation. Cancelling an armed session creates no log.

Commands: `/fg play`, `/fg pause`, `/fg stop`, `/fg save`, `/fg settings`.

The journal filters character, realm, starting/ending level range, and location. Click XP/hour, estimated gold/hour, vendor-baseline/hour, or active-time headings to sort. Selecting a session opens a full-width report with its name, character/realm, location, and status. Four headline figures stay visible: XP/hour, estimated gold/hour, active time, and total XP.

- **Overview:** aligned XP sources, an additive earnings breakdown, a separate vendor-only comparison, and data-status warnings. The comparison baseline is an alternative to AH estimates, not extra income.
- **Loot:** item rows show quantity, vendor/AH recommendation, estimated value, and AH advantage. Select a row for source, vendor value, quote age, and the recommendation reason. Hover an item for its native tooltip.
- **Session details:** timestamps, levels, start/stop coordinates, active/paused time, wrapped notes, pricing assumptions, and visited zones sorted by active time.
- **Route:** native map artwork, your traveled path, kill clusters, and a selectable/sortable mob table with counts, kills/hour, and confidently assigned combat XP.

The report keeps name/notes editing, Keep, and confirmed Delete controls available. **Back to sessions** restores the same history tab, filters, sort order, and page. Live updates preserve scrolling and unfinished edits. Opening a different session resets to Overview and the top of the report.

Start and stop/save locations include map ID, zone, subzone, and available coordinates. Missing coordinates say **unavailable**, never `(0, 0)`. Paused duration includes the offline pause; offline time never enters hourly rates.

## Routes and mobs

Open a session's **Route** tab to revisit its movement and kills. The blue line is your sampled travel; gold dots are **your position when a kill was recorded**, not enemy corpse or spawn coordinates. Green S and blue E mark mapped endpoints (S/E when they coincide). Direction arrows show travel order. Stationary farming adds kills without duplicate movement points.

Use **< / >** beside the map name to select a visited map/floor, **Fit** to frame that route, the mouse wheel to zoom, and left-drag to pan. **Route / Kills / Ends** buttons independently show or hide those layers. Nearby kills cluster within 24 screen pixels; hover for counts, mob breakdown, and active-time range. Click a cluster to zoom, or right-click for navigation.

The mob table sorts by name, count, kills/hour, or combat XP; its default is count descending. Click a row to highlight that mob's clusters and dim other kills; **All mobs** clears the filter. XP that could not confidently be assigned stays in **Unassigned combat XP**. Session XP, quest XP, loot estimates, and frozen prices remain independent of map attribution.

**World map** opens Blizzard's normal map with one selected-session overlay and its own Hide control. Standard map interactions and other addons' pins remain in place. Clicking a recorded point opens **Set native waypoint** and, if installed, **Navigate with TomTom**. Navigation is explicit: recording never creates waypoints automatically. Native pins require an eligible map. TomTom waypoints are nonpersistent, and replacement removes only the waypoint this addon created.

Movement is sampled every two seconds after at least five yards of movement when map dimensions are available. Missing distance data uses coordinate changes with an explanatory notice. Pauses, offline travel, map/floor transitions, loading/teleports, missing coordinates, and jumps over 100 yards/second break the line. Routes are sampled approximations, not every step you took. Hover the capture notice below the map for missing-location and coverage details.

Kill evidence combines localized named XP notifications with readable native `PARTY_KILL` GUIDs from you, your current party/raid, and pets. Nearby `UNIT_DIED` events alone do not count a kill, nor does each looted item/corpse. Names come from readable GUID lookup or observed target/nameplate identities. Unknown creatures retain their NPC ID when available. Repeated GUIDs/chat IDs are deduplicated, with two-second, one-to-one matching for name/GUID reports. Ambiguous identities conservatively suppress possible duplicates and show a notice; their counts or per-mob XP can be incomplete. Restricted or unreported kills cannot be guaranteed. No restricted combat-log events are registered.

Routes belong to their sessions: Stop/Save closes them, Keep preserves them, and deletion or 21st-entry eviction removes them. Existing closed sessions say **Route and mob history were not recorded**. A pre-update unfinished session resumes with an explicit partial-history notice. Saved route data grows with the sessions you retain. A combined account-wide kill atlas, heatmaps, comparisons, automatic route following, and per-mob loot-value attribution are outside this version.

## Loot estimates

The ledger retains original earned quantities after you sell, bank, or discard them. It counts self-looted drops, gathering/container loot, confirmed quest items (fixed rewards and the selected choice), corpse coin, and quest gold. Purchases, trades, mail, crafting, and sale revenue are excluded. It does not infer income from bag or wallet deltas.

| Total | Meaning |
| --- | --- |
| Vendor-everything baseline | Vendor value of every acquired item |
| Vendor-route value | Vendor value of items not assigned to AH |
| Estimated AH proceeds | AH-assigned quantities at cached prices, after configured cut |
| Projected total | Looted coin + quest gold + vendor-route value + estimated AH proceeds |

Headline estimated gold/hour divides projected total by active time. Vendor-baseline/hour includes coin, quest gold, and the vendor-everything baseline, allowing comparisons without AH-price differences. The baseline is never added on top of AH proceeds.

Auctionator integration defaults on when available. Settings default to a **5% estimated cut** and **7-day maximum quote age**, both adjustable. Only its supported external v1 API is used: cached item-link prices, age in days, and database-update callbacks. No scans, listings, or auctions are initiated.

Unbound, auctionable items are recommended for AH only when proceeds after cut exceed vendor value. Missing/stale/unusable quotes fall back to vendor with a reason. Unknown receipt binding stays conservative; mixed bound/unbound copies in your bags may need vendor fallback. Item details sort by estimated advantage and show quantity, quote age, and recommendation reason. Without Auctionator, values use coin plus vendor estimates.

Unknown item metadata is explicitly pending, not confirmed zero value. An item with known vendor value zero is distinct from an unpriced item. Unfinished sessions revalue on cached database updates; quote ages advance with time. Closing freezes cached quotes, missing quotes, and pricing settings. Late item metadata may finish pending values, but never fetches newer AH prices for history.

All gold figures are **estimates**, not sales or realized profit. Deposits, failed listings, expenses, and actual sale outcomes are outside this valuation. Quest capture uses a successful turn-in plus its observed reward offer/choice and ignores generic pushed-item messages to prevent duplicates. Turn-ins that bypass Blizzard's offer can leave reward items incomplete; the session shows a warning. Verify your quest automation using the checklist.

## Development

Install Lua 5.1, `luac5.1`, and Python 3, then run:

```sh
python3 tools/check.py
python3 tools/package.py
```

The package is `dist/ForeverGrind-0.2.0.zip`, containing one `ForeverGrind/` directory. CI runs the same checks on pushes and pull requests. Tests exercise pure calculations and a mocked client; they do not prove live-client API timing, taint safety, locale behavior, or visual appearance. `python3 tools/assets.py` regenerates the original map-dot texture; checks verify its exact reproduction.

Modules: `Session.lua` state machine; `Parsing.lua` localized notifications/XP deltas; `Collector.lua` single acquisition pipeline; `Valuation.lua` estimates; `Util.lua` storage/helpers; `Route.lua` movement and pure map calculations; `Kills.lua` identity/correlation and per-mob XP; `Map.lua` artwork, pooled rendering and optional navigation; `XPBar.lua` native attachment; `UI.lua` strip/settings/journal list; `Report.lua` structured session reports; `Core.lua` client event/API bridge. Visible timers/maps refresh at most twice per second, with immediate responses to user controls. Inventory checks are acquisition/bag-event driven, not continuous scans.

Saved data: `ForeverGrindDB` contains versioned settings and shared history; `ForeverGrindCharacterDB` contains this character's unfinished session and armed/stopped state. Both migrate from schema 1 to **2**, retaining settings, history, prices, and unfinished sessions. GUID/chat deduplication persists for unfinished sessions; reload still pauses recording. Back up SavedVariables before testing previews. Future schema versions are rejected rather than silently downgraded; older addon versions cannot open schema 2.

Primary integration references: [Forever Blizzard UI source](https://github.com/Gethe/wow-ui-source/tree/forever), [Auctionator external API](https://github.com/Auctionator/Auctionator/tree/master/Source/API).
