local _, FG = ...
local XPBar = { attached = {}, questXP = 0, missing = 0, requested = {} }
FG.XPBar = XPBar

function XPBar.Project(xp, maximum, quests)
    if maximum <= 0 then return { start = 0, length = 0, overflow = 0, percent = 0 } end
    return { start = math.min(1, xp / maximum),
        length = math.max(0, math.min(maximum, xp + quests) - xp) / maximum,
        overflow = math.max(0, xp + quests - maximum), percent = (xp + quests) * 100 / maximum }
end

function XPBar:ScanQuests()
    self.questXP, self.missing = 0, 0
    if not C_QuestLog or not C_QuestLog.GetQuestIDForLogIndex or not GetQuestLogRewardXP then return end
    for index = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local id = C_QuestLog.GetQuestIDForLogIndex(index)
        if id and id > 0 and C_QuestLog.IsComplete(id) then
            local known = not HaveQuestRewardData or HaveQuestRewardData(id)
            local xp = known and GetQuestLogRewardXP(id) or nil
            if type(xp) == "number" then self.questXP = self.questXP + math.max(0, xp)
            else
                self.missing = self.missing + 1
                if not self.requested[id] and C_QuestLog.RequestLoadQuestByID then
                    self.requested[id] = true
                    C_QuestLog.RequestLoadQuestByID(id)
                end
            end
        end
    end
end

function XPBar:Tooltip()
    local current, maximum = UnitXP("player"), UnitXPMax("player")
    local projection = self.Project(current, maximum, self.questXP)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Forever Grind: completed quests", 1, 0.8, 0.2)
    GameTooltip:AddLine(string.format("Current: %d / %d XP (%.1f%%)", current, maximum,
        maximum > 0 and current * 100 / maximum or 0), 1, 1, 1, true)
    GameTooltip:AddLine(string.format("Ready rewards: +%d XP; projected %.1f%% of current level", self.questXP, projection.percent), 1, 1, 1, true)
    if current + self.questXP >= maximum and maximum > 0 then
        GameTooltip:AddLine(string.format("Level ready; %d XP beyond current requirement", projection.overflow), 1, 0.8, 0.2, true)
    end
    if self.missing > 0 then GameTooltip:AddLine(self.missing .. " completed quest(s) awaiting reward data", 1, 0.6, 0.2) end
    GameTooltip:AddLine("Projection uses current quest rewards; rested XP is separate.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function XPBar:Paint(state)
    if not FG.db then return end
    local bar, region = state.bar, state.bar.StatusBar
    local current, maximum = UnitXP("player"), UnitXPMax("player")
    local projection = self.Project(current, maximum, self.questXP)
    local width = region:GetWidth()
    state.fill:ClearAllPoints()
    state.fill:SetPoint("TOPLEFT", region, "TOPLEFT", width * projection.start, 0)
    state.fill:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", width * projection.start, 0)
    state.fill:SetWidth(math.max(0.01, width * projection.length))
    state.fill:SetShown(FG.db.settings.questOverlay and bar:IsShown() and projection.length > 0)
    local text = bar.OverlayFrame and bar.OverlayFrame.Text
    if text and FG.db.settings.xpText and maximum > 0 then
        local suffix = current + self.questXP >= maximum
            and string.format("Level ready (+%d beyond)", projection.overflow)
            or string.format("after turn-ins %.1f%%", projection.percent)
        local long = string.format("%d / %d XP (%.1f%%) | Quests +%d | %s%s",
            current, maximum, current * 100 / maximum, self.questXP, suffix, self.missing > 0 and " [partial]" or "")
        text:SetText(long)
        if text:GetStringWidth() > width - 12 then
            text:SetText(string.format("%.1f%% | +%s quest XP | %s%s", current * 100 / maximum,
                FG.Short(self.questXP), suffix, self.missing > 0 and " [partial]" or ""))
        end
        if text:GetStringWidth() > width - 12 then
            local short = current + self.questXP >= maximum and ("Level ready +" .. FG.Short(projection.overflow))
                or string.format("→ %.1f%%", projection.percent)
            text:SetText(string.format("%.1f%% %s%s", current * 100 / maximum, short, self.missing > 0 and "*" or ""))
        end
        if text:GetStringWidth() > width - 12 then text:SetText(string.format("%.0f%%", current * 100 / maximum)) end
        text:Show()
        state.textActive = true
    elseif text and state.textActive then
        state.textActive = false
        bar:UpdateCurrentText()
        bar:UpdateTextVisibility()
    end
end

function XPBar:Attach(bar)
    if self.attached[bar] or not bar.StatusBar then return end
    local fill = bar.StatusBar:CreateTexture(nil, "OVERLAY", nil, 1)
    fill:SetColorTexture(1, 0.72, 0.12, 0.8)
    local state = { bar = bar, fill = fill }
    self.attached[bar] = state
    local function paint() self:Paint(state) end
    hooksecurefunc(bar, "UpdateCurrentText", paint)
    hooksecurefunc(bar, "UpdateTextVisibility", paint)
    bar.StatusBar:HookScript("OnSizeChanged", paint)
    bar:HookScript("OnShow", paint)
    bar:HookScript("OnEnter", function() self:Tooltip() end)
    paint()
end

function XPBar:Refresh()
    local manager = StatusTrackingBarManager
    local visible = false
    for _, container in ipairs(manager and manager.barContainers or {}) do
        for key, bar in pairs(container.bars or {}) do
            if bar.isExpBar or (StatusTrackingBarInfo and key == StatusTrackingBarInfo.BarsEnum.Experience) then
                self:Attach(bar)
                if self.attached[bar] then self:Paint(self.attached[bar]) end
                visible = visible or bar:IsVisible()
            end
        end
    end
    self.status = visible and "Blizzard XP bar augmented."
        or "Blizzard XP bar unavailable/hidden (or level capped). Session tracking remains available."
end
