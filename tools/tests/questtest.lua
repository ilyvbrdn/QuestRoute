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


local LEGS = dofile("questlegs.lua")
ns.db.useFlights = false; ns.db.useTransports = true; ns.db.avoidDanger = true
local only = arg and arg[2]
local tot, fail, wet, straight, roadLen, allLen = 0, 0, 0, 0, 0, 0
local band = {}
local probs = {}
for n, L in ipairs(LEGS) do
  local q, kind, fac, lvl, m, x0, y0, x1, y1, title = unpack(L)
  if not only or (only == "A" and fac == 2) or (only == "H" and fac == 1) then
  faction = fac == 2 and "Alliance" or "Horde"
  _G.UnitLevel = function() return lvl end
  local r = ns.Route:Plan(x0, y0, m, { wx = x1, wy = y1, instance = m, title = title })
  tot = tot + 1
  local b = math.min(5, math.floor((lvl - 1) / 10)); band[b] = band[b] or { n = 0, ok = 0, road = 0, len = 0 }
  local B = band[b]; B.n = B.n + 1
  local bad
  local straightD = math.sqrt((x1-x0)^2 + (y1-y0)^2)
  if not r then
    if straightD > 260 or segCrossesWater(m, x0, y0, x1, y1) then bad = "no route"; fail = fail + 1 end
  else
    local px, py, pi, len, onr = x0, y0, m, 0, 0
    for _, s in ipairs(r.stops) do
      if ns.Route.TRAVEL[s.kind] or s.inst ~= pi then px, py, pi = s.wx, s.wy, s.inst else
      local d = math.sqrt((s.wx-px)^2 + (s.wy-py)^2); len = len + d
      if s.onRoad then onr = onr + d end
      if not bad and d > 260 and not s.nav and not s.road then bad = ("straight %d yd"):format(d); straight = straight + 1 end
      if not bad and not (s.special == "dock") and segCrossesWater(pi, px, py, s.wx, s.wy) then bad = "over water"; wet = wet + 1 end
      px, py = s.wx, s.wy
      end
    end
    roadLen = roadLen + onr; allLen = allLen + len; B.road = B.road + onr; B.len = B.len + len
  end
  if not bad then B.ok = B.ok + 1 else probs[#probs + 1] = ("%s L%d %s #%d %s (%s): %s"):format(faction, lvl, kind, q, title, m == 0 and "EK" or "Kal", bad) end
  end
end
for b = 0, 5 do local B = band[b]; if B then print(("levels %2d-%2d: %4d legs, %5.1f%% ok, %4.1f%% of walking on roads"):format(b*10+1, b*10+10, B.n, 100*B.ok/B.n, B.len > 0 and 100*B.road/B.len or 0)) end end
print(("ALL: %d legs, ok %.1f%%  (no route %d, over water %d, long straight %d), on roads %.1f%%"):format(tot, 100*(tot-fail-wet-straight)/tot, fail, wet, straight, 100*roadLen/allLen))
local f = io.open("problems_quests.txt", "w"); for _, p in ipairs(probs) do f:write(p, "\n") end; f:close()
]==]
assert(loadstring(head))(...)
