local _, FG = ...
FG.title = "Forever Grind"
FG.version = "0.2.0"

function FG.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = FG.Copy(item) end
    return copy
end

function FG.Number(value)
    return tonumber((tostring(value or ""):gsub("%D", ""))) or 0
end

function FG.Duration(seconds)
    seconds = math.floor(math.max(0, seconds or 0))
    return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

function FG.Money(copper)
    copper = math.floor(copper or 0)
    return string.format("%dg %02ds %02dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function FG.Short(number)
    number = number or 0
    if number >= 1000000 then return string.format("%.1fm", number / 1000000) end
    if number >= 1000 then return string.format("%.1fk", number / 1000) end
    return tostring(math.floor(number))
end

function FG.LocationText(location)
    location = location or {}
    local text = location.zone or "Unknown zone"
    if location.subzone and location.subzone ~= "" and location.subzone ~= text then
        text = text .. " / " .. location.subzone
    end
    if location.x and location.y then
        return string.format("%s (%.1f, %.1f)", text, location.x * 100, location.y * 100)
    end
    return text .. " (coordinates unavailable)"
end

function FG.InitializeDB(global, character)
    global = type(global) == "table" and global or {}
    character = type(character) == "table" and character or {}
    if (tonumber(global.version) or 0) > 2 or (tonumber(character.version) or 0) > 2 then
        error("Forever Grind: saved data belongs to a newer addon version; install that version before loading it.")
    end
    global.version, character.version = 2, 2
    global.saved = type(global.saved) == "table" and global.saved or {}
    global.temporary = type(global.temporary) == "table" and global.temporary or {}
    global.nextID = tonumber(global.nextID) or 1
    global.settings = type(global.settings) == "table" and global.settings or {}
    local defaults = { auctionator = true, ahCut = 5, maxPriceAge = 7, locked = false,
        scale = 1, xpText = true, questOverlay = true }
    for key, value in pairs(defaults) do
        if type(global.settings[key]) ~= type(value) then global.settings[key] = value end
    end
    global.settings.ahCut = math.max(0, math.min(100, global.settings.ahCut))
    global.settings.maxPriceAge = math.max(0, global.settings.maxPriceAge)
    global.settings.scale = math.max(0.6, math.min(2, global.settings.scale))
    if type(character.current) ~= "table" then character.current = nil end
    if character.current then
        FG.Route.Ensure(character.current, true)
        character.current.route.generation = (character.current.route.generation or 1) + 1
        FG.Route.Break(character.current)
        character.mode = "paused"
    elseif character.mode ~= "stopped" then
        character.mode = "armed"
    end
    while #global.temporary > 20 do table.remove(global.temporary, 1) end
    return global, character
end
