-- Minimal fake WoW environment to exercise QuestRoute code paths.
local ADDON_DIR = arg[1]
local now = 100
local calls = { lines = 0, textures = 0 }
local scripts = {}   -- all frames with scripts
local frames = {}

local function newObj(kind, parent)
  local o = { dragging = false, kind = kind, parent = parent, shown = true, scripts = {}, w = 200, h = 200, level = 5 }
  local mt = {}
  mt.__index = function(t, k)
    return function(self, ...) return nil end
  end
  setmetatable(o, mt)
  function o:SetScript(n, fn) self.scripts[n] = fn end
  function o:HookScript(n, fn) local old = self.scripts[n]; self.scripts[n] = function(...) if old then old(...) end fn(...) end end
  function o:GetScript(n) return self.scripts[n] end
  function o:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function o:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
  function o:SetShown(v) if v then self:Show() else self:Hide() end end
  function o:IsShown() return self.shown end
  function o:SetSize(w, h) self.w, self.h = w, h end
  function o:GetWidth() return self.w end
  function o:GetHeight() return self.h end
  function o:GetSize() return self.w, self.h end
  function o:GetFrameLevel() return self.level end
  function o:SetFrameLevel(l) assert(type(l) == "number", "SetFrameLevel needs number"); self.level = l end
  function o:CreateLine() calls.lines = calls.lines + 1; return newObj("Line", self) end
  function o:CreateTexture() calls.textures = calls.textures + 1; return newObj("Texture", self) end
  function o:CreateFontString() local f = newObj("FontString", self); function f:SetText(t) self.text = t end; function f:GetStringWidth() return 50 end; return f end
  function o:GetPoint() return "TOP", UIParent, "TOP", 10, -20 end
  function o:GetCenter() return rawget(self,"cx") or 960, rawget(self,"cy") or 540 end
  function o:GetEffectiveScale() return 1 end
  function o:GetScale() return rawget(self,"scale") or 1 end
  function o:SetScale(v) assert(type(v)=="number" and v > 0, "bad scale"); self.scale = v end
  function o:GetChecked() return true end
  function o:GetValue() return self.value or 1 end
  function o:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
  function o:SetThickness(t) assert(t > 0 and t < 1000, "bad thickness " .. tostring(t)) end
  function o:SetStartPoint(p, rel, x, y) assert(type(x) == "number" and x == x and type(y) == "number" and y == y, "bad start point") end
  function o:SetEndPoint(p, rel, x, y) assert(type(x) == "number" and x == x and type(y) == "number" and y == y, "bad end point") end
  function o:SetRotation(r) assert(type(r) == "number" and r == r, "bad rotation") ; self.rotation = r end
  function o:SetVertexColor(r, g, b, a) assert(type(r) == "number" and type(a or 1) == "number", "bad color") end
  return o
end

-- globals
_G.UIParent = newObj("Frame")
_G.Minimap = newObj("Minimap"); Minimap.w, Minimap.h = 140, 140
function Minimap:GetZoom() return 0 end
function _G.CreateFrame(kind, name, parent, template)
  local f = newObj(kind, parent)
  table.insert(frames, f)
  if name then _G[name] = f end
  return f
end
local canvas = newObj("Canvas"); canvas.w, canvas.h = 1002, 668
_G.WorldMapFrame = newObj("WorldMapFrame")
WorldMapFrame.ScrollContainer = newObj("Scroll")
function WorldMapFrame.ScrollContainer:GetCanvasScale() return 1.5 end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return 1426 end
function WorldMapFrame:GetPinFrameLevelsManager() return { GetValidFrameLevel = function(_, n) return 42 end } end
_G.GameTooltip = newObj("Tooltip")
local editCallbacks = {}
_G.EventRegistry = { RegisterCallback = function(_, ev, fn) editCallbacks[ev] = fn end }
_G.hooksecurefunc = function() end
_G.ColorPickerFrame = newObj("ColorPicker")
_G.UISpecialFrames = {}
_G.C_Timer = { After = function(_, fn) fn() end }
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end
_G.tinsert = table.insert
_G.GetTime = function() return now end
_G.GetCVar = function(n) if n == "rotateMinimap" then return "1" end return "0" end
local facing = 0.5
_G.GetPlayerFacing = function() return facing end
local unitSpeed = 7
_G.GetUnitSpeed = function() return unitSpeed end
_G.IsShiftKeyDown = function() return false end
_G.geterrorhandler = function() return function(e) error(e) end end
_G.SlashCmdList = {}
_G.HideUIPanel = function() end
_G.print = function(...) local t = {...}; for i=1,select('#',...) do t[i]=tostring(t[i]) end; io.write("[chat] ", table.concat(t, " "), "\n") end

local selected = 0
_G.C_QuestLog = {
  GetSelectedQuest = function() return selected end,
  GetLogIndexForQuestID = function(id) return id == 1275 and 3 or nil end,
  GetTitleForQuestID = function(id) return "Researching the Corruption" end,
  GetNextWaypoint = function() return nil end,
  GetQuestsOnMap = function() return {} end,
}
_G.C_AddOns = { GetAddOnMetadata = function() return "0.1.1" end }
_G.C_Map = { GetBestMapForUnit = function() return 1426 end, GetMapInfo = function() return { name = "Dun Morogh" } end }

-- HBD fake: simple linear map, zone 1426 is 4000x2600 yards with left/top at 0/0
local HBD = {}
local playerX, playerY, playerI = -1000, -900, 0
function HBD:GetPlayerWorldPosition() return playerX, playerY, playerI end
function HBD:GetWorldCoordinatesFromZone(x, y, zone) return 0 - 4000 * x, 0 - 2600 * y, 0 end
function HBD:GetZoneCoordinatesFromWorldInstance(x, y, inst, zone, oob) if inst ~= 0 then return nil end return (0 - x) / 4000, (0 - y) / 2600 end
function HBD:GetWorldVector(i, ox, oy, dx, dy) local ddx, ddy = dx - ox, dy - oy; local a = math.atan2(-ddx, ddy); if a > 0 then a = 2*math.pi - a else a = -a end; return a, math.sqrt(ddx * ddx + ddy * ddy) end
local Pins = { GetMinimapView = function() return 233, true end }
local libs = {
  ["LibDataBroker-1.1"] = { NewDataObject = function(_, n, o) return o end },
  ["LibDBIcon-1.0"] = { Register = function() end, Show = function() end, Hide = function() end } }
_G.LibStub = function(name, silent) return libs[name] end

-- Questie fake
local spawnX, spawnY = 30, 40
local modules = {
  ActiveQuests = { Get = function(id) return { quest = { Id = id } } end },
  DistanceUtils = { GetNearestSpawnForQuest = function(q) return { spawnX, spawnY }, 1, "Blackfathom Ruins" end },
  ZoneDB = { GetUiMapIdByAreaId = function(_, z) return 1426 end },
  QuestieMap = { GetFramesForQuest = function(_, id) return { a = { x = 50, y = 50, UiMapID = 1426, data = { Name = "Icon Target" } }, b = { x = 10, y = 10, UiMapID = 1426, miniMapIcon = true } } end },
}
modules.HBD = HBD; modules.HBDPins = Pins
_G.QuestieLoader = { _modules = modules, ImportModule = function(_, n) return modules[n] or {} end }

-- load addon files in toc order
local ns = {}
for line in io.lines(ADDON_DIR .. "/QuestRoute.toc") do
  if line:match("%.lua$") then
    local chunk = assert(loadfile(ADDON_DIR .. "/" .. line:gsub("\\", "/")))
    chunk("QuestRoute", ns)
  end
end

local function fire(event, ...)
  for _, f in ipairs(frames) do if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
local function tick(dt)
  now = now + dt
  for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.shown then f.scripts.OnUpdate(f, dt) end end
end

fire("ADDON_LOADED", "QuestRoute")
ns.NavData = nil -- this suite uses a made-up map; the real network is tested in alltest.lua
ns.FlightLegs = nil
fire("PLAYER_LOGIN")
for i = 1, 5 do tick(0.1) end
print("before select: target", ns.target, "compass shown", QuestRouteCompass:IsShown())

selected = 1275
for i = 1, 30 do tick(0.05) end
assert(ns.questId == 1275, "quest not picked up")
assert(ns.target and ns.target.name == "Blackfathom Ruins", "no target")
print("target", ns.target.name, ns.target.wx, ns.target.wy, "compass shown", QuestRouteCompass:IsShown())
local ang, dist = ns:VectorToTarget()
print(("vector angle %.2f dist %.0f"):format(ang, dist))
print("lines created", calls.lines, "textures", calls.textures)

for _, style in ipairs({ "solid", "dashed", "dotted" }) do
  ns.db.style = style; ns.db.glow = true
  for i = 1, 10 do tick(0.04) end
  print("style", style, "ok; lines", calls.lines, "textures", calls.textures)
end

-- open settings, poke every slider/checkbox
SlashCmdList.QUESTROUTE("")
assert(QuestRouteOptions and QuestRouteOptions:IsShown(), "options not shown")
for _, f in ipairs(frames) do
  if f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton") end
  if f.scripts.OnValueChanged then f.scripts.OnValueChanged(f, 3) end
  if f.scripts.OnMouseWheel then f.scripts.OnMouseWheel(f, 1) end
end
for i = 1, 10 do tick(0.04) end
print("options interactions ok")

-- other continent
playerI = 1
for i = 1, 10 do tick(0.05) end
print("other continent ok")
playerI = 0

-- arrival
playerX, playerY = ns.target.wx + 2, ns.target.wy + 2
for i = 1, 10 do tick(0.05) end
print("arrival ok")

-- quest removed
fire("QUEST_REMOVED", 1275)
assert(ns.questId == nil and ns.target == nil, "not cleared")
for i = 1, 10 do tick(0.05) end
print("cleared ok; compass shown", QuestRouteCompass:IsShown())

SlashCmdList.QUESTROUTE("debug")
SlashCmdList.QUESTROUTE("toggle")
SlashCmdList.QUESTROUTE("compass")
for i = 1, 5 do tick(0.05) end

-- fallback: Questie nearest fails -> icons
SlashCmdList.QUESTROUTE("toggle")
modules.DistanceUtils.GetNearestSpawnForQuest = function() return nil end
selected = 0; for i=1,3 do tick(0.1) end
selected = 1275; for i = 1, 40 do tick(0.05) end
assert(ns.target and ns.target.source == "Questie icons", "icon fallback failed: " .. tostring(ns.target and ns.target.source))
print("icon fallback ok:", ns.target.name)
SlashCmdList.QUESTROUTE("debug")
-- error inside Questie -> still falls back
modules.DistanceUtils.GetNearestSpawnForQuest = function() error("boom") end
ns:ComputeTarget(); assert(ns.target.source == "Questie icons")
-- compass modes
ns.db.compassMode = "arrow"; ns:NotifyChanged(); for i=1,5 do tick(0.05) end
ns.db.arrowUseLineColor = false; ns.db.arrowScale = 1.5; ns:NotifyChanged(); for i=1,5 do tick(0.05) end
-- options with no quest: preview mode
ns.db.compass = true; fire("QUEST_REMOVED", 1275); ns:ToggleOptions(true); for i=1,5 do tick(0.05) end
assert(QuestRouteCompass:IsShown(), "compass preview should show while options open")
-- every compass style x arrow placement x arrow shape
ns:ToggleOptions(false)
for _, st in ipairs({"gold","modern","bar","none"}) do
  for _, pl in ipairs({"inside","above","below"}) do
    for _, ar in ipairs({"arrow","chevron","needle"}) do
      ns.db.compassStyle, ns.db.arrowPlacement, ns.db.arrowStyle = st, pl, ar
      ns:NotifyChanged(); for i=1,3 do tick(0.05) end
    end
  end
end
print("compass styles ok")
-- outline on all line styles
ns.db.outline = true
for _, st in ipairs({"solid","dashed","dotted","gilded","footprints"}) do ns.db.style = st; for i=1,3 do tick(0.05) end end
for _, mk in ipairs({"glow","x"}) do ns.db.markerStyle = mk; for i=1,3 do tick(0.05) end end
print("outline ok")
-- centring and drag snapping
ns:CenterCompass(true); assert(ns.db.compassPos.x == 0)
ns:CenterCompass(false); assert(ns.db.compassPos.y == 0)
QuestRouteCompass.cx = 970; QuestRouteCompass.cy = 800
QuestRouteCompass.scripts.OnDragStart(QuestRouteCompass); tick(0.05)
QuestRouteCompass.scripts.OnDragStop(QuestRouteCompass)
assert(ns.db.compassPos.x == 0 and ns.db.compassPos.y == 260, "snap failed "..ns.db.compassPos.x..","..ns.db.compassPos.y)
print("snapping ok")
-- old saved settings migrate
QuestRouteDB = { compassMode = "arrow", compassPos = {"TOP","TOP",0,-90} }
fire("ADDON_LOADED", "QuestRoute")
assert(QuestRouteDB.compassStyle == "none" and QuestRouteDB.compassPos == nil and QuestRouteDB.outline == true, "migration")
print("migration ok")
-- ghost: route to corpse even with no quest selected
local ghost = false
_G.UnitIsGhost = function() return ghost end
_G.C_DeathInfo = { GetCorpseMapPosition = function(m) return { GetXY = function() return 0.6, 0.7 end } end }
_G.C_Map.GetMapInfo = function() return { name = "Dun Morogh", parentMapID = 0 } end
ns:ToggleOptions(false); ns:ClearQuest(); ns.db.compass = true; ns.db.compassHideIdle = true
ghost = true; fire("PLAYER_DEAD"); for i=1,40 do tick(0.05) end
assert(ns.target and ns.target.corpse, "no corpse target")
assert(QuestRouteCompass:IsShown(), "compass should show for corpse")
print("corpse route ok", ns.target.wx, ns.target.wy)
ghost = false; fire("PLAYER_UNGHOST"); for i=1,40 do tick(0.05) end
assert(ns.target == nil, "corpse target should clear")
print("unghost ok")
-- scan + dock recording
local vec = function(x,y) return { GetXY = function() return x, y end } end
_G.GetBuildInfo = function() return "1.60.1", "1", "", 16001 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.time = os.time
_G.C_Map.GetMapInfo = function(id) return { name = "Map"..id, mapType = 2, parentMapID = 947 } end
_G.C_Map.GetMapChildrenInfo = function(id) if id == 1415 then return { { mapID = 1437 }, { mapID = 1453 } } end return {} end
_G.C_Map.GetPlayerMapPosition = function() return vec(0.05, 0.57) end
_G.C_AreaPoiInfo = { GetAreaPOIForMap = function(m) return m == 1437 and {101} or {} end,
  GetAreaPOIInfo = function(m, id) return { name = "Boat to Theramore", description = "Ship", position = vec(0.05, 0.6), atlasName = "Ship" } end }
_G.C_TaxiMap = { GetTaxiNodesForMap = function(m) return { { nodeID = 7, name = "Menethil Harbor", position = vec(0.1,0.2), state = 1 } } end }
SlashCmdList.QUESTROUTE("scan")
assert(#QuestRouteDB.scan.pois == 1 and #QuestRouteDB.scan.taxi >= 1, "scan")
SlashCmdList.QUESTROUTE("dock menethil to theramore")
assert(QuestRouteDB.spots[1].label == "menethil to theramore")
print("scan ok")
-- route planning with flights
_G.UnitLevel = function() return 30 end
local onTaxi = false
_G.UnitOnTaxi = function() return onTaxi end
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { 52, 72 }, 1, "Far Target" end -- near Lakeshire FP
ns.db.compass = true
-- (this fake world is far smaller than the real one, while flight times come from the real flight
-- network: make walking cost what it would over the real distance, so the flight is worth taking)
local savedOff = ns.db.offroadPenalty; ns.db.offroadPenalty = 6
playerX, playerY = HBD:GetWorldCoordinatesFromZone(0.4874, 0.5237, 1415) -- standing at Ironforge FP
selected = 0; for i=1,3 do tick(0.1) end
selected = 1275; for i = 1, 40 do tick(0.05) end
assert(ns.target and ns.target.name == "Far Target", "target "..tostring(ns.target and ns.target.name))
assert(ns.route == nil, "no flights known yet -> straight")
-- learn flights at the flight master
_G.GetTaxiMapID = function() return 1415 end
_G.C_TaxiMap.GetAllTaxiNodes = function() return { { nodeID = 6, name = "Ironforge, Dun Morogh", state = 0 }, { nodeID = 5, name = "Lakeshire, Redridge", state = 1 }, { nodeID = 2, name = "Stormwind, Elwynn", state = 1 } } end
fire("TAXIMAP_OPENED"); for i=1,20 do tick(0.05) end
print("known", ns.Route:KnownCount())
assert(ns.route, "expected a flight route")
for i, st in ipairs(ns.route.stops) do print("stop", i, st.kind, st.name) end
print("waypoint:", ns.waypoint.name, ns.waypoint.text, ("total %.0fs"):format(ns.route.total))
assert(ns.waypoint.text and ns.waypoint.text:match("Take the flight"), "should say take the flight")
-- walk away from the FP: should say go to the flight master
playerX, playerY = playerX + 200, playerY + 100; for i=1,20 do tick(0.05) end
print("waypoint:", ns.waypoint and ns.waypoint.text)
-- in the air
onTaxi = true; playerX, playerY = playerX - 900, playerY - 900; for i=1,20 do tick(0.05) end
print("on taxi:", ns.waypoint and ns.waypoint.text)
assert(ns.waypoint.text:match("Flying to"), "flying text")
onTaxi = false
local segs = ns:RouteSegments(); print("segments", #segs)
SlashCmdList.QUESTROUTE("flights")
print("route ok")
-- Edit Mode
ns:ToggleOptions(false); ns:ClearQuest(); ns.db.compass = true; ns.db.compassHideIdle = true; ns.db.compassLocked = true; ns:NotifyChanged()
assert(not QuestRouteCompass:IsShown(), "idle compass hidden")
editCallbacks["EditMode.Enter"](); tick(0.05)
assert(ns.editMode and QuestRouteCompass:IsShown() and QuestRouteCompass.editBox.shown, "edit mode should show compass with box")
QuestRouteCompass.scripts.OnMouseDown(QuestRouteCompass)
QuestRouteCompass.scripts.OnMouseUp(QuestRouteCompass, "LeftButton")
assert(QuestRouteOptions:IsShown(), "click in edit mode opens settings")
QuestRouteCompass.scripts.OnDragStart(QuestRouteCompass); assert(QuestRouteCompass.dragging, "drag allowed in edit mode even if locked")
QuestRouteCompass.scripts.OnDragStop(QuestRouteCompass)
editCallbacks["EditMode.Exit"](); tick(0.05)
assert(not ns.editMode and not QuestRouteOptions:IsShown() and not QuestRouteCompass:IsShown(), "exit edit mode")
print("edit mode ok")
-- ===== roads, boats, cross-continent =====
_G.IsSwimming = function() return false end
_G.UnitOnTaxi = function() return false end
ghost = false
local kalimdor = { [1438]=1, [1439]=1, [1445]=1, [1413]=1, [1411]=1, [1444]=1, [1414]=1 }
function HBD:GetWorldCoordinatesFromZone(x, y, zone) return 0 - 4000 * x, 0 - 2600 * y, kalimdor[zone] and 1 or 0 end
function HBD:GetZoneCoordinatesFromWorldInstance(x, y, inst, zone, oob) local zi = kalimdor[zone] and 1 or 0; if inst ~= zi then return nil end return (0 - x) / 4000, (0 - y) / 2600 end
ns.Route:Replan()
-- rebuild static data with the new fake
fire("PLAYER_LOGIN_ROUTE_ONLY")
QuestRouteDB.roads = {}; QuestRouteDB.transports = {}
ns.db.useFlights = false; ns.db.assumeAllFlights = false

-- 1) walk an L-shaped road: east 600 yd, then south 600 yd
playerI = 0
local sx, sy = -1000, -1000
playerX, playerY = sx, sy
unitSpeed = 7
for i = 1, 60 do playerX = sx - i * 10; tick(0.5) end      -- world x decreases going east
for i = 1, 60 do playerY = sy - i * 10; tick(0.5) end
local nodes = ns.Learn:RoadStats()
print("road nodes learned", nodes)
assert(nodes > 40, "should learn road nodes")

-- target at the end of the L; go back to the start and plan
modules.ZoneDB.GetUiMapIdByAreaId = function() return 1426 end
local tx, ty = sx - 600, sy - 600
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { (0 - tx) / 4000 * 100, (0 - ty) / 2600 * 100 }, 1, "Road End" end
playerX, playerY = sx, sy; unitSpeed = 0
ns.db.offroadPenalty = 1.6
ns:SetQuest(1275)
ns:ComputeTarget(); ns.Route:Replan(); for i = 1, 6 do tick(0.5) end
if not ns.route then
  print("DEBUG target", ns.target and ns.target.wx, ns.target and ns.target.wy, ns.target and ns.target.instance, "player", playerX, playerY, playerI)
  print("DEBUG db", ns.db.useRoads, ns.db.offroadPenalty, ns.db.useTransports, ns.db.useFlights)
  local r = QuestRouteDB.roads[0]; print("DEBUG roads inst0", r and #r.x, r and r.x[1], r and r.y[1], r and #r.adj[1])
  local plan = ns.Route:Plan(playerX, playerY, playerI, ns.target); print("DEBUG plan", plan)
  local n = 0; ns.Learn:ForNear(0, playerX, playerY, 250, function() n = n + 1 end); print("DEBUG near start", n)
end
assert(ns.route, "expected a road route")
local roadStops = 0
for _, st in ipairs(ns.route.stops) do if st.road then roadStops = roadStops + 1 end end
print("route stops", #ns.route.stops, "road stops", roadStops)
assert(roadStops > 20, "route should follow the road")
local polys = ns:RoutePolylines(); print("polylines", #polys, "points in first", #polys[1].pts)
-- straight line is 849 yd, road is 1200 yd (1.41x): with penalty 1.0 it should go straight
ns.db.offroadPenalty = 1.0; ns.Route:Replan(); for i = 1, 4 do tick(0.5) end
print("penalty 1.0 ->", ns.route and "road" or "straight")
assert(ns.route == nil, "with no penalty it should go straight")
ns.db.offroadPenalty = 1.6

-- 2) ride a boat: stand still while being carried 400 yd, then walk off
playerX, playerY = -3000, -3000; unitSpeed = 0; tick(0.5)
for i = 1, 40 do playerX = playerX - 10; tick(0.5) end
unitSpeed = 7; playerX = playerX - 3; tick(0.5)
print("transports learned", #QuestRouteDB.transports)
assert(#QuestRouteDB.transports == 1, "should learn the boat ride")

-- 3) cross-continent: target in Theramore (Kalimdor), player in Wetlands near Menethil
QuestRouteDB.transports = {}
modules.ZoneDB.GetUiMapIdByAreaId = function() return 1445 end
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { 66, 50 }, 1, "Theramore Target" end
playerX, playerY = HBD:GetWorldCoordinatesFromZone(0.10, 0.55, 1437); playerI = 0; unitSpeed = 0
ns:ComputeTarget(); ns.Route:Replan(); for i = 1, 6 do tick(0.5) end
assert(ns.target.instance == 1, "target on Kalimdor")
assert(ns.route, "expected a boat route")
for i, st in ipairs(ns.route.stops) do if not st.road then print("stop", i, st.kind, st.name, st.inst) end end
print("waypoint text:", ns.waypoint.text)
assert(ns.waypoint.text and ns.waypoint.text:match("boat dock"), "should send us to the boat dock")
for i = 1, 6 do tick(0.1) end
print("cross continent ok")
-- no flicker: the boat route must stay up while the target is rechecked and re-planned
local gaps = 0
for i = 1, 160 do tick(0.05); if not ns.route then gaps = gaps + 1 end end
print("route missing in", gaps, "of 160 frames")
assert(gaps == 0, "route flickers")
print("no flicker ok")
-- ===== quests Questie doesn't know =====
modules.DistanceUtils.GetNearestSpawnForQuest = function() return nil end
modules.QuestieMap.GetFramesForQuest = function() return {} end
_G.C_Map.GetMapChildrenInfo = function(root, t, all)
  if root == 1415 then return { { mapID = 1424, mapType = 3, name = "Hillsbrad Foothills" }, { mapID = 1437, mapType = 3, name = "Wetlands" } } end
  return {}
end
_G.C_QuestLog.GetInfo = function(i) if i == 2 then return { isHeader = true, title = "Hillsbrad Foothills" } end return { isHeader = false, title = "Hillsbrad's Hoard" } end
_G.C_QuestLog.GetLogIndexForQuestID = function(id) return 3 end
ns.custom = nil; ns:SetQuest(nil); ns:SetQuest(98059); ns:ComputeTarget()
assert(ns.target and ns.target.approx and ns.target.mapId == 1424, "zone fallback: " .. tostring(ns.target and ns.target.source))
print("zone fallback ok:", ns.target.name)
SlashCmdList.QUESTROUTE("debug")
-- Ctrl + right-click on the map
_G.IsControlKeyDown = function() return true end
WorldMapFrame.GetNormalizedCursorPosition = function() return 0.3, 0.4 end
WorldMapFrame.ScrollContainer.scripts.OnMouseDown(WorldMapFrame.ScrollContainer, "RightButton")
assert(ns.target and ns.target.custom, "custom target")
print("map click ok:", ns.target.name)
WorldMapFrame.ScrollContainer.scripts.OnMouseDown(WorldMapFrame.ScrollContainer, "RightButton")
assert(not ns.custom, "second click removes marker")
print("marker removed ok")
-- dungeon quests route to the entrance
_G.IsControlKeyDown = function() return false end
local header = "Excavation Site: Wetlands"
_G.C_QuestLog.GetInfo = function(i) if i == 2 then return { isHeader = true, title = header } end return { isHeader = false, title = "Highland Hides" } end
ns:SetQuest(nil); ns:SetQuest(98815); ns:ComputeTarget()
assert(ns.target and ns.target.source == "Dungeon entrance", "dungeon: " .. tostring(ns.target and ns.target.source))
print("dungeon ok:", ns.target.name)
header = "The Deadmines"; ns:ComputeTarget()
assert(ns.target.name == "Deadmines (entrance)", "alias: " .. tostring(ns.target.name))
print("dungeon alias ok:", ns.target.name)
-- one-time reset of flight paths learned wrongly by v0.6.4
QuestRouteCharDB.knownTaxi = { ["Booty Bay, Stranglethorn"] = true }; QuestRouteCharDB.taxiReset065 = nil
fire("PLAYER_LOGIN")
assert(next(QuestRouteCharDB.knownTaxi) == nil and QuestRouteCharDB.taxiReset065, "flight reset")
QuestRouteCharDB.knownTaxi = { ["Lakeshire, Redridge"] = true }; fire("PLAYER_LOGIN")
assert(QuestRouteCharDB.knownTaxi["Lakeshire, Redridge"], "reset must happen only once")
print("flight reset ok")
_G.C_TaxiMap.GetTaxiNodesForMap = function() return { { nodeID = 4, name = "Sentinel Hill, Westfall", atlasName = "TaxiNode_Alliance", isUndiscovered = false, faction = 2 } } end
SlashCmdList.QUESTROUTE("fpinfo")
print("fpinfo ok")
-- waypoint button: click it, click the map, waypoint set; right-click removes
local wp = ns.waypointUI
WorldMapFrame.GetNormalizedCursorPosition = function() return 0.42, 0.61 end
wp.button.scripts.OnClick(wp.button, "LeftButton")
assert(wp.catcher:IsShown(), "placing mode")
wp.catcher.scripts.OnClick(wp.catcher, "LeftButton")
assert(not wp.catcher:IsShown() and ns.custom and ns.custom.x == 0.42, "waypoint placed")
assert(ns.target and ns.target.custom, "routes to the waypoint")
wp.button.scripts.OnClick(wp.button, "LeftButton"); wp.catcher.scripts.OnClick(wp.catcher, "RightButton")
assert(not wp.catcher:IsShown() and ns.custom.x == 0.42, "right-click cancels placing")
wp.button.scripts.OnClick(wp.button, "RightButton")
assert(ns.custom == nil, "right-click on the button removes it")
print("waypoint button ok")
-- coordinate box
local box = wp.box
local txt = ""
function box:GetText() return txt end
function box:SetText(t) txt = t end
txt = "45 63"; box.scripts.OnEnterPressed(box)
assert(ns.custom and ns.custom.mapId == 1426 and math.abs(ns.custom.x - 0.45) < 1e-9, "plain coords on shown map")
txt = "wetl 12.5, 60"; box.scripts.OnEnterPressed(box)
assert(ns.custom.mapId == 1437 and ns.custom.x == 0.125 and ns.custom.y == 0.60, "partial zone name: " .. tostring(ns.custom.mapId))
local before = ns.custom
txt = "narnia 10 10"; box.scripts.OnEnterPressed(box)
assert(ns.custom == before, "unknown zone must not change the waypoint")
txt = "200 5"; box.scripts.OnEnterPressed(box)
assert(ns.custom == before, "out of range must not change the waypoint")
SlashCmdList.QUESTROUTE("way hillsbrad 30 40")
assert(ns.custom.mapId == 1424 and ns.custom.x == 0.30, "/qroute way")
if SlashCmdList.QUESTROUTEWAY then SlashCmdList.QUESTROUTEWAY("Wetlands 50 50"); assert(ns.custom.mapId == 1437, "/way") end
print("coordinate box ok:", ns.custom.name)
-- walking then stopping must NOT count as being carried
unitSpeed = 7; for i = 1, 5 do playerX = playerX - 3.5; tick(0.5) end
unitSpeed = 0; playerX = playerX - 2.5; tick(0.5)   -- stopped mid-interval
tick(0.5); tick(0.5)
assert(not ns.carried, "stopping after walking must not look like a boat ride")
print("stop-after-walk ok")
-- deselecting / untracking clears the route
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { 40, 40 }, 1, "Some Mob" end
modules.ZoneDB.GetUiMapIdByAreaId = function() return 1426 end
ns.custom = nil
selected = 0; for i=1,3 do tick(0.1) end
selected = 1275; for i=1,10 do tick(0.1) end
assert(ns.questId == 1275 and ns.target, "quest selected")
selected = 0; for i=1,5 do tick(0.1) end
assert(ns.questId == nil and ns.target == nil, "deselect should clear")
assert(not QuestRouteCompass:IsShown() or not ns.db.compassHideIdle, "compass hidden when idle")
print("deselect ok")
local watched = true
_G.C_QuestLog.GetQuestWatchType = function() return watched and 0 or nil end
selected = 1275; for i=1,5 do tick(0.1) end
assert(ns.questId == 1275)
watched = false; for i=1,5 do tick(0.1) end
assert(ns.questId == nil, "untrack should clear")
print("untrack ok")
-- monsters in two places: Questie's straight-line nearest is far from the game's own quest marker
watched = true
modules.ZoneDB.GetUiMapIdByAreaId = function() return 1426 end
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { 90, 90 }, 1, "Far Basilisk" end
modules.QuestieMap.GetFramesForQuest = function() return {
  a = { x = 90, y = 90, UiMapID = 1426, data = { Name = "Far Basilisk" } },
  b = { x = 21, y = 22, UiMapID = 1426, data = { Name = "Basilisk by the marker" } } } end
local oldOnMap = _G.C_QuestLog.GetQuestsOnMap
_G.C_QuestLog.GetQuestsOnMap = function(m) if not kalimdor[m] then return { { questID = 1275, x = 0.20, y = 0.20 } } end return {} end
playerX, playerY, playerI = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, 1426)
selected = 0; for i=1,3 do tick(0.1) end
tick(11)
selected = 1275; for i=1,10 do tick(0.1) end
SlashCmdList.QUESTROUTE("debug")
assert(ns.target and ns.target.name == "Basilisk by the marker", "game area pick failed: " .. tostring(ns.target and ns.target.name) .. " via " .. tostring(ns.target and ns.target.source))
print("game area ok:", ns.target.name, ns.target.source)
-- standing among the far ones: keep them
playerX, playerY = HBD:GetWorldCoordinatesFromZone(0.9, 0.9, 1426)
selected = 0; for i=1,3 do tick(0.1) end
selected = 1275; for i=1,10 do tick(0.1) end
assert(ns.target and ns.target.name == "Far Basilisk", "should keep the spawn you're at: " .. tostring(ns.target and ns.target.name))
print("near you ok")
_G.C_QuestLog.GetQuestsOnMap = oldOnMap
-- a finished route is announced (the world map redraws without reopening), and it takes few frames
_G.debugprofilestop = function() return os.clock() * 1000 end
local notified = 0
ns:OnChange(function() notified = notified + 1 end)
modules.DistanceUtils.GetNearestSpawnForQuest = function() return { 52, 72 }, 1, "Responsive Target" end
_G.C_QuestLog.GetQuestsOnMap = function() return {} end
ns.custom = nil; ns.db.useFlights = true; ns.db.offroadPenalty = 6; ns.db.assumeAllFlights = true
playerX, playerY, playerI = HBD:GetWorldCoordinatesFromZone(0.4874, 0.5237, 1415)
modules.ZoneDB.GetUiMapIdByAreaId = function() return 1415 end
modules.QuestieMap.GetFramesForQuest = function() return {} end
selected = 0; for i=1,3 do tick(0.1) end
tick(11)
ns.route = nil
selected = 1275
local frames = 0
local firstTarget
for i = 1, 200 do tick(0.016); frames = i
  if not firstTarget and ns.target and ns.target.name == "Responsive Target" then firstTarget = i end
  if ns.route and firstTarget then break end end
print("target set at frame", firstTarget, "route", ns.route and #ns.route.stops, "questId", ns.questId, "target", ns.target and ns.target.name)
local before = notified
assert(ns.route, "route never arrived")
print(("route ready after %d frames; map told %d time(s)"):format(frames, notified))
assert(notified > 0, "the map was never told about the new route")
-- in a cave (micro map) or a dungeon the route is paused; outside it's back
local oldInfo, oldBest = _G.C_Map.GetMapInfo, _G.C_Map.GetBestMapForUnit
_G.C_Map.GetBestMapForUnit = function() return 9999 end
_G.C_Map.GetMapInfo = function(id) if id == 9999 then return { name = "Cave", mapType = 5 } end return oldInfo(id) end
tick(1)
assert(ns.target and not ns:RouteActive(), "route should pause in a cave")
_G.IsInInstance = function() return true, "party" end; _G.C_Map.GetMapInfo = oldInfo; _G.C_Map.GetBestMapForUnit = oldBest
tick(1); assert(not ns:RouteActive(), "route should pause in a dungeon")
_G.IsInInstance = function() return false, "none" end
tick(1); assert(ns:RouteActive(), "route should come back outside")
print("pause in caves and dungeons ok")
assert(ns.HBD == HBD and ns.HBDPins == Pins, "libs not found via Questie")
print("ALL OK")
