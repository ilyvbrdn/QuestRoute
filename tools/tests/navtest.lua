-- Realistic test: real network data, continent coordinate math matching the game.
local src = io.open("harness.lua"):read("*a")
local cut = src:find("fire%(\"ADDON_LOADED\", \"QuestRoute\"%)")
local head = src:sub(1, cut - 1) .. [==[
local CAL = {
  [1415] = { fx0 = -2.8402092891789313e-05, fx1 = 0.45456991573281436, fy0 = -4.261220244903351e-05, fy1 = 0.31817552105114527, inst = 0 },
  [1414] = { fx0 = -2.717400445200379e-05, fx1 = 0.46376835583779386, fy0 = -4.076109746408814e-05, fy1 = 0.52173788731071, inst = 1 },
}
-- world (HBD) x = server X, y = server Y.  cont_x = fx0*Y + fx1, cont_y = fy0*X + fy1
function HBD:GetWorldCoordinatesFromZone(x, y, zone)
  local c = CAL[zone]; if not c then return nil end
  return (y - c.fy1) / c.fy0, (x - c.fx1) / c.fx0, c.inst
end
function HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, inst, zone)
  local c = CAL[zone]; if not c or c.inst ~= inst then return nil end
  return c.fx0 * wy + c.fx1, c.fy0 * wx + c.fy1
end
fire("ADDON_LOADED", "QuestRoute"); fire("PLAYER_LOGIN")
_G.UnitLevel = function() return 40 end
_G.UnitFactionGroup = function() return "Alliance" end
ns.db.useFlights = false
local function fp(name) for _, n in ipairs(ns.FlightData) do if n.name:find(name, 1, true) then return n end end end
local function plan(fromName, toName, label)
  local a, b = fp(fromName), fp(toName)
  local ax, ay, ai = HBD:GetWorldCoordinatesFromZone(a.x, a.y, a.cont)
  local bx, by, bi = HBD:GetWorldCoordinatesFromZone(b.x, b.y, b.cont)
  local t = { wx = bx, wy = by, instance = bi, title = toName }
  local t0 = os.clock()
  local r = ns.Route:Plan(ax, ay, ai, t)
  local ms = (os.clock() - t0) * 1000
  local len, px, py = 0, ax, ay
  local nearRefuge = 1e9
  local rp = fp("Refuge Pointe"); local rx, ry = HBD:GetWorldCoordinatesFromZone(rp.x, rp.y, rp.cont)
  for _, s in ipairs(r and r.stops or {}) do
    if s.inst == ai then len = len + math.sqrt((s.wx - px)^2 + (s.wy - py)^2); px, py = s.wx, s.wy end
    nearRefuge = math.min(nearRefuge, math.sqrt((s.wx - rx)^2 + (s.wy - ry)^2))
  end
  print(("%s: %s stops, %.0f yd walked (straight %.0f), %.0f ms, closest to Refuge Pointe %.0f yd"):format(
    label, r and #r.stops or "NO ROUTE", len, math.sqrt((ax-bx)^2 + (ay-by)^2), ms, nearRefuge))
  return r
end
local t0 = os.clock(); ns.Nav:Ensure(); print(("unpack network: %.0f ms, %d points"):format((os.clock()-t0)*1000, ns.Nav:Stats()))
plan("Menethil", "Sepulcher", "Menethil -> Sepulcher")
plan("Lakeshire", "Sentinel Hill", "Lakeshire -> Sentinel Hill")
plan("Ironforge", "Menethil", "Ironforge -> Menethil")
plan("Ratchet", "Theramore", "Ratchet -> Theramore")
-- with flights known: Lakeshire -> Sentinel Hill should fly
ns.db.useFlights = true; ns.db.assumeAllFlights = true
local r = plan("Lakeshire", "Sentinel Hill", "with flights")
for _, s in ipairs(r.stops) do if not s.road then print("   ", s.kind, s.name) end end
-- cross continent: Ironforge -> Theramore (boat from Menethil)
local a = fp("Ironforge"); local b = fp("Theramore")
local ax, ay, ai = HBD:GetWorldCoordinatesFromZone(a.x, a.y, a.cont)
local bx, by, bi = HBD:GetWorldCoordinatesFromZone(b.x, b.y, b.cont)
ns.db.assumeAllFlights = false
local r2 = ns.Route:Plan(ax, ay, ai, { wx = bx, wy = by, instance = bi, title = "Theramore" })
print("Ironforge -> Theramore (no flights):")
for _, s in ipairs(r2 and r2.stops or {}) do if not s.road then print("   ", s.kind, s.name, s.inst) end end
]==]
assert(loadstring(head))(...)
