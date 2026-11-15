-- QuestRoute: the built-in walkable-ground network (Data/NavEK.lua, Data/NavKalimdor.lua).
-- Unpacked on first use (spread over frames when called from the planner) into
-- world coordinates, with compact adjacency arrays and a spatial grid.
local _, ns = ...
local Nav = {}
ns.Nav = Nav

local CELL = 80
local OFF, SCALE = 0.25, 131072
local floor, sqrt = math.floor, math.sqrt
local byte = string.byte

local DEC = {}
do
    local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do DEC[byte(B64, i)] = i - 1 end
end

local graphs = {}   -- [instance] = { x, y, start, adj, kind, grid }
local ready = false

local function maybeYield(i)
    if i % 4000 == 0 and coroutine.running() then coroutine.yield() end
end

local function unpack(cont, data)
    if not ns.HBD then return end
    -- continent map coordinates -> world coordinates (affine, from HereBeDragons)
    local ox, oy, inst = ns.HBD:GetWorldCoordinatesFromZone(0, 0, cont)
    local ax, ay = ns.HBD:GetWorldCoordinatesFromZone(1, 0, cont)
    local bx, by = ns.HBD:GetWorldCoordinatesFromZone(0, 1, cont)
    if not ox or not ax or not bx then return end
    local uxx, uxy = ax - ox, ay - oy
    local uyx, uyy = bx - ox, by - oy

    local s, n = data.nodes, data.count
    local X, Y = {}, {}
    for i = 1, n do
        local p = (i - 1) * 6
        local a1, a2, a3, b1, b2, b3 = byte(s, p + 1, p + 6)
        local cx = (DEC[a1] * 4096 + DEC[a2] * 64 + DEC[a3]) / SCALE - OFF
        local cy = (DEC[b1] * 4096 + DEC[b2] * 64 + DEC[b3]) / SCALE - OFF
        X[i] = ox + uxx * cx + uyx * cy
        Y[i] = oy + uxy * cx + uyy * cy
        maybeYield(i)
    end

    -- edges -> compressed adjacency (start index per node)
    local e, m = data.edges, data.links
    local ea, eb, et = {}, {}, {}
    local deg = {}
    for i = 1, n do deg[i] = 0 end
    for k = 1, m do
        local p = (k - 1) * 7
        local a1, a2, a3, b1, b2, b3, t = byte(e, p + 1, p + 7)
        local a = DEC[a1] * 4096 + DEC[a2] * 64 + DEC[a3] + 1
        local b = DEC[b1] * 4096 + DEC[b2] * 64 + DEC[b3] + 1
        ea[k], eb[k], et[k] = a, b, DEC[t]
        deg[a] = deg[a] + 1
        deg[b] = deg[b] + 1
        maybeYield(k)
    end
    local start, fill = {}, {}
    local pos = 1
    for i = 1, n do
        start[i] = pos
        fill[i] = pos
        pos = pos + deg[i]
    end
    start[n + 1] = pos
    local adj, kind = {}, {}
    for k = 1, m do
        local a, b, t = ea[k], eb[k], et[k]
        adj[fill[a]], kind[fill[a]] = b, t
        fill[a] = fill[a] + 1
        adj[fill[b]], kind[fill[b]] = a, t
        fill[b] = fill[b] + 1
        maybeYield(k)
    end

    -- connected parts of the network (a new area's own patch can be cut off from the rest)
    local comp, compSize, nc = {}, {}, 0
    for i = 1, n do
        if not comp[i] then
            nc = nc + 1
            local stack, size = { i }, 0
            comp[i] = nc
            while #stack > 0 do
                local u = stack[#stack]; stack[#stack] = nil
                size = size + 1
                for q = start[u], start[u + 1] - 1 do
                    local v = adj[q]
                    if not comp[v] then comp[v] = nc; stack[#stack + 1] = v end
                end
                maybeYield(size)
            end
            compSize[nc] = size
        end
    end

    local grid = {}
    for i = 1, n do
        local key = floor(X[i] / CELL) * 100000 + floor(Y[i] / CELL)
        local c = grid[key]
        if not c then c = {}; grid[key] = c end
        c[#c + 1] = i
        maybeYield(i)
    end
    -- typical level of the hostile monsters around each point (0 = none)
    -- (separate lists per faction: the other faction's guards and towns count as deadly)
    local function levels(str)
        local t = {}
        if str then for i = 1, n do t[i] = DEC[byte(str, i)] or 0 end end
        return t
    end
    local lvl = levels(data.levels)
    -- water markers (sea creatures, fishing pools): shortcuts must not cross them
    local wgrid = {}
    local ws = data.water
    if ws then
        for i = 1, #ws / 6 do
            local p = (i - 1) * 6
            local a1, a2, a3, b1, b2, b3 = byte(ws, p + 1, p + 6)
            local cx = (DEC[a1] * 4096 + DEC[a2] * 64 + DEC[a3]) / SCALE - OFF
            local cy = (DEC[b1] * 4096 + DEC[b2] * 64 + DEC[b3]) / SCALE - OFF
            local wx, wy = ox + uxx * cx + uyx * cy, oy + uxy * cx + uyy * cy
            local key = floor(wx / CELL) * 100000 + floor(wy / CELL)
            local c = wgrid[key]
            if not c then c = {}; wgrid[key] = c end
            c[#c + 1] = { wx, wy }
        end
    end
    graphs[inst] = { x = X, y = Y, start = start, adj = adj, kind = kind, grid = grid, n = n, lvl = lvl, water = wgrid,
        comp = comp, compSize = compSize,
        lvlA = data.levelsAlliance and levels(data.levelsAlliance) or lvl,
        lvlH = data.levelsHorde and levels(data.levelsHorde) or lvl }
end

--- Unpack all continents (once). Safe to call from inside a coroutine (yields).
function Nav:Ensure()
    if ready then return true end
    if not ns.NavData or not ns.HBD then return false end
    for cont, data in pairs(ns.NavData) do
        local inst = select(3, ns.HBD:GetWorldCoordinatesFromZone(0.5, 0.5, cont))
        if not (inst and graphs[inst]) then unpack(cont, data) end -- (already unpacked: skip)
    end
    ready = true
    return true
end

function Nav:IsReady() return ready end

function Nav:Graph(inst) return graphs[inst] end

--- Calls fn(i, distance) for network points within radius of x, y.
function Nav:ForNear(inst, x, y, radius, fn)
    local g = graphs[inst]
    if not g then return end
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local span = math.ceil(radius / CELL)
    local X, Y = g.x, g.y
    for gx = cx - span, cx + span do
        for gy = cy - span, cy + span do
            local c = g.grid[gx * 100000 + gy]
            if c then
                for _, i in ipairs(c) do
                    local dx, dy = X[i] - x, Y[i] - y
                    local d = sqrt(dx * dx + dy * dy)
                    if d <= radius then fn(i, d) end
                end
            end
        end
    end
end

--- True if any network point lies within radius of x, y (fast: stops at the first hit).
function Nav:HasNear(inst, x, y, radius)
    local g = graphs[inst]
    if not g then return false end
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local span = math.ceil(radius / CELL)
    local X, Y, r2 = g.x, g.y, radius * radius
    for gx = cx - span, cx + span do
        for gy = cy - span, cy + span do
            local c = g.grid[gx * 100000 + gy]
            if c then
                for _, i in ipairs(c) do
                    local dx, dy = X[i] - x, Y[i] - y
                    if dx * dx + dy * dy <= r2 then return true end
                end
            end
        end
    end
    return false
end

--- True if a water marker lies within radius of x, y.
function Nav:NearWater(inst, x, y, radius)
    local g = graphs[inst]
    if not g or not g.water then return false end
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local r2 = radius * radius
    for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
            local c = g.water[gx * 100000 + gy]
            if c then
                for _, p in ipairs(c) do
                    local dx, dy = p[1] - x, p[2] - y
                    if dx * dx + dy * dy <= r2 then return true end
                end
            end
        end
    end
    return false
end

function Nav:Stats()
    local n = 0
    for _, g in pairs(graphs) do n = n + g.n end
    return n
end
