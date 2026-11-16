-- QuestRoute: on-screen compass pointing at the quest target.
-- Styles: gold ring (WoW-like), modern ring, horizontal bar, or arrow only.
-- The arrow can sit inside the compass, above it or below it.
local _, ns = ...

local DIAL = 110
local BAR_W, BAR_H = 300, 34
local FOV = math.pi -- the bar shows 180 degrees
local SNAP = 18
local PI, TAU = math.pi, math.pi * 2
local msin, mcos, floor, abs = math.sin, math.cos, math.floor, math.abs

local f, dial, bar, arrow, title, sub, info
local dialBg, ringModern, ringGold, letters
local barBg, barEdge, barNotch, barMarker, barTicks, barLabels
local guideV, guideH
local arrowEnabled = true

local ARROW_TEX = { arrow = "Arrow", chevron = "Chevron", needle = "Needle" }

local function norm(a)
    a = a % TAU
    if a > PI then a = a - TAU end
    return a
end

---------------------------------------------------------------------------
-- Position, snapping and guides
---------------------------------------------------------------------------
local function centerOffset()
    local fx, fy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return fx * s - ux, fy * s - uy
end

local function applyPosition()
    f:ClearAllPoints()
    local p = ns.db.compassPos
    local sc = f:GetScale()
    if p and p.x then
        f:SetPoint("CENTER", UIParent, "CENTER", p.x / sc, p.y / sc)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -80 / sc)
    end
end

local function savePosition()
    local dx, dy = centerOffset()
    if ns.db.compassSnap then
        if abs(dx) < SNAP then dx = 0 end
        if abs(dy) < SNAP then dy = 0 end
    end
    ns.db.compassPos = { x = dx, y = dy }
    applyPosition()
end

function ns:CenterCompass(horizontalOnly)
    if not f then return end
    local _, dy = centerOffset()
    self.db.compassPos = { x = 0, y = horizontalOnly and dy or 0 }
    applyPosition()
end

local function createGuides()
    local function guide(vertical)
        local t = UIParent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0.2, 0.7)
        if vertical then
            t:SetWidth(1)
            t:SetPoint("TOP", UIParent, "TOP")
            t:SetPoint("BOTTOM", UIParent, "BOTTOM")
        else
            t:SetHeight(1)
            t:SetPoint("LEFT", UIParent, "LEFT")
            t:SetPoint("RIGHT", UIParent, "RIGHT")
        end
        t:Hide()
        return t
    end
    guideV, guideH = guide(true), guide(false)
end

local function updateGuides()
    if not f.dragging or not ns.db.compassSnap then
        guideV:Hide(); guideH:Hide()
        return
    end
    local dx, dy = centerOffset()
    guideV:SetShown(abs(dx) < SNAP)
    guideH:SetShown(abs(dy) < SNAP)
end

---------------------------------------------------------------------------
-- Layout: which parts are visible and where the arrow goes
---------------------------------------------------------------------------
local function layout()
    local db = ns.db
    local style = db.compassStyle
    local place = db.arrowPlacement
    local main

    dial:SetShown(style == "gold" or style == "modern")
    bar:SetShown(style == "bar")
    if style == "gold" or style == "modern" then main = dial elseif style == "bar" then main = bar end

    -- container size = the compass part (or the arrow alone)
    local arrowSize
    if not main then
        arrowSize = DIAL * 0.7 * db.arrowScale
        f:SetSize(arrowSize, arrowSize)
    elseif main == dial then
        f:SetSize(DIAL, DIAL)
        arrowSize = DIAL * (place == "inside" and 0.5 or 0.42) * db.arrowScale
    else
        f:SetSize(BAR_W, BAR_H)
        arrowSize = DIAL * 0.42 * db.arrowScale
    end

    arrowEnabled = not (main == bar and place == "inside")
    arrow:ClearAllPoints()
    arrow:SetSize(arrowSize, arrowSize)
    local lowest = f
    if not main or place == "inside" then
        arrow:SetPoint("CENTER", f, "CENTER")
    elseif place == "above" then
        arrow:SetPoint("BOTTOM", f, "TOP", 0, 4)
    else
        arrow:SetPoint("TOP", f, "BOTTOM", 0, -4)
        lowest = arrow
    end
    arrow:SetTexture(ns.MEDIA .. (ARROW_TEX[db.arrowStyle] or "Arrow"))

    title:ClearAllPoints()
    title:SetPoint("TOP", lowest, "BOTTOM", 0, -4)

    -- dial parts
    local gold = style == "gold"
    ringGold:SetShown(gold)
    ringModern:SetShown(not gold)
    dialBg:SetSize(gold and DIAL * 0.8 or DIAL - 6, gold and DIAL * 0.8 or DIAL - 6)
    letters.radius = gold and (DIAL / 2 - 21) or (DIAL / 2 - 14)
end

---------------------------------------------------------------------------
-- Drawing every frame
---------------------------------------------------------------------------
local function arrowColor(arrived)
    local db = ns.db
    local c
    if arrived then
        c = db.arrivedColor
    elseif db.arrowStyle == "needle" then
        c = { r = 1, g = 1, b = 1 }
    else
        c = db.arrowUseLineColor and db.color or db.arrowColor
    end
    arrow:SetVertexColor(c.r, c.g, c.b, db.arrowOpacity)
    barMarker:SetVertexColor(c.r, c.g, c.b, db.arrowOpacity)
end

local function updateDial(facing)
    local db = ns.db
    local show = db.compassLetters and facing
    for _, l in ipairs(letters) do
        if show then
            local rel = l.bearing - facing
            l:SetPoint("CENTER", dial, "CENTER", -msin(rel) * letters.radius, mcos(rel) * letters.radius)
            l:Show()
        else
            l:Hide()
        end
    end
end

local function barX(rel)
    return -rel * (BAR_W / FOV)
end

local function updateBar(facing, targetAngle)
    local db = ns.db
    local half = BAR_W / 2 - 8
    for _, t in ipairs(barTicks) do
        if facing then
            local x = barX(norm(t.bearing - facing))
            if abs(x) <= half then
                t:SetPoint("CENTER", bar, "CENTER", x, t.major and -6 or -8)
                t:SetAlpha(1 - (abs(x) / half) ^ 3)
                t:Show()
            else
                t:Hide()
            end
        else
            t:Hide()
        end
    end
    for _, l in ipairs(barLabels) do
        if facing and db.compassLetters then
            local x = barX(norm(l.bearing - facing))
            if abs(x) <= half then
                l:SetPoint("CENTER", bar, "CENTER", x, 4)
                l:SetAlpha((1 - (abs(x) / half) ^ 3) * db.compassOpacity)
                l:Show()
            else
                l:Hide()
            end
        else
            l:Hide()
        end
    end
    if facing and targetAngle then
        local rel = norm(targetAngle - facing)
        local x = barX(rel)
        barMarker:ClearAllPoints()
        if abs(x) <= half then
            barMarker:SetRotation(PI)
            barMarker:SetPoint("CENTER", bar, "CENTER", x, 2)
        else
            -- off the bar: sit at the edge pointing sideways
            local left = x < 0
            barMarker:SetRotation(left and PI / 2 or -PI / 2)
            barMarker:SetPoint("CENTER", bar, "CENTER", left and -half or half, 2)
        end
        barMarker:Show()
    else
        barMarker:Hide()
    end
end

local function update()
    local db = ns.db
    local t = ns.target
    local facing = GetPlayerFacing and GetPlayerFacing()
    local style = db.compassStyle

    local showText = db.compassText
    title:SetShown(showText); sub:SetShown(showText); info:SetShown(showText)

    local angle, dist, otherContinent
    local arrived = false
    if not ns.questId and not t then
        if ns.optionsOpen then
            angle, dist = (GetTime() * 0.8) % TAU + (facing or 0), 123
            title:SetText("Compass preview")
            sub:SetText("Select a quest to start a route")
            info:SetText(db.showTimes and "123 yd  |cffaaaaaa~0:18|r" or "123 yd")
        else
            title:SetText("No quest selected")
            sub:SetText("Click a quest in your quest log")
            info:SetText("")
        end
    elseif t and ns:RoutePaused() then
        title:SetText(t.title)
        sub:SetText("|cff999999Route paused inside here|r")
        info:SetText("|cff999999It comes back when you're outside|r")
    elseif not t then
        title:SetText(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(ns.questId) or "Quest")
        sub:SetText("|cffff8040No location known for this quest|r")
        info:SetText("|cff999999type /qroute debug for details|r")
    else
        title:SetText(t.title)
        local wp = ns.waypoint
        local warn
        local myLevel = UnitLevel and UnitLevel("player") or 0
        local limit = myLevel + (db.dangerMargin or 3)
        if ns.route and ns.route.maxLevel and ns.route.maxLevel > limit then
            if ns.route.enemyTown then
                local enemy = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "Horde" or "Alliance"
                warn = ("|cffff5040passes a %s town!|r"):format(enemy)
            else
                warn = ("|cffff5040level %d area on the way!|r"):format(ns.route.maxLevel)
            end
        elseif ns.route and ns.route.goalLevel and ns.route.goalLevel > limit then
            warn = ("|cffffa040destination is a level %d area|r"):format(ns.route.goalLevel)
        end
        if wp and wp.text then
            sub:SetText("|cff80d0ff" .. wp.text .. "|r")
        elseif t.approx then
            sub:SetText("|cffffb040Exact spot unknown: " .. (t.name or "") .. "|r")
        else
            sub:SetText(t.name or "")
        end
        angle, dist, otherContinent = ns:VectorToTarget()
        if otherContinent then
            info:SetText("|cffffb040On another continent|r")
        elseif not angle or not facing then
            angle = nil
            info:SetText("|cff999999Position unavailable here|r")
        elseif t.approx and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") == t.mapId then
            info:SetText("|cffffb040You're in the right zone. Check the quest text.|r")
        elseif dist <= db.arriveDistance and not (wp and not wp.final) then
            arrived = true
            info:SetText("|cff60ff60You have arrived|r")
        else
            if wp and wp.pathDist and wp.pathDist > dist then dist = wp.pathDist end -- (along the route)
            local text = ("%d yd"):format(dist)
            local speed = GetUnitSpeed("player")
            if db.showTimes and speed and speed > 0 then
                text = text .. "  |cffaaaaaa~" .. ("%d:%02d"):format(floor(dist / speed / 60), floor(dist / speed % 60)) .. "|r"
            end
            if db.showTimes and ns.route and ns.route.total then
                local tt = ns.route.total
                text = text .. ("  |cff80d0fftrip ~%d:%02d|r"):format(floor(tt / 60), floor(tt % 60))
            end
            if warn then text = text .. "  " .. warn end
            info:SetText(text)
        end
    end

    arrowColor(arrived)
    if angle and facing and arrowEnabled then
        arrow:SetRotation(angle - facing)
        arrow:Show()
    else
        arrow:Hide()
    end

    if style == "gold" or style == "modern" then
        updateDial(facing)
    elseif style == "bar" then
        updateBar(facing, angle)
    end
end

function ns:RefreshCompass()
    if not f then return end
    local db = self.db
    f:SetScale(db.compassScale)
    f:EnableMouse(self.editMode or not db.compassLocked)
    if f.editBox then f.editBox:SetShown(self.editMode and true or false) end
    layout()

    local c = db.compassColor
    ringModern:SetVertexColor(c.r, c.g, c.b, db.compassOpacity)
    ringGold:SetVertexColor(1, 1, 1, db.compassOpacity)
    dialBg:SetVertexColor(0, 0, 0, db.compassBgOpacity)
    dialBg:SetShown(db.compassBg)
    for _, l in ipairs(letters) do
        if l.north then l:SetTextColor(1, 0.3, 0.3, db.compassOpacity)
        else l:SetTextColor(c.r, c.g, c.b, db.compassOpacity) end
    end
    barBg:SetVertexColor(0, 0, 0, db.compassBgOpacity)
    barBg:SetShown(db.compassBg)
    barEdge:SetVertexColor(c.r, c.g, c.b, db.compassOpacity)
    barNotch:SetVertexColor(c.r, c.g, c.b, db.compassOpacity)
    for _, tk in ipairs(barTicks) do tk:SetVertexColor(c.r, c.g, c.b, db.compassOpacity) end
    for _, l in ipairs(barLabels) do
        if l.north then l:SetTextColor(1, 0.3, 0.3) else l:SetTextColor(c.r, c.g, c.b) end
    end

    applyPosition()
    local idle = (self.questId == nil and self.target == nil)
    f:SetShown(db.compass and (self.editMode or self.optionsOpen or not (db.compassHideIdle and idle)))
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function buildDial()
    dial = CreateFrame("Frame", nil, f)
    dial:SetSize(DIAL, DIAL)
    dial:SetPoint("CENTER")

    dialBg = dial:CreateTexture(nil, "BACKGROUND")
    dialBg:SetTexture(ns.MEDIA .. "Dot")
    dialBg:SetPoint("CENTER")

    ringModern = dial:CreateTexture(nil, "BORDER")
    ringModern:SetTexture(ns.MEDIA .. "Ring")
    ringModern:SetAllPoints()
    ringGold = dial:CreateTexture(nil, "BORDER")
    ringGold:SetTexture(ns.MEDIA .. "RingGold")
    ringGold:SetAllPoints()

    letters = { radius = DIAL / 2 - 14 }
    for _, c in ipairs({ { "N", 0, true }, { "W", PI / 2 }, { "S", PI }, { "E", PI * 1.5 } }) do
        local l = dial:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetText(c[1])
        l.bearing, l.north = c[2], c[3]
        table.insert(letters, l)
    end
end

local function buildBar()
    bar = CreateFrame("Frame", nil, f)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("CENTER")

    barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(ns.MEDIA .. "BarBg")
    barBg:SetAllPoints()
    barEdge = bar:CreateTexture(nil, "BORDER")
    barEdge:SetTexture(ns.MEDIA .. "BarEdge")
    barEdge:SetAllPoints()

    barNotch = bar:CreateTexture(nil, "ARTWORK")
    barNotch:SetTexture(ns.MEDIA .. "Arrow")
    barNotch:SetSize(12, 12)
    barNotch:SetPoint("BOTTOM", bar, "BOTTOM", 0, -4)

    barTicks, barLabels = {}, {}
    for deg = 0, 345, 15 do
        if deg % 45 ~= 0 then
            local t = bar:CreateTexture(nil, "ARTWORK")
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            local major = (deg % 45 == 0)
            t:SetSize(1, 6)
            t.bearing = math.rad(deg)
            t.major = major
            table.insert(barTicks, t)
        end
    end
    local names = { [0] = "N", [45] = "NW", [90] = "W", [135] = "SW", [180] = "S", [225] = "SE", [270] = "E", [315] = "NE" }
    for deg, name in pairs(names) do
        local cardinal = deg % 90 == 0
        local l = bar:CreateFontString(nil, "OVERLAY", cardinal and "GameFontNormal" or "GameFontNormalSmall")
        l:SetText(name)
        l.bearing = math.rad(deg)
        l.north = (deg == 0)
        table.insert(barLabels, l)
    end

    barMarker = bar:CreateTexture(nil, "OVERLAY")
    barMarker:SetTexture(ns.MEDIA .. "Arrow")
    barMarker:SetSize(18, 18)
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    if f then return end -- set up once
    f = CreateFrame("Frame", "QuestRouteCompass", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ns.db.compassLocked and not ns.editMode then return end
        self.dragging = true
        self.didDrag = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:StopMovingOrSizing()
        savePosition()
        updateGuides()
    end)
    f:SetScript("OnMouseDown", function(self) self.didDrag = false end)
    f:SetScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" and IsShiftKeyDown() then
            ns:ClearQuest()
            ns:Print("route cleared")
        elseif mouse == "RightButton" then
            ns:ToggleOptions(nil, 3)
        elseif ns.editMode and not self.didDrag then
            -- clicking the compass in Edit Mode opens its settings, like Blizzard's HUD elements
            ns:ToggleOptions(true, 3)
            ns.optionsFromEditMode = true
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("QuestRoute compass")
        GameTooltip:AddLine("Drag to move (snaps to the screen centre).", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click for settings.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift + right-click to clear the route.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buildDial()
    buildBar()

    arrow = f:CreateTexture(nil, "OVERLAY")

    title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetWidth(260)
    title:SetWordWrap(false)
    sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetWidth(260)
    sub:SetWordWrap(false)
    info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", sub, "BOTTOM", 0, -2)

    createGuides()

    local accum = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < 0.02 then return end
        accum = 0
        update()
        updateGuides()
    end)

    -- Edit Mode highlight (blue box like Blizzard's HUD elements)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", -6, 6)
    box:SetPoint("BOTTOMRIGHT", 6, -6)
    box:SetFrameLevel(f:GetFrameLevel() + 10)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    box:SetBackdropColor(0.25, 0.6, 1, 0.18)
    box:SetBackdropBorderColor(0.35, 0.7, 1, 0.9)
    box:EnableMouse(false)
    local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("BOTTOM", box, "TOP", 0, 2)
    lbl:SetText("QuestRoute Compass")
    box:Hide()
    f.editBox = box

    ns:RefreshCompass()
    ns:OnChange(function() ns:RefreshCompass() end)
end)

---------------------------------------------------------------------------
-- Blizzard Edit Mode support
---------------------------------------------------------------------------
local function setEditMode(on)
    if (ns.editMode and true or false) == on then return end
    ns.editMode = on
    if not on and ns.optionsFromEditMode then
        ns.optionsFromEditMode = false
        ns:ToggleOptions(false)
    end
    ns:NotifyChanged()
end

local editHook = CreateFrame("Frame")
editHook:RegisterEvent("PLAYER_LOGIN")
editHook:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents() -- set up once
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() setEditMode(true) end, editHook)
        EventRegistry:RegisterCallback("EditMode.Exit", function() setEditMode(false) end, editHook)
    end
    if EditModeManagerFrame then
        if EditModeManagerFrame.EnterEditMode then
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() setEditMode(true) end)
        end
        if EditModeManagerFrame.ExitEditMode then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() setEditMode(false) end)
        end
    end
end)
