-- QuestRoute: route planner.
-- Finds the fastest trip to the target over one graph made of:
--   * learned roads (paths you have walked or ridden)
--   * cross-country walking (slower on purpose, so known roads are preferred)
--   * flight paths this character knows
--   * boats, zeppelins and the tram (built-in + learned)
-- Output: ns.route = { stops = { {wx, wy, inst, name, kind, road, special}, ... }, total = seconds }
-- Each stop's "kind" is how you travel TO it: "walk", "fly", "boat", "zeppelin", "tram", "ferry".
local _, ns = ...
local R = {}
ns.Route = R

-- Flight time estimate, fitted to real recorded flights: about 35.7 yards (straight
-- line) per second plus ~54 s for take-off, landing and the detours flight paths make.
-- Real recorded times (QuestRoute's own, or OpenMap's) are used whenever available.
local FLY_SPEED = 35.7
local FLY_DETOUR = 1.0
local FLY_OVERHEAD = 54
local BOARDING = 10       -- seconds: talking to the flight master
local AT_STOP = 25        -- yards: "you are at this stop"
local CONNECT = 250       -- yards: how far off a road we'll look for it
local MAX_CONNECT = 6     -- road nodes linked to each special point
-- each boat, zeppelin or flight you board costs a little extra (getting on and off, the odd missed
-- ship): between two equally fast routes, the one with fewer changes wins
local TRANSFER = 60
local LOOKAHEAD = 60      -- yards: the arrow aims this far down the road
local ROAD_ID = 1000000   -- road node id = instance * ROAD_ID + index
local sqrt, huge, floor = math.sqrt, math.huge, math.floor

local TRAVEL = { fly = true, boat = true, zeppelin = true, airship = true, tram = true, ferry = true, portal = true }
R.TRAVEL = TRAVEL

local flightNodes, transportSeeds

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- All recorded flight times (QuestRoute's own, plus OpenMap's if installed): legs[from][to] = seconds.
local function recordedLegs()
    local legs = {}
    local function add(src)
        if type(src) ~= "table" then return end
        for key, secs in pairs(src) do
            local a, b = tostring(key):match("^(.-)|(.+)$")
            secs = tonumber(secs)
            if a and b and secs then
                legs[a] = legs[a] or {}
                if not legs[a][b] or secs < legs[a][b] then legs[a][b] = secs end
            end
        end
    end
    add(OpenMapDB and OpenMapDB.worldmap and OpenMapDB.worldmap.flightTimes)
    add(QuestRouteDB and QuestRouteDB.flightTimes)
    return legs
end

-- Shortest chain of recorded legs from one flight point to another (multi-stop flights
-- take about as long as their legs added up). nil if the recorded legs don't connect them.
local function chainTime(legs, from, to)
    local best, done = { [from] = 0 }, {}
    while true do
        local u, bu
        for n, c in pairs(best) do
            if not done[n] and (not bu or c < bu) then u, bu = n, c end
        end
        if not u then return nil end
        if u == to then return bu end
        done[u] = true
        for v, secs in pairs(legs[u] or {}) do
            if not best[v] or bu + secs < best[v] then best[v] = bu + secs end
        end
        -- a recorded flight can be flown the other way in about the same time
        for a, row in pairs(legs) do
            if row[u] and (not best[a] or bu + row[u] < best[a]) then best[a] = bu + row[u] end
        end
    end
end

-- Real flight network (Data/FlightLegs.lua). Flights follow these legs, only through flight
-- points you have unlocked. Time fitted to recorded flights: ~33.5 yd/s plus ~10.5 s per leg.
local LEG_SPEED, LEG_STOP, LEG_BASE = 33.5, 10.5, 10.5
local legAdj
local function buildLegAdj()
    legAdj = {}
    for _, l in ipairs(ns.FlightLegs or {}) do
        local a, b, yards = l[1], l[2], l[3]
        legAdj[a] = legAdj[a] or {}
        legAdj[b] = legAdj[b] or {}
        legAdj[a][b], legAdj[b][a] = yards, yards
    end
end

-- Seconds from flight point `from` (node id) to every reachable flight point, through `allowed` ids.
local function networkTimes(from, allowed)
    if not legAdj then buildLegAdj() end
    if not legAdj[from] then return nil end
    local best, done = { [from] = 0 }, {}
    while true do
        local u, bu
        for n, c in pairs(best) do
            if not done[n] and (not bu or c < bu) then u, bu = n, c end
        end
        if not u then break end
        done[u] = true
        for v, yards in pairs(legAdj[u] or {}) do
            if allowed[v] then
                local c = bu + yards / LEG_SPEED + LEG_STOP
                if not best[v] or c < best[v] then best[v] = c end
            end
        end
    end
    for n, c in pairs(best) do best[n] = c + LEG_BASE - LEG_STOP end
    best[from] = nil
    return best
end
R.NetworkTimes = networkTimes

-- Seconds for a flight between two flight points (by name).
local legsCache, legsAt = nil, -100
local function recordedTime(from, to)
    if not legsCache or GetTime() - legsAt > 10 then legsCache, legsAt = recordedLegs(), GetTime() end
    local legs = legsCache
    if legs[from] and legs[from][to] then return legs[from][to] end
    if legs[to] and legs[to][from] then return legs[to][from] end
end

local function flightTime(from, to, dist)
    if not legsCache or GetTime() - legsAt > 10 then legsCache, legsAt = recordedLegs(), GetTime() end
    local legs = legsCache
    if legs[from] and legs[from][to] then return legs[from][to] end
    if legs[to] and legs[to][from] then return legs[to][from] end
    local chained = chainTime(legs, from, to)
    if chained then return chained end
    return dist * FLY_DETOUR / FLY_SPEED + FLY_OVERHEAD
end
R.FlightTime = flightTime

local function groundSpeed()
    local lvl = UnitLevel and UnitLevel("player") or 1
    return (lvl >= 40) and 11.2 or 7 -- running, or the level 40 mount
end

local function myFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and 2 or (f == "Horde" and 1 or -1)
end

local function d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

local function world(map, x, y)
    return ns.HBD:GetWorldCoordinatesFromZone(x, y, map)
end

local function buildStatic()
    flightNodes, transportSeeds = {}, {}
    if not ns.HBD then return end
    for _, n in ipairs(ns.FlightData or {}) do
        local wx, wy, inst = world(n.cont, n.x, n.y)
        if wx then
            table.insert(flightNodes, { id = n.id, name = n.name, fac = n.fac, wx = wx, wy = wy, inst = inst })
        end
    end
    local function dock(p)
        if p.inst then return p.wx, p.wy, p.inst end -- given directly in world coordinates
        return world(p.map, p.x, p.y)
    end
    for _, t in ipairs(ns.TransportData or {}) do
        local ax, ay, ai = dock(t.a)
        local bx, by, bi = dock(t.b)
        if ax and bx then
            table.insert(transportSeeds, {
                kind = t.kind, fac = t.fac, time = t.time, oneway = t.oneway,
                a = { x = ax, y = ay, inst = ai, name = t.a.name },
                b = { x = bx, y = by, inst = bi, name = t.b.name },
            })
        end
    end
end

function R:IsKnown(node)
    if ns.db.assumeAllFlights then return true end
    local k = QuestRouteCharDB and QuestRouteCharDB.knownTaxi
    return k and (k[node.id] or k[node.name]) and true or false
end

function R:KnownCount()
    if not flightNodes then buildStatic() end
    local n, fac = 0, myFaction()
    for _, node in ipairs(flightNodes) do
        if (node.fac == 0 or node.fac == fac) and self:IsKnown(node) then n = n + 1 end
    end
    return n
end

-- All transports we can use: learned ones first; a built-in route is dropped
-- when a learned one covers the same docks (the learned spots are exact).
local function transports()
    local fac = myFaction()
    local list = {}
    local learned = QuestRouteDB.transports or {}
    for _, t in ipairs(learned) do table.insert(list, t) end
    for _, s in ipairs(transportSeeds) do
        if s.fac == 0 or s.fac == fac then
            local covered = false
            for _, t in ipairs(learned) do
                local function near(p, q) return p.inst == q.inst and d2(p.x, p.y, q.x, q.y) < 400 end
                if (near(t.a, s.a) and near(t.b, s.b)) or (near(t.a, s.b) and near(t.b, s.a)) then covered = true break end
            end
            if not covered then table.insert(list, s) end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Binary heap for Dijkstra
---------------------------------------------------------------------------
local function heapPush(h, cost, id)
    local n = #h + 1
    h[n] = { cost, id }
    while n > 1 do
        local p = floor(n / 2)
        if h[p][1] <= h[n][1] then break end
        h[p], h[n] = h[n], h[p]
        n = p
    end
end

local function heapPop(h)
    local top = h[1]
    if not top then return end
    local last = h[#h]
    h[#h] = nil
    if #h > 0 then
        h[1] = last
        local n, size = 1, #h
        while true do
            local l, r, m = n * 2, n * 2 + 1, n
            if l <= size and h[l][1] < h[m][1] then m = l end
            if r <= size and h[r][1] < h[m][1] then m = r end
            if m == n then break end
            h[m], h[n] = h[n], h[m]
            n = m
        end
    end
    return top[1], top[2]
end

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------
-- Cost multipliers for links of the built-in network:
-- 0 open ground, 1 road (guard patrol route), 2 short gap, 3 long gap (rarely needed)
local NAV_FACTOR = { [0] = 1.25, [1] = 1.0, [2] = 1.6, [3] = 2.5 }
local NAV_BASE = 500000     -- network node id = instance * ROAD_ID + NAV_BASE + index
local NAV_CONNECT = 200     -- yards: how far a point (you, the target, a flight master) looks for the network
local DIRECT_MAX = 250      -- yards: longer straight walks only where the network has no data

function R:Plan(px, py, pinst, t, far)
    if t.corpse or not px then return nil end -- ghosts go straight (they walk on water)
    if pinst == t.instance and d2(px, py, t.wx, t.wy) < 120 then return nil end -- close by: straight
    if not flightNodes then buildStatic() end
    local db = ns.db
    local gs = groundSpeed()
    local off = db.offroadPenalty or 1.6
    local roads = QuestRouteDB.roads or {}
    local fac = myFaction()
    local useNav = db.useRoads and ns.Nav and ns.Nav:Ensure()
    local openFactor = 1 + (off - 1) * 1.0 -- open ground vs roads follows the "Prefer roads" slider
    NAV_FACTOR[0] = openFactor
    -- areas with monsters well above your level count as much slower, so routes go around them
    local dangerFrom = db.avoidDanger and ((UnitLevel and UnitLevel("player") or 1) + (db.dangerMargin or 3)) or nil
    local function myLevels(g) return (fac == 2 and g.lvlA) or (fac == 1 and g.lvlH) or g.lvl end
    local function danger(g, j)
        if not dangerFrom then return 1 end
        local L = myLevels(g)[j]
        if not L or L <= dangerFrom then return 1 end
        return math.min(10, 1 + 0.8 * (L - dangerFrom))
    end

    -- special points: 1 = start, 2 = goal, then flight points and docks
    local S = {
        { wx = px, wy = py, inst = pinst, name = "you", type = "start" },
        { wx = t.wx, wy = t.wy, inst = t.instance, name = t.name or t.title, type = "goal" },
    }
    if db.useFlights then
        for _, n in ipairs(flightNodes) do
            if n.fac == 0 or n.fac == fac then
                if self:IsKnown(n) then
                    table.insert(S, { wx = n.wx, wy = n.wy, inst = n.inst, name = n.name, type = "fp", id = n.id })
                else
                    -- not learned yet: you can walk up, learn it and fly out from it right away
                    -- (only to flight points you already have, never through or into it)
                    table.insert(S, { wx = n.wx, wy = n.wy, inst = n.inst, name = n.name, type = "fp", id = n.id, learn = true })
                end
            end
        end
    end
    if db.useTransports then
        for _, tr in ipairs(transports()) do
            local ia = #S + 1
            S[ia] = { wx = tr.a.x, wy = tr.a.y, inst = tr.a.inst, name = tr.a.name or "Dock", type = "dock", trans = {} }
            S[ia + 1] = { wx = tr.b.x, wy = tr.b.y, inst = tr.b.inst, name = tr.b.name or "Dock", type = "dock", trans = {} }
            local kind = tr.kind or "boat"
            table.insert(S[ia].trans, { to = ia + 1, time = tr.time or 200, kind = kind })
            if not tr.oneway then
                table.insert(S[ia + 1].trans, { to = ia, time = tr.time or 200, kind = kind })
            end
        end
    end

    -- flight times between the flight points you can use, along the real flight network
    if not legAdj then buildLegAdj() end
    local allowed = {}
    for _, sp in ipairs(S) do if sp.type == "fp" and sp.id and not sp.learn then allowed[sp.id] = true end end
    for _, sp in ipairs(S) do
        if sp.type == "fp" then
            sp.ft = {}
            local times = sp.id and networkTimes(sp.id, allowed)
            for j, o in ipairs(S) do
                if o.type == "fp" and o ~= sp and o.inst == sp.inst and not o.learn then
                    local exact = recordedTime(sp.name, o.name)
                    if exact then
                        sp.ft[j] = exact
                    elseif times then
                        sp.ft[j] = times[o.id] -- nil: no flight connects them through your flight points
                    elseif not (o.id and legAdj[o.id]) then
                        -- neither end is in the network data (e.g. a brand-new flight point): estimate
                        sp.ft[j] = d2(sp.wx, sp.wy, o.wx, o.wy) * FLY_DETOUR / FLY_SPEED + FLY_OVERHEAD
                    end
                end
            end
        end
    end

    -- a short straight walk between two points must not cross water (a harbour, a lake)
    local function dryLine(a, b, dist)
        if not useNav or dist < 40 then return true end
        local n = floor(dist / 12)
        for k = 1, n - 1 do
            local x, y = a.wx + (b.wx - a.wx) * k / n, a.wy + (b.wy - a.wy) * k / n
            if ns.Nav:NearWater(a.inst, x, y, 15) then return false end
        end
        return true
    end
    -- link special points to nearby learned roads and to the built-in network
    local roadToSpecial = {}
    local function attach(si, s, id, dd, mult)
        s.near[#s.near + 1] = { id = id, d = dd, m = mult }
        local list = roadToSpecial[id]
        if not list then list = {}; roadToSpecial[id] = list end
        list[#list + 1] = { s = si, d = dd, m = mult }
    end
    for si, s in ipairs(S) do
        s.near = {}
        if db.useRoads and ns.Learn then
            local near = {}
            ns.Learn:ForNear(s.inst, s.wx, s.wy, CONNECT, function(i, dd) near[#near + 1] = { i, dd } end)
            table.sort(near, function(a, b) return a[2] < b[2] end)
            for k = 1, math.min(MAX_CONNECT, #near) do
                attach(si, s, s.inst * ROAD_ID + near[k][1], near[k][2], off)
            end
        end
        if useNav then
            local near = {}
            ns.Nav:ForNear(s.inst, s.wx, s.wy, NAV_CONNECT, function(i, dd) near[#near + 1] = { i, dd } end)
            local mult, count = off, MAX_CONNECT
            -- reach the nearest points of the bigger parts of the network: when nothing is close, and
            -- when cut off on a patch of its own (a new area's few points)
            local function reachBig(own, mult2, radius)
                local g = ns.Nav:Graph(s.inst)
                if not g or not g.comp then return end
                local cand = {}
                ns.Nav:ForNear(s.inst, s.wx, s.wy, radius or 3000, function(i, dd)
                    local c = g.comp[i]
                    if not own[c] and g.compSize[c] >= 200 then cand[#cand + 1] = { i, dd, c } end
                end)
                table.sort(cand, function(a, b) return a[2] < b[2] end)
                -- per part of the network: its nearest point you can walk to without crossing water
                -- (when there is none, only you or the target take the nearest one regardless)
                local list, got, tried, nearest = {}, {}, {}, {}
                for _, e in ipairs(cand) do
                    local c = e[3]
                    if not nearest[c] then nearest[c] = e end
                    if not got[c] and (tried[c] or 0) < 12 then
                        tried[c] = (tried[c] or 0) + 1
                        if dryLine(s, { wx = g.x[e[1]], wy = g.y[e[1]] }, e[2]) then got[c] = true; list[#list + 1] = e end
                    end
                end
                if #list == 0 and si <= 2 then
                    for _, e in pairs(nearest) do list[#list + 1] = e end
                end
                table.sort(list, function(a, b) return a[2] < b[2] end)
                for k = 1, math.min(3, #list) do
                    s.onNav = true
                    attach(si, s, s.inst * ROAD_ID + NAV_BASE + list[k][1], list[k][2], mult2)
                end
            end
            if #near > 0 then
                local g, own, big, biggest = ns.Nav:Graph(s.inst), {}, false, 0
                if g and g.comp then
                    for _, e in ipairs(near) do
                        local c = g.comp[e[1]]
                        own[c] = true
                        if g.compSize[c] >= 200 then big = true end
                        if g.compSize[c] > biggest then biggest = g.compSize[c] end
                    end
                    -- cut off (a new area's patch), or only scraps in reach (a dock just past the edge of
                    -- the network): also reach the nearest points of the bigger parts
                    if far and si <= 2 then reachBig(own, off * 1.5)
                    elseif not big and biggest < 20 then reachBig(own, off * 1.5, 500) end -- (only lone scraps in reach)
                end
            end
            if #near == 0 then
                -- nothing close (e.g. a new WoW Forever area): reach the network from further away
                ns.Nav:ForNear(s.inst, s.wx, s.wy, 3000, function(i, dd) near[#near + 1] = { i, dd } end)
                -- (you and the target must reach it; a dock or flight master out there is a last resort:
                -- the way to it is unknown, often over sea)
                mult, count = off * (si <= 2 and 1.5 or 6), 3
                local g, own = ns.Nav:Graph(s.inst), {}
                if g and g.comp then
                    table.sort(near, function(a, b) return a[2] < b[2] end)
                    for k = 1, math.min(count, #near) do own[g.comp[near[k][1]]] = true end
                    reachBig(own, mult)
                end
            end
            if #near > 0 then s.onNav = true end
            table.sort(near, function(a, b) return a[2] < b[2] end)
            for k = 1, math.min(count, #near) do
                attach(si, s, s.inst * ROAD_ID + NAV_BASE + near[k][1], near[k][2], mult)
            end
        end
    end

    -- Dijkstra. Special points have negative ids, road/network nodes positive ids.
    local cost, prev, how, done = { [-1] = 0 }, {}, {}, {}
    local heap = {}
    heapPush(heap, 0, -1)
    local onRoad = {} -- reached along a road link (keep its bends when smoothing the line)
    local function relax(u, v, c, kind, roadLink)
        local nc = cost[u] + c
        if not done[v] and (cost[v] == nil or nc < cost[v]) then
            cost[v], prev[v], how[v] = nc, u, kind
            onRoad[v] = roadLink
            heapPush(heap, nc, v)
        end
    end

    local pops = 0
    while true do
        local c, u = heapPop(heap)
        if not u then break end
        if not done[u] and c <= (cost[u] or huge) then
            done[u] = true
            if u == -2 then break end
            pops = pops + 1
            if pops > 400000 then break end -- safety net
            if pops % 400 == 0 and coroutine.running() then coroutine.yield() end -- spread over frames
            if u < 0 then
                local s = S[-u]
                for j, o in ipairs(S) do
                    if j ~= -u and o.type ~= "start" and o.inst == s.inst then
                        local dist = d2(s.wx, s.wy, o.wx, o.wy)
                        -- a straight walk is fine when short, or when an end can't reach the network at all
                        if (dist <= DIRECT_MAX and dryLine(s, o, dist)) or not (s.onNav and o.onNav) then
                            relax(u, -j, dist * off / gs, "walk")
                        end
                        if s.type == "fp" and o.type == "fp" and s.ft and s.ft[j] then
                            relax(u, -j, s.ft[j] + BOARDING + TRANSFER, "fly")
                        end
                    end
                end
                for _, nr in ipairs(s.near) do relax(u, nr.id, nr.d * nr.m / gs, "walk") end
                for _, e in ipairs(s.trans or {}) do relax(u, -e.to, e.time + (e.kind == "portal" and 0 or TRANSFER), e.kind) end
            else
                local inst = floor(u / ROAD_ID)
                local i = u - inst * ROAD_ID
                local x, y
                if i >= NAV_BASE then
                    -- built-in network
                    local g = ns.Nav:Graph(inst)
                    local k = i - NAV_BASE
                    local X, Y = g.x, g.y
                    x, y = X[k], Y[k]
                    local base = inst * ROAD_ID + NAV_BASE
                    for p = g.start[k], g.start[k + 1] - 1 do
                        local j = g.adj[p]
                        relax(u, base + j, d2(x, y, X[j], Y[j]) * NAV_FACTOR[g.kind[p]] * danger(g, j) / gs, "walk", g.kind[p] == 1)
                    end
                    if ns.Learn then -- step onto a learned road
                        ns.Learn:ForNear(inst, x, y, 20, function(j, dd) relax(u, inst * ROAD_ID + j, dd / gs, "walk") end)
                    end
                else
                    -- learned road
                    local r = roads[inst]
                    x, y = r.x[i], r.y[i]
                    for _, j in ipairs(r.adj[i]) do
                        relax(u, inst * ROAD_ID + j, d2(x, y, r.x[j], r.y[j]) / gs, "walk", true)
                    end
                    if useNav then -- step onto the built-in network
                        local base = inst * ROAD_ID + NAV_BASE
                        ns.Nav:ForNear(inst, x, y, 20, function(j, dd) relax(u, base + j, dd / gs, "walk") end)
                    end
                end
                for _, e in ipairs(roadToSpecial[u] or {}) do
                    if S[e.s].type ~= "start" then relax(u, -e.s, e.d * e.m / gs, "walk") end
                end
            end
        end
    end
    if not cost[-2] then
        -- you or the target sit on a patch of the network cut off from the rest (a new WoW Forever
        -- area): try again reaching the network from further away
        if not far and useNav then return self:Plan(px, py, pinst, t, true) end
        return nil
    end

    -- rebuild the chain of stops
    local chain = {}
    local v = -2
    while v and v ~= -1 do
        table.insert(chain, 1, v)
        v = prev[v]
    end
    local stops, interesting = {}, false
    for _, id in ipairs(chain) do
        local st
        if id < 0 then
            local s = S[-id]
            st = { wx = s.wx, wy = s.wy, inst = s.inst, name = s.name, special = s.type, learn = s.learn }
        else
            local inst = floor(id / ROAD_ID)
            local i = id - inst * ROAD_ID
            if i >= NAV_BASE then
                local g = ns.Nav:Graph(inst)
                local k = i - NAV_BASE
                local mine = ((fac == 2 and g.lvlA) or (fac == 1 and g.lvlH) or g.lvl)
                st = { wx = g.x[k], wy = g.y[k], inst = inst, road = true, nav = true, onRoad = onRoad[id],
                       lvl = mine[k], enemyTown = (mine[k] or 0) > (g.lvl[k] or 0) }
            else
                st = { wx = roads[inst].x[i], wy = roads[inst].y[i], inst = inst, road = true, onRoad = onRoad[id] }
            end
            interesting = true
        end
        st.kind = how[id]
        if TRAVEL[st.kind] then interesting = true end
        table.insert(stops, st)
    end
    if not interesting then return nil end -- straight line is the plan

    -- highest monster level the walk passes (shown as a warning when it's above you), split into
    -- "on the way" and "at the destination" (the last stretch can't be avoided)
    local maxLvl, goalLvl, maxIsTown = 0, 0, false
    for _, st in ipairs(stops) do
        if st.lvl then
            local nearGoal = st.inst == t.instance and d2(st.wx, st.wy, t.wx, t.wy) < 450
            local nearStart = st.inst == pinst and d2(st.wx, st.wy, px, py) < 200
            if nearGoal then
                if st.lvl > goalLvl then goalLvl = st.lvl end
            elseif not nearStart and st.lvl > maxLvl then
                maxLvl = st.lvl
                maxIsTown = st.enemyTown
            end
        end
    end

    -- Straighten the line: skip ahead to the furthest point we can reach in a straight line
    -- that stays over known walkable ground the whole way (never across unmapped hills or water).
    local function corridorClear(a, b)
        local dx, dy = b.wx - a.wx, b.wy - a.wy
        local len = sqrt(dx * dx + dy * dy)
        if len > 120 then return false end -- only smooth small zig-zags; keep the path's real shape
        local steps = math.max(2, floor(len / 10))
        for k = 1, steps - 1 do
            local t = k / steps
            local x, y = a.wx + dx * t, a.wy + dy * t
            if not ns.Nav:HasNear(a.inst, x, y, 22) then return false end
            if ns.Nav:NearWater(a.inst, x, y, 18) then return false end
        end
        return true
    end
    if useNav then
        local out = { stops[1] }
        local i = 1
        while i < #stops do
            local a = stops[i]
            local j = i + 1
            if a.inst and (a.nav or a.special == "start" or a.road) then
                for k = math.min(#stops, i + 10), i + 2, -1 do
                    local okRun = true
                    for m = i + 1, k do
                        local st = stops[m]
                        if TRAVEL[st.kind] or st.inst ~= a.inst or (m < k and not (st.nav or st.road)) or st.onRoad then okRun = false break end
                    end
                    if okRun and corridorClear(a, stops[k]) then j = k break end
                end
            end
            out[#out + 1] = stops[j]
            i = j
        end
        stops = out
    end
    return { stops = stops, total = cost[-2], maxLevel = maxLvl, goalLevel = goalLvl, enemyTown = maxIsTown }
end

---------------------------------------------------------------------------
-- Keeping the route and the next waypoint up to date
---------------------------------------------------------------------------
local VEHICLE = { fly = "flight", boat = "boat", zeppelin = "zeppelin", airship = "airship", tram = "tram", ferry = "boat", portal = "portal" }
local PLACE = { fly = "the flight master", boat = "the boat dock", zeppelin = "the zeppelin tower", airship = "the airship dock", tram = "the Deeprun Tram", ferry = "the boat dock", portal = "the portal" }

local lastPlanX, lastPlanY, lastPlanTime, lastTarget = nil, nil, 0, nil
local planner -- coroutine while a plan is being computed

-- Which stop are we heading to? Progress = the closest stop on our continent;
-- once we reach a road point we aim at the next one. Standing at a departure
-- point (flight master, dock) means the trip itself is next.
local function currentStop(route, px, py, pinst)
    local best, bestD = 1, huge
    for i, s in ipairs(route.stops) do
        if s.inst == pinst then
            local d = d2(s.wx, s.wy, px, py)
            if d < bestD then best, bestD = i, d end
        end
    end
    local i = best
    if route.stops[i].road and bestD < 20 and i < #route.stops then i = i + 1 end
    local s, nxt = route.stops[i], route.stops[i + 1]
    if nxt and TRAVEL[nxt.kind] and s.inst == pinst and d2(s.wx, s.wy, px, py) < AT_STOP then i = i + 1 end
    return i
end

-- Drive the planning coroutine: as much as fits in a few milliseconds each frame, so a route
-- appears quickly without stuttering the game.
local BUDGET_MS = 5
local clock = debugprofilestop
local plannerTarget
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    if not planner then self:Hide() return end
    local start, slices = clock and clock(), 0
    repeat
        slices = slices + 1
        local ok, res = coroutine.resume(planner)
        if coroutine.status(planner) == "dead" then
            planner, plannerTarget = nil, nil
            self:Hide()
            if ok then
                ns.route = res
                ns.lastPlanError = nil
                R:UpdateWaypoint()
            else
                ns.lastPlanError = res
                geterrorhandler()(res)
            end
            ns:NotifyChanged() -- the map, minimap and compass draw the new route now
            return
        end
    until (start and clock() - start > BUDGET_MS) or (not start and slices >= 8)
end)

local function startPlan(px, py, pinst, t)
    plannerTarget = t
    planner = coroutine.create(function() return R:Plan(px, py, pinst, t) end)
    driver:Show()
    driver:GetScript("OnUpdate")(driver) -- first slice right away
end

local tipShown = false
local function maybeTip(px, py, pinst, t)
    if tipShown or not ns.db.useFlights or ns.db.assumeAllFlights or t.corpse then return end
    if R:KnownCount() > 0 then return end
    if pinst == t.instance and d2(px, py, t.wx, t.wy) < 1200 then return end
    tipShown = true
    ns:Print("|cff80d0fftip:|r I don't know your flight paths yet. Open any flight master's map once and long trips will use flights. (Or tick 'Assume all are known' in /qroute.)")
end

function R:Update()
    local t = ns.target
    if not t or not ns.HBD then
        ns.route, ns.waypoint, planner = nil, nil, nil
        return
    end
    local px, py, pinst = ns.HBD:GetPlayerWorldPosition()
    local riding = (UnitOnTaxi and UnitOnTaxi("player")) or ns.carried
    local now = GetTime()
    -- a different quest or destination while still planning the old one: drop the old plan
    if planner and plannerTarget and (plannerTarget.questId ~= t.questId or plannerTarget.custom ~= t.custom
        or plannerTarget.corpse ~= t.corpse) then
        planner, plannerTarget = nil, nil
        driver:Hide()
    end
    if not riding and px and not planner then
        -- a different quest/destination: drop the old route right away so it isn't shown for the
        -- wrong place. The same destination re-planned: keep showing the current route meanwhile.
        -- (the nearest mob of a kill quest moving to another spot is NOT a switch: keep the
        -- current route on screen until the new one is ready)
        local switched = not lastTarget or lastTarget.questId ~= t.questId or lastTarget.custom ~= t.custom
            or lastTarget.corpse ~= t.corpse
        if switched then ns.route, ns.waypoint = nil, nil end
        -- replan only when needed: a new destination, you've left the route, or now and then
        -- (walking along the route doesn't need a new plan: the line starts where you stand)
        local offRoute = not ns.route
        if ns.route and pinst then
            local best = huge
            local stops = ns.route.stops
            local ax, ay, ai = lastPlanX, lastPlanY, pinst
            for k = 1, #stops do
                local s = stops[k]
                if s.inst == pinst and ai == pinst and ax then
                    -- distance from you to the segment (ax,ay)-(s)
                    local dx, dy = s.wx - ax, s.wy - ay
                    local l2 = dx * dx + dy * dy
                    local u = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
                    local d = d2(px, py, ax + dx * u, ay + dy * u)
                    if d < best then best = d end
                end
                ax, ay, ai = s.wx, s.wy, s.inst
            end
            offRoute = best > 50
        end
        if t ~= lastTarget or offRoute or now - lastPlanTime > 20 or ns.forceReplan then
            lastPlanX, lastPlanY, lastPlanTime, lastTarget = px, py, now, t
            ns.forceReplan = false
            maybeTip(px, py, pinst, t)
            startPlan(px, py, pinst, t)
        end
    end
    self:UpdateWaypoint()
end

function R:UpdateWaypoint()
    local px, py, pinst = ns.HBD:GetPlayerWorldPosition()
    local riding = (UnitOnTaxi and UnitOnTaxi("player")) or ns.carried
    local route = ns.route
    if not (route and px) then
        ns.waypoint = nil
        return
    end
    local i = currentStop(route, px, py, pinst)
    if riding then
        -- on a flight/boat: we're heading to the next arrival point
        for j = i, #route.stops do
            if TRAVEL[route.stops[j].kind] then i = j break end
        end
    end

    -- aim a little way down the road instead of at the very next road node
    local aim = i
    local cx, cy, acc = px, py, 0
    for j = i, #route.stops do
        local s = route.stops[j]
        if s.inst ~= pinst then break end
        acc = acc + d2(cx, cy, s.wx, s.wy)
        cx, cy = s.wx, s.wy
        aim = j
        if not s.road or acc >= LOOKAHEAD then break end
    end

    -- describe the step: the next special stop decides the instruction
    local text
    local nextSpecial
    for j = i, #route.stops do
        if not route.stops[j].road then nextSpecial = j break end
    end
    local s = nextSpecial and route.stops[nextSpecial]
    local after = nextSpecial and route.stops[nextSpecial + 1]
    if s then
        if riding then
            text = (UnitOnTaxi and UnitOnTaxi("player")) and ("Flying to " .. s.name) or ("On the " .. (VEHICLE[s.kind] or "boat") .. " to " .. s.name)
        elseif TRAVEL[s.kind] then
            text = "Take the " .. VEHICLE[s.kind] .. " to " .. s.name
        elseif after and TRAVEL[after.kind] then
            text = "Go to " .. PLACE[after.kind] .. ": " .. s.name
            if s.learn and after.kind == "fly" then text = "Learn the flight path: " .. s.name end
        end
    end

    -- the arrow: by default it points at the end of this leg (the quest, or the dock or flight master
    -- you take first), steady, rather than at a spot down the road that swings round every bend
    if not ns.db.arrowFollowsRoad then
        aim = #route.stops
        for j = i, #route.stops do
            local st = route.stops[j]
            if st.inst ~= pinst then break end
            aim = j
            if not st.road and route.stops[j + 1] and TRAVEL[route.stops[j + 1].kind] then break end
        end
        if riding then aim = i end
    end
    -- walking distance along the route to that point
    local pathDist, qx, qy = 0, px, py
    for j = i, aim do
        local st = route.stops[j]
        if st.inst ~= pinst then break end
        pathDist = pathDist + d2(qx, qy, st.wx, st.wy)
        qx, qy = st.wx, st.wy
    end
    local a = route.stops[aim]
    ns.waypoint = {
        wx = a.wx, wy = a.wy, inst = a.inst, name = a.name, text = text,
        index = i, final = (aim == #route.stops), pathDist = (not riding) and pathDist or nil,
    }
end

function R:Replan()
    ns.forceReplan = true
end

---------------------------------------------------------------------------
-- Learning which flight paths this character knows
---------------------------------------------------------------------------
-- Find our flight point record for a name from the game ("Sentinel Hill, Westfall" or just "Sentinel Hill").
local function flightByName(name)
    if not name then return end
    if not flightNodes then buildStatic() end
    local full = name:lower()
    local short = full:match("^([^,]+)") or full
    for _, n in ipairs(flightNodes) do
        local nf = n.name:lower()
        if nf == full then return n end
    end
    for _, n in ipairs(flightNodes) do
        local ns_ = n.name:lower():match("^([^,]+)")
        if ns_ == short then return n end
    end
end

local nearestFlightPoint -- defined below

local function learnFlights(quiet)
    QuestRouteCharDB.knownTaxi = QuestRouteCharDB.knownTaxi or {}
    local k = QuestRouteCharDB.knownTaxi
    local before = R:KnownCount()
    local seen, usable, samples = 0, 0, {}
    local function learn(name, id)
        usable = usable + 1
        if id then k[id] = true end
        if name then
            k[name] = true
            local n = flightByName(name)
            if n then k[n.id], k[n.name] = true, true end
        end
    end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
        for _, node in ipairs(ok and list or {}) do
            seen = seen + 1
            if #samples < 3 then samples[#samples + 1] = tostring(node.name) .. "=" .. tostring(node.state) end
            -- states: 0 current, 1 reachable, 2 unreachable
            if node.state == 0 or node.state == 1 then learn(node.name, node.nodeID) end
        end
    end
    if NumTaxiNodes and TaxiNodeGetType and TaxiNodeName then
        for i = 1, NumTaxiNodes() do
            seen = seen + 1
            local typ = TaxiNodeGetType(i)
            if #samples < 6 then samples[#samples + 1] = tostring(TaxiNodeName(i)) .. "=" .. tostring(typ) end
            -- learned: here, reachable from here, or learned but not connected from here.
            -- (DISTANT is one you haven't learned that a flight would pass through.)
            if typ == "CURRENT" or typ == "REACHABLE" or typ == "UNREACHABLE" then learn(TaxiNodeName(i)) end
        end
    end
    -- the flight master you are talking to is certainly known
    if ns.HBD then
        local x, y, inst = ns.HBD:GetPlayerWorldPosition()
        local n = x and nearestFlightPoint and nearestFlightPoint(x, y, inst, 100)
        if n then k[n.id], k[n.name] = true, true end
    end
    local after = R:KnownCount()
    if after > before then
        ns:Print(("learned %d new flight path(s), %d known."):format(after - before, after))
    elseif not quiet and after == 0 then
        ns:Print(("couldn't read your flight paths from this map (saw %d entries, %d unlocked: %s). Please send this line to the developer."):format(
            seen, usable, table.concat(samples, ", ")))
    end
    ns.lastTaxiScan = { seen = seen, usable = usable, samples = table.concat(samples, ", ") }
    R:Replan()
    ns:NotifyChanged()
end

-- Time every flight: take-off point -> landing point (nearest flight points).
local taxiFrom, taxiStart, groundX, groundY, groundInst
nearestFlightPoint = function(x, y, inst, radius)
    if not flightNodes then buildStatic() end
    local best, bestD
    for _, n in ipairs(flightNodes) do
        if n.inst == inst then
            local d = d2(n.wx, n.wy, x, y)
            if d < radius and (not bestD or d < bestD) then best, bestD = n, d end
        end
    end
    return best
end
local taxiWatch = CreateFrame("Frame")
local taxiAcc, wasOnTaxi = 0, false
taxiWatch:SetScript("OnUpdate", function(_, e)
    taxiAcc = taxiAcc + e
    if taxiAcc < 0.5 or not ns.HBD or not QuestRouteDB then return end
    taxiAcc = 0
    local on = UnitOnTaxi and UnitOnTaxi("player")
    local x, y, inst = ns.HBD:GetPlayerWorldPosition()
    if on and not wasOnTaxi then
        local n = groundX and nearestFlightPoint(groundX, groundY, groundInst, 120)
        taxiFrom, taxiStart = n and n.name, GetTime()
        if n then R:MarkKnown(n) end -- you can only fly from a flight path you know
    elseif not on and wasOnTaxi and taxiFrom and x then
        local n = nearestFlightPoint(x, y, inst, 150)
        if n then R:MarkKnown(n) end
        local dt = GetTime() - taxiStart
        if n and n.name ~= taxiFrom and dt > 15 and dt < 1800 then
            QuestRouteDB.flightTimes = QuestRouteDB.flightTimes or {}
            QuestRouteDB.flightTimes[taxiFrom .. "|" .. n.name] = math.floor(dt + 0.5)
        end
        taxiFrom = nil
    end
    if not on and x then groundX, groundY, groundInst = x, y, inst end
    wasOnTaxi = on and true or false
end)

function R:MarkKnown(node)
    QuestRouteCharDB.knownTaxi = QuestRouteCharDB.knownTaxi or {}
    local k = QuestRouteCharDB.knownTaxi
    if not (k[node.name] or k[node.id]) then
        k[node.name], k[node.id] = true, true
        ns:Print("flight path learned: " .. node.name)
        R:Replan()
        ns:NotifyChanged()
    end
end

function R:KnownNames()
    if not flightNodes then buildStatic() end
    local list, fac = {}, myFaction()
    for _, n in ipairs(flightNodes) do
        if (n.fac == 0 or n.fac == fac) and self:IsKnown(n) then list[#list + 1] = n.name end
    end
    table.sort(list)
    return list
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("UI_INFO_MESSAGE")
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "TAXIMAP_OPENED" then
        learnFlights(true)
        -- read again a moment later, in case the map wasn't filled in yet
        C_Timer.After(0.5, function() learnFlights(false) end)
    elseif event == "UI_INFO_MESSAGE" then
        -- "New flight path discovered!" -> the flight point you're standing at
        local msg = type(a2) == "string" and a2 or a1
        if ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH and ns.HBD then
            local x, y, inst = ns.HBD:GetPlayerWorldPosition()
            local n = x and nearestFlightPoint(x, y, inst, 150)
            if n then R:MarkKnown(n) end
        end
    else
        buildStatic()
    end
end)

function R:IsPlanning() return planner ~= nil end

-- OpenMap remembers, per character, the flight masters you've talked to (its blue icons).
-- If it's installed, take those over: no trip to a flight master on each continent needed.
function R:ImportOpenMap()
    QuestRouteCharDB.knownTaxi = QuestRouteCharDB.knownTaxi or {}
    local k = QuestRouteCharDB.knownTaxi
    local gained = 0
    for name, v in pairs(_G) do
        if type(name) == "string" and name:find("^OpenMap") and type(v) == "table" then
            local wm = rawget(v, "worldmap")
            local list = type(wm) == "table" and rawget(wm, "flightsKnown")
            if type(list) == "table" then
                for fpName, known in pairs(list) do
                    if known and type(fpName) == "string" then
                        local n = flightByName(fpName)
                        if n and not (k[n.id] or k[n.name]) then
                            k[n.id], k[n.name] = true, true
                            gained = gained + 1
                        end
                    end
                end
            end
        end
    end
    if gained > 0 then
        ns:Print(("learned %d flight path(s) from OpenMap, %d known."):format(gained, self:KnownCount()))
        self:Replan()
        ns:NotifyChanged()
    end
    return gained
end

local om = CreateFrame("Frame")
om:RegisterEvent("PLAYER_ENTERING_WORLD")
om:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function() R:ImportOpenMap() end)
end)

-- Unpack the built-in path network in the background soon after logging in, a few milliseconds a
-- frame, so the first route doesn't have to wait for it.
do
    local warm = CreateFrame("Frame")
    local job
    warm:Hide()
    warm:SetScript("OnUpdate", function(self)
        if not job or (ns.Nav and ns.Nav:IsReady()) then self:Hide() return end
        local start = clock and clock()
        repeat
            local ok = coroutine.resume(job)
            if not ok or coroutine.status(job) == "dead" then job = nil; self:Hide(); return end
        until not start or clock() - start > BUDGET_MS
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        if job or not ns.Nav or ns.Nav:IsReady() then return end
        C_Timer.After(1, function()
            if planner or ns.Nav:IsReady() then return end -- (a route already started it)
            job = coroutine.create(function() ns.Nav:Ensure() end)
            warm:Show()
        end)
    end)
end
