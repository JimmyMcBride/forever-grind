local _, FG = ...
local Collector = {}
Collector.__index = Collector
FG.Collector = Collector

function Collector.New(model, api)
    return setmetatable({ model = model, api = api, pending = {}, seen = {}, seenOrder = {},
        credits = {}, offers = {}, offerSerial = 0 }, Collector)
end

function Collector:Queue(event)
    local mode = self.model.character.mode
    if mode ~= "running" and mode ~= "armed" then return end
    event.context = event.context or self.api.context()
    event.now, event.epoch = self.api.now(), self.api.epoch()
    self.pending[#self.pending + 1] = event
    if not self.scheduled then
        self.scheduled = true
        self.scheduleToken = (self.scheduleToken or 0) + 1
        local token = self.scheduleToken
        self.api.after(0.05, function() if token == self.scheduleToken then self:Flush() end end)
    end
end

function Collector:Unique(kind, id)
    if not id or id == 0 or id == "" then return true end
    local key = kind .. ":" .. tostring(id)
    if self.seen[key] then return false end
    self.seen[key] = true
    self.seenOrder[#self.seenOrder + 1] = key
    if #self.seenOrder > 256 then self.seen[table.remove(self.seenOrder, 1)] = nil end
    return true
end

function Collector:ObserveXP(snapshot)
    local delta, jump = FG.Parsing.XPDelta(self.previousXP, snapshot)
    self.previousXP = snapshot
    if delta > 0 then self:Queue({ kind = "xp", amount = delta, jump = jump }) end
end

function Collector:Rebaseline()
    self.previousXP = self.api.xp()
    self.credits, self.deaths, self.recentXP = {}, {}, {}
end

function Collector:Loot(text, lineID)
    if not self:Unique("loot", lineID) then return end
    local link, quantity = FG.Parsing.Item(text, self.api.globals)
    if not link then return end
    link = self.api.resolveLink(link)
    local origin = self.api.lootOrigin(link, quantity)
    self:Queue({ kind = "item", link = link, quantity = quantity,
        source = origin == "gathering" and "gathering" or "loot", corpse = origin == "corpse" })
end

function Collector:Money(text, lineID)
    if not self:Unique("money", lineID) then return end
    local amount = FG.Parsing.Money(text, self.api.globals)
    if amount and amount > 0 then
        self:Queue({ kind = "coin", amount = amount, corpse = self.api.lootOrigin(nil, amount) == "corpse" })
    end
end

function Collector:Kill(text, lineID)
    local mode = self.model.character.mode
    if mode ~= "running" and mode ~= "armed" then return end
    local amount, name = FG.Parsing.KillXP(text, self.api.globals)
    if amount and self:Unique("kill", lineID) then
        local record = self.model.character.current
        if record and record.route and lineID and record.route.lines[tostring(lineID)] then return end
        self:Queue({ kind = "kill", source = "xp", amount = amount, name = name, lineID = lineID })
    end
end

function Collector:Death(guid)
    local mode = self.model.character.mode
    if mode ~= "running" and mode ~= "armed" then return end
    self.deaths = self.deaths or {}
    local epoch = self.api.epoch()
    for key, event in pairs(self.deaths) do if epoch - event.epoch > 2 then self.deaths[key] = nil end end
    local record = self.model.character.current
    local index = record and record.route and record.route.guids[guid]
    local kill = index and record.route.kills[index]
    if kill and not record.closed and not kill.deathObserved then
        kill.deathObserved = true; record.route.revision = record.route.revision + 1
    end
    self.deaths[guid] = { context = self.api.context(), now = self.api.now(), epoch = epoch }
end

function Collector:PartyKill(guid, name, npcID)
    local mode = self.model.character.mode
    if mode ~= "running" and mode ~= "armed" then return end
    local death = self.deaths and self.deaths[guid]
    local event = { kind = "kill", source = "party", amount = 0, guid = guid, name = name, npcID = npcID }
    if death and self.api.now() - death.now <= 2 then event.context, event.deathNow = death.context, death.now end
    self:Queue(event)
end

function Collector:Offer(offer)
    self.offerSerial = self.offerSerial + 1
    offer.serial = self.offerSerial
    self.offers[offer.id] = offer
    self.latestOffer = offer
end

function Collector:Choice(index)
    if self.latestOffer then self.latestOffer.choice = index end
end

function Collector:AddItem(link, quantity, source)
    local record, entry = self.model:Item(link, quantity, source)
    if entry then self.api.loadItem(record, entry) end
end

function Collector:Flush()
    self.scheduled = false
    self.scheduleToken = (self.scheduleToken or 0) + 1
    local events = self.pending
    self.pending = {}
    if #events == 0 then return end
    local mode = self.model.character.mode
    if mode ~= "armed" and mode ~= "running" then return end
    local trigger, killStart
    if mode == "armed" then
        for index, event in ipairs(events) do
            if event.kind == "kill" then trigger, killStart = index, true; break end
        end
        if not trigger then
            for index, event in ipairs(events) do
                if event.corpse then trigger = index; break end
            end
        end
        if not trigger then return end
        local event = events[trigger]
        self.model:Start(event.now, event.epoch, event.context)
    end
    self.model:Tick(self.api.now(), self.api.context().location)
    local delta, jump, excludedQuestXP = 0, false, 0
    local questSeen = {}
    for index, event in ipairs(events) do
        local included = not trigger or index >= trigger
        if event.kind == "xp" and (included or killStart) then
            delta, jump = delta + event.amount, jump or event.jump
        elseif event.kind == "kill" and included then
            event.processedAt = self.api.now()
            local kill, duplicate = FG.Kills.Record(self.model.character.current, event)
            if event.source == "xp" and not duplicate then
                self.credits[#self.credits + 1] = { kind = "combat", amount = event.amount, at = event.now, kill = kill }
            end
        elseif event.kind == "coin" and included then
            self.model:Coin(event.amount, "loot")
        elseif event.kind == "item" and included then
            self:AddItem(event.link, event.quantity, event.source)
        elseif event.kind == "quest" then
            local offer = event.offer or self.offers[event.id]
            local identity = offer and ("offer:" .. offer.serial) or ("quest:" .. event.id)
            local duplicate = questSeen[identity] or (offer and offer.used)
            questSeen[identity] = true
            if included and not duplicate then
                self.credits[#self.credits + 1] = { kind = "quest", amount = event.xp, at = event.now }
                self.model:Coin(event.money, "quest")
                if offer and not offer.used then
                    offer.used = true
                    for _, reward in pairs(offer.rewards) do self:AddItem(reward.link, reward.quantity, "quest") end
                    local choices = offer.choiceCount or #offer.choices
                    local choice = offer.choices[offer.choice or (choices == 1 and 1 or 0)]
                    if choice then self:AddItem(choice.link, choice.quantity, "quest")
                    elseif choices > 0 and not (offer.nonItems and offer.nonItems[offer.choice or 0]) then
                        self.model.character.current.warnings.questChoice = "A quest reward choice could not be observed."
                    end
                elseif not offer then
                    self.model.character.current.warnings.questOffer = "A quest reward offer was not visible; reward items may be incomplete."
                end
            elseif not included and not duplicate then excludedQuestXP = excludedQuestXP + event.xp end
        end
    end
    delta = math.max(0, delta - excludedQuestXP)
    local now, usable, known = self.api.now(), {}, 0
    for _, credit in ipairs(self.credits) do
        if now - credit.at <= 2 then usable[#usable + 1] = credit; known = known + credit.amount end
    end
    self.credits = usable
    if jump then delta = math.max(delta, known) end
    if delta > 0 then
        local remaining = delta
        -- Quest rewards have an authoritative numeric payload; allocate those first.
        for _, kind in ipairs({ "quest", "combat" }) do
            for _, credit in ipairs(usable) do
                if credit.kind == kind then
                    local amount = math.min(remaining, credit.amount)
                    self.model:XP(amount, kind)
                    if kind == "combat" then FG.Kills.Assign(self.model.character.current, credit.kill, amount) end
                    remaining = remaining - amount
                    credit.amount = credit.amount - amount
                end
            end
        end
        local onlyCombat = #usable > 0
        for _, credit in ipairs(usable) do if credit.kind ~= "combat" then onlyCombat = false end end
        self.model:XP(remaining, onlyCombat and "combat" or "other")
        if remaining > 0 and not onlyCombat then
            self.recentXP = self.recentXP or {}
            self.recentXP[#self.recentXP + 1] = { amount = remaining, at = now, record = self.model.character.current }
        end
    end
    -- A unit-XP update may precede its localized kill notification. Reclassify
    -- only already-counted, recent Other XP; never add the message a second time.
    local recent = {}
    for _, packet in ipairs(self.recentXP or {}) do
        if packet.record == self.model.character.current and now - packet.at <= 2 then recent[#recent + 1] = packet end
    end
    for _, credit in ipairs(usable) do
        if credit.kind == "combat" and credit.amount > 0 then
            for index = #recent, 1, -1 do
                local packet = recent[index]
                if math.abs(packet.at - credit.at) <= 2 then
                    local amount = math.min(packet.amount, credit.amount)
                    self.model.character.current.xp.other = self.model.character.current.xp.other - amount
                    self.model:XP(amount, "combat")
                    FG.Kills.Assign(self.model.character.current, credit.kill, amount)
                    packet.amount, credit.amount = packet.amount - amount, credit.amount - amount
                end
            end
        end
    end
    self.recentXP, self.credits = recent, {}
    for _, credit in ipairs(usable) do if credit.amount > 0 then self.credits[#self.credits + 1] = credit end end
    self.api.changed()
end

function Collector:Boundary()
    self:ObserveXP(self.api.xp())
    self:Flush()
    self:Rebaseline()
end
