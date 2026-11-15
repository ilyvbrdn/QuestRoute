-- QuestRoute: line drawing (solid / dashed / dotted, glow, animation).
-- A "surface" draws paths on one parent frame (world map canvas, minimap, preview box).
local _, ns = ...
local Lines = {}
ns.Lines = Lines

local WHITE = "Interface\\Buttons\\WHITE8X8"
local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min
local MAX_PIECES = 350

---------------------------------------------------------------------------
-- Object pools
---------------------------------------------------------------------------
local Pool = {}
Pool.__index = Pool

local function newPool(parent, kind, sublevel, texture, blend)
    return setmetatable({ parent = parent, kind = kind, sub = sublevel, texture = texture, blend = blend, items = {}, used = 0 }, Pool)
end

function Pool:Acquire()
    self.used = self.used + 1
    local o = self.items[self.used]
    if not o then
        if self.kind == "line" then
            o = self.parent:CreateLine(nil, "ARTWORK", nil, self.sub)
        else
            o = self.parent:CreateTexture(nil, "ARTWORK", nil, self.sub)
        end
        o:SetTexture(self.texture)
        if self.blend then o:SetBlendMode(self.blend) end
        self.items[self.used] = o
    end
    o:Show()
    return o
end

function Pool:Finish()
    for i = self.used + 1, #self.items do self.items[i]:Hide() end
end

---------------------------------------------------------------------------
-- Surface
---------------------------------------------------------------------------
local Surface = {}
Surface.__index = Surface

function Lines:NewSurface(parent)
    local s = setmetatable({}, Surface)
    s.parent = parent
    s.glow = newPool(parent, "line", 0, ns.MEDIA .. "GlowLine")
    s.marker = newPool(parent, "texture", 1, ns.MEDIA .. "GlowDot")
    s.olLine = newPool(parent, "line", 2, WHITE)
    s.olDot = newPool(parent, "texture", 2, ns.MEDIA .. "Dot")
    s.line = newPool(parent, "line", 4, WHITE)
    s.gild = newPool(parent, "line", 4, ns.MEDIA .. "GildLine")
    s.dot = newPool(parent, "texture", 5, ns.MEDIA .. "Dot")
    s.foot = newPool(parent, "texture", 5, ns.MEDIA .. "Footprint")
    s.xmark = newPool(parent, "texture", 6, ns.MEDIA .. "MarkerX")
    s.pools = { s.glow, s.marker, s.olLine, s.olDot, s.line, s.gild, s.dot, s.foot, s.xmark }
    return s
end

function Surface:Begin()
    for _, p in ipairs(self.pools) do p.used = 0 end
end

function Surface:End()
    for _, p in ipairs(self.pools) do p:Finish() end
end

function Surface:Clear()
    self:Begin(); self:End()
end

local function settings(override)
    return override or ns.db
end

local function addLine(pool, anchor, point, x1, y1, x2, y2, thickness, r, g, b, a)
    local l = pool:Acquire()
    l:SetStartPoint(point, anchor, x1, y1)
    l:SetEndPoint(point, anchor, x2, y2)
    l:SetThickness(thickness)
    l:SetVertexColor(r, g, b, a)
    return l
end

local function addDot(pool, anchor, point, x, y, size, r, g, b, a)
    local t = pool:Acquire()
    t:ClearAllPoints()
    t:SetPoint("CENTER", anchor, point, x, y)
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b, a)
    return t
end

-- Returns cumulative distances along the path.
local function measure(pts)
    local cum = { 0 }
    for i = 2, #pts do
        local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        cum[i] = cum[i - 1] + sqrt(dx * dx + dy * dy)
    end
    return cum
end

local function pointAt(pts, cum, d)
    for i = 2, #pts do
        if d <= cum[i] or i == #pts then
            local segLen = cum[i] - cum[i - 1]
            local f = segLen > 0 and (d - cum[i - 1]) / segLen or 0
            return pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f,
                   pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * f, i
        end
    end
    return pts[1][1], pts[1][2], 2
end

--- Draw a path.
-- anchor/point: frame and anchor point the coordinates are relative to.
-- pts: array of {x, y}. opts.scale multiplies the thickness, opts.db overrides settings (preview).
function Surface:DrawPath(anchor, point, pts, opts)
    if #pts < 2 then return end
    local db = settings(opts and opts.db)
    local scale = (opts and opts.scale) or 1
    local th = max(1, db.thickness * scale)
    local c = db.color
    local r, g, b, a = c.r, c.g, c.b, db.opacity

    local gilded = (db.style == "gilded")
    local outline = db.outline and db.outlineSize > 0
    local ow = outline and db.outlineSize * scale or 0
    local oc = db.outlineColor
    local oa = a * (db.outlineOpacity or 1)

    -- one visible line piece, with its outline drawn underneath
    local function piece(x1, y1, x2, y2)
        if outline then
            local dx, dy = x2 - x1, y2 - y1
            local len = sqrt(dx * dx + dy * dy)
            local ex, ey = 0, 0
            if len > 0 then ex, ey = dx / len * ow, dy / len * ow end
            addLine(self.olLine, anchor, point, x1 - ex, y1 - ey, x2 + ex, y2 + ey, th + 2 * ow, oc.r, oc.g, oc.b, oa)
        end
        addLine(gilded and self.gild or self.line, anchor, point, x1, y1, x2, y2, th, r, g, b, a)
    end

    -- glow underneath, continuous along the whole path
    if db.glow and db.glowStrength > 0 then
        local gth = th * (2.5 + 3.5 * db.glowStrength)
        local ga = a * (0.2 + 0.5 * db.glowStrength)
        for i = 2, #pts do
            addLine(self.glow, anchor, point, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], gth, r, g, b, ga)
        end
    end

    local style = db.style
    if style == "footprints" then
        -- boot prints walking along the path, alternating left and right
        local cum = measure(pts)
        local total = cum[#cum]
        if total <= 0 then return end
        local stride = th * 3
        if total / stride > MAX_PIECES then stride = total / MAX_PIECES end
        local fw, fh = th * 1.7, th * 2.4
        local side = th * 0.7
        local animate = db.animate and not (opts and opts.static)
        local offset = animate and ((GetTime() * th * 2.5) % (stride * 2)) or 0
        local d, n = offset - stride, 0
        if d < 0 then d, n = d + stride, 1 end
        while d <= total do
            local x, y, i = pointAt(pts, cum, d)
            local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
            local len = sqrt(dx * dx + dy * dy)
            if len > 0 then
                local ux, uy = dx / len, dy / len
                local left = (n % 2 == 0)
                local o = left and side or -side
                local t = self.foot:Acquire()
                t:ClearAllPoints()
                t:SetPoint("CENTER", anchor, point, x - uy * o, y + ux * o)
                t:SetSize(fw, fh)
                t:SetVertexColor(r, g, b, a)
                if left then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
                t:SetRotation(math.atan2(uy, ux) - math.pi / 2)
            end
            d, n = d + stride, n + 1
        end
        return
    end
    if style == "solid" or style == "gilded" then
        for i = 2, #pts do
            piece(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
        end
        return
    end

    local cum = measure(pts)
    local total = cum[#cum]
    if total <= 0 then return end

    local animate = db.animate and not (opts and opts.static)
    if style == "dotted" then
        local spacing = th * 2.6
        if total / spacing > MAX_PIECES then spacing = total / MAX_PIECES end
        local size = th * 1.5
        local offset = animate and ((GetTime() * th * 4) % spacing) or 0
        local d = offset
        while d <= total do
            local x, y = pointAt(pts, cum, d)
            if outline then addDot(self.olDot, anchor, point, x, y, size + 2 * ow, oc.r, oc.g, oc.b, oa) end
            addDot(self.dot, anchor, point, x, y, size, r, g, b, a)
            d = d + spacing
        end
    else -- dashed
        local dash, gap = th * 3.5, th * 2.2
        local period = dash + gap
        if total / period > MAX_PIECES then
            local k = (total / MAX_PIECES) / period
            dash, gap, period = dash * k, gap * k, period * k
        end
        local offset = animate and ((GetTime() * th * 4) % period) or 0
        local start = offset - period
        while start < total do
            local s1, s2 = max(start, 0), min(start + dash, total)
            if s2 > s1 then
                local x1, y1, i1 = pointAt(pts, cum, s1)
                local x2, y2, i2 = pointAt(pts, cum, s2)
                local cx, cy = x1, y1
                for i = i1, i2 - 1 do
                    piece(cx, cy, pts[i][1], pts[i][2])
                    cx, cy = pts[i][1], pts[i][2]
                end
                piece(cx, cy, x2, y2)
            end
            start = start + period
        end
    end
end

--- Destination marker: soft glow with a solid centre that gently pulses, or a red X.
function Surface:DrawMarker(anchor, point, x, y, opts)
    local db = settings(opts and opts.db)
    local scale = (opts and opts.scale) or 1
    local th = max(1, db.thickness * scale)
    local c = db.color
    if db.markerStyle == "x" then
        local m = db.markerColor
        local size = max(12, th * 4.5)
        addDot(self.xmark, anchor, point, x, y, size, m.r, m.g, m.b, db.opacity)
        return
    end
    local pulse = 1 + 0.15 * math.sin(GetTime() * 4)
    addDot(self.marker, anchor, point, x, y, th * 7 * pulse, c.r, c.g, c.b, 0.6 * db.opacity)
    if db.outline and db.outlineSize > 0 then
        local oc = db.outlineColor
        addDot(self.olDot, anchor, point, x, y, th * 2.4 + 2 * db.outlineSize * scale, oc.r, oc.g, oc.b, db.opacity * (db.outlineOpacity or 1))
    end
    addDot(self.dot, anchor, point, x, y, th * 2.4, 1, 1, 1, db.opacity)
end

---------------------------------------------------------------------------
-- Clipping helpers (used by the minimap)
---------------------------------------------------------------------------

-- Clip segment to a circle of radius R centred on 0,0. Returns clipped coords or nil.
function Lines.ClipCircle(x1, y1, x2, y2, R)
    local dx, dy = x2 - x1, y2 - y1
    local A = dx * dx + dy * dy
    local in1 = x1 * x1 + y1 * y1 <= R * R
    local in2 = x2 * x2 + y2 * y2 <= R * R
    if in1 and in2 then return x1, y1, x2, y2 end
    if A == 0 then return nil end
    local B = 2 * (x1 * dx + y1 * dy)
    local C = x1 * x1 + y1 * y1 - R * R
    local disc = B * B - 4 * A * C
    if disc < 0 then return nil end
    local sd = sqrt(disc)
    local t1, t2 = (-B - sd) / (2 * A), (-B + sd) / (2 * A)
    local ta, tb = max(0, t1), min(1, t2)
    if ta >= tb then return nil end
    return x1 + dx * ta, y1 + dy * ta, x1 + dx * tb, y1 + dy * tb
end

-- Clip segment to a square |x|,|y| <= R (Liang-Barsky).
function Lines.ClipSquare(x1, y1, x2, y2, R)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local p = { -dx, dx, -dy, dy }
    local q = { x1 + R, R - x1, y1 + R, R - y1 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local t = q[i] / p[i]
            if p[i] < 0 then
                if t > t1 then return nil end
                if t > t0 then t0 = t end
            else
                if t < t0 then return nil end
                if t < t1 then t1 = t end
            end
        end
    end
    return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

