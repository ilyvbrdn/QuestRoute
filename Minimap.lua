-- QuestRoute: route line on the minimap, plus the minimap on/off button.
local ADDON, ns = ...

local holder, surface
local INTERVAL = 1 / 30
local accum = 0
local msin, mcos, sqrt, abs, max = math.sin, math.cos, math.sqrt, math.abs, math.max
local LINE_SCALE = 0.8

-- Fallback minimap diameters in yards per zoom level (same table HereBeDragons uses).
local sizes = {
    indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
    outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 6, [4] = 200, [5] = 133 + 1 / 3 },
}

local function viewRadius()
    if ns.HBDPins and ns.HBDPins.GetMinimapView then
        local r = ns.HBDPins:GetMinimapView()
        if r and r > 0 then return r end
    end
    if C_Minimap and C_Minimap.GetViewRadius then
        return C_Minimap.GetViewRadius()
    end
    local zoom = Minimap:GetZoom()
    local where = (tonumber(GetCVar("minimapZoom")) == zoom) and "outdoor" or "indoor"
    local d = sizes[where][zoom]
    return d and d / 2
end

local function draw()
    surface:Begin()
    if ns:RouteActive() and ns.db.showMinimap then
        local t = ns.target
        local px, py, pinst = ns:PlayerWorld()
        local R = viewRadius()
        if px and R and R > 0 then
            local w, h = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
            local s, c
            if GetCVar("rotateMinimap") == "1" then
                local f = GetPlayerFacing()
                if f then s, c = msin(f), mcos(f) end
            end
            -- world position -> minimap pixels (relative to the centre)
            local function toMini(wx, wy)
                local dx, dy = px - wx, py - wy
                if s then dx, dy = dx * c - dy * s, dx * s + dy * c end
                return dx / R * w, -dy / R * h
            end

            local th = ns.db.thickness * LINE_SCALE
            local edge = w - th - 1 - (ns.db.outline and ns.db.outlineSize or 0)
            local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
            local clip = square and ns.Lines.ClipSquare or ns.Lines.ClipCircle
            local opts = { scale = LINE_SCALE }
            local flyOpts = { scale = LINE_SCALE, db = ns.flyDb }

            local first = true
            for _, line in ipairs(ns:RoutePolylines()) do
                if line.inst == pinst then
                    local o = line.kind == "travel" and flyOpts or opts
                    local pts = {}
                    local function flush()
                        if #pts >= 2 then surface:DrawPath(Minimap, "CENTER", pts, o) end
                        pts = {}
                    end
                    local ax, ay = toMini(line.pts[1][1], line.pts[1][2])
                    for k = 2, #line.pts do
                        local bx, by = toMini(line.pts[k][1], line.pts[k][2])
                        local sx, sy = ax, ay
                        if first then
                            -- start a few pixels out so the player arrow stays visible
                            local len = sqrt(bx * bx + by * by)
                            local gap = math.min(7, len)
                            if len > 0 then sx, sy = bx / len * gap, by / len * gap end
                            first = false
                        end
                        local x1, y1, x2, y2 = clip(sx, sy, bx, by, edge)
                        if x1 then
                            local last = pts[#pts]
                            if not last or math.abs(last[1] - x1) > 0.5 or math.abs(last[2] - y1) > 0.5 then
                                flush()
                                pts[1] = { x1, y1 }
                            end
                            pts[#pts + 1] = { x2, y2 }
                        else
                            flush()
                        end
                        ax, ay = bx, by
                    end
                    flush()
                end
            end

            if pinst == t.instance then
                local sx, sy = toMini(t.wx, t.wy)
                local inside
                if square then
                    inside = max(abs(sx), abs(sy)) <= edge
                else
                    inside = sx * sx + sy * sy <= edge * edge
                end
                if inside then
                    surface:DrawMarker(Minimap, "CENTER", sx, sy, opts)
                end
            end
        end
    end
    surface:End()
end

---------------------------------------------------------------------------
-- Minimap button (uses LibDBIcon, which Questie ships)
---------------------------------------------------------------------------
local broker
local function updateBroker()
    if not broker then return end
    local v = ns.db.enabled and 1 or 0.45
    broker.iconR, broker.iconG, broker.iconB = v, v, v
end

local function createMinimapButton()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not DBI then return end
    broker = LDB:NewDataObject(ADDON, {
        type = "launcher",
        text = "QuestRoute",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        OnClick = function(_, mouse)
            if mouse == "RightButton" then
                ns:ToggleOptions()
            elseif IsControlKeyDown and IsControlKeyDown() then
                ns:ClearQuest()
                ns:Print("route cleared")
            elseif IsShiftKeyDown() then
                ns:ToggleCompass()
            else
                ns:ToggleRoute()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("QuestRoute")
            tt:AddLine(ns.db.enabled and "|cff40ff40Route on|r" or "|cffff4040Route off|r")
            if ns.target then
                tt:AddLine(ns.target.title, 1, 1, 1)
                if ns.target.name then tt:AddLine(ns.target.name, 0.8, 0.8, 0.8) end
            elseif ns.questId then
                tt:AddLine("No location known for this quest", 1, 0.5, 0.3)
            else
                tt:AddLine("Click a quest in your quest log", 0.8, 0.8, 0.8)
            end
            tt:AddLine(" ")
            tt:AddLine("Left-click: turn route on/off", 0.8, 0.8, 0.8)
            tt:AddLine("Shift-click: turn compass on/off", 0.8, 0.8, 0.8)
            tt:AddLine("Ctrl-click: clear the route", 0.8, 0.8, 0.8)
            tt:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        end,
    })
    DBI:Register(ADDON, broker, ns.db.minimapButton)
    updateBroker()
end

function ns:SetMinimapButtonShown(show)
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    ns.db.minimapButton.hide = not show
    if DBI then
        if show then DBI:Show(ADDON) else DBI:Hide(ADDON) end
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    if holder then return end -- set up once
    holder = CreateFrame("Frame", nil, Minimap)
    holder:SetAllPoints(Minimap)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    surface = ns.Lines:NewSurface(holder)
    holder:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < INTERVAL then return end
        accum = 0
        draw()
    end)
    createMinimapButton()
    ns:OnChange(function()
        updateBroker()
        draw()
    end)
end)
