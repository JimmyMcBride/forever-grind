local _, FG = ...
local Map = {}
FG.Map = Map
local DOT = "Interface\\AddOns\\ForeverGrind\\Media\\MapDot.tga"
local BLUE, GOLD = { 0.32, 0.64, 0.95, 0.85 }, { 1, 0.76, 0.22, 1 }

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function Map.MapName(id)
    local info = C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, id)
    return info and info.name and (info.name .. " (#" .. id .. ")") or ("Map #" .. tostring(id))
end

function Map.Navigate(point, tomtom)
    if not FG.Route.Valid(point) then return false, "This point has no usable coordinates." end
    if tomtom then
        if not TomTom or type(TomTom.AddWaypoint) ~= "function" or type(TomTom.RemoveWaypoint) ~= "function" then
            return false, "TomTom navigation is unavailable."
        end
        if Map.waypoint then
            local removed = pcall(TomTom.RemoveWaypoint, TomTom, Map.waypoint)
            if not removed then return false, "TomTom could not remove the previous Forever Grind waypoint." end
            Map.waypoint = nil
        end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, point.mapID, point.x, point.y,
            { title = "Forever Grind recorded location", from = "ForeverGrind", persistent = false,
              crazy = false, minimap = true, world = true })
        if not ok or not uid then return false, "TomTom could not create this waypoint." end
        Map.waypoint = uid
        if type(TomTom.SetCrazyArrow) == "function" then
            local arrowOK = pcall(TomTom.SetCrazyArrow, TomTom, uid, 10, "Forever Grind recorded location")
            if not arrowOK then return false, "Waypoint created, but TomTom's arrow is unavailable." end
        end
        return true, "TomTom waypoint created."
    end
    if not C_Map.CanSetUserWaypointOnMap or not Safe(C_Map.CanSetUserWaypointOnMap, point.mapID)
        or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        return false, "Native waypoints are unavailable on this map."
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.mapID, point.x, point.y))
    end)
    return ok, ok and "Native waypoint set." or "Native waypoint could not be set."
end

local function Menu(point)
    if not Map.menu then
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(310, 142); menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true)
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        menu:SetBackdropColor(0.04, 0.04, 0.05, 1)
        local Text, Button = FG.UI.Widgets.Text, FG.UI.Widgets.Button
        menu.label = Text(menu, "", 12, -12, 285, 11)
        menu.message = Text(menu, "", 12, -113, 285, 10); menu.message:SetWordWrap(true)
        local function navigate(tomtom)
            local _, message = Map.Navigate(menu.location, tomtom); menu.message:SetText(message)
        end
        menu.native = Button(menu, "Set native waypoint", 12, -43, 190, function() navigate(false) end)
        menu.tomtom = Button(menu, "Navigate with TomTom", 12, -73, 190, function() navigate(true) end)
        Button(menu, "Close", 216, -73, 80, function() menu:Hide() end)
        Map.menu = menu
    end
    local menu = Map.menu
    menu.location = point; menu.message:SetText("")
    menu.label:SetText(string.format("%s · %.1f, %.1f", Map.MapName(point.mapID), point.x * 100, point.y * 100))
    menu.label:SetWordWrap(false)
    menu.tomtom:SetShown(TomTom and type(TomTom.AddWaypoint) == "function" or false)
    menu:ClearAllPoints(); menu:SetPoint("CENTER", UIParent, "CENTER"); menu:Show()
end

local function Tip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(lines[1])
    for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
end

local function Line(self, x1, y1, x2, y2, color)
    if (x1 - x2) ^ 2 + (y1 - y2) ^ 2 < 0.25 then return end
    self.usedLines = self.usedLines + 1
    local line = self.lines[self.usedLines]
    if not line then line = self.surface:CreateLine(nil, "OVERLAY"); self.lines[self.usedLines] = line end
    line:ClearAllPoints(); line:SetStartPoint("TOPLEFT", self.frame, "TOPLEFT", x1, -y1)
    line:SetEndPoint("TOPLEFT", self.frame, "TOPLEFT", x2, -y2)
    line:SetThickness(1.5 / (self.native and math.max(0.01, self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1)); line:SetColorTexture(unpack(color)); line:Show()
end

-- Liang-Barsky clipping prevents offscreen route geometry from enlarging pools.
function Map.Clip(x1, y1, x2, y2, width, height)
    local dx, dy, a, b = x2 - x1, y2 - y1, 0, 1
    local p, q = { -dx, dx, -dy, dy }, { x1, width - x1, y1, height - y1 }
    for i = 1, 4 do
        if p[i] == 0 then if q[i] < 0 then return end
        else
            local ratio = q[i] / p[i]
            if p[i] < 0 then a = math.max(a, ratio) else b = math.min(b, ratio) end
            if a > b then return end
        end
    end
    return x1 + a * dx, y1 + a * dy, x1 + b * dx, y1 + b * dy
end

local function Pin(self, x, y, text, color, point, cluster, description)
    if x < 0 or y < 0 or x > self.width or y > self.height then return end
    self.usedPins = self.usedPins + 1
    local pin = self.pins[self.usedPins]
    if not pin then
        pin = CreateFrame("Button", nil, self.surface)
        pin:SetSize(18, 18); pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pin.dot = pin:CreateTexture(nil, "ARTWORK"); pin.dot:SetAllPoints(); pin.dot:SetTexture(DOT)
        pin.label = pin:CreateFontString(nil, "OVERLAY"); pin.label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        pin.label:SetPoint("CENTER")
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnEnter", function(button)
            local lines = { button.description or "Recorded kill location", "Your position when the kill was recorded." }
            local c = button.cluster
            if c then
                lines[1] = #c.kills .. " recorded kill(s)"
                lines[#lines + 1] = FG.Duration(c.first) .. "–" .. FG.Duration(c.last) .. " active time"
                local names = {}
                for key, count in pairs(c.mobs) do
                    local mob = self.record.route.mobs[key]
                    names[#names + 1] = (mob and mob.name or "Unknown creature") .. " × " .. count
                end
                table.sort(names)
                for _, name in ipairs(names) do lines[#lines + 1] = name end
                lines[#lines + 1] = #c.kills > 1 and "Click to zoom; right-click for navigation." or "Click for navigation."
            else lines[#lines + 1] = "Click for navigation." end
            Tip(button, lines)
        end)
        pin:SetScript("OnClick", function(button, mouse)
            if button.cluster and #button.cluster.kills > 1 and mouse ~= "RightButton" then
                if self.native then self.native:PanAndZoomTo(button.point.x, button.point.y)
                else self.view.x, self.view.y = button.point.x, button.point.y; self.view.zoom = math.min(16, self.view.zoom * 2) end
                self.invalid = true; self:Draw()
            else Menu(button.point) end
        end)
        self.pins[self.usedPins] = pin
    end
    local scale = self.native and math.max(0.01, self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1
    pin:SetSize((text ~= "" and 18 or 8) / scale, (text ~= "" and 18 or 8) / scale)
    pin.label:SetFont(STANDARD_TEXT_FONT, 10 / scale, "OUTLINE")
    pin:ClearAllPoints(); pin:SetPoint("CENTER", self.frame, "TOPLEFT", x, -y)
    pin.label:SetText(text or ""); pin.dot:SetVertexColor(unpack(color))
    pin:SetAlpha(self.mob and cluster and not cluster.mobs[self.mob] and 0.18 or 1)
    pin.point, pin.cluster, pin.description = point, cluster, description; pin:Show()
end

function Map:Draw()
    if not self.record or not self.frame:IsVisible() then return end
    local route = self.record.route
    local revision = route and route.revision or -1
    local scale = self.native and self.native:GetCanvasScale() or self.view.zoom
    if not self.invalid and self.revision == revision and self.lastMob == self.mob and self.lastScale == scale then return end
    self.invalid, self.revision, self.lastMob, self.lastScale = false, revision, self.mob, scale
    self.usedLines, self.usedPins = 0, 0
    for _, line in ipairs(self.lines) do line:Hide() end
    for _, pin in ipairs(self.pins) do pin:Hide() end
    if not route or not self.mapID or self.width <= 0 or self.height <= 0 then return end
    local width, height = self.width, self.height
    local baseHeight = self.native and height or width / (self.aspect or 1.5)
    local view = self.native and { x = 0.5, y = 0.5, zoom = 1 } or self.view
    view.viewportHeight = height
    local artKey = table.concat({ tostring(self.mapID), view.x, view.y, view.zoom, width, height }, ":")
    if self.artKey ~= artKey then self:Artwork(view, width, baseHeight); self.artKey = artKey end
    local function project(point) return FG.Route.Project(point, view, width, baseHeight) end
    if self.showRoute then
        local previous, lastX, lastY, arrows = nil, nil, nil, 0
        for index, point in ipairs(route.points) do
            if point.mapID == self.mapID then
                local x, y = project(point)
                if previous and previous.segment == point.segment then
                    local nextPoint = route.points[index + 1]
                    local ending = not nextPoint or nextPoint.segment ~= point.segment or nextPoint.mapID ~= point.mapID
                    if ending or not lastX or (x - lastX) ^ 2 + (y - lastY) ^ 2 >= (2 / math.max(0.01, scale)) ^ 2 then
                        local x1, y1, x2, y2 = Map.Clip(lastX or x, lastY or y, x, y, width, height)
                        if x1 then
                            Line(self, x1, y1, x2, y2, BLUE)
                            local dx, dy = x2 - x1, y2 - y1
                            local length = math.sqrt(dx * dx + dy * dy)
                            arrows = arrows + length
                            if arrows >= 80 / math.max(0.01, scale) and length > 0 then
                                arrows = 0
                                local mx, my, ux, uy = (x1 + x2) / 2, (y1 + y2) / 2, dx / length, dy / length
                                Line(self, mx, my, mx - ux * 5 - uy * 3, my - uy * 5 + ux * 3, BLUE)
                                Line(self, mx, my, mx - ux * 5 + uy * 3, my - uy * 5 - ux * 3, BLUE)
                            end
                        end
                        lastX, lastY = x, y
                    end
                else lastX, lastY = x, y end
                previous = point
            else previous, lastX, lastY = nil, nil, nil end
        end
    end
    if self.showKills then
        local radius = 24 / math.max(0.01, self.frame:GetEffectiveScale())
        local clusters = FG.Route.Clusters(self.record, self.mapID, view, width, baseHeight, radius)
        for _, c in ipairs(clusters) do Pin(self, c.x, c.y, #c.kills > 1 and tostring(#c.kills) or "", GOLD, c.location, c) end
    end
    if self.showEnds then
        local first, last
        for _, p in ipairs(route.points) do if p.mapID == self.mapID then first = first or p; last = p end end
        local same = first and last and first.x == last.x and first.y == last.y
        if first then local x, y = project(first); Pin(self, x, y, same and "S/E" or "S", { 0.25, 0.8, 0.6, 1 }, first, nil, "Route segment start") end
        if last and not same then local x, y = project(last); Pin(self, x, y, "E", { 0.4, 0.65, 1, 1 }, last, nil, "Route segment end") end
    end
end

function Map:Artwork(view, width, height)
    if self.native then return end
    local layers = C_Map.GetMapArtLayers and Safe(C_Map.GetMapArtLayers, self.mapID)
    local layer = layers and layers[1]
    local textures = layer and C_Map.GetMapArtLayerTextures and Safe(C_Map.GetMapArtLayerTextures, self.mapID, 1)
    if not layer or not textures then self.artNotice:SetText("Map artwork unavailable"); return end
    self.artNotice:SetText("")
    local rows, columns = math.ceil(layer.layerHeight / layer.tileHeight), math.ceil(layer.layerWidth / layer.tileWidth)
    for column = 1, columns do for row = 1, rows do
        local index = (row - 1) * columns + column
        local tile = self.tiles[index]
        if not tile then tile = self.surface:CreateTexture(nil, "BACKGROUND"); self.tiles[index] = tile end
        tile:SetTexture(textures[index]); tile:ClearAllPoints()
        local fractionX = math.min(1, (layer.layerWidth - (column - 1) * layer.tileWidth) / layer.tileWidth)
        local fractionY = math.min(1, (layer.layerHeight - (row - 1) * layer.tileHeight) / layer.tileHeight)
        tile:SetTexCoord(0, fractionX, 0, fractionY)
        tile:SetSize(width * view.zoom * layer.tileWidth / layer.layerWidth * fractionX, height * view.zoom * layer.tileHeight / layer.layerHeight * fractionY)
        tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", width / 2 - view.x * width * view.zoom + (column - 1) * width * view.zoom * layer.tileWidth / layer.layerWidth,
            -self.height / 2 + view.y * height * view.zoom - (row - 1) * height * view.zoom * layer.tileHeight / layer.layerHeight)
        tile:Show()
    end end
end

function Map:Fit()
    self.view = FG.Route.Fit(self.record, self.mapID)
    local span = 0.8 / self.view.zoom
    self.view.zoom = math.min(self.view.zoom, 0.8 * self.height / (self.width / (self.aspect or 1.5)) / span)
    self.invalid = true; self:Draw()
end

function Map:SelectMap(id)
    self.mapID, self.artKey = id, nil
    for _, tile in ipairs(self.tiles) do tile:Hide() end
    local layers = C_Map.GetMapArtLayers and id and Safe(C_Map.GetMapArtLayers, id)
    self.aspect = layers and layers[1] and layers[1].layerWidth / layers[1].layerHeight or 1.5
    self:Fit()
end

function Map.CreateCanvas(parent, width, height, native)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height); frame:SetClipsChildren(true)
    local self = setmetatable({ frame = frame, width = width, height = height, native = native, tiles = {}, lines = {}, pins = {},
        view = { x = 0.5, y = 0.5, zoom = 1 }, showRoute = true, showKills = true, showEnds = true, invalid = true }, { __index = Map })
    self.surface = CreateFrame("Frame", nil, frame)
    self.surface:SetAllPoints(frame)
    if not native then
        frame:EnableMouse(true); frame:EnableMouseWheel(true); frame:RegisterForDrag("LeftButton")
        self.artNotice = FG.UI.Widgets.Text(frame, "", 8, -8, width - 16, 11)
        frame:SetScript("OnMouseWheel", function(_, delta)
            self.view.zoom = math.max(0.25, math.min(16, self.view.zoom * (delta > 0 and 1.3 or 1 / 1.3)))
            self.invalid = true; self:Draw()
        end)
        frame:SetScript("OnDragStart", function()
            local x, y = GetCursorPosition(); self.drag = { x = x, y = y, vx = self.view.x, vy = self.view.y }
        end)
        frame:SetScript("OnDragStop", function()
            if not self.drag then return end
            local x, y = GetCursorPosition(); local scale = frame:GetEffectiveScale()
            self.view.x = self.drag.vx - (x - self.drag.x) / scale / width / self.view.zoom
            self.view.y = self.drag.vy + (y - self.drag.y) / scale / (width / (self.aspect or 1.5)) / self.view.zoom
            self.drag = nil; self.invalid = true; self:Draw()
        end)
    end
    return self
end

local function ToggleButtons(parent, target, x, y, changed)
    for index, entry in ipairs({ { "showRoute", "Route" }, { "showKills", "Kills" }, { "showEnds", "Ends" } }) do
        local key, title = entry[1], entry[2]
        local button
        button = FG.UI.Widgets.Button(parent, title .. " on", x + (index - 1) * 62, y, 60, function()
            target[key] = not target[key]; button:SetText(title .. (target[key] and " on" or " off"))
            target.invalid = true; target:Draw(); if changed then changed() end
        end)
    end
end

function Map.CreateReport(report)
    local Text, Button = FG.UI.Widgets.Text, FG.UI.Widgets.Button
    local frame = CreateFrame("Frame", nil, report.frame)
    frame:SetPoint("TOPLEFT", 20, -250); frame:SetSize(890, 222)
    local canvas = Map.CreateCanvas(frame, 550, 168)
    canvas.frame:SetPoint("TOPLEFT", 0, -28)
    local self = { frame = frame, canvas = canvas, report = report, sort = "count", descending = true, rows = {} }
    self.mapName = Text(frame, "", 52, -5, 140, 10); self.mapName:SetWordWrap(false)
    local function cycle(direction)
        local maps = FG.Route.Maps(self.record)
        local index = 1
        for i, id in ipairs(maps) do if id == canvas.mapID then index = i end end
        if #maps > 0 then canvas:SelectMap(maps[(index - 1 + direction) % #maps + 1]); self.mapName:SetText(Map.MapName(canvas.mapID)) end
    end
    self.previous = Button(frame, "<", 0, 0, 24, function() cycle(-1) end)
    self.next = Button(frame, ">", 26, 0, 24, function() cycle(1) end)
    self.fit = Button(frame, "Fit", 194, 0, 42, function() canvas:Fit() end)
    self.world = Button(frame, "World map", 240, 0, 88, function()
        local ok, reason = Map.ShowWorld(self.record, canvas.mapID, canvas.mob)
        if not ok then self.notice:SetText(reason) end
    end)
    ToggleButtons(frame, canvas, 334, 0)
    self.notice = Text(frame, "", 0, -201, 550, 10); self.notice:SetWordWrap(false)
    self.noticeFrame = CreateFrame("Frame", nil, frame)
    self.noticeFrame:SetPoint("TOPLEFT", 0, -198); self.noticeFrame:SetSize(550, 24); self.noticeFrame:EnableMouse(true)
    self.noticeFrame:SetScript("OnEnter", function(owner) Tip(owner, self.notices or { "Capture information" }) end)
    self.noticeFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.all = Button(frame, "All mobs", 570, 0, 82, function() canvas.mob = nil; self.revision = nil; self:Refresh(self.record) end)
    self.summary = Text(frame, "", 660, -5, 225, 10); self.summary:SetWordWrap(false)
    self.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    self.scroll:SetPoint("TOPLEFT", 570, -53); self.scroll:SetSize(293, 143)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(293, 140); self.scroll:SetScrollChild(self.content)
    self.unassigned = Text(frame, "", 570, -201, 315, 10); self.unassigned:SetWordWrap(false)
    for _, entry in ipairs({ { "Name", "name", 570, 126 }, { "#", "count", 699, 40 }, { "Kills/h", "hour", 742, 66 }, { "XP", "xp", 811, 74 } }) do
        local key = entry[2]
        Button(frame, entry[1], entry[3], -27, entry[4], function()
            if self.sort == key then self.descending = not self.descending else self.sort, self.descending = key, key ~= "name" end
            self.revision = nil; self:Refresh(self.record)
        end)
    end
    function self:Select(record)
        self.record, self.revision, canvas.record, canvas.mob = record, nil, record, nil
        self.sort, self.descending = "count", true
        self.scroll:SetVerticalScroll(0)
        local maps = FG.Route.Maps(record)
        canvas:SelectMap(maps[1]); self:Refresh(record)
    end
    function self:Refresh(record)
        self.record, canvas.record = record, record
        local route = record.route
        local revision = route and route.revision or -1
        if self.revision ~= revision or self.active ~= record.active then
            self.revision, self.active = revision, record.active
            local offset = self.scroll:GetVerticalScroll()
            local stats = FG.Route.Stats(record, self.sort, self.descending)
            self.stats = stats
            self.summary:SetText(string.format("%d kills · %d types", stats.count, stats.distinct))
            self.unassigned:SetText("Unassigned combat XP: " .. stats.unassigned)
            self.notices = { "Kill and route capture", "Markers show your position when a kill was recorded.",
                "Counts include confirmed player/group/pet kills; unreported or restricted kills cannot be guaranteed.",
                stats.missing .. " kill(s) without map coordinates." }
            for _, notice in ipairs(stats.notices) do self.notices[#self.notices + 1] = notice end
            self.notice:SetText(not route and stats.notices[1] or (stats.missing .. " unlocated · " .. #stats.notices .. " capture notice(s) — hover for details"))
            for _, row in ipairs(self.rows) do row:Hide() end
            for index, mob in ipairs(stats.rows) do
                local row = self.rows[index]
                if not row then
                    row = CreateFrame("Button", nil, self.content); row:SetSize(290, 26)
                    row:SetPoint("TOPLEFT", 0, -(index - 1) * 27)
                    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    row.name = Text(row, "", 0, -3, 126, 10); row.name:SetWordWrap(false)
                    row.count = Text(row, "", 129, -3, 38, 10)
                    row.hour = Text(row, "", 172, -3, 63, 10)
                    row.xp = Text(row, "", 241, -3, 49, 10); row.xp:SetTextColor(0.4, 0.75, 1)
                    row:SetScript("OnClick", function(button)
                        canvas.mob = canvas.mob == button.mob.key and nil or button.mob.key
                        canvas.invalid = true; canvas:Draw()
                        for _, item in ipairs(self.rows) do if item.mob then item.name:SetTextColor(item.mob.key == canvas.mob and 1 or 0.85, item.mob.key == canvas.mob and 0.8 or 0.85, 0.85) end end
                    end)
                    row:SetScript("OnEnter", function(button)
                        Tip(button, { button.mob.name, button.mob.npcID and ("NPC ID: " .. button.mob.npcID) or "Identity grouped by localized name.",
                            "Click to highlight this mob's recorded kill locations." })
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    self.rows[index] = row
                end
                row.mob = mob; row.name:SetText(mob.name); row.count:SetText(tostring(mob.count))
                row.name:SetTextColor(mob.key == canvas.mob and 1 or 0.85, mob.key == canvas.mob and 0.8 or 0.85, 0.85)
                row.hour:SetText(string.format("%.1f", mob.hour)); row.xp:SetText(FG.Short(mob.xp)); row:Show()
            end
            self.content:SetHeight(math.max(1, #stats.rows * 27))
            self.scroll:SetVerticalScroll(math.min(offset, math.max(0, #stats.rows * 27 - self.scroll:GetHeight())))
        end
        if not canvas.mapID then local maps = FG.Route.Maps(record); if maps[1] then canvas:SelectMap(maps[1]) end end
        self.mapName:SetText(canvas.mapID and Map.MapName(canvas.mapID) or "No mapped points")
        self.world:SetEnabled(canvas.mapID ~= nil)
        canvas:Draw()
    end
    frame:Hide()
    return self
end

function Map.HideWorld()
    if Map.world then Map.world.frame:Hide(); Map.world.record = nil; Map.world.controls:Hide() end
end

function Map.ShowWorld(record, mapID, mob)
    if not WorldMapFrame then
        if InCombatLockdown and InCombatLockdown() then return false, "Open the world map after combat to load its UI." end
        if C_AddOns and C_AddOns.LoadAddOn then Safe(C_AddOns.LoadAddOn, "Blizzard_WorldMap") end
    end
    local native = WorldMapFrame
    if not native or not native.GetCanvas then return false, "Blizzard's world map is unavailable." end
    if not Map.world then
        local canvas = native:GetCanvas()
        local world = Map.CreateCanvas(canvas, canvas:GetWidth(), canvas:GetHeight(), native)
        world.frame:SetPoint("TOPLEFT"); world.frame:EnableMouse(false)
        local controls = CreateFrame("Frame", nil, native, "BackdropTemplate")
        controls:SetSize(520, 28); controls:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", 20, 5)
        controls:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" }); controls:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
        world.title = FG.UI.Widgets.Text(controls, "", 6, -7, 230, 11); world.title:SetWordWrap(false)
        ToggleButtons(controls, world, 238, -3)
        FG.UI.Widgets.Button(controls, "Hide", 430, -3, 78, Map.HideWorld)
        world.controls = controls; Map.world = world
        native:HookScript("OnShow", function() if world.record then world.invalid = true end end)
    end
    local world = Map.world
    world.record, world.mob, world.invalid = record, mob, true
    world.title:SetText("Forever Grind: " .. (record.name or FG.LocationText(record.startLocation)))
    local opened = pcall(function() native:SetMapID(mapID); native:Show() end)
    if not opened then Map.HideWorld(); return false, "Blizzard's world map could not be opened here." end
    world.frame:Show(); world.controls:Show()
    Map.RefreshWorld()
    return true
end

function Map.RefreshWorld()
    local world = Map.world
    if not world or not world.record then return end
    local found = false
    for _, record in ipairs(FG.model:Records()) do if record == world.record then found = true; break end end
    if not found then Map.HideWorld(); return end
    if not world.frame:IsVisible() then return end
    local id = world.native:GetMapID()
    local width, height = world.native:GetCanvas():GetWidth(), world.native:GetCanvas():GetHeight()
    if id ~= world.mapID or width ~= world.width or height ~= world.height then
        world.mapID, world.width, world.height, world.invalid = id, width, height, true
        world.frame:SetSize(width, height)
    end
    world:Draw()
end
