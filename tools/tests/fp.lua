-- Every route test: all flight point pairs on each continent + cross-continent trips.
local src = io.open("harness.lua"):read("*a")
local cut = src:find("fire%(\"ADDON_LOADED\", \"QuestRoute\"%)")
local head = src:sub(1, cut - 1) .. [==[
local CAL = {
  [1415] = { fx0 = -2.8402092891789313e-05, fx1 = 0.45456991573281436, fy0 = -4.261220244903351e-05, fy1 = 0.31817552105114527, inst = 0 },
  [1414] = { fx0 = -2.717400445200379e-05, fx1 = 0.46376835583779386, fy0 = -4.076109746408814e-05, fy1 = 0.52173788731071, inst = 1 },
}
function HBD:GetWorldCoordinatesFromZone(x, y, zone)
  local c = CAL[zone]; if not c then return nil end
  return (y - c.fy1) / c.fy0, (x - c.fx1) / c.fx0, c.inst
end
fire("ADDON_LOADED", "QuestRoute"); fire("PLAYER_LOGIN")
_G.UnitLevel = function() return 40 end
local faction = "Alliance"
_G.UnitFactionGroup = function() return faction end
ns.db.assumeAllFlights = false
ns.Nav:Ensure()
local WATER = dofile("water.lua")
-- grid for water lookups
local wgrid = {}
for inst, list in pairs(WATER) do
  wgrid[inst] = {}
  for _, p in ipairs(list) do
    local k = math.floor(p[1] / 100) .. ":" .. math.floor(p[2] / 100)
    wgrid[inst][k] = wgrid[inst][k] or {}; table.insert(wgrid[inst][k], p)
  end
end
local function nearWater(inst, x, y, r)
  local g = wgrid[inst]; local cx, cy = math.floor(x / 100), math.floor(y / 100)
  for i = cx - 1, cx + 1 do for j = cy - 1, cy + 1 do
    for _, p in ipairs(g[i .. ":" .. j] or {}) do
      if (p[1] - x)^2 + (p[2] - y)^2 < r * r then return true end
    end
  end end
  return false
end
local function segCrossesWater(inst, x1, y1, x2, y2)
  local L = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
  if L < 60 then return false end
  -- a real water crossing has water under a good part of the line, not just beside a bank
  local steps = math.floor(L / 10)
  local wet, n = 0, 0
  for k = 2, steps - 1 do -- interior only
    local t = k / steps
    n = n + 1
    if nearWater(inst, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 12) then wet = wet + 1 end
  end
  return n > 0 and wet / n >= 0.3
end
local function world(n) return HBD:GetWorldCoordinatesFromZone(n.x, n.y, n.cont) end
local FP = {}
for _, n in ipairs(ns.FlightData) do
  local x, y, i = world(n)
  if x and not n.name:find("Alterac Valley") then table.insert(FP, { n = n, x = x, y = y, inst = i }) end
end

local stats = { total = 0, ok = 0, noroute = 0, water = 0, longleg = 0, detour = 0 }
local problems = {}
local function check(a, b, label, needTravel)
  stats.total = stats.total + 1
  local t = { wx = b.x, wy = b.y, instance = b.inst, title = b.n.name }
  local r = ns.Route:Plan(a.x, a.y, a.inst, t)
  local bad
  if not r then
    -- no route = the addon draws a straight line. Fine only when short and dry.
    local d = math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    if a.inst == b.inst and d <= 260 and not segCrossesWater(a.inst, a.x, a.y, b.x, b.y) then stats.ok = stats.ok + 1 return end
    stats.noroute = stats.noroute + 1; bad = ("no route (straight line of %d yd)"):format(d)
  else
    local px, py, pi = a.x, a.y, a.inst
    local len, travel = 0, false
    local prevDock = false
    for _, s in ipairs(r.stops) do
      local pier = prevDock or s.special == "dock"  -- walking onto/off a pier is over water by design
      prevDock = (s.special == "dock")
      if ns.Route.TRAVEL[s.kind] then travel = true
      elseif s.inst == pi then
        local L = math.sqrt((s.wx - px)^2 + (s.wy - py)^2)
        len = len + L
        if not bad and L > 260 and not s.nav and not s.road then bad = ("straight walk of %d yd"):format(L); stats.longleg = stats.longleg + 1 end
        if not bad and not pier and segCrossesWater(pi, px, py, s.wx, s.wy) then bad = ("walks over water near %d,%d"):format(s.wx, s.wy); stats.water = stats.water + 1 end
      end
      px, py, pi = s.wx, s.wy, s.inst
    end
    if not bad and needTravel and not travel then bad = "should use a boat/zeppelin"; stats.noroute = stats.noroute + 1 end
    local straight = math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    if not bad and not travel and a.inst == b.inst and straight > 300 and len / straight > 4.5 then
      bad = ("detour x%.1f (%d vs %d yd)"):format(len / straight, len, straight); stats.detour = stats.detour + 1
    end
  end
  if bad then table.insert(problems, label .. ": " .. a.n.name .. " -> " .. b.n.name .. ": " .. bad)
  else stats.ok = stats.ok + 1 end
end

ns.db.useFlights = true; ns.db.assumeAllFlights = false
_G.UnitLevel = function() return 25 end
QuestRouteCharDB.knownTaxi = { ["Lakeshire, Redridge"] = true, ["Stormwind, Elwynn"] = true, ["Ironforge, Dun Morogh"] = true, ["Sentinel Hill, Westfall"] = true, ["Thelsamar, Loch Modan"] = true, ["Menethil Harbor, Wetlands"] = true }
print("known flights:", ns.Route:KnownCount())
local function find(n) for _, f in ipairs(FP) do if f.n.name:find(n, 1, true) then return f end end end
local a = find("Lakeshire")
-- quest in western Dun Morogh (like the screenshot)
local qx, qy, qi = HBD:GetWorldCoordinatesFromZone(0.462, 0.505, 1415)
local r = ns.Route:Plan(a.x + 3, a.y + 3, a.inst, { wx = qx, wy = qy, instance = qi, title = "quest" })
for i, s in ipairs(r and r.stops or {}) do if not s.road then print(i, s.kind, s.name, s.special) end end
print("total", r and r.total)
local L = 0
print("flight Lakeshire->Ironforge time", ns.Route.FlightTime("Lakeshire, Redridge", "Ironforge, Dun Morogh", 4700))
]==]
assert(loadstring(head))(...)
