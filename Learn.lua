-- QuestRoute: learns the world as you play.
--  * Roads: the paths you walk or ride become a road network (nodes ~20 yd apart).
--  * Transports: when you are carried (you move but aren't walking yourself, and
--    aren't on a flight path) for a long way, that's a boat/zeppelin/tram. The
--    boarding and landing spots are saved as a transport link.
-- Everything is stored account-wide in QuestRouteDB.roads / QuestRouteDB.transports.
local _, ns = ...
local CreateFrame = ns.CreateFrame -- (protected scripts: see Core.lua)
local L = {}
ns.Learn = L

local SPACING = 20        -- yards between road nodes
local MERGE = 12          -- snap to an existing node within this distance
local MAX_STEP = 70       -- a bigger jump between samples is a teleport, not a road
local CELL = 60           -- spatial grid cell size (yards)
local CARRIED_MIN = 150   -- yards carried before it counts as a transport
local sqrt, floor = math.sqrt, math.floor

---------------------------------------------------------------------------
-- Road graph. Saved format per instance: { x = {}, y = {}, adj = { [i] = {j, k, ...} } }
-- Runtime adds a spatial grid per instance.
---------------------------------------------------------------------------
local grids = {}

local function roadsFor(inst)
    local all = QuestRouteDB.roads
    local r = all[inst]
    if not r then
        r = { x = {}, y = {}, adj = {} }
        all[inst] = r
    end
    return r
end

local function cellKey(x, y)
    return floor(x / CELL) * 100000 + floor(y / CELL)
end

local function gridFor(inst)
    local g = grids[inst]
    if g then return g end
    g = {}
    local r = QuestRouteDB.roads[inst]
    if r then
        for i = 1, #r.x do
            local k = cellKey(r.x[i], r.y[i])
            local c = g[k]
            if not c then c = {}; g[k] = c end
            c[#c + 1] = i
        end
    end
    grids[inst] = g
    return g
end

--- Calls fn(i, distance) for road nodes within radius of x,y.
function L:ForNear(inst, x, y, radius, fn)
    local r = QuestRouteDB.roads[inst]
    if not r then return end
    local g = gridFor(inst)
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local span = math.ceil(radius / CELL)
    for gx = cx - span, cx + span do
        for gy = cy - span, cy + span do
            local c = g[gx * 100000 + gy]
            if c then
                for _, i in ipairs(c) do
                    local dx, dy = r.x[i] - x, r.y[i] - y
                    local d = sqrt(dx * dx + dy * dy)
                    if d <= radius then fn(i, d) end
                end
            end
        end
    end
end

local function nearestNode(inst, x, y, radius)
    local best, bestD
    L:ForNear(inst, x, y, radius, function(i, d)
        if not bestD or d < bestD then best, bestD = i, d end
    end)
    return best, bestD
end

local function addNode(inst, x, y)
    local r = roadsFor(inst)
    local i = #r.x + 1
    r.x[i], r.y[i], r.adj[i] = x, y, {}
    local g = gridFor(inst)
    local k = cellKey(x, y)
    local c = g[k]
    if not c then c = {}; g[k] = c end
    c[#c + 1] = i
    return i
end

local function link(inst, a, b)
    if a == b then return end
    local adj = roadsFor(inst).adj
    for _, j in ipairs(adj[a]) do if j == b then return end end
    table.insert(adj[a], b)
    table.insert(adj[b], a)
end

function L:RoadStats()
    local nodes, insts = 0, 0
    for _, r in pairs(QuestRouteDB.roads or {}) do
        nodes = nodes + #r.x
        insts = insts + 1
    end
    return nodes, insts
end

function L:ResetRoads()
    QuestRouteDB.roads = {}
    grids = {}
end

---------------------------------------------------------------------------
-- Transports
---------------------------------------------------------------------------
local function addTransport(a, b, seconds)
    local list = QuestRouteDB.transports
    for _, t in ipairs(list) do
        local function near(p, q)
            return p.inst == q.inst and (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 < 80 * 80
        end
        if (near(t.a, a) and near(t.b, b)) or (near(t.a, b) and near(t.b, a)) then
            t.count = (t.count or 1) + 1
            return
        end
    end
    table.insert(list, { a = a, b = b, time = seconds + 60, count = 1, kind = (a.inst ~= b.inst) and "boat" or "ferry" })
    ns:Print("learned a new boat/zeppelin route. Routes can now use it.")
    ns:NotifyChanged()
end

---------------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------------
local lastNode, lastNodeInst          -- road recording
local prevX, prevY, prevInst          -- previous sample
local prevSpeed = 0
local carry                           -- { start = {x,y,inst}, dist, t0 } while being carried

local function sample()
    if not ns.HBD or not QuestRouteDB or not QuestRouteDB.roads then return end
    local x, y, inst = ns.HBD:GetPlayerWorldPosition()
    if not x then
        prevX = nil
        return
    end
    local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local ghost = UnitIsGhost and UnitIsGhost("player")
    local swimming = IsSwimming and IsSwimming()

    local moved = 0
    if prevX and prevInst == inst then
        moved = sqrt((x - prevX) ^ 2 + (y - prevY) ^ 2)
    end

    -- being carried? (position changes, but we weren't moving ourselves at
    -- either end of the interval -- right after you stop walking, the last
    -- interval still contains your own steps)
    local carried = not onTaxi and speed == 0 and prevSpeed == 0 and moved > 2 and moved < MAX_STEP
    -- only treat it as a ride once we've been carried a real distance
    ns.carried = (carry ~= nil and speed == 0 and (carry.dist + (carried and moved or 0)) >= 40) or false
    if carried then
        if not carry then
            carry = { start = { x = prevX, y = prevY, inst = prevInst }, dist = 0, t0 = GetTime() }
        end
        carry.dist = carry.dist + moved
    elseif carry and speed > 0 then
        -- walked off: was it a long ride?
        if carry.dist >= CARRIED_MIN then
            addTransport(carry.start, { x = x, y = y, inst = inst }, GetTime() - carry.t0)
        end
        carry = nil
    end
    if carry and prevInst and inst ~= prevInst then
        if carry.dist < 100 then
            carry = nil -- a short hop then a loading screen: hearthstone or portal, not a boat
        else
            carry.crossed = true -- loading screen while on a boat: the ride continues
        end
    end

    -- record roads: on foot or mounted, on land
    if ns.db.learnRoads and not onTaxi and not ghost and not swimming and not ns.carried and speed > 0 then
        if lastNode and (lastNodeInst ~= inst) then lastNode = nil end
        local r = QuestRouteDB.roads[inst]
        local lx, ly
        if lastNode then lx, ly = r.x[lastNode], r.y[lastNode] end
        local far = not lastNode or ((x - lx) ^ 2 + (y - ly) ^ 2) >= SPACING * SPACING
        if far then
            local node = nearestNode(inst, x, y, MERGE) or addNode(inst, x, y)
            if lastNode then
                r = QuestRouteDB.roads[inst]
                local d = sqrt((r.x[node] - lx) ^ 2 + (r.y[node] - ly) ^ 2)
                if d <= MAX_STEP then link(inst, lastNode, node) end
            end
            lastNode, lastNodeInst = node, inst
        end
    elseif moved > MAX_STEP or onTaxi or ghost then
        lastNode = nil
    end

    prevX, prevY, prevInst, prevSpeed = x, y, inst, speed
end

local f = CreateFrame("Frame")
local acc = 0
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        QuestRouteDB.roads = QuestRouteDB.roads or {}
        QuestRouteDB.transports = QuestRouteDB.transports or {}
    end
    lastNode = nil -- after a loading screen, don't connect across it
end)
f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    if ns.db then sample() end
end)
