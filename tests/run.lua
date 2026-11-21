local H = assert(loadfile("tests/helpers.lua"))()
local passed, failed = 0, 0
local function eq(a, b) assert(a == b, "Expected " .. tostring(b) .. "; got " .. tostring(a)) end
local function near(a, b) assert(math.abs(a - b) < 0.0001, "Expected " .. tostring(b) .. "; got " .. tostring(a)) end
local function test(name, run)
    local ok, err = pcall(run)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. err) end
end

test("fresh settings arm automatically; stopped state survives reload", function()
    local w = H.world()
    eq(w.character.mode, "armed"); eq(w.db.settings.ahCut, 5); eq(w.db.settings.maxPriceAge, 7)
    w.model:Stop(false, w.now, w.epoch, w.context)
    eq(#w.db.temporary, 0)
    eq(H.world(w.db, w.character).character.mode, "stopped")
end)

test("active time excludes armed waiting", function()
    local w = H.world(); w:advance(1000)
    local record = w:start(); w:advance(60)
    near(record.active, 60); eq(record.xp.combat, 100)
end)

test("pause and logout preserve run and exclude offline time and gains", function()
    local w = H.world(); local record = w:start(); w:advance(10)
    w.model:Pause(w.now, w.epoch, w.context.location)
    w.model:XP(500, "other"); w.model:Coin(500, "loot"); eq(w.model:Item("item:1", 1, "loot"), nil)
    local resumed = H.world(w.db, w.character); eq(resumed.character.mode, "paused")
    resumed.epoch = w.epoch + 3600
    resumed.model:Play(resumed.now, resumed.epoch, resumed.context.location)
    resumed:advance(20)
    near(record.active, 30); near(record.paused, 3600); eq(record.xp.combat, 100); eq(record.coin.loot, 0)
end)

test("stop creates temporary log and no automatic restart", function()
    local w = H.world(); w:start(); local record = w:stop(false)
    eq(w.db.temporary[1], record); eq(#w.db.saved, 0)
    w.collector:Kill("Boar dies, you gain 100 experience."); w.collector:Flush()
    eq(w.character.mode, "stopped"); eq(w.character.current, nil)
    w.model:Play(w.now, w.epoch, w.context.location); eq(w.character.mode, "armed")
end)

test("save closes straight to permanent history", function()
    local w = H.world(); w:start(); local r = w:stop(true)
    eq(w.db.saved[1], r); eq(#w.db.temporary, 0); eq(w.character.mode, "stopped")
end)

test("temporary retention evicts oldest at 21 and promotion retains snapshot", function()
    local w = H.world(); local first
    for i = 1, 21 do
        w.model:Play(w.now, w.epoch, w.context.location)
        w:start(); local r = w:stop(false); if i == 1 then first = r.id end
    end
    eq(#w.db.temporary, 20); assert(w.db.temporary[1].id ~= first)
    local original = w.db.temporary[1]; local endpoint = original.endLocation
    w.context.location.x = 0.9
    eq(w.model:Promote(original.id), original); eq(original.endLocation, endpoint)
    near(endpoint.x, 0.25); eq(#w.db.temporary, 19); eq(w.db.saved[1], original)
end)

test("shared journal has independent character current sessions", function()
    local w = H.world(); local a = w:start(); w:stop(true)
    local other = H.world(w.db, {}); other.context.character = "Other"; local b = other:start()
    eq(#other.db.saved, 1); assert(a.id ~= b.id); eq(w.character.current, nil); eq(b.character, "Other")
end)

test("coordinates copied at stop and active time split by zone", function()
    local w = H.world(); local r = w:start(); w:advance(10)
    w.context.location = { zone = "Hills", mapID = 2, x = 0.4, y = 0.6 }
    w.model:Tick(w.now, w.context.location); w:advance(20); w:stop(false)
    near(r.startLocation.x, 0.25); near(r.endLocation.x, 0.4)
    near(r.zones["1:Forest"].seconds, 10); near(r.zones["2:Hills"].seconds, 20)
    assert(w.FG.LocationText({ zone = "Dungeon" }):find("unavailable"))
end)

test("localized positional formats and numeric grouping parse", function()
    local P = H.pure().Parsing
    local values = P.Match("Beute: %2$dx %1$s!", "Beute: 1,234x item:1!")
    eq(values[1], "item:1"); eq(values[2], 1234)
    eq(P.KillXP("You gain 100 experience.", H.globals), nil)
    eq(P.KillXP("Boar dies, you gain 100 experience.", H.globals), 100)
end)

test("loot parser excludes pushed, crafted, and other-player messages", function()
    local P = H.pure().Parsing
    local link, quantity = P.Item("You receive loot: item:1x12.", H.globals)
    eq(link, "item:1"); eq(quantity, 12)
    eq(P.Item("You receive item: item:1.", H.globals), nil)
    eq(P.Item("You create: item:1.", H.globals), nil)
    eq(P.Item("Other receives loot: item:1.", H.globals), nil)
end)

test("rested and grouped kill formats start sessions; unnamed quest bonus does not", function()
    local P = H.pure().Parsing
    eq(P.KillXP("Boar dies, you gain 200 experience. (100 exp Rested bonus)", H.globals), 200)
    eq(P.KillXP("Boar dies, you gain 220 experience. (100 exp Rested bonus, +20 group bonus)", H.globals), 220)
    eq(P.KillXP("You gain 100 experience. (10 exp bonus bonus)", H.globals), nil)
    local w = H.world()
    w.collector:Kill("Boar dies, you gain 200 experience. (100 exp Rested bonus)")
    w.xp.xp = 300; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush()
    eq(w.character.current.xp.combat, 200)
end)

test("money parser separates coin denominations and rejects unrelated income", function()
    local P = H.pure().Parsing
    eq(P.Money("You loot 1 Gold 2 Silver 3 Copper.", H.globals), 10203)
    eq(P.Money("Your share of the loot is 2 Silver 5 Copper.", H.globals), 205)
    eq(P.Money("You receive 100 Gold from a sale.", H.globals), nil)
end)

for _, order in ipairs({ "xp-first", "kill-first" }) do
    test("first kill XP counted exactly once: " .. order, function()
        local w = H.world(); w.xp.xp = 200
        if order == "xp-first" then w.collector:ObserveXP(w.FG.Copy(w.xp)) end
        w.collector:Kill("Boar dies, you gain 100 experience.")
        if order == "kill-first" then w.collector:ObserveXP(w.FG.Copy(w.xp)) end
        w.collector:Flush(); eq(w.character.current.xp.combat, 100)
        w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush(); eq(w.character.current.xp.combat, 100)
    end)
end

test("zero-XP corpse receipt starts and includes first item", function()
    local w = H.world(); w.collector:Loot("You receive loot: item:1x2.", 1); w.collector:Flush()
    eq(w.character.mode, "running"); eq(w.character.current.items["item:1:loot"].quantity, 2)
end)

test("gathering or quests alone do not start an armed run", function()
    local w = H.world(); w.origin = "gathering"
    w.collector:Loot("You receive loot: item:1.", 1)
    w.collector:Queue({ kind = "quest", id = 1, xp = 100, money = 50 })
    w.xp.xp = 200; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush()
    eq(w.character.mode, "armed"); eq(w.character.current, nil)
end)

test("deduplication keeps distinct identical loot acquisitions", function()
    local w = H.world(); w:start()
    w.collector:Loot("You receive loot: item:1.", 1); w.collector:Loot("You receive loot: item:1.", 1)
    w.collector:Loot("You receive loot: item:1.", 2); w.collector:Flush()
    eq(w.character.current.items["item:1:loot"].quantity, 2)
end)

test("quest confirmation counts only fixed and selected rewards once", function()
    local w = H.world(); w:start()
    w.collector:Offer({ id = 5, rewards = { { link = "item:1", quantity = 2 } },
        choices = { { link = "item:2", quantity = 1 }, { link = "item:3", quantity = 1 } } })
    w.collector:Choice(2)
    w.collector:Queue({ kind = "quest", id = 5, xp = 200, money = 500 })
    w.collector:Queue({ kind = "quest", id = 5, xp = 200, money = 500 })
    w.collector:Loot("You receive item: item:3.", 50)
    w.xp.xp = 400; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush()
    local r = w.character.current
    eq(r.items["item:1:quest"].quantity, 2); eq(r.items["item:3:quest"].quantity, 1)
    eq(r.items["item:2:quest"], nil); eq(r.coin.quest, 500); eq(r.xp.quest, 200)
end)

test("separate active XP sources reconcile with unit-XP total", function()
    local w = H.world(); local r = w:start()
    w.collector:Queue({ kind = "quest", id = 6, xp = 200, money = 0 })
    w.collector:Kill("Boar dies, you gain 50 experience.")
    w.xp.xp = 450; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush()
    eq(r.xp.quest, 200); eq(r.xp.combat, 150); eq(r.xp.other, 0)
    w.xp.xp = 500; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush(); eq(r.xp.other, 50)
end)

test("level rollover and multi-level quest grants preserve XP", function()
    local w = H.world(); local r = w:start()
    w.collector.previousXP = { xp = 900, maximum = 1000, level = 10 }
    w.xp = { xp = 100, maximum = 1200, level = 11 }
    w.collector:Queue({ kind = "quest", id = 1, xp = 200, money = 0 })
    w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush(); eq(r.xp.quest, 200)
    w.collector:Queue({ kind = "quest", id = 2, xp = 3000, money = 0 })
    w.xp = { xp = 100, maximum = 1600, level = 13 }
    w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush(); eq(r.xp.quest, 3200)
end)

test("source notification before a delayed XP event is not counted twice", function()
    local w = H.world(); local r = w:start()
    w.collector:Kill("Boar dies, you gain 50 experience."); w.collector:Flush(); eq(r.xp.combat, 100)
    w.xp.xp = 250; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush(); eq(r.xp.combat, 150)
end)

test("old scheduled callback cannot prematurely flush next session", function()
    local w = H.world(); w:start(); local old = w.timers[1]
    w:stop(false); w.model:Play(w.now, w.epoch, w.context.location)
    w.collector:Kill("Boar dies, you gain 100 experience.")
    old(); eq(w.character.current, nil)
    w.collector:Flush(); eq(w.character.mode, "running")
end)

test("valuation separates baseline, vendor route, AH proceeds and coin", function()
    local w = H.world(); local r = w:start(); r.active = 3600
    r.items = { a = { link = "item:1", quantity = 10, source = "loot", vendor = 100, auctionable = true,
        liveQuote = { price = 1000, age = 1 } }, b = { link = "item:2", quantity = 4, source = "quest", vendor = 50, auctionable = false } }
    r.coin = { loot = 80, quest = 20 }
    local t = w.FG.Value.Total(r, w.db.settings, function(e) return e.liveQuote end)
    eq(t.baseline, 1200); eq(t.vendor, 200); eq(t.ah, 9500); eq(t.projected, 9800)
    eq(t.goldHour, 9800); eq(t.vendorHour, 1300); eq(t.rows[1].value.upside, 8500)
end)

test("bound items, stale/absent quotes, unknown age, and ties use vendor route", function()
    local w = H.world(); local V = w.FG.Value
    local entry = { quantity = 2, vendor = 95, auctionable = true }
    eq(V.Item(entry, w.db.settings, { price = 100, age = 1 }).route, "vendor")
    eq(V.Item(entry, w.db.settings, { price = 1000, age = 8 }).route, "vendor")
    eq(V.Item(entry, w.db.settings, { price = 1000 }).route, "vendor")
    eq(V.Item(entry, w.db.settings, nil).route, "vendor")
    entry.auctionable = false; eq(V.Item(entry, w.db.settings, { price = 1000, age = 1 }).route, "vendor")
    entry.vendor = nil; eq(V.Item(entry, w.db.settings, nil).pending, 2)
end)

test("integration off uses vendor values; successful AH sale never adds baseline twice", function()
    local w = H.world(); local r = w:start()
    r.items.a = { link = "item:1", quantity = 1, source = "loot", vendor = 100, auctionable = true }
    w.db.settings.auctionator = false
    local t = w.FG.Value.Total(r, w.db.settings, function() return { price = 1000, age = 0 } end)
    eq(t.projected, 100); eq(t.ah, 0)
end)

test("closed records never fetch newer quotes, even when closing quote was missing", function()
    local w = H.world(); local r = w:start()
    r.items.a = { link = "item:1", quantity = 1, source = "loot", vendor = 10, auctionable = true }
    w:stop(false)
    local t = w.FG.Value.Total(r, { auctionator = true, ahCut = 0, maxPriceAge = 100 }, function() error("Fetched newer quote") end)
    eq(t.projected, 10); eq(r.pricing.ahCut, 5)
end)

test("late metadata completes frozen estimates without mutating new run", function()
    local w = H.world(); local r = w:start()
    r.items.a = { link = "item:1", quantity = 2, source = "loot", liveQuote = { price = 100, age = 1 } }
    w:stop(false); w.model:Play(w.now, w.epoch, w.context.location); local nextRun = w:start()
    r.items.a.vendor, r.items.a.auctionable = 10, true
    local t = w.FG.Value.Total(r, w.db.settings, function() error("Fetched later price") end)
    eq(t.projected, 190); eq(next(nextRun.items), nil)
end)

test("XP projection clips at boundary and exposes overflow", function()
    local X = H.pure().XPBar
    local p = X.Project(700, 1000, 500)
    near(p.start, 0.7); near(p.length, 0.3); eq(p.overflow, 200); eq(p.percent, 120)
    eq(X.Project(0, 0, 100).length, 0)
end)

test("journal filters character realm level and precise location", function()
    local w = H.world(); local r = w:start(); w:stop(false)
    local f = { character = "test", realm = "realm", minimum = "9", maximum = "11", location = "25.0" }
    eq(w.FG.UI.Filter(r, f), true); f.maximum = "8"; eq(w.FG.UI.Filter(r, f), false)
end)

test("native addon boots with compact controls, native settings and slash command", function()
    local w = H.native()
    eq(w.FG.character.mode, "armed"); eq(w.env.SLASH_FOREVERGRIND1, "/fg")
    eq(w.FG.UI.strip:GetWidth(), 572); eq(w.FG.UI.save.enabled, false)
    w.env.SlashCmdList.FOREVERGRIND("settings"); eq(w.opened, 42)
    w.env.SlashCmdList.FOREVERGRIND(""); eq(w.FG.UI.journal:IsShown(), true)
end)

test("native first kill, play/pause/stop/save controls and shared journal work", function()
    local w = H.native(); local r = w:start(); w:advance(2)
    eq(r.xp.combat, 100); assert(r.active >= 2)
    w.FG.Action("pause"); local active = r.active; w:advance(5); near(r.active, active)
    w.FG.Action("play"); w:advance(1); w.FG.Action("save")
    eq(w.FG.db.saved[1], r); eq(w.FG.character.mode, "stopped"); eq(w.FG.UI.tab, "saved")
    w.FG.UI.OpenJournal(); w.FG.UI.Select(r); w.FG.UI.RefreshJournal()
    assert(w.FG.UI.report.location:GetText():find("25.0, 75.0", 1, true))
end)

test("corpse evidence survives auto-loot empty opening and starts on receipt only", function()
    local w = H.native()
    w.loot = { { link = "item:1", quantity = 2, source = "Creature-0-1" } }
    w:emit("LOOT_READY"); eq(w.FG.character.mode, "armed")
    w.loot = {}; w:emit("LOOT_OPENED")
    w:chat("CHAT_MSG_LOOT", "You receive loot: item:1x2.", 11); w:advance(0.1)
    eq(w.FG.character.mode, "running")
    eq(w.FG.character.current.items["item:1:loot"].quantity, 2)
end)

test("loot window with no receipt and pushed purchases do not start a run", function()
    local w = H.native(); w.loot = { { link = "item:1", quantity = 1, source = "Creature-0-1" } }
    w:emit("LOOT_READY"); w:chat("CHAT_MSG_LOOT", "You receive item: item:1.", 12)
    w:advance(1); eq(w.FG.character.mode, "armed")
end)

test("native quest reward selection is observed without collecting other choices", function()
    local w = H.native(); local r = w:start()
    w.offer = { id = 42, rewards = { { link = "item:1", quantity = 1 } },
        choices = { { link = "item:2", quantity = 1 }, { link = "item:3", quantity = 1 } } }
    w:emit("QUEST_COMPLETE"); w.env.GetQuestReward(2)
    w:emit("QUEST_TURNED_IN", 42, 200, 300); w.xp = 400; w:emit("PLAYER_XP_UPDATE", "player"); w:advance(0.1)
    eq(r.coin.quest, 300); eq(r.xp.quest, 200); eq(r.items["item:2:quest"], nil)
    eq(r.items["item:3:quest"].quantity, 1)
end)

test("native XP attachment resizes overlay, preserves rested region and restores text", function()
    local w = H.native()
    w.quests = { { id = 5, complete = true, known = true, xp = 300 } }
    w:emit("QUEST_LOG_UPDATE"); w:advance(0.6)
    local state = w.FG.XPBar.attached[w.bar]
    near(state.fill.width, 150)
    local rest = w.bar.ExhaustionLevelFillBar
    w.bar.StatusBar.width = 1000; w.bar.StatusBar.scripts.OnSizeChanged()
    near(state.fill.width, 300); eq(w.bar.ExhaustionLevelFillBar, rest)
    eq(w.bar.OverlayFrame.Text:GetText(), "100 / 1000 XP (10.0%)")
    w.FG.db.settings.xpText = false; w.FG.XPBar:Refresh()
    eq(w.bar.OverlayFrame.Text:GetText(), "Native XP"); eq(w.bar.OverlayFrame.Text:IsShown(), false)
end)

test("quest data requests show partial projection and resolve independently of session", function()
    local w = H.native(); w.quests = { { id = 9, complete = true, known = false, xp = 500 } }
    w:emit("QUEST_LOG_UPDATE"); eq(w.FG.XPBar.missing, 1); eq(w.requests.quest9, true)
    w.quests[1].known = true; w:emit("QUEST_DATA_LOAD_RESULT", 9, true)
    eq(w.FG.XPBar.questXP, 500); eq(w.FG.XPBar.missing, 0); eq(w.FG.character.current, nil)
end)

test("reputation switching and hidden XP bars never get forced shown", function()
    local w = H.native(); w.bar.shown = false; w:advance(0.6)
    eq(w.bar.shown, false); assert(w.FG.XPBar.status:find("unavailable")); eq(w.FG.UI.strip:IsShown(), true)
end)

test("Auctionator absent falls back and scan updates reprice only unfinished records", function()
    local w = H.native({ auctionator = true }); local r = w:start()
    w.quotes["item:1"] = { price = 100, age = 1 }
    w:chat("CHAT_MSG_LOOT", "You receive loot: item:1x2.", 20); w:advance(0.1)
    eq(w.FG.Totals(r).ah, 190)
    w.FG.Action("stop"); w.quotes["item:1"] = { price = 10000, age = 0 }; w.priceUpdate()
    eq(w.FG.Totals(r).ah, 190)
    local noAPI = H.native(); local r2 = noAPI:start()
    noAPI:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 21); noAPI:advance(0.1)
    eq(noAPI.FG.Totals(r2).projected, 10)
end)

test("metadata callback after stop retains captured quote and correct session ownership", function()
    local w = H.native({ auctionator = true }); w.items[1] = nil; w.quotes["item:1"] = { price = 100, age = 1 }
    local r = w:start(); w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 22); w:advance(0.1)
    eq(w.FG.Totals(r).pending, 1); w.FG.Action("stop")
    w.FG.Action("play"); local nextRun = w:start()
    w.items[1] = { vendor = 10, binding = 0 }; w.quotes["item:1"] = { price = 10000, age = 0 }
    w:emit("GET_ITEM_INFO_RECEIVED", 1, true)
    eq(w.FG.Totals(r).projected, 95); eq(next(nextRun.items), nil)
end)

test("logout pauses without saving or losing current record", function()
    local w = H.native(); local r = w:start(); w:advance(1); w:emit("PLAYER_LOGOUT")
    eq(w.FG.character.mode, "paused"); eq(w.FG.character.current, r)
    eq(#w.FG.db.saved, 0); eq(#w.FG.db.temporary, 0)
end)

test("paused native XP and loot gains stay excluded after resuming", function()
    local w = H.native(); local r = w:start(); w.FG.Action("pause")
    w.xp = 700; w:emit("PLAYER_XP_UPDATE", "player")
    w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 90); w:advance(1)
    w.FG.Action("play"); w.xp = 710; w:emit("PLAYER_XP_UPDATE", "player"); w:advance(0.1)
    eq(r.xp.combat, 100); eq(r.xp.other, 10); eq(next(r.items), nil)
end)

test("coin-only corpse loot starts zero-XP farming and includes that coin", function()
    local w = H.native(); w.loot = { { kind = 2, quantity = 203, source = "Creature-0-1" } }
    w:emit("LOOT_READY"); w:chat("CHAT_MSG_MONEY", "You loot 2 Silver 3 Copper.", 91); w:advance(0.1)
    eq(w.FG.character.mode, "running"); eq(w.FG.character.current.coin.loot, 203)
end)

test("manual loot remains attributable while window stays open", function()
    local w = H.native(); w.loot = { { link = "item:1", quantity = 1, source = "Creature-0-1" } }
    w:emit("LOOT_READY"); w:advance(20)
    w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 92); w:advance(0.1)
    eq(w.FG.character.mode, "running")
end)

test("expired corpse evidence cannot start on unrelated later loot", function()
    local w = H.native(); w.loot = { { link = "item:1", quantity = 1, source = "Creature-0-1" } }
    w:emit("LOOT_READY"); w:emit("LOOT_CLOSED"); w:advance(2)
    w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 93); w:advance(0.1)
    eq(w.FG.character.mode, "armed")
end)

test("bag update resolves receipt binding without continuous bag scanning", function()
    local w = H.native({ auctionator = true }); w.bags = {}; w.quotes["item:1"] = { price = 100, age = 1 }
    local r = w:start(); w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 94); w:advance(0.1)
    eq(w.FG.Totals(r).ah, 0)
    w.bags = { { itemID = 1, isBound = false } }; w:emit("BAG_UPDATE_DELAYED")
    eq(w.FG.Totals(r).ah, 95)
end)

test("mixed bound and unbound copies use conservative vendor fallback", function()
    local w = H.native({ auctionator = true })
    w.bags = { { itemID = 1, isBound = true }, { itemID = 1, isBound = false } }
    w.quotes["item:1"] = { price = 100, age = 1 }
    local r = w:start(); w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 95); w:advance(0.1)
    local t = w.FG.Totals(r)
    eq(t.ah, 0); assert(t.rows[1].value.reason:find("unknown"))
end)

test("quest XP before first kill is excluded despite same-frame event ordering", function()
    local w = H.world()
    w.collector:Queue({ kind = "quest", id = 10, xp = 200, money = 500 })
    w.collector:Queue({ kind = "quest", id = 10, xp = 200, money = 500 })
    w.xp.xp = 300; w.collector:ObserveXP(w.FG.Copy(w.xp))
    w.collector:Kill("Boar dies, you gain 100 experience.")
    w.xp.xp = 400; w.collector:ObserveXP(w.FG.Copy(w.xp)); w.collector:Flush()
    eq(w.character.current.xp.combat, 100); eq(w.character.current.xp.quest, 0); eq(w.character.current.coin.quest, 0)
end)

test("confirmed quest offer cannot award items or money twice across batches", function()
    local w = H.world(); local r = w:start()
    w.collector:Offer({ id = 5, rewards = { { link = "item:1", quantity = 1 } }, choices = {} })
    w.collector:Queue({ kind = "quest", id = 5, xp = 0, money = 100 }); w.collector:Flush()
    w.collector:Queue({ kind = "quest", id = 5, xp = 0, money = 100 }); w.collector:Flush()
    eq(r.coin.quest, 100); eq(r.items["item:1:quest"].quantity, 1)
end)

test("future saved-data version is rejected without downgrading it", function()
    local FG = H.pure(); local db = { version = 3 }
    local ok = pcall(FG.InitializeDB, db, {})
    eq(ok, false); eq(db.version, 3)
end)

test("unknown map coordinates stay unavailable and compact XP text adapts", function()
    local w = H.native(); w.noCoords = true
    eq(w.FG.Context().location.x, nil)
    w.bar.StatusBar.width = 80; w.FG.XPBar:Refresh()
    assert(w.bar.OverlayFrame.Text:GetStringWidth() < 80)
end)

test("temporary journal promotion and captured deletion target retain integrity", function()
    local w = H.native(); local r = w:start(); w.FG.Action("stop")
    w.FG.UI.OpenJournal(); w.FG.UI.tab = "temporary"; w.FG.UI.Select(r); w.FG.UI.RefreshJournal()
    w.FG.UI.promote.scripts.OnClick()
    eq(w.FG.db.saved[1], r); eq(#w.FG.db.temporary, 0)
    w.FG.UI.delete.scripts.OnClick()
    w.FG.UI.Select(nil)
    w.env.StaticPopupDialogs[w.popup.key].OnAccept(nil, w.popup.data)
    eq(#w.FG.db.saved, 0)
end)

test("cached quote ages while unfinished and freezes its age at closing", function()
    local w = H.native({ auctionator = true })
    w.bags = { { itemID = 1, isBound = false } }
    w.quotes["item:1"] = { price = 100, age = 6 }
    local r = w:start(); w:chat("CHAT_MSG_LOOT", "You receive loot: item:1.", 96); w:advance(0.1)
    eq(w.FG.Totals(r).ah, 95)
    w.epoch = w.epoch + 172800
    eq(w.FG.Totals(r).ah, 0)
    w.FG.Action("stop")
    local age = r.items["item:1:loot"].quote.age
    w.epoch = w.epoch + 86400
    eq(r.items["item:1:loot"].quote.age, age)
end)

test("logout preserves armed state without creating or resuming a session", function()
    local w = H.native()
    w:emit("PLAYER_LOGOUT")
    eq(w.FG.character.mode, "armed"); eq(w.FG.character.current, nil)
    eq(#w.FG.db.temporary, 0)
end)

test("time to level uses remaining XP and all earned XP over active time", function()
    local X = H.pure().XPBar
    local record = { active = 1800, xp = { combat = 300, quest = 150, other = 50 } }
    near(X.TimeToLevel(400, 1000, record, "running"), 2160)
    eq(X.TimeToLevel(1000, 1000, record, "running"), 0)
    eq(X.TimeToLevel(0, 0, record, "running"), nil)
    for _, mode in ipairs({ "armed", "paused", "stopped" }) do
        eq(X.TimeToLevel(400, 1000, record, mode), nil)
    end
    record.active = 0; eq(X.TimeToLevel(400, 1000, record, "running"), nil)
    record.active = 100; record.xp = { combat = 0, quest = 0, other = 0 }
    eq(X.TimeToLevel(400, 1000, record, "running"), nil)
end)

test("XP text shows active ETA without quest projection text and removes it when paused", function()
    local w = H.native(); local r = w:start()
    r.active = 600
    w.bar.StatusBar.width = 1000
    w.quests = { { id = 5, complete = true, known = true, xp = 900 } }
    w:emit("QUEST_LOG_UPDATE"); w.FG.XPBar:Refresh()
    eq(w.bar.OverlayFrame.Text:GetText(), "200 / 1000 XP (20.0%) | Level in 1 hour and 20 minutes")
    near(w.FG.XPBar.attached[w.bar].fill.width, 800)
    w.bar.StatusBar.width = 160; w.FG.XPBar:Refresh()
    assert(w.bar.OverlayFrame.Text:GetText():find("Level in", 1, true))
    assert(w.bar.OverlayFrame.Text:GetStringWidth() <= 148)
    w.FG.Action("pause"); w.bar.StatusBar.width = 1000; w.FG.XPBar:Refresh()
    eq(w.bar.OverlayFrame.Text:GetText(), "200 / 1000 XP (20.0%)")
end)

test("full-width report navigation retains history filters sorting and page", function()
    local w = H.native(); local r = w:start(); w.FG.Action("save")
    local U = w.FG.UI
    for index = 1, 14 do
        local copy = w.FG.Copy(r); copy.id = "extra:" .. index
        w.FG.db.saved[#w.FG.db.saved + 1] = copy
    end
    U.OpenJournal(); U.ShowList()
    U.filters.character:SetText("Tester"); U.filters.realm:SetText("Realm")
    U.filters.location:SetText("Forest"); U.filters.minimum:SetText("9"); U.filters.maximum:SetText("11")
    U.sort, U.descending, U.page = "goldHour", false, 2
    U.RefreshJournal(); U.rows[1].scripts.OnClick()
    eq(U.reportVisible, true); eq(U.listFrame:IsShown(), false); eq(U.report.frame:IsShown(), true)
    eq(U.report.tab, "overview"); U.report.back.scripts.OnClick()
    eq(U.reportVisible, false); eq(U.listFrame:IsShown(), true); eq(U.page, 2)
    eq(U.tab, "saved"); eq(U.sort, "goldHour"); eq(U.descending, false)
    eq(U.filters.character:GetText(), "Tester"); eq(U.filters.realm:GetText(), "Realm")
    eq(U.filters.location:GetText(), "Forest"); eq(U.filters.minimum:GetText(), "9"); eq(U.filters.maximum:GetText(), "11")
end)

test("report overview separates additive estimates from vendor comparison", function()
    local w = H.native(); local r = w:start(); r.active = 3600
    r.xp.quest, r.xp.other = 200, 300; r.coin.loot, r.coin.quest = 100, 200
    r.items = {
        ah = { link = "item:1", source = "loot", quantity = 2, vendor = 10, auctionable = true,
            liveQuote = { price = 100, age = 1 } },
        vendor = { link = "item:2", source = "quest", quantity = 3, vendor = 50, auctionable = false },
    }
    local U = w.FG.UI; U.OpenJournal(); local R = U.report
    eq(R.metrics.xpHour:GetText(), "600"); eq(R.metrics.xp:GetText(), "600")
    eq(R.metrics.active:GetText(), "1:00:00"); eq(R.metrics.goldHour:GetText(), w.FG.Money(640))
    eq(R.labels.coin:GetText(), w.FG.Money(100)); eq(R.labels.questGold:GetText(), w.FG.Money(200))
    eq(R.labels.vendor:GetText(), w.FG.Money(150)); eq(R.labels.ah:GetText(), w.FG.Money(190))
    eq(R.labels.projected:GetText(), w.FG.Money(640)); eq(R.labels.baseline:GetText(), w.FG.Money(170))
    eq(R.labels.vendorHour:GetText(), w.FG.Money(470))
    assert(R.labels.baselineNote:GetText():find("not additional income", 1, true))
    eq(R.labels.xpcombat:GetText(), "100"); eq(R.labels.xpquest:GetText(), "200"); eq(R.labels.xpother:GetText(), "300")
end)

test("report notices distinguish pending items from known zero vendor value", function()
    local w = H.native(); local r = w:start()
    r.items = { pending = { link = "item:2", source = "loot", quantity = 7 },
        zero = { link = "item:3", source = "loot", quantity = 2, vendor = 0 } }
    r.warnings.example = "A reward choice could not be observed."
    w.FG.UI.OpenJournal(); local R = w.FG.UI.report
    eq(R.totals.pending, 7); eq(R.totals.quantity, 9)
    assert(R.labels.notice:GetText():find("7 item(s)", 1, true))
    assert(R.labels.notice:GetText():find(r.warnings.example, 1, true))
    R:SetTab("loot")
    eq(R.lootRows[1].row.value.route, "pending")
    eq(R.labels.loot1Value:GetText(), "Pending")
    eq(R.labels.loot2Value:GetText(), "0g 00s 00c")
end)

test("loot report rows sort by advantage and reveal independent item details", function()
    local w = H.native(); local r = w:start()
    r.items = { first = { link = "item:1", source = "loot", quantity = 2, vendor = 10, auctionable = true,
        liveQuote = { price = 100, age = 2 } },
        second = { link = "item:2", source = "gathering", quantity = 3, vendor = 20, auctionable = false } }
    w.FG.UI.OpenJournal(); local R = w.FG.UI.report; R:SetTab("loot")
    eq(R.lootRows[1].row.entry.link, "item:1"); eq(R.labels.loot1Upside:GetText(), "+0g 01s 70c")
    R.lootRows[1].scripts.OnClick()
    eq(R.item, r.items.first); eq(R.itemLabels.reason:GetText(), R.lootRows[1].row.value.reason)
    eq(R.lootRows[1].selection:IsShown(), true)
    assert(R.itemLabels.quote:GetText():find("2.0 days", 1, true))
    assert(R.itemLabels.source:GetText():find("quantity 2", 1, true))
    R.lootRows[1].scripts.OnEnter(R.lootRows[1]); eq(w.env.GameTooltip.link, "item:1")
    R.lootRows[2].scripts.OnClick()
    eq(R.item, r.items.second); eq(R.lootRows[1].selection:IsShown(), false)
    assert(R.itemLabels.source:GetText():find("Gathering / containers", 1, true))
    eq(R.itemLabels.quote:GetText(), "No cached AH quote.")
end)

test("report refresh preserves scroll selection and unfinished edits without allocating frames", function()
    local w = H.native(); local r = w:start(); local U = w.FG.UI
    w.FG.XPBar:Refresh()
    U.OpenJournal(); local R = U.report
    R.scroll:SetVerticalScroll(90)
    U.nameEdit:SetText("Typing name"); U.notesEdit:SetText("Typing notes")
    local frameCount = #w.frames
    w:advance(1.2)
    eq(R.scroll:GetVerticalScroll(), 90); eq(#w.frames, frameCount)
    eq(U.nameEdit:GetText(), "Typing name"); eq(U.notesEdit:GetText(), "Typing notes")
    R:SetTab("details"); R.scroll:SetVerticalScroll(180)
    R:SetTab("overview"); eq(R.scroll:GetVerticalScroll(), 90)
    R:SetTab("details"); eq(R.scroll:GetVerticalScroll(), 180)
    local other = w.FG.Copy(r); other.id = "different"; other.closed = true
    w.FG.db.saved[#w.FG.db.saved + 1] = other
    U.Select(other); U.RefreshJournal()
    eq(R.tab, "overview"); eq(R.scroll:GetVerticalScroll(), 0); eq(R.item, nil)
end)

test("session details wrap notes expose missing coordinates and sort visited zones", function()
    local w = H.native(); local r = w:start()
    r.name = string.rep("Long session ", 15); r.notes = string.rep("A useful observation about this farming spot. ", 30)
    r.startLocation = { zone = "Dungeon", mapID = 5 }; r.zones = {
        short = { zone = "Short", seconds = 20, mapID = 1 },
        long = { zone = "Long", seconds = 120, mapID = 2 },
    }
    w.FG.Action("save"); w.FG.UI.OpenJournal(); w.FG.UI.Select(r); w.FG.UI.RefreshJournal()
    local R = w.FG.UI.report; R:SetTab("details")
    eq(R.name:GetText(), r.name); eq(R.labels.notes:GetText(), r.notes)
    assert(R.labels.startLocation:GetText():find("coordinates unavailable", 1, true))
    assert(R.labels.endLocation:GetText():find("25.0, 75.0", 1, true))
    assert(R.labels.zone1:GetText():find("Long", 1, true)); eq(R.labels.zoneTime1:GetText(), "0:02:00")
    assert(R.labels.frozen:GetText():find("frozen", 1, true)); eq(R.labels.cut:GetText(), "5.0%")
    w.FG.UI.nameEdit:SetText("Renamed"); w.FG.UI.notesEdit:SetText("New notes\nA second line")
    w.FG.UI.applyName.scripts.OnClick()
    eq(r.name, "Renamed"); eq(R.labels.notes:GetText(), "New notes\nA second line")
end)

test("report handles empty histories zero items and running paused saved unsaved states", function()
    local w = H.native(); local U = w.FG.UI
    U.OpenJournal(); eq(U.emptyList:IsShown(), true); eq(U.reportVisible, false)
    local r = w:start(); U.Select(r); U.RefreshJournal(); local R = U.report
    eq(R.status:GetText(), "Running"); eq(U.delete.enabled, false); eq(U.promote.enabled, false)
    R:SetTab("loot"); assert(R.labels.emptyLoot:IsShown())
    w.FG.Action("pause"); eq(R.status:GetText(), "Paused")
    w.FG.Action("stop"); eq(R.status:GetText(), "Unsaved"); eq(U.promote.enabled, true)
    local endedAt, active, quoted = r.endedAt, r.active, w.FG.Copy(r.pricing)
    U.promote.scripts.OnClick(); eq(R.status:GetText(), "Saved"); eq(U.promote.enabled, false)
    eq(r.endedAt, endedAt); eq(r.active, active); eq(r.pricing.ahCut, quoted.ahCut)
    U.delete.scripts.OnClick(); w.env.StaticPopupDialogs[w.popup.key].OnAccept(nil, w.popup.data)
    eq(U.reportVisible, false); eq(#w.FG.db.saved, 0)
end)

test("closed report retains frozen quotes after settings change and selection changes", function()
    local w = H.native(); local r = w:start()
    r.items = { a = { link = "item:1", source = "loot", quantity = 2, vendor = 10, auctionable = true,
        liveQuote = { price = 100, age = 2 } } }
    w.FG.Action("save"); w.FG.db.settings.ahCut = 90
    w.FG.UI.OpenJournal(); w.FG.UI.Select(r); w.FG.UI.RefreshJournal(); local R = w.FG.UI.report
    eq(R.labels.ah:GetText(), w.FG.Money(190)); R:SetTab("details"); eq(R.labels.cut:GetText(), "5.0%")
    w.FG.UI.delete.scripts.OnClick()
    w.FG.Action("play"); local other = w:start(); w.FG.UI.Select(other); w.FG.UI.RefreshJournal()
    w.env.StaticPopupDialogs[w.popup.key].OnAccept(nil, w.popup.data)
    eq(w.FG.UI.selected, other); eq(w.FG.UI.reportVisible, true)
end)

assert(loadfile("tests/routes.lua"))()(H, test, eq, near)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
