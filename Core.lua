-- QuestRoute: core state, settings, quest selection and target lookup.
local ADDON, ns = ...
_G.QuestRoute = ns

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
-- HereBeDragons does our map math. Questie ships its own copy as an internal
-- Questie module ("HBD"/"HBDPins"); a standalone copy registers with LibStub.
local function findLib(libName, moduleName, mustHave)
    local lib = LibStub and LibStub(libName, true)
    if type(lib) == "table" and lib[mustHave] then return lib end
    if QuestieLoader then
        local mods = QuestieLoader._modules
        lib = mods and mods[moduleName]
        if type(lib) == "table" and lib[mustHave] then return lib end
        local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, moduleName)
        if ok and type(m) == "table" and m[mustHave] then return m end
    end
end

function ns:FindLibraries()
    self.HBD = findLib("HereBeDragons-2.0", "HBD", "GetPlayerWorldPosition")
    self.HBDPins = findLib("HereBeDragons-Pins-2.0", "HBDPins", "GetMinimapView")
end
ns:FindLibraries()

local defaults = {
    enabled = true,          -- master switch for the route
    showWorldMap = true,
    showMinimap = true,
    compass = true,
    compassLocked = false,
    compassScale = 1,
    compassHideIdle = true,  -- hide the compass when there is no route
    compassText = true,
    showTimes = false,       -- estimated travel/trip times under the compass
    compassPos = nil,
    compassStyle = "gold",   -- gold | modern | bar | none
    arrowPlacement = "inside", -- inside | above | below
    arrowStyle = "arrow",    -- arrow | chevron | needle
    compassSnap = true,      -- snap to the screen centre while dragging
    compassLetters = true,
    compassBg = true,
    compassBgOpacity = 0.5,
    compassColor = { r = 0.95, g = 0.85, b = 0.55 },
    compassOpacity = 0.9,
    arrowUseLineColor = true,
    arrowColor = { r = 1, g = 0.78, b = 0.18 },
    arrowFollowsRoad = false, -- false: point at the end of the leg; true: at a spot just down the road
    arrowScale = 1,
    arrowOpacity = 1,
    arrivedColor = { r = 0.3, g = 1, b = 0.3 },
    style = "dashed",        -- solid | dashed | dotted
    color = { r = 1, g = 0.78, b = 0.18 },
    thickness = 4,
    opacity = 0.9,
    glow = true,
    glowStrength = 0.6,
    markerStyle = "glow",    -- glow | x
    markerColor = { r = 0.8, g = 0.1, b = 0.05 },
    outline = true,
    outlineSize = 1.5,
    outlineColor = { r = 0, g = 0, b = 0 },
    outlineOpacity = 0.85,
    animate = true,
    arriveDistance = 10,
    minimapButton = { hide = false },
    corpseRoute = true,
    clearOnDeselect = true,  -- deselecting/untracking the routed quest removes the route
    useFlights = true,       -- plan routes with the flight paths this character knows
    useTransports = true,    -- boats, zeppelins and the tram
    useRoads = true,         -- follow learned roads
    learnRoads = true,       -- record roads while travelling
    offroadPenalty = 1.6,    -- how much slower cross-country walking counts vs a known road
    avoidDanger = true,      -- route around areas with monsters well above your level
    dangerMargin = 3,        -- ...more than this many levels above you
    assumeAllFlights = false, -- pretend every flight path of my faction is known      -- lead a ghost back to its body (straight line, ghosts walk on water)
}
ns.defaults = defaults

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns:Print(...)
    print("|cffffc72eQuestRoute:|r", ...)
end

---------------------------------------------------------------------------
-- Change notifications: displays register a callback and get poked when
-- the target or settings change.
---------------------------------------------------------------------------
ns.listeners = {}
function ns:OnChange(fn) table.insert(self.listeners, fn) end
function ns:NotifyChanged()
    for _, fn in ipairs(self.listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Quest helpers
---------------------------------------------------------------------------
local function questInLog(questId)
    if not questId or questId == 0 then return false end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(questId)
        return idx ~= nil and idx > 0
    elseif GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(questId)
        return idx ~= nil and idx > 0
    end
    return true
end

local function questTitle(questId)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local t = C_QuestLog.GetTitleForQuestID(questId)
        if t and t ~= "" then return t end
    end
    return "Quest " .. tostring(questId)
end

local function selectedQuest()
    local id
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        id = C_QuestLog.GetSelectedQuest()
    end
    if (not id or id == 0) and GetQuestLogSelection and GetQuestLogTitle then
        local idx = GetQuestLogSelection()
        if idx and idx > 0 then id = select(8, GetQuestLogTitle(idx)) end
    end
    return id
end

local function superTrackedQuest()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        return C_SuperTrack.GetSuperTrackedQuestID()
    end
end

---------------------------------------------------------------------------
-- Target lookup. Questie first (it knows every mob/NPC/object location),
-- then Blizzard's own quest data as a fallback.
---------------------------------------------------------------------------
local function fromQuestie(questId)
    if not QuestieLoader then return end
    local ok, mapId, x, y, name = pcall(function()
        local ActiveQuests = QuestieLoader:ImportModule("ActiveQuests")
        local DistanceUtils = QuestieLoader:ImportModule("DistanceUtils")
        local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
        local quest
        if ActiveQuests and ActiveQuests.Get then
            local acceptance = ActiveQuests.Get(questId)
            quest = acceptance and acceptance.quest
        end
        if not quest then
            local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
            quest = QuestiePlayer and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[questId]
        end
        if not quest then return end
        local spawn, zone, spawnName = DistanceUtils.GetNearestSpawnForQuest(quest)
        if not spawn or not zone then return end
        return ZoneDB:GetUiMapIdByAreaId(zone), spawn[1] / 100, spawn[2] / 100, spawnName
    end)
    if ok and mapId and x and y then
        return mapId, x, y, name
    elseif not ok then
        ns.lastError = mapId
    end
end

-- Fallback: the icons Questie actually draws on the world map for this quest.
local function fromQuestieIcons(questId)
    if not QuestieLoader or not ns.HBD then return end
    local ok, mapId, x, y, name = pcall(function()
        local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
        if not (QuestieMap and QuestieMap.GetFramesForQuest) then return end
        local px, py, pinst = ns.HBD:GetPlayerWorldPosition()
        local best, bestDist
        for _, frame in pairs(QuestieMap:GetFramesForQuest(questId)) do
            if not frame.miniMapIcon and frame.x and frame.y and frame.UiMapID then
                local wx, wy, inst = ns.HBD:GetWorldCoordinatesFromZone(frame.x / 100, frame.y / 100, frame.UiMapID)
                if wx then
                    local d
                    if px and inst == pinst then
                        d = (wx - px) ^ 2 + (wy - py) ^ 2
                    else
                        d = 1e12
                    end
                    if not bestDist or d < bestDist then best, bestDist = frame, d end
                end
            end
        end
        if best then
            local data = best.data or {}
            return best.UiMapID, best.x / 100, best.y / 100, data.Name or data.name
        end
    end)
    if ok and mapId then
        return mapId, x, y, name
    elseif not ok then
        ns.lastError = mapId
    end
end

local function fromBlizzard(questId)
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local mapId, x, y = C_QuestLog.GetNextWaypoint(questId)
        if mapId and x and y then return mapId, x, y, "Quest area" end
    end
    if C_QuestLog and C_QuestLog.GetQuestsOnMap and C_Map and C_Map.GetBestMapForUnit then
        local mapId = C_Map.GetBestMapForUnit("player")
        local quests = mapId and C_QuestLog.GetQuestsOnMap(mapId)
        for _, info in ipairs(quests or {}) do
            if info.questID == questId and info.x and info.y then
                return mapId, info.x, info.y
            end
        end
    end
end

-- Every zone map in the game (built once): used to search Blizzard's quest
-- markers everywhere and to look zones up by name.
local zoneMaps, zoneByName
local function allZones()
    if zoneMaps and #zoneMaps > 0 then return zoneMaps end
    zoneMaps, zoneByName = {}, {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return zoneMaps end
    local seen = {}
    local continents = {}
    for _, root in ipairs({ 947, 1414, 1415 }) do
        for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
            if not seen[info.mapID] and (info.mapType == 3 or info.mapType == 2) then
                seen[info.mapID] = true
                -- zone maps first: their quest markers are more precise than the continent's
                if info.mapType == 3 then
                    table.insert(zoneMaps, info.mapID)
                    if info.name then zoneByName[info.name] = info.mapID end
                else
                    table.insert(continents, info.mapID)
                end
            end
        end
    end
    for _, id in ipairs(continents) do table.insert(zoneMaps, id) end
    return zoneMaps
end

-- Blizzard's own quest markers, searched on every zone map (cached for a few seconds).
local poiCache = {}
local function fromBlizzardAnyMap(questId)
    if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    local c = poiCache[questId]
    if c and GetTime() - c.t < 10 then return c.map, c.x, c.y end
    local found
    for _, mapId in ipairs(allZones()) do
        local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapId)
        for _, info in ipairs(ok and quests or {}) do
            if info.questID == questId and info.x and info.y and (info.x > 0 or info.y > 0) then
                found = { map = mapId, x = info.x, y = info.y }
                break
            end
        end
        if found then break end
    end
    poiCache[questId] = { t = GetTime(), map = found and found.map, x = found and found.x, y = found and found.y }
    if found then return found.map, found.x, found.y end
end

--- Find a zone map by (part of) its name, case-insensitive. Returns mapId, name.
function ns:FindZoneMap(text)
    allZones()
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local exact, prefix, contains
    for name, id in pairs(zoneByName or {}) do
        local n = name:lower()
        if n == text then exact = exact or { id, name }
        elseif n:sub(1, #text) == text then prefix = prefix or { id, name }
        elseif n:find(text, 1, true) then contains = contains or { id, name } end
    end
    local hit = exact or prefix or contains
    if hit then return hit[1], hit[2] end
end

--- Parse "x y", "x, y", "zone x y" or "/way zone x y". Coordinates are 0-100.
-- Returns mapId, x (0-1), y (0-1), label  -- or nil, error message.
function ns:ParseCoords(text, defaultMap)
    text = (text or ""):gsub("^%s*/way%s*", ""):gsub(",", " ")
    local nums = {}
    for n in text:gmatch("(%-?%d+%.?%d*)") do nums[#nums + 1] = tonumber(n) end
    if #nums < 2 then return nil, "type coordinates like: 45 63  or  Elwynn 45 63" end
    local x, y = nums[#nums - 1], nums[#nums]
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil, "coordinates go from 0 to 100" end
    local zoneText = text:match("^%s*(.-)%s*%-?%d") or ""
    local mapId, zoneName = defaultMap, nil
    if zoneText ~= "" then
        mapId, zoneName = self:FindZoneMap(zoneText)
        if not mapId then return nil, "no zone called \"" .. zoneText .. "\"" end
    end
    if not mapId then return nil, "open the map of the zone first, or include its name" end
    if not zoneName then
        local info = C_Map.GetMapInfo(mapId)
        zoneName = info and info.name or "Map"
    end
    return mapId, x / 100, y / 100, ("%s %.1f, %.1f"):format(zoneName, x, y)
end

function ns:WayCommand(text)
    local mapId, x, y, label = self:ParseCoords(text, C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not mapId then self:Print(x) return end
    self:SetCustomTarget(mapId, x, y, label)
    self:Print("routing to " .. label)
end

-- Last resort: the zone heading the quest sits under in the quest log.
local function questZoneName(questId)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local idx = C_QuestLog.GetLogIndexForQuestID(questId)
        for i = (idx or 0), 1, -1 do
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader then return info.title end
        end
    elseif GetQuestLogIndexByID and GetQuestLogTitle then
        local idx = GetQuestLogIndexByID(questId)
        for i = (idx or 0), 1, -1 do
            local title, _, _, isHeader = GetQuestLogTitle(i)
            if isHeader then return title end
        end
    end
end

-- Quests that belong to a dungeon: route to the dungeon's entrance.
local DUNGEON_ALIAS = {
    ["the deadmines"] = "deadmines", ["the stockade"] = "stormwind stockade",
    ["the temple of atal'hakkar"] = "sunken temple", ["temple of atal'hakkar"] = "sunken temple",
    ["the temple of ahn'qiraj"] = "ahn'qiraj temple", ["ahn'qiraj"] = "ahn'qiraj temple",
    ["upper blackrock spire"] = "blackrock spire", ["lower blackrock spire"] = "blackrock spire",
    ["dire maul east"] = "dire maul", ["dire maul west"] = "dire maul", ["dire maul north"] = "dire maul",
    ["scarlet monastery graveyard"] = "scarlet monastery", ["scarlet monastery library"] = "scarlet monastery",
    ["scarlet monastery armory"] = "scarlet monastery", ["scarlet monastery cathedral"] = "scarlet monastery",
}
local function dungeonKey(name)
    name = (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    name = DUNGEON_ALIAS[name] or name
    return (name:gsub("^the ", ""))
end
local function findDungeon(name)
    if not name or not ns.DungeonData then return end
    local key = dungeonKey(name)
    for _, d in ipairs(ns.DungeonData) do
        if dungeonKey(d.name) == key then return d end
    end
end

-- A quest whose monsters live in several places (Questie knows them all): go to the place the game
-- itself marks for the quest (WoW Forever moved some), not just the spot nearest you in a straight line.
-- Returns a better mapId, x, y, name, or nothing to keep Questie's pick.
local AGREE, NEAR_YOU = 1000, 400
local function preferGameArea(questId, mapId, x, y)
    local HBD = ns.HBD
    if not HBD or not QuestieLoader then return end
    local bm, bx, by = fromBlizzardAnyMap(questId)
    if not bm then return end
    local gx, gy, ginst = HBD:GetWorldCoordinatesFromZone(bx, by, bm)
    if not gx then return end
    local qx, qy, qinst = HBD:GetWorldCoordinatesFromZone(x, y, mapId)
    if qx and qinst == ginst and (qx - gx) ^ 2 + (qy - gy) ^ 2 < AGREE * AGREE then return end -- they agree
    local px, py, pinst = HBD:GetPlayerWorldPosition()
    if qx and px and pinst == qinst and (qx - px) ^ 2 + (qy - py) ^ 2 < NEAR_YOU * NEAR_YOU then return end -- you're there
    -- Questie's spawn nearest the game's marker
    local ok, m2, x2, y2, n2 = pcall(function()
        local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
        if not (QuestieMap and QuestieMap.GetFramesForQuest) then return end
        local best, bestD
        for _, frame in pairs(QuestieMap:GetFramesForQuest(questId)) do
            if not frame.miniMapIcon and frame.x and frame.y and frame.UiMapID then
                local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(frame.x / 100, frame.y / 100, frame.UiMapID)
                if wx and inst == ginst then
                    local d = (wx - gx) ^ 2 + (wy - gy) ^ 2
                    if not bestD or d < bestD then best, bestD = frame, d end
                end
            end
        end
        if best and bestD < AGREE * AGREE then
            local data = best.data or {}
            return best.UiMapID, best.x / 100, best.y / 100, data.Name or data.name
        end
    end)
    if ok and m2 then return m2, x2, y2, n2, "Questie (game's quest area)" end
    return bm, bx, by, nil, "Blizzard map (game's quest area)"
end

local function fromQuestZone(questId)
    local zone = questZoneName(questId)
    allZones()
    local mapId = zone and zoneByName[zone]
    if mapId then return mapId, 0.5, 0.5, zone end
end

-- Where is my body? Tries the player's map, then its parent maps.
local function corpseLocation()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map and C_Map.GetBestMapForUnit) then return end
    local mapId = C_Map.GetBestMapForUnit("player")
    local guard = 0
    while mapId and mapId > 0 and guard < 6 do
        local pos = C_DeathInfo.GetCorpseMapPosition(mapId)
        if pos then
            local x, y = pos:GetXY()
            if x and y and (x > 0 or y > 0) then return mapId, x, y end
        end
        local info = C_Map.GetMapInfo(mapId)
        mapId = info and info.parentMapID
        guard = guard + 1
    end
end

local function isGhost()
    return UnitIsGhost and UnitIsGhost("player")
end

local function setTarget(self, t)
    local old = self.target
    local changed = (old == nil) ~= (t == nil)
        or (old and t and (old.wx ~= t.wx or old.wy ~= t.wy or old.questId ~= t.questId or old.name ~= t.name
            or old.corpse ~= t.corpse or old.custom ~= t.custom or old.title ~= t.title))
    if not changed then return end -- same destination: keep the same target (and its route)
    self.target = t
    self:NotifyChanged()
    if self.Route then self.Route:Update() end -- start the new route now, not on the next tick
end

-- ns.target fields: questId, title, name, mapId, x, y, wx, wy, instance, source, corpse
function ns:ComputeTarget()
    -- dead: run back to the body
    if self.db.corpseRoute and isGhost() and self.HBD then
        local mapId, x, y = corpseLocation()
        if mapId then
            local wx, wy, instance = self.HBD:GetWorldCoordinatesFromZone(x, y, mapId)
            if wx then
                setTarget(self, {
                    title = "Your corpse", name = "Run back to your body", corpse = true,
                    mapId = mapId, x = x, y = y, wx = wx, wy = wy, instance = instance, source = "Corpse",
                })
                return
            end
        end
    end

    -- a spot the player picked on the map (Ctrl + right-click)
    local c = self.custom
    if c and self.HBD then
        local wx, wy, instance = self.HBD:GetWorldCoordinatesFromZone(c.x, c.y, c.mapId)
        if wx then
            setTarget(self, {
                title = "Map marker", name = c.name, custom = true,
                mapId = c.mapId, x = c.x, y = c.y, wx = wx, wy = wy, instance = instance, source = "Map click",
            })
            return
        end
    end

    local questId = self.questId
    if not questId or not questInLog(questId) then
        if self.target then
            self.target = nil
            self:NotifyChanged()
        end
        return
    end

    local mapId, x, y, name = fromQuestie(questId)
    local source = "Questie"
    if mapId then
        local m2, x2, y2, n2, src2 = preferGameArea(questId, mapId, x, y)
        if m2 then mapId, x, y, name, source = m2, x2, y2, n2 or name, src2 end
    end
    if not mapId then
        mapId, x, y, name = fromQuestieIcons(questId)
        source = "Questie icons"
    end
    if not mapId then
        mapId, x, y, name = fromBlizzard(questId)
        source = "Blizzard"
    end
    if not mapId then
        mapId, x, y = fromBlizzardAnyMap(questId)
        source = "Blizzard map"
        if mapId then name = "Quest area" end
    end
    local approx = false
    if not mapId then
        -- a dungeon quest: go to the entrance
        local d = findDungeon(questZoneName(questId))
        if d then
            if d.inst then
                setTarget(self, { questId = questId, title = questTitle(questId), name = d.name .. " (entrance)",
                    wx = d.wx, wy = d.wy, instance = d.inst, source = "Dungeon entrance" })
                return
            end
            mapId, x, y, name, source = d.map, d.x, d.y, d.name .. " (entrance)", "Dungeon entrance"
        end
    end
    if not mapId then
        local zone
        mapId, x, y, zone = fromQuestZone(questId)
        if mapId then
            source, approx = "Quest zone", true
            name = "Somewhere in " .. zone
        end
    end

    self.lastLookup = mapId and { mapId = mapId, x = x, y = y, source = source } or nil
    local t
    if mapId and self.HBD then
        local wx, wy, instance = self.HBD:GetWorldCoordinatesFromZone(x, y, mapId)
        if wx then
            t = {
                questId = questId, title = questTitle(questId), name = name,
                mapId = mapId, x = x, y = y, wx = wx, wy = wy, instance = instance, source = source,
                approx = approx,
            }
        end
    end

    self.noLocation = (t == nil)
    setTarget(self, t)
end

function ns:SetCustomTarget(mapId, x, y, name)
    self.custom = mapId and { mapId = mapId, x = x, y = y, name = name } or nil
    self:ComputeTarget()
    if self.Route then self.Route:Replan() end
    self:NotifyChanged()
end

function ns:SetQuest(questId)
    if questId == 0 then questId = nil end
    if questId and self.custom then
        self.custom = nil -- choosing a quest replaces a map marker
        self.questId = nil
    end
    if self.questId == questId then return end
    self.questId = questId
    QuestRouteCharDB.questId = questId
    self:ComputeTarget()
    self:NotifyChanged()
end

function ns:ClearQuest()
    self.custom = nil
    self:SetQuest(nil)
    self:ComputeTarget()
    if self.Route then self.Route:Replan() end
    self:NotifyChanged()
end

---------------------------------------------------------------------------
-- Player position helpers shared by every display
---------------------------------------------------------------------------
function ns:PlayerWorld()
    if not self.HBD then return end
    return self.HBD:GetPlayerWorldPosition()
end

-- angle (radians, same convention as GetPlayerFacing) and distance in yards
-- Vector to the next stop of the route (a flight master, or the target itself).
function ns:VectorToTarget()
    local t = self.waypoint or self.target
    if not t then return end
    local inst = t.inst or t.instance
    local px, py, pinst = self:PlayerWorld()
    if not px or pinst ~= inst then return nil, nil, true end
    local angle, dist = self.HBD:GetWorldVector(pinst, px, py, t.wx, t.wy)
    return angle, dist, false
end

-- The segments to draw, starting at the player's live position.
-- Returns a list of { x1, y1, x2, y2, inst, kind } in world coordinates.
function ns:RouteSegments()
    local t = self.target
    if not t then return {} end
    local px, py, pinst = self:PlayerWorld()
    local segs = {}
    local route = self.route
    if route and self.waypoint then
        local cx, cy, cinst = px, py, pinst
        for i = self.waypoint.index, #route.stops do
            local s = route.stops[i]
            if cx and cinst == s.inst then
                table.insert(segs, { cx, cy, s.wx, s.wy, s.inst, s.kind })
            end
            cx, cy, cinst = s.wx, s.wy, s.inst
        end
    elseif px and pinst == t.instance and not (self.Route and self.Route:IsPlanning()) then
        table.insert(segs, { px, py, t.wx, t.wy, pinst, "walk" })
    end
    return segs
end

-- Segments joined into continuous lines (same kind, same continent).
-- Returns a list of { kind = "walk"|"travel", inst = n, pts = { {x, y}, ... } }.
function ns:RoutePolylines()
    local lines, cur = {}, nil
    for _, sg in ipairs(self:RouteSegments()) do
        local kind = (sg[6] == "walk" or sg[6] == nil) and "walk" or "travel"
        if cur and cur.kind == kind and cur.inst == sg[5] and cur.lx == sg[1] and cur.ly == sg[2] then
            cur.pts[#cur.pts + 1] = { sg[3], sg[4] }
        else
            cur = { kind = kind, inst = sg[5], pts = { { sg[1], sg[2] }, { sg[3], sg[4] } } }
            lines[#lines + 1] = cur
        end
        cur.lx, cur.ly = sg[3], sg[4]
    end
    return lines
end

-- Settings used for drawing flight/boat legs: dotted and a bit fainter.
ns.flyDb = setmetatable({}, { __index = function(_, k)
    if k == "style" then return "dotted" end
    if k == "opacity" then return ns.db.opacity * 0.75 end
    if k == "glow" then return false end
    return ns.db[k]
end })

-- In a dungeon, raid or battleground, or in a cave or tunnel (the game shows its own small map
-- there), the route can't be drawn sensibly: it's paused until you're back outside.
local pausedAt, pausedValue = -1, false
function ns:RoutePaused()
    local now = GetTime and GetTime() or 0
    if now - pausedAt < 0.5 then return pausedValue end
    pausedAt = now
    local paused = false
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and kind ~= "none" then paused = true end
    end
    if not paused and C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local m = C_Map.GetBestMapForUnit("player")
        local info = m and C_Map.GetMapInfo(m)
        local t = info and info.mapType
        -- (4: a dungeon map, 5: a micro map such as a cave; cities and buildings are zone maps)
        if t == 4 or t == 5 then paused = true end
    end
    pausedValue = paused
    return paused
end

function ns:RouteActive()
    return self.db and self.db.enabled and self.target ~= nil and not self:RoutePaused()
end

---------------------------------------------------------------------------
-- Public toggles (also used by key bindings)
---------------------------------------------------------------------------
function ns:ToggleRoute(state)
    if state == nil then state = not self.db.enabled end
    self.db.enabled = state
    self:Print(state and "route |cff40ff40ON|r" or "route |cffff4040OFF|r")
    self:NotifyChanged()
end

function ns:ToggleCompass(state)
    if state == nil then state = not self.db.compass end
    self.db.compass = state
    self:Print(state and "compass |cff40ff40ON|r" or "compass |cffff4040OFF|r")
    self:NotifyChanged()
end

function QuestRoute_ToggleRoute() ns:ToggleRoute() end
function QuestRoute_ToggleCompass() ns:ToggleCompass() end
BINDING_HEADER_QUESTROUTE = "QuestRoute"
BINDING_NAME_QUESTROUTE_TOGGLE = "Toggle route"
BINDING_NAME_QUESTROUTE_COMPASS = "Toggle compass"

---------------------------------------------------------------------------
-- Events and timers
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame

local lastSelected, lastSuper
local selectionTimer, targetTimer, routeTimer, refreshQueued = 0, 0, 0, false

local function isWatched(questId)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        return C_QuestLog.GetQuestWatchType(questId) ~= nil
    end
    if IsQuestWatched and GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(questId)
        if idx and idx > 0 then return IsQuestWatched(idx) end
    end
    return nil -- unknown
end

local lastWatched
local function watchSelection()
    if not ns.db then return end
    local sel = selectedQuest()
    if sel == 0 then sel = nil end
    if sel ~= lastSelected then
        local was = lastSelected
        lastSelected = sel
        if sel then
            ns:SetQuest(sel)
        elseif was and was == ns.questId and ns.db.clearOnDeselect then
            ns:ClearQuest() -- the routed quest was deselected
        end
    end
    local sup = superTrackedQuest()
    if sup == 0 then sup = nil end
    if sup ~= lastSuper then
        local was = lastSuper
        lastSuper = sup
        if sup then
            ns:SetQuest(sup)
        elseif was and was == ns.questId and ns.db.clearOnDeselect then
            ns:ClearQuest()
        end
    end
    -- untracking the routed quest clears the route too
    local q = ns.questId
    if q then
        local w = isWatched(q)
        if lastWatched and lastWatched.id == q and lastWatched.w == true and w == false and ns.db.clearOnDeselect then
            ns:ClearQuest()
        end
        lastWatched = { id = q, w = w }
    end
end

frame:SetScript("OnUpdate", function(_, elapsed)
    if not ns.db then return end
    selectionTimer = selectionTimer + elapsed
    if selectionTimer > 0.1 then
        selectionTimer = 0
        watchSelection()
    end
    targetTimer = targetTimer + elapsed
    if targetTimer > 1.5 or (refreshQueued and targetTimer > 0.3) then
        targetTimer = 0
        refreshQueued = false
        ns:ComputeTarget()
    end
    routeTimer = routeTimer + elapsed
    if routeTimer > 0.5 then
        routeTimer = 0
        if ns.Route then ns.Route:Update() end
    end
end)

frame:RegisterEvent("ADDON_LOADED")
pcall(frame.RegisterEvent, frame, "SUPER_TRACKING_CHANGED")
-- clicking a quest in the quest log or on the map: react on the next frame
local function selectionHook() if C_Timer and ns.db then C_Timer.After(0, watchSelection) end end
if hooksecurefunc then
    if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(hooksecurefunc, C_QuestLog, "SetSelectedQuest", selectionHook) end
    if SelectQuestLogEntry then pcall(hooksecurefunc, "SelectQuestLogEntry", selectionHook) end
    if QuestMapFrame_ShowQuestDetails then pcall(hooksecurefunc, "QuestMapFrame_ShowQuestDetails", selectionHook) end
end
pcall(frame.RegisterEvent, frame, "QUEST_WATCH_LIST_CHANGED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "SUPER_TRACKING_CHANGED" or event == "QUEST_WATCH_LIST_CHANGED" then
        -- a quest was clicked or (un)tracked: react now, not on the next check
        if ns.db then watchSelection() end
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON then
        QuestRouteDB = QuestRouteDB or {}
        QuestRouteCharDB = QuestRouteCharDB or {}
        -- settings from older versions
        if QuestRouteDB.compassMode == "arrow" then QuestRouteDB.compassStyle = "none" end
        if QuestRouteDB.compassRing == false and QuestRouteDB.compassStyle == nil then QuestRouteDB.compassStyle = "none" end
        QuestRouteDB.compassMode, QuestRouteDB.compassRing = nil, nil
        local pos = QuestRouteDB.compassPos
        if pos and type(pos[1]) == "string" then QuestRouteDB.compassPos = nil end
        copyDefaults(defaults, QuestRouteDB)
        QuestRouteDB.roads = QuestRouteDB.roads or {}
        QuestRouteDB.transports = QuestRouteDB.transports or {}
        ns.db = QuestRouteDB
    elseif event == "PLAYER_LOGIN" then
        if not ns.HBD then ns:FindLibraries() end
        if not ns.HBD then
            ns:Print("|cffff4040could not find the HereBeDragons map library inside Questie. Is Questie enabled and up to date?|r")
        end
        lastSelected, lastSuper = selectedQuest(), superTrackedQuest()
        -- v0.6.4 guessed known flight paths from the world map and got it wrong: start over once
        if not QuestRouteCharDB.taxiReset065 then
            QuestRouteCharDB.taxiReset065 = true
            if QuestRouteCharDB.knownTaxi and next(QuestRouteCharDB.knownTaxi) then
                QuestRouteCharDB.knownTaxi = {}
                ns:Print("flight paths reset (the last version marked some you haven't unlocked). Open a flight master's map once on each continent; new ones are learned when you discover them or fly.")
            end
        end
        local saved = QuestRouteCharDB.questId
        if saved and questInLog(saved) then
            ns.questId = saved
        end
        if ns.InitOptions then ns:InitOptions() end
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if not (isLoaded and isLoaded("TomTom")) and not SlashCmdList.TOMTOM_WAY then
            SLASH_QUESTROUTEWAY1 = "/way"
            SlashCmdList.QUESTROUTEWAY = function(m) ns:WayCommand(m) end
        end
        refreshQueued = true
        ns:NotifyChanged()
    elseif event == "QUEST_REMOVED" and arg1 == ns.questId then
        ns:ClearQuest()
    else
        refreshQueued = true
    end
end)

---------------------------------------------------------------------------
-- Diagnostics: walks every lookup step and reports what happened.
---------------------------------------------------------------------------
function ns:Diagnose()
    local P = function(...) self:Print(...) end
    local id = self.questId
    P("---- debug ----")
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local function ver(a) return meta and meta(a, "Version") or "?" end
    P("QuestRoute", ver("QuestRoute"), " Questie", ver("Questie"))
    P("HereBeDragons:", self.HBD and "ok" or "MISSING", " QuestieLoader:", QuestieLoader and "ok" or "MISSING")
    P("selected quest:", tostring(selectedQuest()), " route quest:", tostring(id), id and questTitle(id) or "")
    if not id then return end
    P("in quest log:", tostring(questInLog(id)))

    if QuestieLoader then
        local ok, err = pcall(function()
            local ActiveQuests = QuestieLoader:ImportModule("ActiveQuests")
            local hasGet = ActiveQuests and ActiveQuests.Get
            P("Questie ActiveQuests.Get:", hasGet and "yes" or "no")
            local quest = hasGet and ActiveQuests.Get(id)
            quest = quest and quest.quest
            P("Questie quest object:", quest and "found" or "not found")
            if quest then
                local nObj, nSpawn = 0, 0
                for _, o in pairs(quest.Objectives or {}) do
                    nObj = nObj + 1
                    for _, s in pairs(o.spawnList or {}) do
                        for _, list in pairs(s.Spawns or {}) do nSpawn = nSpawn + #list end
                    end
                end
                P("objectives:", nObj, " spawn points:", nSpawn, " complete:", tostring(quest.IsComplete and quest:IsComplete()))
                local DistanceUtils = QuestieLoader:ImportModule("DistanceUtils")
                local spawn, zone, name = DistanceUtils.GetNearestSpawnForQuest(quest)
                P("nearest:", spawn and ("%.1f, %.1f"):format(spawn[1], spawn[2]) or "none", " zone:", tostring(zone), " name:", tostring(name))
            end
            local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
            local n = 0
            if QuestieMap and QuestieMap.GetFramesForQuest then
                for _ in pairs(QuestieMap:GetFramesForQuest(id)) do n = n + 1 end
            end
            P("Questie map icons for quest:", n)
        end)
        if not ok then P("|cffff4040Questie error:|r", tostring(err)) end
    end

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local m, x, y = C_QuestLog.GetNextWaypoint(id)
        P("Blizzard waypoint:", m and ("map %d %.2f %.2f"):format(m, x, y) or "none")
    end

    local bm, bx, by = fromBlizzardAnyMap(id)
    P("Blizzard markers (all maps):", bm and ("map %d %.2f %.2f"):format(bm, bx, by) or "none")
    P("quest log zone:", tostring((questZoneName(id))), " zone maps known:", #allZones())
    local t = self.target
    if t then
        P(("TARGET: %s  map %d  %.1f, %.1f  (via %s)"):format(tostring(t.name), t.mapId, t.x * 100, t.y * 100, t.source))
        local _, dist, other = self:VectorToTarget()
        P(self.waypoint and not self.waypoint.final and "distance to the next stop:" or "distance:",
            dist and math.floor(dist) .. " yd" or (other and "other continent" or "?"))
    else
        local l = self.lastLookup
        if l then
            P(("|cffff8040found map %s %.1f, %.1f via %s, but could not convert it to world position|r"):format(tostring(l.mapId), l.x * 100, l.y * 100, l.source))
        else
            P("|cffff8040no target location found|r")
        end
    end
    if self.lastError then P("last error:", tostring(self.lastError)) end
    local r = self.route
    if r then
        local steps = {}
        for _, s in ipairs(r.stops) do
            if not s.road then steps[#steps + 1] = (s.kind or "?") .. " " .. tostring(s.name) end
        end
        P(("route: %d points, ~%ds: %s"):format(#r.stops, r.total or 0, table.concat(steps, " > ")))
    else
        P("route:", self.Route and self.Route:IsPlanning() and "planning..." or "straight line")
    end
    P("flight paths known:", self.Route and self.Route:KnownCount() or 0, " (/qroute flights lists them)")
    if self.lastPlanError then P("|cffff4040last route error:|r", tostring(self.lastPlanError)) end
end

---------------------------------------------------------------------------
-- Map scan: reads every flight point and map point of interest (boats,
-- zeppelins, trams...) from the game's own map data and stores it in the
-- saved variables, so we can build the travel network from exact data.
---------------------------------------------------------------------------
function ns:ScanMaps()
    local out = {
        build = select(4, GetBuildInfo()), faction = UnitFactionGroup and UnitFactionGroup("player"),
        time = time and time(), maps = {}, pois = {}, taxi = {},
    }
    local visited, seenTaxi = {}, {}
    local function xy(pos)
        if pos and pos.GetXY then return pos:GetXY() end
    end
    local function visit(mapId, depth)
        if not mapId or mapId == 0 or visited[mapId] or depth > 6 then return end
        visited[mapId] = true
        local info = C_Map.GetMapInfo(mapId)
        if not info then return end
        local entry = { id = mapId, name = info.name, type = info.mapType, parent = info.parentMapID }
        -- where the map sits on the world map (947), and the real-world corners of the map
        if mapId ~= 947 and C_Map.GetMapRectOnMap then
            local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, mapId, 947)
            if ok and l then entry.onWorld = { l, r, t, b } end
        end
        if C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok0, i0, p0 = pcall(C_Map.GetWorldPosFromMapPos, mapId, CreateVector2D(0, 0))
            local ok1, i1, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapId, CreateVector2D(1, 1))
            local x0, y0 = xy(ok0 and p0)
            local x1, y1 = xy(ok1 and p1)
            if x0 and x1 then entry.world = { i0, x0, y0, x1, y1 } end
        end
        table.insert(out.maps, entry)

        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
            local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapId)
            for _, poiId in ipairs(ok and ids or {}) do
                local p = C_AreaPoiInfo.GetAreaPOIInfo(mapId, poiId)
                if p then
                    local x, y = xy(p.position)
                    table.insert(out.pois, { map = mapId, id = poiId, name = p.name, desc = p.description,
                        x = x, y = y, atlas = p.atlasName, tex = p.textureIndex })
                end
            end
        end
        if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
            local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapId)
            for _, n in ipairs(ok and nodes or {}) do
                local key = mapId .. ":" .. tostring(n.nodeID)
                if not seenTaxi[key] then
                    seenTaxi[key] = true
                    local x, y = xy(n.position)
                    table.insert(out.taxi, { map = mapId, id = n.nodeID, name = n.name, x = x, y = y,
                        state = n.state, faction = n.faction, atlas = n.atlasName, kit = n.textureKit,
                        undiscovered = n.isUndiscovered })
                end
            end
        end
        if C_Map.GetMapChildrenInfo then
            for _, child in ipairs(C_Map.GetMapChildrenInfo(mapId) or {}) do
                visit(child.mapID, depth + 1)
            end
        end
    end
    for _, id in ipairs({ 947, 1414, 1415 }) do visit(id, 0) end -- Azeroth, Kalimdor, Eastern Kingdoms
    QuestRouteDB.scan = out
    self:Print(("scan done: %d maps, %d points of interest, %d flight point entries."):format(#out.maps, #out.pois, #out.taxi))
    self:Print("Type /reload so the game writes it to disk.")
end

-- Record the player's exact position with a label (e.g. a boat dock).
function ns:RecordSpot(label)
    local mapId = C_Map.GetBestMapForUnit("player")
    local pos = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    if not pos then
        self:Print("can't read your position here")
        return
    end
    local x, y = pos:GetXY()
    QuestRouteDB.spots = QuestRouteDB.spots or {}
    local info = C_Map.GetMapInfo(mapId)
    table.insert(QuestRouteDB.spots, { map = mapId, zone = info and info.name, x = x, y = y, label = label,
        faction = UnitFactionGroup and UnitFactionGroup("player") })
    self:Print(("saved spot #%d: %s %.1f, %.1f  \"%s\""):format(#QuestRouteDB.spots, info and info.name or mapId, x * 100, y * 100, label))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_QUESTROUTE1 = "/questroute"
SLASH_QUESTROUTE2 = "/qroute"
SlashCmdList.QUESTROUTE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "toggle" or msg == "route" then
        ns:ToggleRoute()
    elseif msg == "compass" then
        ns:ToggleCompass()
    elseif msg == "clear" then
        ns.custom = nil
        ns:ClearQuest()
        ns:Print("route cleared")
    elseif msg == "reset" then
        ns.db.compassPos = nil
        ns:NotifyChanged()
        ns:Print("compass position reset")
    elseif msg == "debug" then
        ns:Diagnose()
    elseif msg == "flights" then
        local names = ns.Route:KnownNames()
        ns:Print(("%d flight path(s) known%s"):format(#names, #names > 0 and ":" or ". Open any flight master's map to update."))
        for _, n in ipairs(names) do ns:Print("   " .. n) end
        if ns.lastTaxiScan then
            ns:Print(("last flight map read: %d entries, %d unlocked (%s)"):format(ns.lastTaxiScan.seen, ns.lastTaxiScan.usable, ns.lastTaxiScan.samples))
        end
    elseif msg == "roads" then
        local n = ns.Learn:RoadStats()
        ns:Print(("road points learned: %d, boat routes learned: %d"):format(n, #(QuestRouteDB.transports or {})))
    elseif msg:match("^way") then
        ns:WayCommand(msg:gsub("^way%s*", ""))
    elseif msg == "fpinfo" then
        -- every field the world map reports per flight point, to find the "unlocked" signal
        local mapId = C_Map.GetBestMapForUnit("player")
        local info = mapId and C_Map.GetMapInfo(mapId)
        while info and info.mapType and info.mapType > 2 and info.parentMapID and info.parentMapID > 0 do
            mapId = info.parentMapID
            info = C_Map.GetMapInfo(mapId)
        end
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapId)
        ns:Print(("flight points on map %s (%s): %d"):format(tostring(mapId), info and info.name or "?", ok and nodes and #nodes or 0))
        local seenKeys = {}
        for _, n in ipairs(ok and nodes or {}) do
            local parts = {}
            for key, val in pairs(n) do
                if key ~= "position" and key ~= "nodeID" and key ~= "name" then
                    parts[#parts + 1] = key .. "=" .. tostring(val)
                    seenKeys[key] = true
                end
            end
            table.sort(parts)
            ns:Print(("%s: %s"):format(tostring(n.name), table.concat(parts, " ")))
        end
    elseif msg == "scan" then
        ns:ScanMaps()
    elseif msg:match("^dock") or msg:match("^spot") then
        local label = msg:gsub("^%a+%s*", "")
        ns:RecordSpot(label ~= "" and label or "dock")
    else
        if ns.ToggleOptions then ns:ToggleOptions() end
    end
end
