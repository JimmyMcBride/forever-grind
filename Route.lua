local _, FG = ...
local Route = {}
FG.Route = Route

function FG.Plain(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

function Route.Valid(p)
    return p and type(p.mapID) == "number" and type(p.x) == "number" and type(p.y) == "number"
        and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 and not (p.x == 0 and p.y == 0)
end

function Route.Ensure(record, partial)
    if not record.route then
        record.route = { version = 1, points = {}, kills = {}, mobs = {}, guids = {}, lines = {},
            revision = 0, segment = 0, generation = 1, pendingBreak = true, assignedXP = 0, notices = {} }
        if partial then record.route.notices.legacy = "Recording began after this session started; route and mob history are partial." end
    end
    return record.route
end

function Route.Distance(a, b)
    if not Route.Valid(a) or not Route.Valid(b) or a.mapID ~= b.mapID then return end
    local width, height = b.width or a.width, b.height or a.height
    if not width or not height or width <= 0 or height <= 0 then return end
    return math.sqrt(((a.x - b.x) * width) ^ 2 + ((a.y - b.y) * height) ^ 2)
end

function Route.Break(record)
    if record and record.route and not record.closed then
        record.route.pendingBreak, record.route.observed = true, nil
    end
end

function Route.Sample(record, location, force)
    if not record or record.closed then return end
    local route = Route.Ensure(record)
    if not Route.Valid(location) then
        if not route.notices.coordinates then route.revision = route.revision + 1 end
        route.notices.coordinates = "Some locations were unavailable; the route has gaps."
        Route.Break(record)
        return
    end
    local active = record.active
    local previous = route.observed
    if previous then
        local distance = Route.Distance(previous, location)
        if previous.mapID ~= location.mapID or (distance and distance > 100 * math.max(0.01, active - previous.at)) then
            route.pendingBreak = true
        end
    end
    route.observed = FG.Copy(location); route.observed.at = active
    local last = route.points[#route.points]
    if not force and not route.pendingBreak and active - (route.sampleAt or 0) < 2 then return end
    route.sampleAt = active
    local distance = last and Route.Distance(last, location)
    local moved = not last or last.x ~= location.x or last.y ~= location.y or last.mapID ~= location.mapID
    if not moved and not route.pendingBreak then return end
    if not force and not route.pendingBreak and distance and distance < 5 then return end
    if not distance and last and last.mapID == location.mapID and moved then
        route.notices.distance = "Map distance was unavailable for some samples; movement spacing is approximate."
    end
    if route.pendingBreak then route.segment = route.segment + 1; route.pendingBreak = false end
    local point = FG.Copy(location)
    point.at, point.segment = active, route.segment
    route.points[#route.points + 1] = point
    route.revision = route.revision + 1
end

function Route.Maps(record)
    local result, seen = {}, {}
    if record.route then
        for _, list in ipairs({ record.route.points, record.route.kills }) do
            for _, entry in ipairs(list) do
                local p = entry.location or entry
                if Route.Valid(p) and not seen[p.mapID] then
                    seen[p.mapID] = true; result[#result + 1] = p.mapID
                end
            end
        end
    end
    table.sort(result)
    return result
end

function Route.Stats(record, sort, descending)
    local route = record.route
    local result = { rows = {}, count = 0, missing = 0, distinct = 0, unassigned = record.xp.combat, notices = {} }
    if not route then result.notices[1] = "Route and mob history were not recorded."; return result end
    result.count = #route.kills
    for _, kill in ipairs(route.kills) do if not Route.Valid(kill.location) then result.missing = result.missing + 1 end end
    for key, mob in pairs(route.mobs) do
        local row = FG.Copy(mob); row.key = key
        row.hour = record.active > 0 and row.count * 3600 / record.active or 0
        result.rows[#result.rows + 1] = row
    end
    result.distinct, result.unassigned = #result.rows, math.max(0, record.xp.combat - route.assignedXP)
    for _, notice in pairs(route.notices) do result.notices[#result.notices + 1] = notice end
    table.sort(result.notices)
    sort = sort or "count"
    table.sort(result.rows, function(a, b)
        if a[sort] ~= b[sort] then
            if descending == false then return a[sort] < b[sort] end
            return a[sort] > b[sort]
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    return result
end

-- Pure viewport calculations are shared by the journal and native-map overlay.
function Route.Project(p, view, width, height)
    return (p.x - view.x) * width * view.zoom + width / 2,
        (p.y - view.y) * height * view.zoom + (view.viewportHeight or height) / 2
end

function Route.Fit(record, mapID)
    local minX, minY, maxX, maxY = 1, 1, 0, 0
    local found = false
    if record.route then
        for _, list in ipairs({ record.route.points, record.route.kills }) do
            for _, entry in ipairs(list) do
                local p = entry.location or entry
                if Route.Valid(p) and p.mapID == mapID then
                    found = true
                    minX, minY, maxX, maxY = math.min(minX, p.x), math.min(minY, p.y), math.max(maxX, p.x), math.max(maxY, p.y)
                end
            end
        end
    end
    if not found then return { x = 0.5, y = 0.5, zoom = 1 } end
    return { x = (minX + maxX) / 2, y = (minY + maxY) / 2,
        zoom = math.min(8, 0.8 / math.max(0.1, maxX - minX, maxY - minY)) }
end

function Route.Clusters(record, mapID, view, width, height, radius)
    local clusters, grid = {}, {}
    radius = radius or 24
    if not record.route then return clusters end
    for _, kill in ipairs(record.route.kills) do
        local p = kill.location
        if Route.Valid(p) and p.mapID == mapID then
            local x, y = Route.Project(p, view, width, height)
            local gx, gy, cluster = math.floor(x / radius), math.floor(y / radius), nil
            for dx = -1, 1 do for dy = -1, 1 do
                for _, candidate in ipairs(grid[(gx + dx) .. ":" .. (gy + dy)] or {}) do
                    if (candidate.x - x) ^ 2 + (candidate.y - y) ^ 2 < radius ^ 2 then cluster = candidate; break end
                end
                if cluster then break end
            end if cluster then break end end
            if not cluster then
                cluster = { x = x, y = y, location = p, kills = {}, mobs = {}, first = kill.at, last = kill.at }
                clusters[#clusters + 1] = cluster
                local key = gx .. ":" .. gy; grid[key] = grid[key] or {}; table.insert(grid[key], cluster)
            end
            cluster.kills[#cluster.kills + 1] = kill
            cluster.mobs[kill.key] = (cluster.mobs[kill.key] or 0) + 1
            cluster.first, cluster.last = math.min(cluster.first, kill.at), math.max(cluster.last, kill.at)
        end
    end
    return clusters
end
