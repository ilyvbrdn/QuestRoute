-- QuestRoute: route line on the world map, plus an on/off button on the map.
local _, ns = ...
local CreateFrame = ns.CreateFrame -- (protected scripts: see Core.lua)

local holder, surface, button
local FRAME_INTERVAL = 1 / 30
local accum = 0

local function canvasScale()
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then
        local s = sc:GetCanvasScale()
        if s and s > 0 then return s end
    end
    return 1
end

local function toCanvas(wx, wy, instance, mapId, w, h)
    local x, y = ns.HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, instance, mapId, true)
    if not x then return end
    return x * w, -y * h
end

local function draw()
    surface:Begin()
    if ns:RouteActive() and ns.db.showWorldMap and ns.HBD then
        local mapId = WorldMapFrame:GetMapID()
        local t = ns.target
        local canvas = WorldMapFrame:GetCanvas()
        local w, h = canvas:GetWidth(), canvas:GetHeight()
        local opts = { scale = 1 / canvasScale() }
        local flyOpts = { scale = opts.scale, db = ns.flyDb }
        for _, line in ipairs(ns:RoutePolylines()) do
            local pts = {}
            local function flush()
                if #pts >= 2 then
                    surface:DrawPath(canvas, "TOPLEFT", pts, line.kind == "travel" and flyOpts or opts)
                end
                pts = {}
            end
            for _, p in ipairs(line.pts) do
                local cx, cy = toCanvas(p[1], p[2], line.inst, mapId, w, h)
                if cx then pts[#pts + 1] = { cx, cy } else flush() end
            end
            flush()
        end
        local tx, ty = toCanvas(t.wx, t.wy, t.instance, mapId, w, h)
        if tx then
            surface:DrawMarker(canvas, "TOPLEFT", tx, ty, opts)
        end
    end
    surface:End()
end

-- Sit above the map artwork but below quest icons where the client tells us
-- the right level; otherwise go on top so the line is never hidden.
local function placeHolder()
    local canvas = WorldMapFrame:GetCanvas()
    local level
    if WorldMapFrame.GetPinFrameLevelsManager then
        local ok, lvl = pcall(function()
            return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
        end)
        if ok and type(lvl) == "number" then level = lvl end
    end
    holder:SetFrameLevel(level or (canvas:GetFrameLevel() + 2000))
end

local function updateButton()
    if not button then return end
    local on = ns.db.enabled
    button.icon:SetDesaturated(not on)
    button.icon:SetVertexColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
    button.off:SetShown(not on)
end

local function createButton()
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    button = CreateFrame("Button", nil, parent)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 6, 6)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    button.icon:SetSize(17, 17)
    button.icon:SetPoint("TOPLEFT", 7, -6)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.off = button:CreateTexture(nil, "OVERLAY")
    button.off:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    button.off:SetSize(14, 14)
    button.off:SetPoint("BOTTOMRIGHT", -4, 4)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns:ToggleOptions()
        else
            ns:ToggleRoute()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("QuestRoute")
        GameTooltip:AddLine(ns.db.enabled and "|cff40ff40Route on|r" or "|cffff4040Route off|r")
        if ns.target then
            GameTooltip:AddLine(ns.target.title, 1, 1, 1)
        end
        GameTooltip:AddLine("Left-click: turn route on/off", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Ctrl + right-click the map: route to that spot", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Waypoint button: click it, then click the map to route there.
---------------------------------------------------------------------------
local wpButton, catcher

local function setPlacing(on)
    catcher:SetShown(on)
    wpButton.glow:SetShown(on)
end

local function placeWaypointAtCursor()
    local mapId = WorldMapFrame:GetMapID()
    local x, y
    if WorldMapFrame.GetNormalizedCursorPosition then
        x, y = WorldMapFrame:GetNormalizedCursorPosition()
    end
    if not (mapId and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    local info = C_Map.GetMapInfo(mapId)
    local name = ("%s %.1f, %.1f"):format(info and info.name or "Map", x * 100, y * 100)
    ns:SetCustomTarget(mapId, x, y, name)
    ns:Print("waypoint set: " .. name)
    return true
end

local function createWaypointButton()
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    wpButton = CreateFrame("Button", nil, parent)
    wpButton:SetSize(31, 31)
    wpButton:SetFrameStrata("HIGH")
    wpButton:SetPoint("LEFT", button, "RIGHT", 2, 0)
    wpButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = wpButton:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = wpButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "MarkerX")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 8, -7)
    icon:SetVertexColor(0.9, 0.2, 0.1)
    local border = wpButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    wpButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    wpButton.glow = wpButton:CreateTexture(nil, "OVERLAY")
    wpButton.glow:SetTexture(ns.MEDIA .. "GlowDot")
    wpButton.glow:SetSize(44, 44)
    wpButton.glow:SetPoint("CENTER", 0, 0)
    wpButton.glow:SetVertexColor(1, 0.8, 0.2, 0.9)
    wpButton.glow:Hide()

    -- invisible layer over the map that takes the next click while placing
    catcher = CreateFrame("Button", nil, parent)
    catcher:SetAllPoints(parent)
    catcher:SetFrameStrata("HIGH")
    catcher:SetFrameLevel(wpButton:GetFrameLevel() - 1)
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:Hide()
    local hint = catcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hint:SetPoint("TOP", catcher, "TOP", 0, -12)
    hint:SetText("Click the map to set a waypoint  |cffaaaaaa(right-click to cancel)|r")
    catcher:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" then placeWaypointAtCursor() end
        setPlacing(false)
    end)
    WorldMapFrame:HookScript("OnHide", function() setPlacing(false) end)

    wpButton:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            setPlacing(false)
            if ns.custom then
                ns:SetCustomTarget(nil)
                ns:Print("waypoint removed")
            end
        else
            setPlacing(not catcher:IsShown())
        end
    end)
    wpButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("QuestRoute waypoint")
        GameTooltip:AddLine("Left-click, then click the map: route to that spot", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: remove the waypoint", 0.8, 0.8, 0.8)
        if ns.custom then GameTooltip:AddLine("Current: " .. ns.custom.name, 1, 1, 1) end
        GameTooltip:Show()
    end)
    wpButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- coordinate box: "45 63" or "Elwynn 45 63", Enter to route there
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(150, 20)
    box:SetPoint("LEFT", wpButton, "RIGHT", 8, 0)
    box:SetFrameStrata("HIGH")
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    local ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 2, 0)
    ph:SetText("Go to: 45 63 or zone 45 63")
    local function updatePh() ph:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", updatePh)
    box:SetScript("OnEditFocusLost", updatePh)
    box:SetScript("OnTextChanged", updatePh)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        local mapId, x, y, label = ns:ParseCoords(self:GetText(), WorldMapFrame:GetMapID())
        if mapId then
            ns:SetCustomTarget(mapId, x, y, label)
            ns:Print("routing to " .. label)
            self:SetText("")
            self:ClearFocus()
        else
            ns:Print(x)
        end
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Route to coordinates")
        GameTooltip:AddLine("45 63  -  on the map you're looking at", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Elwynn 45 63  -  in a zone (part of the name is enough)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Also in chat: /way elwynn 45 63", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updatePh()

    ns.waypointUI = { button = wpButton, catcher = catcher, box = box } -- for tests
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    if holder then return end -- set up once
    if not WorldMapFrame or not WorldMapFrame.GetCanvas then
        ns:Print("world map not found; map line disabled")
        return
    end
    local canvas = WorldMapFrame:GetCanvas()
    holder = CreateFrame("Frame", nil, canvas)
    holder:SetAllPoints(canvas)
    surface = ns.Lines:NewSurface(holder)
    placeHolder()

    -- redraw only when something that shows has changed: the route, the map shown, its zoom or
    -- size, the settings, or you moving a couple of yards (the line starts where you stand)
    local lastSig
    local function signature()
        local px, py = 0, 0
        if ns.HBD then
            local x, y = ns.HBD:GetPlayerWorldPosition()
            if x then px, py = math.floor(x / 2), math.floor(y / 2) end
        end
        local canvas = WorldMapFrame:GetCanvas()
        local wp = ns.waypoint
        return table.concat({ tostring(ns.route), tostring(ns.target), wp and wp.index or 0, WorldMapFrame:GetMapID() or 0,
            ("%.4f"):format(canvasScale()), math.floor(canvas:GetWidth()), math.floor(canvas:GetHeight()),
            px, py, ns.db.enabled and 1 or 0, ns.db.showWorldMap and 1 or 0, ns.settingsVersion or 0 }, ":")
    end
    holder:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < FRAME_INTERVAL then return end
        accum = 0
        local sig = signature()
        if sig ~= lastSig then lastSig = sig; draw() end
    end)
    WorldMapFrame:HookScript("OnShow", function()
        placeHolder()
        lastSig = nil -- always draw when the map opens
        accum = FRAME_INTERVAL
    end)

    -- Ctrl + right-click on the map: route to that spot. Captured on mouse-down,
    -- before the map reacts to the right-click.
    local sc = WorldMapFrame.ScrollContainer or WorldMapFrame
    sc:HookScript("OnMouseDown", function(_, mouse)
        if mouse ~= "RightButton" or not IsControlKeyDown() then return end
        local mapId = WorldMapFrame:GetMapID()
        local x, y
        if WorldMapFrame.GetNormalizedCursorPosition then
            x, y = WorldMapFrame:GetNormalizedCursorPosition()
        elseif sc.GetNormalizedCursorPosition then
            x, y = sc:GetNormalizedCursorPosition()
        end
        if not (mapId and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
        local c = ns.custom
        if c and c.mapId == mapId and math.abs(c.x - x) < 0.015 and math.abs(c.y - y) < 0.015 then
            ns:SetCustomTarget(nil)
            ns:Print("map marker removed")
            return
        end
        local info = C_Map.GetMapInfo(mapId)
        local name = ("%s %.1f, %.1f"):format(info and info.name or "Map", x * 100, y * 100)
        ns:SetCustomTarget(mapId, x, y, name)
        ns:Print("routing to " .. name .. " (Ctrl + right-click it again to remove)")
    end)

    createButton()
    createWaypointButton()
    updateButton()
    ns:OnChange(function()
        updateButton()
        ns.settingsVersion = (ns.settingsVersion or 0) + 1 -- (settings or route changed: redraw)
        if WorldMapFrame:IsShown() then draw() end
    end)
end)
