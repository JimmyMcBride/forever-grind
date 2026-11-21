local _, FG = ...
local Kills = {}
FG.Kills = Kills

function Kills.Identity(guid)
    guid = FG.Plain(guid)
    if type(guid) ~= "string" then return end
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function Key(kill)
    return kill.npcID and ("npc:" .. kill.npcID) or kill.name and ("name:" .. kill.name) or "unknown"
end

local function ChangeMob(route, kill, sign)
    local key = Key(kill)
    local mob = route.mobs[key]
    if not mob then
        mob = { name = kill.name or (kill.npcID and ("Unknown creature #" .. kill.npcID) or "Unknown creature"),
            npcID = kill.npcID, count = 0, xp = 0 }; route.mobs[key] = mob
    end
    mob.count, mob.xp = mob.count + sign, mob.xp + sign * (kill.xp or 0)
    if kill.name then mob.name = kill.name end
    if mob.count == 0 then route.mobs[key] = nil end
    kill.key = key
end

function Kills.Record(record, event)
    if not record or record.closed then return end
    local route = FG.Route.Ensure(record)
    local isXP = event.source == "xp"
    if isXP and event.lineID and route.lines[tostring(event.lineID)] then return nil, true end
    if isXP and event.lineID then route.lines[tostring(event.lineID)] = true end
    local index = event.guid and route.guids[event.guid]
    local kill = index and route.kills[index]
    if index ~= nil then return kill, true end
    if not kill then
        local candidates, unknown, ids = {}, {}, {}
        for i = #route.kills, 1, -1 do
            local candidate = route.kills[i]
            if event.now - candidate.when > 2 then break end
            if candidate.generation == route.generation and math.abs(event.now - candidate.when) <= 2 and (not event.name or not candidate.name)
                and ((isXP and candidate.party and not candidate.chat) or (not isXP and candidate.chat and not candidate.party and not candidate.unresolvedParty)) then
                unknown[#unknown + 1] = candidate
            end
            if candidate.generation == route.generation and math.abs(event.now - candidate.when) <= 2 and event.name and candidate.name == event.name
                and ((isXP and candidate.party and not candidate.chat) or (not isXP and candidate.chat and not candidate.party)) then
                candidates[#candidates + 1] = candidate
                ids[tostring(candidate.npcID or event.npcID or "?")] = true
            end
        end
        if #candidates == 0 and #unknown > 0 then
            route.notices.identity = "Some GUID/name reports could not be matched confidently; possible duplicate reports were suppressed and counts or per-mob XP may be incomplete."
            route.revision = route.revision + 1
            local candidate = unknown[#unknown]
            if isXP then candidate.chat = true
            else candidate.unresolvedParty = true; route.guids[event.guid] = 0 end
            return nil, false
        end
        local distinct = 0
        for _ in pairs(ids) do distinct = distinct + 1 end
        if distinct > 1 then
            route.notices.ambiguous = "Some same-name kills could not be matched confidently; their XP remains unassigned."
            route.revision = route.revision + 1
            if isXP then return nil, false end
        elseif #candidates > 0 then kill = candidates[#candidates] end
    end
    if kill then
        ChangeMob(route, kill, -1)
        if event.guid then kill.guid, kill.npcID = event.guid, event.npcID end
        kill.name = event.name or kill.name
    else
        kill = { guid = event.guid, npcID = event.npcID, name = event.name, epoch = event.epoch, when = event.now, generation = route.generation,
            at = math.max(0, record.active - math.max(0, (event.processedAt or event.now) - (event.deathNow or event.now))),
            location = FG.Copy(event.context.location), xp = 0 }
        route.kills[#route.kills + 1] = kill
    end
    if event.deathNow then kill.deathObserved = true end
    if isXP then kill.chat = true else kill.party = true end
    ChangeMob(route, kill, 1)
    if kill.guid then
        -- Index assignment is once per kill, without scanning the complete ledger.
        if not route.guids[kill.guid] then
            if route.kills[#route.kills] == kill then route.guids[kill.guid] = #route.kills
            else for i = #route.kills, 1, -1 do if route.kills[i] == kill then route.guids[kill.guid] = i; break end end end
        end
    end
    route.revision = route.revision + 1
    return kill, false
end

function Kills.Assign(record, kill, amount)
    if not kill or amount <= 0 or record.closed then return end
    local route = record.route
    kill.xp = kill.xp + amount
    route.mobs[kill.key].xp = route.mobs[kill.key].xp + amount
    route.assignedXP, route.revision = route.assignedXP + amount, route.revision + 1
end
