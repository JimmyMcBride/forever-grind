local addonName, FG = ...
local events = CreateFrame("Frame")
local lootContext, registeredAuctionator
local identities, attackers = {}, {}
local killEventsAvailable = true

local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return FG.Plain(value) end
end

local function ObserveUnit(unit)
    local guid = Read(UnitGUID, unit)
    if not FG.Kills.Identity(guid) then return end
    local name = Read(UnitName, unit)
    if type(name) == "string" and name ~= "" then identities[guid] = name end
end

local function GroupAttackers()
    attackers = {}
    local function add(unit)
        local guid = Read(UnitGUID, unit)
        if type(guid) == "string" then attackers[guid] = true end
    end
    add("player"); add("pet")
    for i = 1, 4 do add("party" .. i); add("partypet" .. i) end
    for i = 1, 40 do add("raid" .. i); add("raidpet" .. i) end
end

function FG.Context()
    local location = { zone = GetZoneText(), subzone = GetSubZoneText() }
    local id = Read(C_Map.GetBestMapForUnit, "player")
    location.mapID = id
    if id then
        local point = C_Map.GetPlayerMapPosition(id, "player")
        if point then
            local x, y = point:GetXY()
            x, y = FG.Plain(x), FG.Plain(y)
            if type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) then location.x, location.y = x, y end
        end
    end
    if id and C_Map.GetMapWorldSize then
        local ok, width, height = pcall(C_Map.GetMapWorldSize, id)
        if ok then location.width, location.height = FG.Plain(width), FG.Plain(height) end
    end
    return { character = UnitName("player"), realm = GetRealmName(), guid = UnitGUID("player"),
        level = UnitLevel("player"), location = location }
end

local function SnapshotXP()
    return { xp = UnitXP("player"), maximum = UnitXPMax("player"), level = UnitLevel("player") }
end

local function ItemID(link)
    return tonumber(link:match("item:(%d+)")) or C_Item.GetItemInfoInstant(link:gsub("^%[", ""):gsub("%]$", ""))
end

local function ResolveLink(link)
    if link:find("item:", 1, true) then return link end
    local id = ItemID(link)
    return id and ("item:" .. id) or link
end

local function FetchQuote(entry)
    if not FG.db.settings.auctionator or not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return end
    local api = Auctionator.API.v1
    if not api.GetAuctionPriceByItemLink or not api.GetAuctionAgeByItemLink then return end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, "ForeverGrind", entry.link)
    local ageOK, age = pcall(api.GetAuctionAgeByItemLink, "ForeverGrind", entry.link)
    if ok and type(price) == "number" and price > 0 then
        return { price = price, age = ageOK and type(age) == "number" and age or nil, quotedAt = time() }
    end
end

function FG.Quote(entry)
    local quote = FG.Copy(entry.liveQuote)
    if quote and quote.age and quote.quotedAt then
        quote.age = quote.age + math.max(0, time() - quote.quotedAt) / 86400
        quote.quotedAt = time()
    end
    return quote
end

function FG.Totals(record)
    return FG.Value.Total(record, FG.db.settings, FG.Quote)
end

local function ReceiptBinding(entry)
    local id = ItemID(entry.link)
    local bound, unbound = false, false
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id and type(info.isBound) == "boolean" then
                if info.isBound then bound = true else unbound = true end
            end
        end
    end
    if bound ~= unbound then entry.receiptBound = bound end
end

function FG.LoadItem(record, entry)
    entry.itemID = entry.itemID or ItemID(entry.link)
    if entry.receiptBound == nil and not record.closed then ReceiptBinding(entry) end
    local name, link, _, _, _, _, _, _, _, _, vendor, _, _, binding = C_Item.GetItemInfo(entry.link)
    if name and vendor ~= nil then
        entry.name, entry.displayLink, entry.vendor = name, link or entry.link, vendor
        entry.bindingPending = binding == nil or ((binding == 0 or binding == 2 or binding == 3) and entry.receiptBound == nil)
        -- Unknown receipt binding stays conservative; never recommend a bound copy.
        entry.auctionable = entry.receiptBound == false and (binding == 0 or binding == 2 or binding == 3)
    elseif entry.itemID then C_Item.RequestLoadItemDataByID(entry.itemID) end
    if not record.closed then entry.liveQuote = FetchQuote(entry) end
end

function FG.Reprice()
    local current = FG.character.current
    if current then
        for _, entry in pairs(current.items) do entry.liveQuote = FetchQuote(entry) end
    end
    FG.Changed()
end

function FG.Changed()
    local record = FG.character and FG.character.current
    if record and record.route and not killEventsAvailable then
        record.route.notices.events = "Credited-kill events are unavailable; zero-XP mob counts may be incomplete."
    end
    if FG.UI then FG.UI.dirty = true end
end

local function CaptureLoot()
    if GetNumLootItems() == 0 then return end
    lootContext = { at = GetTime(), items = {}, money = nil }
    for slot = 1, GetNumLootItems() do
        local source = "gathering"
        local origins = { GetLootSourceInfo(slot) }
        for index = 1, #origins, 2 do
            if type(origins[index]) == "string" and origins[index]:match("^Creature%-") then source = "corpse" end
        end
        local kind = GetLootSlotType(slot)
        if kind == LOOT_SLOT_MONEY then lootContext.money = source
        else
            local link = GetLootSlotLink(slot)
            local id = link and ItemID(link)
            local _, _, quantity = GetLootSlotInfo(slot)
            if id then
                local previous = lootContext.items[id]
                lootContext.items[id] = { source = source == "corpse" and source or (previous and previous.source or source),
                    quantity = (previous and previous.quantity or 0) + (quantity or 1) }
            end
        end
    end
end

local function LootOrigin(link, quantity)
    if not lootContext or (lootContext.closedAt and GetTime() - lootContext.closedAt > 1) then return end
    if not link then
        local source = lootContext.money
        lootContext.money = nil
        return source
    end
    local id = ItemID(link)
    local item = id and lootContext.items[id]
    if item and item.quantity >= quantity then item.quantity = item.quantity - quantity; return item.source end
end

local function CaptureOffer()
    local id = GetQuestID and GetQuestID()
    if not id or id <= 0 then return end
    local offer = { id = id, rewards = {}, choices = {}, nonItems = {}, choiceCount = GetNumQuestChoices() }
    for _, category in ipairs({ { "reward", GetNumQuestRewards(), offer.rewards }, { "choice", GetNumQuestChoices(), offer.choices } }) do
        for index = 1, category[2] do
            if not GetQuestItemInfoLootType or GetQuestItemInfoLootType(category[1], index) == 0 then
                local name, _, quantity, _, _, itemID = GetQuestItemInfo(category[1], index)
                local link = GetQuestItemLink(category[1], index)
                category[3][index] = { link = link or (itemID and ("item:" .. itemID)) or (name or ("Unresolved quest reward " .. id)),
                    quantity = quantity or 1 }
            elseif category[1] == "choice" then offer.nonItems[index] = true
            end
        end
    end
    FG.collector:Offer(offer)
end

function FG.Action(action)
    if not FG.collector then return end
    FG.collector:Boundary()
    local now, epoch, context = GetTime(), time(), FG.Context()
    if action == "play" then FG.model:Play(now, epoch, context.location)
    elseif action == "pause" then FG.model:Pause(now, epoch, context.location)
    elseif action == "stop" or action == "save" then
        local record = FG.model:Stop(action == "save", now, epoch, context)
        if record then
            FG.Value.Freeze(record, FG.db.settings, FG.Quote)
            FG.UI.tab = action == "save" and "saved" or "temporary"
            FG.UI.Select(record)
        end
    end
    FG.collector:Rebaseline()
    lootContext, identities = nil, {}
    FG.Changed()
    FG.UI.Refresh()
end

local function RegisterAuctionator()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not registeredAuctionator and api and api.RegisterForDBUpdate then
        registeredAuctionator = pcall(api.RegisterForDBUpdate, "ForeverGrind", FG.Reprice)
    end
end

local function Initialize()
    ForeverGrindDB, ForeverGrindCharacterDB = FG.InitializeDB(ForeverGrindDB, ForeverGrindCharacterDB)
    FG.db, FG.character = ForeverGrindDB, ForeverGrindCharacterDB
    if FG.character.current and not FG.character.current.pauseEpoch then FG.character.current.pauseEpoch = time() end
    FG.model = FG.Session.New(FG.db, FG.character)
    FG.collector = FG.Collector.New(FG.model, { globals = _G, now = GetTime, epoch = time, xp = SnapshotXP,
        context = FG.Context, after = C_Timer.After, resolveLink = ResolveLink, lootOrigin = LootOrigin,
        loadItem = FG.LoadItem, changed = FG.Changed })
    FG.collector:Rebaseline()
    GroupAttackers()
    if type(GetQuestReward) == "function" then hooksecurefunc("GetQuestReward", function(index) FG.collector:Choice(index) end) end
    FG.UI.Create()
    FG.XPBar:ScanQuests()
    RegisterAuctionator()
    for _, record in ipairs(FG.model:Records()) do
        for _, entry in pairs(record.items) do if entry.vendor == nil then FG.LoadItem(record, entry) end end
    end
    FG.Reprice()
end

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_LEAVING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "GROUP_ROSTER_UPDATE", "UNIT_PET", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
    "QUEST_COMPLETE", "QUEST_ITEM_UPDATE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "QUEST_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "UPDATE_EXHAUSTION" }) do
    events:RegisterEvent(event)
end
for _, event in ipairs({ "PARTY_KILL", "UNIT_DIED" }) do
    local ok = pcall(events.RegisterEvent, events, event)
    if event == "PARTY_KILL" and not ok then killEventsAvailable = false end
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then Initialize(); return end
    if not FG.collector then return end
    if event == "ADDON_LOADED" then RegisterAuctionator()
    elseif event == "PLAYER_LOGOUT" then
        FG.collector:Boundary()
        if FG.character.mode == "running" then FG.Action("pause") end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then GroupAttackers()
    elseif event == "PLAYER_TARGET_CHANGED" then ObserveUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then ObserveUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then ObserveUnit(...)
    elseif event == "UNIT_DIED" then
        local guid = FG.Plain(...)
        if FG.Kills.Identity(guid) then FG.collector:Death(guid) end
    elseif event == "PARTY_KILL" then
        local attacker, victim = ...
        attacker, victim = FG.Plain(attacker), FG.Plain(victim)
        local npcID = FG.Kills.Identity(victim)
        if type(attacker) == "string" and npcID and attackers[attacker] then
            local name = Read(UnitNameFromGUID, victim) or identities[victim]
            FG.collector:PartyKill(victim, type(name) == "string" and name ~= "" and name or nil, npcID)
        elseif FG.character.current and (attacker == nil or victim == nil) then
            FG.character.current.route.notices.restricted = "Some kill identities were restricted; mob counts may be incomplete."
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        FG.collector:Boundary()
        if FG.character.mode == "running" then
            FG.Route.Sample(FG.character.current, FG.Context().location, true)
            FG.Route.Break(FG.character.current)
        end
        identities = {}
    elseif event == "PLAYER_ENTERING_WORLD" then
        GroupAttackers(); FG.Route.Break(FG.character.current)
    elseif event == "PLAYER_XP_UPDATE" then
        if ... == "player" then FG.collector:ObserveXP(SnapshotXP()) end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then local text = ...; FG.collector:Kill(text, select(11, ...))
    elseif event == "CHAT_MSG_LOOT" then local text = ...; FG.collector:Loot(text, select(11, ...))
    elseif event == "CHAT_MSG_MONEY" then local text = ...; FG.collector:Money(text, select(11, ...))
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then CaptureLoot()
    elseif event == "LOOT_CLOSED" then if lootContext then lootContext.closedAt = GetTime() end
    elseif event == "QUEST_COMPLETE" or event == "QUEST_ITEM_UPDATE" then CaptureOffer()
    elseif event == "QUEST_TURNED_IN" then
        local id, xp, money = ...
        FG.collector:Queue({ kind = "quest", id = id, xp = xp or 0, money = math.max(0, money or 0), offer = FG.collector.offers[id] })
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id, success = ...
        if success then
            for _, record in ipairs(FG.model:Records()) do
                for _, entry in pairs(record.items) do if entry.itemID == id and entry.vendor == nil then FG.LoadItem(record, entry) end end
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        local record = FG.character.current
        if record then
            for _, entry in pairs(record.items) do if entry.receiptBound == nil then FG.LoadItem(record, entry) end end
        end
    elseif event:match("^ZONE_CHANGED") then FG.model:Tick(GetTime(), FG.Context().location)
    end
    if event:match("^QUEST_") or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then FG.XPBar:ScanQuests() end
    FG.Changed()
end)
local accumulator = 0
events:SetScript("OnUpdate", function(_, elapsed)
    if not FG.collector then return end
    accumulator = accumulator + elapsed
    if accumulator < 0.5 then return end
    accumulator = 0
    FG.model:Tick(GetTime(), FG.Context().location)
    if FG.character.current then FG.character.current.levelEnd = UnitLevel("player") end
    FG.XPBar:Refresh()
    FG.UI.Refresh()
    if FG.Map then FG.Map.RefreshWorld() end
end)
