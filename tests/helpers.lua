local H = {}
H.globals = {
    COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
    COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience.",
    COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)",
    COMBATLOG_XPGAIN_EXHAUSTION1_GROUP = "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)",
    COMBATLOG_XPGAIN_QUEST = "You gain %d experience. (%s exp %s bonus)",
    LOOT_ITEM_SELF = "You receive loot: %s.", LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
    LOOT_ITEM_PUSHED_SELF = "You receive item: %s.", LOOT_ITEM_CREATED_SELF = "You create: %s.",
    LOOT_MONEY = "You loot %s.", LOOT_MONEY_SPLIT = "Your share of the loot is %s.",
    GOLD_AMOUNT = "%d Gold", SILVER_AMOUNT = "%d Silver", COPPER_AMOUNT = "%d Copper",
}

function H.load(FG, filename, env)
    local fn = assert(loadfile(filename))
    if env then setfenv(fn, env) end
    fn("ForeverGrind", FG)
end

function H.pure()
    local FG = {}
    for _, name in ipairs({ "Util", "Route", "Kills", "Session", "Valuation", "Parsing", "Collector", "XPBar", "UI", "Report", "Map" }) do H.load(FG, name .. ".lua") end
    return FG
end

function H.world(global, character)
    local FG = H.pure()
    local w = { FG = FG, now = 100, epoch = 10000, timers = {}, xp = { xp = 100, maximum = 1000, level = 10 },
        context = { character = "Tester", realm = "Realm", guid = "Player-1", level = 10,
            location = { zone = "Forest", subzone = "Camp", mapID = 1, x = 0.25, y = 0.75 } },
        loaded = {}, globals = FG.Copy(H.globals), itemLoads = {}, origin = "corpse" }
    w.db, w.character = FG.InitializeDB(global, character)
    w.model = FG.Session.New(w.db, w.character)
    w.collector = FG.Collector.New(w.model, {
        globals = w.globals, now = function() return w.now end, epoch = function() return w.epoch end,
        xp = function() return FG.Copy(w.xp) end, context = function() return FG.Copy(w.context) end,
        after = function(delay, fn) w.timers[#w.timers + 1] = fn end,
        resolveLink = function(link) return link end, lootOrigin = function() return w.origin end,
        changed = function() w.changed = true end,
        loadItem = function(record, entry) w.itemLoads[#w.itemLoads + 1] = { record, entry } end,
    })
    w.collector:Rebaseline()
    function w:advance(seconds)
        self.now, self.epoch = self.now + seconds, self.epoch + seconds
        self.model:Tick(self.now, self.context.location)
    end
    function w:start()
        self.collector:Kill("Boar dies, you gain 100 experience.")
        self.xp.xp = self.xp.xp + 100
        self.collector:ObserveXP(FG.Copy(self.xp))
        self.collector:Flush()
        return self.character.current
    end
    function w:stop(permanent)
        self.collector:Boundary()
        local record = self.model:Stop(permanent, self.now, self.epoch, self.context)
        if record then FG.Value.Freeze(record, self.db.settings, function(entry) return entry.liveQuote end) end
        return record
    end
    return w
end

function H.native(options)
    options = options or {}
    local FG, env = {}, setmetatable({}, { __index = _G })
    local w = { FG = FG, env = env, now = 0, epoch = 10000, frames = {}, timers = {}, requests = {},
        xp = 100, maximum = 1000, level = 10, loot = {}, quests = {}, offers = {}, bags = { { itemID = 1, isBound = false } },
        items = { [1] = { vendor = 10, binding = 0 } }, quotes = {}, hooks = {} }
    env._G = env
    for k, v in pairs(H.globals) do env[k] = v end
    local F = {}
    F.__index = F
    local function structural(self) assert(not self.stock, "Changed native bar structure/shown state") end
    function F:SetSize(x, y) structural(self); self.width, self.height = x, y end
    function F:SetWidth(x) self.width = x end
    function F:SetHeight(x) self.height = x end
    function F:GetWidth() return self.width or 400 end
    function F:GetHeight() return self.height or 200 end
    function F:SetPoint(...) structural(self); self.point = { ... } end
    function F:GetPoint() return unpack(self.point or { "TOP", env.UIParent, "TOP", 0, -60 }) end
    function F:ClearAllPoints() structural(self); self.point = nil end
    function F:SetText(text)
        self.text = tostring(text or "")
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function F:GetText() return self.text or "" end
    function F:GetStringWidth() return #(self.text or "") * 5 end
    function F:GetStringHeight()
        local lines = 1
        for _ in (self.text or ""):gmatch("\n") do lines = lines + 1 end
        return math.max(lines, math.ceil(#(self.text or "") / 40)) * 14
    end
    function F:SetScript(event, fn) structural(self); self.scripts[event] = fn end
    function F:HookScript(event, fn)
        local old = self.scripts[event]
        self.scripts[event] = function(...) if old then old(...) end; fn(...) end
    end
    function F:RegisterEvent(event) self.events[event] = true end
    function F:Show() structural(self); self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function F:Hide() structural(self); self.shown = false end
    function F:SetShown(value) if value then self:Show() else self:Hide() end end
    function F:IsShown() return self.shown end
    function F:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function F:SetScrollChild(child) self.child = child end
    function F:SetVerticalScroll(value) self.scrollOffset = value end
    function F:GetVerticalScroll() return self.scrollOffset or 0 end
    function F:SetChecked(value) self.checked = value end
    function F:GetChecked() return self.checked end
    function F:SetEnabled(value) self.enabled = value end
    function F:GetID() return 42 end
    function F:SetColorTexture(...) self.color = { ... } end
    function F:SetTextColor(...) self.color = { ... } end
    function F:GetEffectiveScale() return self.effectiveScale or 1 end
    function F:SetTexture(value) self.texture = value end
    function F:SetVertexColor(...) self.color = { ... } end
    function F:SetAlpha(value) self.alpha = value end
    function F:SetStartPoint(...) self.startPoint = { ... } end
    function F:SetEndPoint(...) self.endPoint = { ... } end
    function F:GetFont() return "font", 11, "OUTLINE" end
    function F:SetOwner(owner) self.owner = owner; self.lines = {} end
    function F:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
    function F:SetHyperlink(link) self.link = link end
    for _, method in ipairs({ "SetAllPoints", "SetClipsChildren", "EnableMouseWheel", "RegisterForClicks", "SetThickness", "SetTexCoord", "SetJustifyH", "SetFont", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
        "SetBackdrop", "SetBackdropColor", "SetAutoFocus", "ClearFocus", "StartMoving", "StopMovingOrSizing", "SetScale", "SetWordWrap", "SetHighlightTexture", "SetJustifyV" }) do
        F[method] = function() end
    end
    function env.CreateFrame(kind, name, parent, template)
        local frame = setmetatable({ kind = kind, name = name, parent = parent, template = template, scripts = {}, events = {}, shown = true }, F)
        w.frames[#w.frames + 1] = frame
        if name then env[name] = frame end
        return frame
    end
    function F:CreateFontString() return env.CreateFrame("FontString", nil, self) end
    function F:CreateLine() return env.CreateFrame("Line", nil, self) end
    function F:CreateTexture() return env.CreateFrame("Texture", nil, self) end
    env.UIParent = env.CreateFrame("Frame")
    env.UIParent.width, env.UIParent.height = 1280, 800
    env.GameTooltip = env.CreateFrame("GameTooltip")
    env.STANDARD_TEXT_FONT, env.YES, env.NO = "font", "Yes", "No"
    env.UISpecialFrames, env.StaticPopupDialogs, env.SlashCmdList = {}, {}, {}
    env.StaticPopup_Show = function(key, _, _, data) w.popup = { key = key, data = data } end
    env.Settings = { RegisterCanvasLayoutCategory = function(panel) w.settingsPanel = panel; return env.CreateFrame("Category") end,
        RegisterAddOnCategory = function() end, OpenToCategory = function(id) w.opened = id end }
    env.GetTime, env.time = function() return w.now end, function() return w.epoch end
    env.date = os.date
    env.UnitXP, env.UnitXPMax, env.UnitLevel = function() return w.xp end, function() return w.maximum end, function() return w.level end
    w.units = { player = { guid = "Player-1", name = "Tester" } }
    env.UnitName = function(unit) return w.units[unit] and w.units[unit].name end
    env.GetRealmName = function() return "Realm" end
    env.UnitGUID = function(unit) return w.units[unit] and w.units[unit].guid end
    env.UnitNameFromGUID = function(guid) return w.names and w.names[guid] end
    env.GetCursorPosition = function() return w.cursorX or 0, w.cursorY or 0 end
    env.GetZoneText, env.GetSubZoneText = function() return "Forest" end, function() return "Camp" end
    w.mapID, w.mapX, w.mapY = 1, 0.25, 0.75
    env.C_Map = { GetBestMapForUnit = function() return w.mapID end,
        GetMapWorldSize = function() return 1000, 1000 end,
        GetMapInfo = function(id) return { name = "Map " .. id } end,
        GetMapArtLayers = function() if not w.noArt then return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end end,
        GetMapArtLayerTextures = function() return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } end,
        CanSetUserWaypointOnMap = function() return not w.noWaypoint end,
        SetUserWaypoint = function(point) w.waypoint = point end,
        GetPlayerMapPosition = function() if not w.noCoords then return { GetXY = function() return w.mapX, w.mapY end } end end }
    env.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { mapID = id, x = x, y = y } end }
    env.C_Timer = { After = function(delay, fn) w.timers[#w.timers + 1] = { due = w.now + delay, fn = fn } end }
    env.C_Item = {
        GetItemInfoInstant = function(link) return tonumber(link:match("item:(%d+)")) end,
        GetItemInfo = function(link)
            local id = tonumber(link:match("item:(%d+)"))
            local item = w.items[id]
            if item then return "Item " .. id, link, 1, 1, 1, "", "", 20, "", "", item.vendor, 0, 0, item.binding end
        end,
        RequestLoadItemDataByID = function(id) w.requests[id] = true end,
    }
    env.NUM_BAG_SLOTS = 4
    env.C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and #w.bags or 0 end,
        GetContainerItemInfo = function(_, slot) return w.bags[slot] end }
    env.C_QuestLog = { GetNumQuestLogEntries = function() return #w.quests end,
        GetQuestIDForLogIndex = function(index) return w.quests[index] and w.quests[index].id end,
        IsComplete = function(id) for _, q in ipairs(w.quests) do if q.id == id then return q.complete end end end,
        RequestLoadQuestByID = function(id) w.requests["quest" .. id] = true end }
    env.HaveQuestRewardData = function(id) for _, q in ipairs(w.quests) do if q.id == id then return q.known end end end
    env.GetQuestLogRewardXP = function(id) for _, q in ipairs(w.quests) do if q.id == id then return q.xp end end end
    env.GetQuestID = function() return w.offer and w.offer.id or 0 end
    env.GetNumQuestRewards = function() return w.offer and #w.offer.rewards or 0 end
    env.GetNumQuestChoices = function() return w.offer and #w.offer.choices or 0 end
    local function reward(kind, index) return w.offer[kind == "choice" and "choices" or "rewards"][index] end
    env.GetQuestItemInfo = function(kind, index)
        local r = reward(kind, index)
        return "Reward", nil, r.quantity, 1, true, tonumber(r.link:match("item:(%d+)"))
    end
    env.GetQuestItemLink = function(kind, index) return reward(kind, index).link end
    env.GetQuestItemInfoLootType = function() return 0 end
    env.GetQuestReward = function() end
    env.LOOT_SLOT_MONEY = 2
    env.GetNumLootItems = function() return #w.loot end
    env.GetLootSourceInfo = function(slot) return w.loot[slot].source, w.loot[slot].quantity end
    env.GetLootSlotType = function(slot) return w.loot[slot].kind or 1 end
    env.GetLootSlotLink = function(slot) return w.loot[slot].link end
    env.GetLootSlotInfo = function(slot) return nil, nil, w.loot[slot].quantity end
    env.hooksecurefunc = function(target, key, fn)
        if type(target) == "string" then fn, key, target = key, target, env end
        local old = target[key]
        assert(type(old) == "function", "Hooking missing function " .. tostring(key))
        target[key] = function(...) local result = { old(...) }; fn(...); return unpack(result) end
    end
    env.StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
    local bar = env.CreateFrame("Frame")
    bar.isExpBar, bar.stock = true, true
    bar.StatusBar = env.CreateFrame("StatusBar", nil, bar)
    bar.StatusBar.width = 500
    bar.OverlayFrame = { Text = env.CreateFrame("FontString", nil, bar) }
    bar.ExhaustionLevelFillBar = env.CreateFrame("Texture", nil, bar)
    function bar:UpdateCurrentText() self.OverlayFrame.Text:SetText("Native XP") end
    function bar:UpdateTextVisibility() self.OverlayFrame.Text:SetShown(false) end
    w.bar, w.reputation = bar, env.CreateFrame("Frame")
    w.reputation.stock = true
    env.StatusTrackingBarManager = { barContainers = { { bars = { [1] = bar, [2] = w.reputation } } } }
    if options.auctionator then
        env.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, link) local q = w.quotes[link]; return q and q.price end,
            GetAuctionAgeByItemLink = function(_, link) local q = w.quotes[link]; return q and q.age end,
            RegisterForDBUpdate = function(_, callback) w.priceUpdate = callback end,
        } } }
    end
    for _, name in ipairs({ "Util", "Route", "Kills", "Session", "Valuation", "Parsing", "Collector", "XPBar", "UI", "Report", "Map", "Core" }) do H.load(FG, name .. ".lua", env) end
    function w:emit(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    function w:chat(event, text, id) self:emit(event, text, "", "", "", "", "", 0, 0, "", "", id, "Player-1") end
    function w:advance(seconds)
        local finish = self.now + seconds
        while self.now < finish - 0.000001 do
            local delta = math.min(0.01, finish - self.now)
            self.now, self.epoch = self.now + delta, self.epoch + delta
            local ready = {}
            for index = #self.timers, 1, -1 do
                if self.timers[index].due <= self.now + 0.000001 then table.insert(ready, 1, table.remove(self.timers, index).fn) end
            end
            for _, fn in ipairs(ready) do fn() end
            for _, frame in ipairs(self.frames) do if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, delta) end end
        end
    end
    function w:start()
        self.killSerial = (self.killSerial or 0) + 1
        self:chat("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 100 experience.", self.killSerial)
        self.xp = self.xp + 100
        self:emit("PLAYER_XP_UPDATE", "player")
        self:advance(0.1)
        return FG.character.current
    end
    w:emit("ADDON_LOADED", "ForeverGrind")
    return w
end

return H
