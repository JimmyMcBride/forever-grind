local _, FG = ...
local UI = { tab = "saved", page = 1, sort = "endedAt", descending = true, dirty = true }
FG.UI = UI

local function Text(parent, text, x, y, width, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size or 11, "OUTLINE")
    label:SetPoint("TOPLEFT", x, y)
    if width then label:SetWidth(width) end
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Button(parent, text, x, y, width, callback, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return button
end

local function Edit(parent, x, y, width, label, callback)
    Text(parent, label, x, y, width, 10)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", x + 4, y - 16)
    box:SetText("")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if callback then callback() end end)
    if callback then box:SetScript("OnTextChanged", callback) end
    return box
end

local function Panel(name, title, width, height)
    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    panel:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
    Text(panel, title, 16, -14, width - 50, 15)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    UISpecialFrames[#UISpecialFrames + 1] = name
    panel:Hide()
    return panel
end

function UI.ApplyPosition()
    local settings = FG.db.settings
    UI.strip:SetScale(settings.scale)
    UI.strip:ClearAllPoints()
    local p = settings.position
    if p then UI.strip:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else UI.strip:SetPoint("TOP", UIParent, "TOP", 0, -60) end
end

function UI.Tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Forever Grind — " .. FG.character.mode)
    local record = FG.character.current
    if record then
        local t = FG.Totals(record)
        GameTooltip:AddLine("Active: " .. FG.Duration(record.active), 1, 1, 1)
        GameTooltip:AddLine(string.format("XP: %d (combat %d / quest %d / other %d)", t.xp, record.xp.combat, record.xp.quest, record.xp.other), 0.4, 0.75, 1, true)
        GameTooltip:AddLine("Looted coin: " .. FG.Money(record.coin.loot), 1, 1, 1)
        GameTooltip:AddLine("Quest gold: " .. FG.Money(record.coin.quest), 1, 1, 1)
        GameTooltip:AddLine("Vendor everything (items only): " .. FG.Money(t.baseline), 1, 1, 1)
        GameTooltip:AddLine("Vendor route: " .. FG.Money(t.vendor), 1, 1, 1)
        GameTooltip:AddLine("Estimated AH after cut: " .. FG.Money(t.ah), 1, 0.8, 0.2)
        GameTooltip:AddLine("Projected total: " .. FG.Money(t.projected), 1, 0.8, 0.2)
        GameTooltip:AddLine("Item value: drops " .. FG.Money(t.sources.loot) .. " / gathering, containers " .. FG.Money(t.sources.gathering) .. " / quests " .. FG.Money(t.sources.quest), 0.8, 0.8, 0.8, true)
        if t.pending > 0 then GameTooltip:AddLine(t.pending .. " item(s) awaiting valuation", 1, 0.6, 0.2) end
        local shown = 0
        for _, row in ipairs(t.rows) do
            if row.value.route == "AH" and shown < 3 then
                shown = shown + 1
                GameTooltip:AddLine("AH: " .. (row.entry.displayLink or row.entry.link) .. " x" .. row.entry.quantity .. " (advantage " .. FG.Money(row.value.upside) .. ")", 1, 0.8, 0.2, true)
            end
        end
    elseif FG.character.mode == "armed" then
        GameTooltip:AddLine("Waiting for first kill XP, or first confirmed corpse loot for zero-XP farming.", 1, 1, 1, true)
    else GameTooltip:AddLine("Press Play to arm a fresh session.", 1, 1, 1) end
    GameTooltip:AddLine("Estimate uses cached prices; excludes expenses and failed-listing costs.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(FG.XPBar.status or "Waiting for Blizzard XP bar.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function UI.Select(record)
    UI.selected = record
    UI.nameEdit:SetText(record and (record.name or FG.LocationText(record.startLocation)) or "")
    UI.notesEdit:SetText(record and (record.notes or "") or "")
end

function UI.Filter(record, filters)
    if filters.character ~= "" and not (record.character or ""):lower():find(filters.character:lower(), 1, true) then return false end
    if filters.realm ~= "" and not (record.realm or ""):lower():find(filters.realm:lower(), 1, true) then return false end
    if filters.location ~= "" then
        local haystack = ((record.name or "") .. " " .. FG.LocationText(record.endLocation or record.startLocation)):lower()
        if not haystack:find(filters.location:lower(), 1, true) then return false end
    end
    local minimum, maximum = tonumber(filters.minimum), tonumber(filters.maximum)
    if minimum and (record.levelEnd or record.levelStart) < minimum then return false end
    if maximum and record.levelStart > maximum then return false end
    return true
end

local function Details(record)
    if not record then return "Select a session to inspect its totals and items." end
    local t = FG.Totals(record)
    local lines = { record.name or "Current session", record.character .. " — " .. record.realm,
        "Levels " .. record.levelStart .. " → " .. record.levelEnd,
        "Started: " .. date("%Y-%m-%d %H:%M", record.startedAt),
        record.endedAt and ("Ended: " .. date("%Y-%m-%d %H:%M", record.endedAt)) or ("Status: " .. FG.character.mode),
        "Start: " .. FG.LocationText(record.startLocation),
        "Stop/save: " .. (record.endLocation and FG.LocationText(record.endLocation) or "Not stopped"),
        "Active: " .. FG.Duration(record.active) .. " / paused: " .. FG.Duration(record.paused + (record.pauseEpoch and math.max(0, time() - record.pauseEpoch) or 0)),
        string.format("XP %d (%s/h)", t.xp, FG.Short(t.xpHour)),
        string.format("Combat %d / quests %d / other %d", record.xp.combat, record.xp.quest, record.xp.other),
        "Looted coin: " .. FG.Money(record.coin.loot), "Quest gold: " .. FG.Money(record.coin.quest),
        "Vendor all items: " .. FG.Money(t.baseline), "Vendor route: " .. FG.Money(t.vendor),
        "Estimated AH proceeds: " .. FG.Money(t.ah), "Projected total: " .. FG.Money(t.projected),
        "Estimated value/h: " .. FG.Money(t.goldHour), "Vendor baseline/h (with coin): " .. FG.Money(t.vendorHour),
        "Item quantities: " .. t.quantity .. " / awaiting data: " .. t.pending }
    local pricing = record.pricing or FG.db.settings
    lines[#lines + 1] = string.format("AH cut %.1f%% / max quote age %.1f days / integration %s", pricing.ahCut, pricing.maxPriceAge, pricing.auctionator and "on" or "off")
    lines[#lines + 1] = record.closed and "Quotes frozen at stop; missing metadata may still resolve." or "Unfinished estimates refresh with Auctionator data."
    lines[#lines + 1] = "\nActive time by zone:"
    for _, zone in pairs(record.zones) do lines[#lines + 1] = (zone.zone or "Unknown") .. ": " .. FG.Duration(zone.seconds) end
    for _, warning in pairs(record.warnings) do lines[#lines + 1] = warning end
    lines[#lines + 1] = "\nItems — greatest AH advantage first:"
    for _, row in ipairs(t.rows) do
        local e, value, quote = row.entry, row.value, row.quote
        lines[#lines + 1] = string.format("\n[%s] %s x%d (%s)", value.route, e.displayLink or e.link, e.quantity, e.source)
        lines[#lines + 1] = "Vendor " .. (value.vendor and FG.Money(value.vendor) or "pending") .. " / AH " .. FG.Money(value.ah or 0)
        lines[#lines + 1] = value.reason
        if quote then lines[#lines + 1] = "Quote/unit " .. FG.Money(quote.price) .. " / age " .. tostring(quote.age or "unknown") .. "d / advantage " .. FG.Money(value.upside or 0) end
    end
    return table.concat(lines, "\n")
end

function UI.RefreshJournal()
    if not UI.journal:IsShown() then return end
    UI.dirty = false
    local list = UI.tab == "saved" and FG.db.saved or FG.db.temporary
    if UI.tab == "current" then list = FG.character.current and { FG.character.current } or {} end
    local filters = {}
    for key, box in pairs(UI.filters) do filters[key] = box:GetText() end
    local records = {}
    for _, record in ipairs(list) do if UI.Filter(record, filters) then records[#records + 1] = record end end
    table.sort(records, function(a, b)
        local function value(record)
            if UI.sort == "xpHour" or UI.sort == "goldHour" or UI.sort == "vendorHour" then return FG.Totals(record)[UI.sort] end
            return record[UI.sort] or 0
        end
        local left, right = value(a), value(b)
        if left == right then return a.id < b.id end
        if UI.descending then return left > right else return left < right end
    end)
    local pages = math.max(1, math.ceil(#records / #UI.rows))
    UI.page = math.min(UI.page, pages)
    UI.pageText:SetText(string.format("%d session(s) · page %d/%d", #records, UI.page, pages))
    for index, row in ipairs(UI.rows) do
        local record = records[(UI.page - 1) * #UI.rows + index]
        row.record = record
        row:SetShown(record ~= nil)
        if record then
            local t = FG.Totals(record)
            row.title:SetText(record.name or FG.LocationText(record.startLocation))
            row.subtitle:SetText(string.format("%s / %s · L%d–%d · %s", record.character, record.realm, record.levelStart, record.levelEnd, date("%m/%d %H:%M", record.startedAt)))
            row.xp:SetText(FG.Short(t.xpHour))
            row.gold:SetText(string.format("%.2fg", t.goldHour / 10000))
            row.vendor:SetText(string.format("%.2fg", t.vendorHour / 10000))
            row.active:SetText(FG.Duration(record.active))
        end
    end
    if UI.selected then
        local exists = UI.selected == FG.character.current
        for _, record in ipairs(FG.model:Records()) do if record == UI.selected then exists = true end end
        if not exists then UI.Select(nil) end
    end
    UI.detailText:SetText(Details(UI.selected))
    UI.detailContent:SetHeight(math.max(400, UI.detailText:GetStringHeight() + 20))
    UI.promote:SetEnabled(UI.selected ~= nil and UI.selected.closed and UI.tab == "temporary")
    UI.delete:SetEnabled(UI.selected ~= nil and UI.selected.closed == true)
    UI.applyName:SetEnabled(UI.selected ~= nil)
end

function UI.OpenJournal()
    UI.tab = FG.character.current and "current" or "saved"
    UI.page = 1
    UI.Select(FG.character.current)
    UI.journal:SetScale(math.min(1, (UIParent:GetWidth() - 32) / 940, (UIParent:GetHeight() - 32) / 600))
    UI.journal:Show()
    UI.RefreshJournal()
end

local function CreateJournal()
    local panel = Panel("ForeverGrindJournal", "Forever Grind — Session Journal", 940, 600)
    UI.journal, UI.filters, UI.rows = panel, {}, {}
    for index, tab in ipairs({ "saved", "temporary", "current" }) do
        local selected = tab
        Button(panel, tab == "temporary" and "Unsaved (20)" or tab:gsub("^%l", string.upper), 18 + (index - 1) * 110, -42, 104,
            function() UI.tab = selected; UI.page = 1; UI.Select(nil); UI.RefreshJournal() end)
    end
    local function filterChanged() UI.page = 1; UI.dirty = true end
    UI.filters.character = Edit(panel, 20, -78, 110, "Character", filterChanged)
    UI.filters.realm = Edit(panel, 145, -78, 110, "Realm", filterChanged)
    UI.filters.minimum = Edit(panel, 270, -78, 45, "Min level", filterChanged)
    UI.filters.maximum = Edit(panel, 330, -78, 45, "Max level", filterChanged)
    UI.filters.location = Edit(panel, 395, -78, 240, "Location / name", filterChanged)
    Text(panel, "Location / session", 20, -130, 245)
    for _, sort in ipairs({ { "XP/h", "xpHour", 285 }, { "Est g/h", "goldHour", 370 }, { "Vendor g/h", "vendorHour", 458 }, { "Active", "active", 548 } }) do
        local key = sort[2]
        Button(panel, sort[1], sort[3], -123, 82, function()
            if UI.sort == key then UI.descending = not UI.descending else UI.sort, UI.descending = key, true end
            UI.RefreshJournal()
        end)
    end
    for index = 1, 10 do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(620, 35)
        row:SetPoint("TOPLEFT", 20, -151 - (index - 1) * 36)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.title = Text(row, "", 0, 0, 255)
        row.title:SetWordWrap(false)
        row.subtitle = Text(row, "", 0, -17, 255, 9)
        row.subtitle:SetWordWrap(false)
        row.xp = Text(row, "", 270, 0, 78)
        row.gold = Text(row, "", 355, 0, 80)
        row.vendor = Text(row, "", 443, 0, 80)
        row.active = Text(row, "", 530, 0, 85)
        row:SetScript("OnClick", function() UI.Select(row.record); UI.RefreshJournal() end)
        UI.rows[index] = row
    end
    Button(panel, "<", 20, -520, 30, function() UI.page = math.max(1, UI.page - 1); UI.RefreshJournal() end)
    Button(panel, ">", 55, -520, 30, function() UI.page = UI.page + 1; UI.RefreshJournal() end)
    UI.pageText = Text(panel, "", 96, -525, 520)
    Text(panel, "Unsaved logs survive logout; oldest is removed when a 21st is added.", 20, -558, 615, 10)
    Text(panel, "Session details / item recommendations", 662, -46, 255)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 660, -70)
    scroll:SetPoint("BOTTOMRIGHT", -32, 156)
    UI.detailContent = CreateFrame("Frame", nil, scroll)
    UI.detailContent:SetSize(240, 400)
    scroll:SetScrollChild(UI.detailContent)
    UI.detailText = Text(UI.detailContent, "", 0, 0, 240, 11)
    UI.nameEdit = Edit(panel, 660, -460, 242, "Session name")
    UI.notesEdit = Edit(panel, 660, -502, 242, "Notes")
    UI.applyName = Button(panel, "Apply name / notes", 662, -552, 145, function()
        if UI.selected then
            local name = UI.nameEdit:GetText():match("^%s*(.-)%s*$")
            UI.selected.name = name ~= "" and name or FG.LocationText(UI.selected.endLocation or UI.selected.startLocation)
            UI.selected.notes = UI.notesEdit:GetText()
            UI.RefreshJournal()
        end
    end)
    UI.promote = Button(panel, "Keep", 812, -552, 44, function()
        if UI.selected then FG.model:Promote(UI.selected.id); UI.tab = "saved"; UI.RefreshJournal() end
    end, "Keep selected temporary session permanently, preserving its original stop location and estimates.")
    StaticPopupDialogs.FOREVER_GRIND_DELETE = {
        text = "Delete this session permanently?", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, record)
            for _, list in ipairs({ FG.db.saved, FG.db.temporary }) do
                for index, candidate in ipairs(list) do if candidate.id == record.id then table.remove(list, index); break end end
            end
            UI.Select(nil); UI.RefreshJournal()
        end,
    }
    UI.delete = Button(panel, "Delete", 861, -552, 50, function()
        if UI.selected then StaticPopup_Show("FOREVER_GRIND_DELETE", nil, nil, UI.selected) end
    end)
end

local function CreateSettings()
    local host = CreateFrame("Frame")
    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(560, 600)
    scroll:SetScrollChild(panel)
    Text(panel, "Forever Grind", 16, -18, 520, 16)
    local y = -54
    for _, item in ipairs({ { "auctionator", "Use Auctionator estimates" }, { "xpText", "Show XP / completed-quest text on Blizzard bar" },
        { "questOverlay", "Highlight completed-quest XP" }, { "locked", "Lock compact strip position" } }) do
        local key = item[1]
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(26, 26); check:SetPoint("TOPLEFT", 14, y)
        Text(check, item[2], 30, -7, 500)
        check:SetScript("OnShow", function() check:SetChecked(FG.db.settings[key]) end)
        check:SetScript("OnClick", function()
            FG.db.settings[key] = check:GetChecked() == true
            FG.Reprice(); FG.XPBar:Refresh(); UI.Refresh()
        end)
        y = y - 34
    end
    local cut = Edit(panel, 18, -204, 100, "AH cut (%)")
    local age = Edit(panel, 150, -204, 150, "Max quote age (days)")
    local scale = Edit(panel, 332, -204, 100, "Strip scale (0.6–2)")
    panel:SetScript("OnShow", function()
        cut:SetText(tostring(FG.db.settings.ahCut)); age:SetText(tostring(FG.db.settings.maxPriceAge)); scale:SetText(tostring(FG.db.settings.scale))
    end)
    Button(panel, "Apply", 18, -254, 90, function()
        FG.db.settings.ahCut = math.max(0, math.min(100, tonumber(cut:GetText()) or FG.db.settings.ahCut))
        FG.db.settings.maxPriceAge = math.max(0, math.min(3650, tonumber(age:GetText()) or FG.db.settings.maxPriceAge))
        FG.db.settings.scale = math.max(0.6, math.min(2, tonumber(scale:GetText()) or FG.db.settings.scale))
        UI.ApplyPosition(); FG.Reprice(); UI.Refresh()
    end)
    Button(panel, "Reset strip position", 124, -254, 160, function() FG.db.settings.position = nil; UI.ApplyPosition() end)
    UI.settingsStatus = Text(panel, "", 18, -306, 530)
    Text(panel, "All settings are account-wide. Unfinished sessions remain per character.\n\nAuctionator uses prices already scanned by the user. No automatic scans or sales. Estimates exclude expenses, deposits lost on failed listings, and future market changes. Missing/stale quotes use vendor fallback.\n\nDisable Grinding Made Simple's duplicate display and any option hiding Blizzard's XP bar. Other XP-bar replacements may prevent native-bar enhancements; session tracking stays available.\n\n/fg opens journal. /fg settings opens this panel. /fg play, pause, stop, save control sessions.", 18, -372, 530)
    UI.category = Settings.RegisterCanvasLayoutCategory(host, FG.title)
    Settings.RegisterAddOnCategory(UI.category)
end

function UI.Refresh()
    if not UI.strip then return end
    local record, mode = FG.character.current, FG.character.mode
    local t = record and FG.Totals(record)
    UI.xp:SetText("XP/h " .. (t and record.active >= 1 and FG.Short(t.xpHour) or "—"))
    UI.gold:SetText("Est/h " .. (t and record.active >= 1 and string.format("%.2fg", t.goldHour / 10000) or "—"))
    UI.clock:SetText(record and FG.Duration(record.active) or (mode == "armed" and "Armed" or "Stopped"))
    UI.clock:SetTextColor(mode == "paused" and 1 or 0.8, mode == "paused" and 0.65 or 0.9, mode == "paused" and 0.2 or 0.8)
    UI.play:SetText(mode == "running" and "Pause" or (mode == "armed" and "Wait" or "Play"))
    UI.save:SetEnabled(record ~= nil)
    UI.stop:SetEnabled(record ~= nil or mode == "armed")
    UI.settingsStatus:SetText((Auctionator and Auctionator.API and "Auctionator API available." or "Auctionator not available: vendor estimates only.") .. "\n" .. (FG.XPBar.status or "Waiting for Blizzard XP bar."))
    if UI.dirty or UI.tab == "current" then UI.RefreshJournal() end
end

function UI.Create()
    local strip = CreateFrame("Frame", "ForeverGrindStrip", UIParent, "BackdropTemplate")
    UI.strip = strip
    strip:SetSize(572, 30)
    strip:SetClampedToScreen(true); strip:SetMovable(true); strip:EnableMouse(true); strip:RegisterForDrag("LeftButton")
    strip:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    strip:SetBackdropColor(0.03, 0.03, 0.04, 0.9)
    strip:SetScript("OnDragStart", function(self) if not FG.db.settings.locked then self:StartMoving() end end)
    strip:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        FG.db.settings.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    strip:SetScript("OnEnter", UI.Tooltip); strip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.play = Button(strip, "Wait", 5, -4, 46, function()
        local mode = FG.character.mode
        FG.Action((mode == "running" or mode == "armed") and "pause" or "play")
    end, "Play arms a new run or resumes a paused run. Pause excludes time and gains. Wait means armed; click to disarm.")
    UI.xp = Text(strip, "", 60, -9, 120)
    UI.xp:SetTextColor(0.35, 0.75, 1)
    UI.gold = Text(strip, "", 186, -9, 136)
    UI.gold:SetTextColor(1, 0.8, 0.25)
    UI.clock = Text(strip, "", 330, -9, 76)
    UI.stop = Button(strip, "Stop", 410, -4, 38, function() FG.Action("stop") end, "Stop into temporary history. Latest 20 unsaved runs survive logout.")
    UI.save = Button(strip, "Save", 451, -4, 38, function() FG.Action("save") end, "Stop and keep this session permanently.")
    Button(strip, "Log", 492, -4, 34, UI.OpenJournal, "Open current session, saved history, and temporary logs.")
    Button(strip, "...", 530, -4, 34, function() Settings.OpenToCategory(UI.category:GetID()) end, "Settings")
    CreateJournal(); CreateSettings(); UI.ApplyPosition()
    SLASH_FOREVERGRIND1 = "/fg"
    SlashCmdList.FOREVERGRIND = function(message)
        message = (message or ""):lower():match("^%s*(.-)%s*$")
        if message == "settings" or message == "options" then Settings.OpenToCategory(UI.category:GetID())
        elseif message == "play" or message == "pause" or message == "stop" or message == "save" then FG.Action(message)
        else UI.OpenJournal() end
    end
    UI.Refresh()
end
