local _, FG = ...
local Session = {}
Session.__index = Session
FG.Session = Session

function Session.New(db, character)
    return setmetatable({ db = db, character = character }, Session)
end

function Session:Start(now, epoch, context)
    if self.character.mode ~= "armed" then return end
    local record = { id = tostring(epoch) .. ":" .. tostring(self.db.nextID),
        character = context.character, realm = context.realm, guid = context.guid,
        levelStart = context.level, levelEnd = context.level, startedAt = epoch,
        startLocation = FG.Copy(context.location), active = 0, paused = 0,
        xp = { combat = 0, quest = 0, other = 0 }, coin = { loot = 0, quest = 0 },
        items = {}, zones = {}, warnings = {} }
    self.db.nextID = self.db.nextID + 1
    self.character.current, self.character.mode = record, "running"
    self.lastTick, self.lastLocation = now, FG.Copy(context.location)
    FG.Route.Ensure(record)
    FG.Route.Sample(record, context.location, true)
    return record
end

function Session:Tick(now, location)
    local record = self.character.current
    if record and self.character.mode == "running" then
        local elapsed = math.max(0, now - (self.lastTick or now))
        record.active = record.active + elapsed
        local previous = self.lastLocation or location or {}
        local key = tostring(previous.mapID or "?") .. ":" .. (previous.zone or "Unknown")
        record.zones[key] = record.zones[key] or { zone = previous.zone, mapID = previous.mapID, seconds = 0 }
        record.zones[key].seconds = record.zones[key].seconds + elapsed
        self.lastTick, self.lastLocation = now, FG.Copy(location)
        FG.Route.Sample(record, location)
    end
end

function Session:Pause(now, epoch, location)
    if self.character.mode == "armed" then self.character.mode = "stopped"; return end
    if self.character.mode ~= "running" then return end
    self:Tick(now, location)
    FG.Route.Sample(self.character.current, location, true)
    FG.Route.Break(self.character.current)
    self.character.current.pauseEpoch = epoch
    self.character.mode = "paused"
end

function Session:Play(now, epoch, location)
    local record = self.character.current
    if record and self.character.mode == "paused" then
        record.paused = record.paused + math.max(0, epoch - (record.pauseEpoch or epoch))
        record.pauseEpoch = nil
        self.character.mode = "running"
        self.lastTick, self.lastLocation = now, FG.Copy(location)
        FG.Route.Ensure(record).generation = (record.route.generation or 1) + 1
        FG.Route.Break(record)
        FG.Route.Sample(record, location, true)
    elseif not record then
        self.character.mode = "armed"
    end
end

function Session:XP(amount, kind)
    local record = self.character.current
    if record and self.character.mode == "running" and amount > 0 then
        record.xp[kind] = record.xp[kind] + amount
    end
end

function Session:Coin(amount, source)
    local record = self.character.current
    if record and self.character.mode == "running" and amount > 0 then
        record.coin[source] = record.coin[source] + amount
    end
end

function Session:Item(link, quantity, source)
    local record = self.character.current
    if not record or self.character.mode ~= "running" or quantity <= 0 then return end
    local key = (link:match("|H(item:[^|]+)") or link) .. ":" .. source
    local entry = record.items[key]
    if not entry then
        entry = { link = link, quantity = 0, source = source }
        record.items[key] = entry
    end
    entry.quantity = entry.quantity + quantity
    return record, entry
end

function Session:Stop(permanent, now, epoch, context)
    local record = self.character.current
    if not record then self.character.mode = "stopped"; return end
    self:Tick(now, context.location)
    if self.character.mode == "paused" then
        record.paused = record.paused + math.max(0, epoch - (record.pauseEpoch or epoch))
    end
    if self.character.mode == "running" then FG.Route.Sample(record, context.location, true) end
    record.pauseEpoch = nil
    record.endedAt, record.endLocation = epoch, FG.Copy(context.location)
    record.levelEnd, record.closed = context.level, true
    record.name = record.name or FG.LocationText(record.endLocation)
    record.notes = record.notes or ""
    local destination = permanent and self.db.saved or self.db.temporary
    destination[#destination + 1] = record
    while #self.db.temporary > 20 do table.remove(self.db.temporary, 1) end
    self.character.current, self.character.mode = nil, "stopped"
    self.lastTick, self.lastLocation = nil, nil
    return record
end

function Session:Promote(id)
    for index, record in ipairs(self.db.temporary) do
        if record.id == id then
            table.remove(self.db.temporary, index)
            self.db.saved[#self.db.saved + 1] = record
            return record
        end
    end
end

function Session:Records()
    local records = {}
    if self.character.current then records[#records + 1] = self.character.current end
    for _, list in ipairs({ self.db.saved, self.db.temporary }) do
        for _, record in ipairs(list) do records[#records + 1] = record end
    end
    return records
end
