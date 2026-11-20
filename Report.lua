local _, FG = ...
local Report = {}
Report.__index = Report
FG.Report = Report

local BLUE, GOLD, WHITE, MUTED = { 0.4, 0.75, 1 }, { 1, 0.8, 0.25 }, { 0.95, 0.95, 0.95 }, { 0.7, 0.73, 0.76 }
local sources = { loot = "Drops", gathering = "Gathering / containers", quest = "Quest rewards" }

function Report.Status(record, db, character)
    if record == character.current then
        return character.mode == "running" and "Running" or "Paused"
    end
    for _, saved in ipairs(db.saved) do if saved == record then return "Saved" end end
    return "Unsaved"
end

function Report.Zones(record)
    local zones = {}
    for key, zone in pairs(record.zones) do
        zones[#zones + 1] = { key = key, zone = zone.zone or "Unknown zone", mapID = zone.mapID, seconds = zone.seconds }
    end
    table.sort(zones, function(a, b)
        if a.seconds ~= b.seconds then return a.seconds > b.seconds end
        return a.key < b.key
    end)
    return zones
end

local function Label(pool, parent, key, text, x, y, width, size, color, align)
    local label = pool[key]
    if not label then
        label = FG.UI.Widgets.Text(parent, "", x, -y, width, size or 12)
        label:SetWordWrap(true)
        label:SetJustifyV("TOP")
        pool[key] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", x, -y)
    label:SetWidth(width)
    label:SetJustifyH(align or "LEFT")
    label:SetTextColor(unpack(color or WHITE))
    label:SetText(text)
    label:Show()
    return label, y + label:GetStringHeight()
end

function Report:Label(key, text, x, y, width, size, color, align)
    return Label(self.labels, self.content, key, text, x, y, width, size, color, align)
end

function Report:Row(key, title, value, x, y, color)
    self:Label(key .. "Label", title, x, y, 230, 12, MUTED)
    self:Label(key, value, x + 234, y, 172, 12, color, "RIGHT")
end

function Report:Overview(record, t)
    self:Label("xpHeading", "EXPERIENCE", 0, 0, 410, 13)
    for index, source in ipairs({ { "combat", "Combat" }, { "quest", "Quest" }, { "other", "Other / exploration" } }) do
        self:Row("xp" .. source[1], source[2], tostring(record.xp[source[1]]), 0, 30 + (index - 1) * 28, BLUE)
    end
    self:Label("itemsHeading", "ITEMS ACQUIRED", 0, 136, 410, 13)
    self:Row("quantity", "Total quantity", tostring(t.quantity), 0, 166)
    for index, source in ipairs({ "loot", "gathering", "quest" }) do
        self:Row("source" .. source, sources[source] .. " value", FG.Money(t.sources[source]), 0, 198 + (index - 1) * 28, GOLD)
    end
    self:Label("earningsHeading", "ESTIMATED EARNINGS", 440, 0, 410, 13)
    for index, row in ipairs({
        { "coin", "Looted coin", record.coin.loot }, { "questGold", "+ Quest gold", record.coin.quest },
        { "vendor", "+ Vendor-route items", t.vendor }, { "ah", "+ AH proceeds after cut", t.ah },
    }) do self:Row(row[1], row[2], FG.Money(row[3]), 440, 30 + (index - 1) * 28, GOLD) end
    self:Row("projected", "= Projected total", FG.Money(t.projected), 440, 154, GOLD)
    self:Label("baselineHeading", "VENDOR-ONLY COMPARISON", 440, 212, 410, 13)
    self:Row("baseline", "All items at vendor value", FG.Money(t.baseline), 440, 242)
    self:Row("vendorHour", "Baseline / hour (with coin)", FG.Money(t.vendorHour), 440, 270)
    local _, bottom = self:Label("baselineNote", "Alternative to AH estimates, not additional income. Baseline/hour includes looted coin and quest gold.", 440, 304, 410, 11, MUTED)
    local notices = {}
    if t.pending > 0 then notices[#notices + 1] = t.pending .. " item(s) await valuation; totals are incomplete." end
    for _, warning in pairs(record.warnings) do notices[#notices + 1] = warning end
    table.sort(notices)
    self:Label("noticeHeading", "DATA STATUS", 0, 304, 410, 13)
    local _, noticeBottom = self:Label("notice", #notices > 0 and table.concat(notices, "\n\n") or "No pending valuations or capture warnings.", 0, 334, 410, 12, #notices > 0 and GOLD or MUTED)
    local y = math.max(bottom, noticeBottom) + 28
    local _, last = self:Label("estimateNote", "Estimated values use cached prices. Expenses, deposits, failed listings, and actual sale outcomes are excluded.", 0, y, 850, 11, MUTED)
    return last + 20
end

function Report:SessionDetails(record)
    local pricing = record.pricing or FG.db.settings
    local paused = record.paused + (record.pauseEpoch and math.max(0, time() - record.pauseEpoch) or 0)
    self:Label("sessionHeading", "SESSION", 0, 0, 850, 13)
    self:Row("started", "Started", date("%Y-%m-%d %H:%M", record.startedAt), 0, 32)
    self:Row("ended", "Ended", record.endedAt and date("%Y-%m-%d %H:%M", record.endedAt) or "Not stopped", 440, 32)
    self:Row("levels", "Levels", record.levelStart .. " → " .. record.levelEnd, 0, 62, BLUE)
    self:Row("active", "Active duration", FG.Duration(record.active), 440, 62)
    self:Row("paused", "Paused / offline duration", FG.Duration(paused), 440, 90)
    self:Label("locationsHeading", "LOCATIONS", 0, 138, 850, 13)
    local bottom = 0
    for index, entry in ipairs({ { "start", "Start", record.startLocation }, { "end", "Stop / save", record.endLocation } }) do
        local key, title, location = unpack(entry)
        local x = (index - 1) * 440
        self:Label(key .. "LocationLabel", title, x, 170, 410, 11, MUTED)
        local _, last = self:Label(key .. "Location", location and (FG.LocationText(location) .. "\nMap: " .. tostring(location.mapID or "unavailable")) or "Not stopped", x, 192, 410, 12)
        bottom = math.max(bottom, last)
    end
    local y = bottom + 30
    self:Label("notesHeading", "NOTES", 0, y, 850, 13)
    local _, last = self:Label("notes", record.notes and record.notes ~= "" and record.notes or "No notes yet. Use the editor below to add notes.", 0, y + 28, 850, 12)
    y = last + 30
    self:Label("pricingHeading", "PRICING ASSUMPTIONS", 0, y, 850, 13)
    self:Row("integration", "Auctionator setting", pricing.auctionator and "Enabled" or "Disabled", 0, y + 32)
    self:Row("cut", "Estimated AH cut", string.format("%.1f%%", pricing.ahCut), 440, y + 32)
    self:Row("age", "Maximum quote age", string.format("%.1f days", pricing.maxPriceAge), 0, y + 60)
    local _, priceBottom = self:Label("frozen", record.closed and "Quotes and pricing settings frozen at stop. Missing metadata may still resolve." or "Unfinished estimates refresh with cached Auctionator data. Missing or stale quotes use vendor fallback.", 0, y + 94, 850, 11, MUTED)
    y = priceBottom + 30
    self:Label("zonesHeading", "ACTIVE TIME BY ZONE", 0, y, 850, 13)
    y = y + 32
    local zones = self.Zones(record)
    for index, zone in ipairs(zones) do
        self:Label("zone" .. index, zone.zone .. " (map " .. tostring(zone.mapID or "unavailable") .. ")", 0, y, 650, 12)
        self:Label("zoneTime" .. index, FG.Duration(zone.seconds), 680, y, 170, 12, WHITE, "RIGHT")
        y = y + 28
    end
    if #zones == 0 then self:Label("noZones", "No active zone time recorded yet.", 0, y, 850, 12, MUTED); y = y + 28 end
    return y + 20
end

function Report:ItemDetails(row)
    local function text(key, value, y, color, size)
        local _, bottom = Label(self.itemLabels, self.itemContent, key, value, 0, y, 274, size or 12, color)
        return bottom + 16
    end
    if not row then return text("empty", "Select a loot row to inspect its recommendation and pricing.", 0, MUTED) end
    local e, value, quote = row.entry, row.value, row.quote
    local y = text("name", e.displayLink or e.name or e.link, 0, WHITE, 14)
    y = text("source", (sources[e.source] or e.source) .. " · quantity " .. e.quantity, y, MUTED)
    y = text("route", "Recommendation: " .. (value.route == "AH" and "Auction House" or value.route == "pending" and "Pending data" or "Vendor"), y, value.route == "AH" and GOLD or WHITE)
    y = text("reason", value.reason, y)
    y = text("vendor", "Vendor total: " .. (value.vendor and FG.Money(value.vendor) or "Pending"), y)
    y = text("proceeds", "Estimated AH proceeds: " .. FG.Money(value.ah or 0), y, GOLD)
    y = text("advantage", "Advantage over vendor: " .. FG.Money(value.upside or 0), y, GOLD)
    y = text("quote", quote and ("Quote per item: " .. FG.Money(quote.price) .. "\nQuote age: " .. (quote.age and string.format("%.1f days", quote.age) or "Unknown")) or "No cached AH quote.", y, MUTED)
    return y
end

function Report:Loot(t)
    for _, entry in ipairs({ { "itemHead", "Item", 0, 195 }, { "qtyHead", "Qty", 200, 40 }, { "routeHead", "Sell via", 245, 65 },
        { "valueHead", "Est. value", 315, 108 }, { "upsideHead", "AH advantage", 435, 110 } }) do
        self:Label(entry[1], entry[2], entry[3], 0, entry[4], 11, MUTED)
    end
    local selected, y = nil, 28
    for index, row in ipairs(t.rows) do
        local button = self.lootRows[index]
        if not button then
            button = CreateFrame("Button", nil, self.content)
            button:SetSize(548, 38)
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            button.selection = button:CreateTexture(nil, "BACKGROUND")
            button.selection:SetPoint("TOPLEFT"); button.selection:SetPoint("BOTTOMRIGHT")
            button.selection:SetColorTexture(0.2, 0.45, 0.65, 0.25)
            button:SetScript("OnClick", function()
                self.item = button.row.entry
                self.itemScroll:SetVerticalScroll(0)
                self:Refresh()
            end)
            button:SetScript("OnEnter", function(owner)
                local link = button.row.entry.displayLink or button.row.entry.link
                if link:find("item:", 1, true) then
                    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(link)
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.lootRows[index] = button
        end
        button.row = row
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", 0, -y); button:Show()
        local e, value = row.entry, row.value
        button.selection:SetShown(self.item == e)
        if self.item == e then selected = row end
        local key = "loot" .. index
        local name = self:Label(key, e.displayLink or e.name or e.link, 0, y + 6, 195, 12)
        name:SetWordWrap(false)
        self:Label(key .. "Qty", tostring(e.quantity), 200, y + 6, 40, 12)
        self:Label(key .. "Route", value.route == "AH" and "AH" or value.route == "pending" and "Pending" or "Vendor", 245, y + 6, 65, 12, value.route == "AH" and GOLD or WHITE)
        local amount = value.route == "AH" and value.ah or value.vendor
        self:Label(key .. "Value", amount and FG.Money(amount) or "Pending", 315, y + 6, 108, 11, GOLD, "RIGHT")
        self:Label(key .. "Upside", value.route == "AH" and ("+" .. FG.Money(value.upside)) or "—", 435, y + 6, 110, 11, GOLD, "RIGHT")
        y = y + 38
    end
    if #t.rows == 0 then self:Label("emptyLoot", "No items acquired in this session.", 0, 40, 540, 12, MUTED); y = 80 end
    self.itemContent:SetHeight(math.max(1, self:ItemDetails(selected)))
    return y + 20
end

function Report:Select(record)
    self.tab, self.item, self.scrolls = "overview", nil, {}
    self.scroll:SetVerticalScroll(0)
    self.itemScroll:SetVerticalScroll(0)
    self.ui.nameEdit:SetText(record.name or FG.LocationText(record.startLocation))
    self.ui.notesEdit:SetText(record.notes or "")
end

function Report:SetTab(tab)
    self.scrolls[self.tab] = self.scroll:GetVerticalScroll()
    self.tab = tab
    self.pendingScroll = self.scrolls[tab] or 0
    self:Refresh()
end

function Report:Refresh()
    local record = self.ui.selected
    if not record then return end
    local t = FG.Totals(record)
    local offset = self.pendingScroll or self.scroll:GetVerticalScroll()
    local itemOffset = self.itemScroll:GetVerticalScroll()
    self.pendingScroll = nil
    self.totals = t
    self.name:SetText(record.name or FG.LocationText(record.startLocation))
    self.character:SetText(record.character .. " — " .. record.realm .. " · Levels " .. record.levelStart .. "–" .. record.levelEnd)
    self.location:SetText(FG.LocationText(record.endLocation or record.startLocation))
    local status = self.Status(record, FG.db, FG.character)
    self.status:SetText(status)
    self.status:SetTextColor(unpack(status == "Running" and BLUE or (status == "Unsaved" or status == "Paused") and GOLD or WHITE))
    self.metrics.xpHour:SetText(FG.Short(t.xpHour))
    self.metrics.goldHour:SetText(FG.Money(t.goldHour))
    self.metrics.active:SetText(FG.Duration(record.active))
    self.metrics.xp:SetText(tostring(t.xp))
    for key, button in pairs(self.tabs) do button:SetEnabled(key ~= self.tab) end
    for _, label in pairs(self.labels) do label:Hide() end
    for _, label in pairs(self.itemLabels) do label:Hide() end
    for _, row in ipairs(self.lootRows) do row:Hide() end
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 20, -250)
    self.scroll:SetPoint("BOTTOMRIGHT", self.tab == "loot" and -350 or -32, 128)
    self.content:SetWidth(self.tab == "loot" and 550 or 860)
    self.itemScroll:SetShown(self.tab == "loot")
    local height
    if self.tab == "overview" then height = self:Overview(record, t)
    elseif self.tab == "loot" then height = self:Loot(t)
    else height = self:SessionDetails(record) end
    self.content:SetHeight(math.max(1, height))
    self.scroll:SetVerticalScroll(math.min(offset, math.max(0, height - self.scroll:GetHeight())))
    self.itemScroll:SetVerticalScroll(math.min(itemOffset, math.max(0, self.itemContent:GetHeight() - self.itemScroll:GetHeight())))
    self.ui.promote:SetEnabled(status == "Unsaved")
    self.ui.delete:SetEnabled(record.closed == true)
    self.ui.applyName:SetEnabled(true)
end

function Report.Create(ui)
    local Text, Button, Edit = ui.Widgets.Text, ui.Widgets.Button, ui.Widgets.Edit
    local frame = CreateFrame("Frame", nil, ui.journal)
    frame:SetSize(940, 600); frame:SetPoint("TOPLEFT")
    local self = setmetatable({ ui = ui, frame = frame, tab = "overview", scrolls = {}, labels = {}, itemLabels = {}, lootRows = {}, tabs = {}, metrics = {} }, Report)
    self.back = Button(frame, "< Back to sessions", 20, -42, 150, function() ui.ShowList(); ui.RefreshJournal() end)
    self.name = Text(frame, "", 20, -76, 700, 17); self.name:SetWordWrap(false)
    self.character = Text(frame, "", 20, -102, 700, 11); self.character:SetWordWrap(false)
    self.location = Text(frame, "", 20, -122, 880, 12); self.location:SetWordWrap(false)
    self.status = Text(frame, "", 740, -80, 165, 13); self.status:SetJustifyH("RIGHT")
    for index, metric in ipairs({ { "xpHour", "XP / HOUR", BLUE }, { "goldHour", "ESTIMATED GOLD / HOUR", GOLD },
        { "active", "ACTIVE TIME", WHITE }, { "xp", "TOTAL XP", BLUE } }) do
        local x = 20 + (index - 1) * 222
        Text(frame, metric[2], x, -164, 212, 10):SetTextColor(unpack(MUTED))
        local value = Text(frame, "", x, -184, 212, metric[1] == "goldHour" and 16 or 20)
        value:SetTextColor(unpack(metric[3])); value:SetWordWrap(false)
        self.metrics[metric[1]] = value
    end
    for index, tab in ipairs({ { "overview", "Overview" }, { "loot", "Loot" }, { "details", "Session details" } }) do
        local key = tab[1]
        self.tabs[key] = Button(frame, tab[2], 20 + (index - 1) * 142, -218, 136, function() self:SetTab(key) end)
    end
    self.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(860, 400); self.scroll:SetScrollChild(self.content)
    self.itemScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    self.itemScroll:SetPoint("TOPLEFT", 610, -250); self.itemScroll:SetPoint("BOTTOMRIGHT", -32, 128)
    self.itemContent = CreateFrame("Frame", nil, self.itemScroll)
    self.itemContent:SetSize(274, 400); self.itemScroll:SetScrollChild(self.itemContent)
    ui.nameEdit = Edit(frame, 20, -494, 290, "Session name")
    ui.notesEdit = Edit(frame, 330, -494, 394, "Notes (read in Session details)")
    ui.applyName = Button(frame, "Apply name / notes", 755, -510, 155, function()
        local record = ui.selected
        if record then
            local name = ui.nameEdit:GetText():match("^%s*(.-)%s*$")
            record.name = name ~= "" and name or FG.LocationText(record.endLocation or record.startLocation)
            record.notes = ui.notesEdit:GetText()
            ui.RefreshJournal()
        end
    end)
    ui.promote = Button(frame, "Keep session", 682, -42, 116, function()
        if ui.selected then FG.model:Promote(ui.selected.id); ui.RefreshJournal() end
    end, "Keep this temporary session permanently with its original location, timestamps, and estimates.")
    StaticPopupDialogs.FOREVER_GRIND_DELETE = {
        text = "Delete this session permanently?", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, record)
            for _, list in ipairs({ FG.db.saved, FG.db.temporary }) do
                for index, candidate in ipairs(list) do if candidate.id == record.id then table.remove(list, index); break end end
            end
            if ui.selected == record then ui.Select(nil) end
            ui.RefreshJournal()
        end,
    }
    ui.delete = Button(frame, "Delete", 808, -42, 100, function()
        if ui.selected and ui.selected.closed then StaticPopup_Show("FOREVER_GRIND_DELETE", nil, nil, ui.selected) end
    end)
    Text(frame, "Gold values are estimates. Saved and unsaved reports retain their closing prices.", 20, -554, 880, 10):SetTextColor(unpack(MUTED))
    return self
end
