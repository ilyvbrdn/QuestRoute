-- QuestRoute: settings window (two tabs) with live previews.
local _, ns = ...

local win
local refreshers = {}
local W, H = 400, 600

local function refreshAll()
    for _, fn in ipairs(refreshers) do fn() end
end

local function changed()
    ns:NotifyChanged()
    refreshAll()
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 20, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    return fs
end

local function tooltip(widget, title, text)
    if not text then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- enabledFn (optional): greys the control out when it returns false
local function checkbox(parent, label, x, y, get, set, tip, enabledFn)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    fs:SetText(label)
    cb:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        changed()
    end)
    tooltip(cb, label, tip)
    table.insert(refreshers, function()
        cb:SetChecked(get())
        local on = not enabledFn or enabledFn()
        cb:SetEnabled(on)
        if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.5, 0.5, 0.5) end
    end)
    return cb
end

local function slider(parent, label, x, y, width, minV, maxV, step, fmt, get, set, enabledFn)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 17)
    s:SetPoint("TOPLEFT", x, y - 16)
    s:SetHitRectInsets(0, 0, -6, -6)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 2, 2)
    name:SetText(label)
    local val = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    val:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -2, 2)

    local function round(v) return math.floor(v / step + 0.5) * step end
    s:SetScript("OnValueChanged", function(self, v)
        v = round(v)
        val:SetText(fmt(v))
        if self.updating then return end
        set(v)
        ns:NotifyChanged()
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        if not self:IsEnabled() then return end
        self:SetValue(math.min(maxV, math.max(minV, self:GetValue() + delta * step)))
    end)
    table.insert(refreshers, function()
        s.updating = true
        s:SetValue(get())
        val:SetText(fmt(get()))
        s.updating = false
        local on = not enabledFn or enabledFn()
        s:SetEnabled(on)
        s:SetAlpha(on and 1 or 0.4)
    end)
    return s
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A row of mutually exclusive buttons. options = { {value, label}, ... }
local function choice(parent, x, y, bw, options, get, set)
    local buttons = {}
    for i, o in ipairs(options) do
        local b = button(parent, o[2], bw, function() set(o[1]); changed() end)
        b:SetPoint("TOPLEFT", x + (i - 1) * (bw + 6), y)
        buttons[o[1]] = b
    end
    table.insert(refreshers, function()
        for key, b in pairs(buttons) do
            if key == get() then b:LockHighlight() else b:UnlockHighlight() end
        end
    end)
end

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
local presets = {
    { 1, 0.78, 0.18 }, { 0.2, 0.85, 1 }, { 0.3, 1, 0.4 },
    { 0.75, 0.45, 1 }, { 1, 0.3, 0.3 }, { 1, 1, 1 },
}

local function setColor(c, r, g, b)
    c.r, c.g, c.b = r, g, b
    changed()
end

local function openColorPicker(getColor)
    local c = getColor()
    local r0, g0, b0 = c.r, c.g, c.b
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        setColor(getColor(), r, g, b)
    end
    local function cancel() setColor(getColor(), r0, g0, b0) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0, hasOpacity = false,
            swatchFunc = apply, cancelFunc = cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r0, g0, b0 }
        ColorPickerFrame.func = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame:SetColorRGB(r0, g0, b0)
        ColorPickerFrame:Show()
    end
end

-- Label, custom color swatch and preset swatches. getColor returns the color table to edit.
local function colorRow(parent, label, x, y, getColor, enabledFn)
    local widgets = {}
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x + 2, y - 4)
    fs:SetText(label)

    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(36, 20)
    swatch:SetPoint("TOPLEFT", x + 90, y)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(1, 1, 1, 0.8)
    swatch:SetScript("OnClick", function() openColorPicker(getColor) end)
    tooltip(swatch, "Custom color", "Click to pick any color.")
    table.insert(widgets, swatch)

    for i, p in ipairs(presets) do
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", x + 136 + (i - 1) * 26, y)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(p[1], p[2], p[3], 1)
        b:SetBackdropBorderColor(0, 0, 0, 1)
        b:SetScript("OnClick", function() setColor(getColor(), p[1], p[2], p[3]) end)
        table.insert(widgets, b)
    end

    table.insert(refreshers, function()
        local c = getColor()
        swatch:SetBackdropColor(c.r, c.g, c.b, 1)
        local on = not enabledFn or enabledFn()
        for _, w in ipairs(widgets) do
            w:SetEnabled(on)
            w:SetAlpha(on and 1 or 0.3)
        end
        if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.5, 0.5, 0.5) end
    end)
end

---------------------------------------------------------------------------
-- Line themes: one click sets the look; everything stays adjustable after.
---------------------------------------------------------------------------
local themes = {
    wow = {
        style = "gilded", color = { r = 1, g = 0.82, b = 0.4 }, thickness = 4.5, opacity = 1,
        glow = true, glowStrength = 0.3, animate = false,
        outline = true, outlineSize = 1.5, outlineColor = { r = 0.16, g = 0.08, b = 0.02 }, outlineOpacity = 1,
        markerStyle = "x", markerColor = { r = 0.8, g = 0.1, b = 0.05 },
    },
    treasure = {
        style = "footprints", color = { r = 0.33, g = 0.18, b = 0.06 }, thickness = 5, opacity = 0.95,
        glow = false, animate = false, outline = false,
        markerStyle = "x", markerColor = { r = 0.8, g = 0.1, b = 0.05 },
    },
    modern = {
        style = "dashed", color = { r = 0.2, g = 0.85, b = 1 }, thickness = 4, opacity = 0.9,
        glow = true, glowStrength = 0.6, animate = true,
        outline = true, outlineSize = 1.5, outlineColor = { r = 0, g = 0, b = 0 }, outlineOpacity = 0.85,
        markerStyle = "glow", markerColor = { r = 0.8, g = 0.1, b = 0.05 },
    },
}

local function applyTheme(db, name)
    for k, v in pairs(themes[name]) do
        if type(v) == "table" then
            db[k] = { r = v.r, g = v.g, b = v.b }
        else
            db[k] = v
        end
    end
    db.lineTheme = name
    changed()
end

---------------------------------------------------------------------------
-- Tab: General
---------------------------------------------------------------------------
local function buildGeneralTab(page, db)
    local y = -6
    header(page, "Route", y); y = y - 20
    checkbox(page, "Show route", 20, y, function() return db.enabled end, function(v) db.enabled = v end,
        "Master switch for the route line. The minimap button and key binding do the same.")
    checkbox(page, "Minimap button", 210, y, function() return not db.minimapButton.hide end, function(v) ns:SetMinimapButtonShown(v) end)
    y = y - 26
    checkbox(page, "On world map", 20, y, function() return db.showWorldMap end, function(v) db.showWorldMap = v end)
    checkbox(page, "On minimap", 210, y, function() return db.showMinimap end, function(v) db.showMinimap = v end)
    y = y - 26
    checkbox(page, "Clear when quest is deselected", 20, y, function() return db.clearOnDeselect end, function(v) db.clearOnDeselect = v end,
        "Deselecting or untracking the quest removes the route, the arrow and the compass text. With 'Hide when idle' (Compass tab) the compass disappears too.")
    y = y - 38

    header(page, "Travel", y); y = y - 20
    checkbox(page, "Use flight paths", 20, y, function() return db.useFlights end, function(v) db.useFlights = v; ns.Route:Replan() end,
        "Plan the trip with the flight paths you know when that is faster. Open a flight master's map once to teach QuestRoute which flight paths you have.")
    checkbox(page, "Include locked flights", 210, y, function() return db.assumeAllFlights end, function(v) db.assumeAllFlights = v; ns.Route:Replan() end,
        "Off: only flight paths you have unlocked are used. On: every flight path of your faction is used, even ones you haven't discovered yet.", function() return db.useFlights end)
    y = y - 26
    checkbox(page, "Boats & zeppelins", 20, y, function() return db.useTransports end, function(v) db.useTransports = v; ns.Route:Replan() end,
        "Use boats, zeppelins and the Deeprun Tram. New routes are learned automatically when you ride them.")
    checkbox(page, "Corpse run as a ghost", 210, y, function() return db.corpseRoute end, function(v) db.corpseRoute = v end,
        "After you release, the route points straight to your body. Ghosts can walk on water, so it goes straight across lakes and rivers.")
    y = y - 38

    checkbox(page, "Avoid dangerous areas", 20, y, function() return db.avoidDanger end, function(v) db.avoidDanger = v; ns.Route:Replan() end,
        "Walk around areas whose monsters are well above your level when there's another way. Off: always the shortest way.")
    y = y - 40
    slider(page, "Danger starts at (levels above you)", 20, y, 360, 0, 15, 1, function(v) return "+" .. v end,
        function() return db.dangerMargin end, function(v) db.dangerMargin = v; ns.Route:Replan() end,
        function() return db.avoidDanger end)
    y = y - 46

    header(page, "Roads", y); y = y - 20
    checkbox(page, "Follow learned roads", 20, y, function() return db.useRoads end, function(v) db.useRoads = v; ns.Route:Replan() end,
        "Route along the paths you have travelled instead of straight across hills and lakes.")
    checkbox(page, "Learn roads", 210, y, function() return db.learnRoads end, function(v) db.learnRoads = v end,
        "Record the paths you walk and ride. The more you travel, the better routes follow real roads.")
    y = y - 40
    slider(page, "Prefer roads", 20, y, 170, 1, 3, 0.1, function(v) return ("%.1fx"):format(v) end,
        function() return db.offroadPenalty end, function(v) db.offroadPenalty = v; ns.Route:Replan() end,
        function() return db.useRoads end)
    local forget = button(page, "Forget learned roads", 170, function()
        StaticPopupDialogs["QUESTROUTE_FORGET_ROADS"] = {
            text = "Forget all learned roads? This can't be undone.",
            button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = function() ns.Learn:ResetRoads(); ns.Route:Replan(); refreshAll() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("QUESTROUTE_FORGET_ROADS")
    end)
    forget:SetPoint("TOPLEFT", 210, y - 12)
    y = y - 46

    local known = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    known:SetPoint("TOPLEFT", 24, y)
    known:SetWidth(W - 48)
    known:SetJustifyH("LEFT")
    known:SetSpacing(3)
    table.insert(refreshers, function()
        local nodes = ns.Learn and ns.Learn:RoadStats() or 0
        local learnedT = QuestRouteDB.transports and #QuestRouteDB.transports or 0
        known:SetText(("Flight paths known: %d (open any flight master's map to update).\nRoad points learned: %d.  Boat routes learned: %d."):format(
            ns.Route and ns.Route:KnownCount() or 0, nodes, learnedT))
    end)
    y = y - 40
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 24, y)
    hint:SetWidth(W - 48)
    hint:SetJustifyH("LEFT")
    hint:SetText("Prefer roads: higher values follow known roads even when they are a longer way round. 1.0 = straight lines whenever shorter.")
end

---------------------------------------------------------------------------
-- Tab: Line
---------------------------------------------------------------------------
local function buildLineTab(page, db)
    local preview = CreateFrame("Frame", nil, page, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", 20, -6)
    preview:SetSize(W - 40, 64)
    preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    preview:SetBackdropBorderColor(1, 0.82, 0, 0.3)
    -- parchment-coloured preview, like the world map
    preview:SetBackdropColor(0.62, 0.53, 0.36, 1)
    local surf = ns.Lines:NewSurface(preview)
    local pts = { { 20, 18 }, { 120, 46 }, { 220, 16 }, { 330, 44 } }
    local acc = 0
    preview:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 1 / 30 then return end
        acc = 0
        surf:Begin()
        surf:DrawPath(preview, "BOTTOMLEFT", pts)
        surf:DrawMarker(preview, "BOTTOMLEFT", 330, 44)
        surf:End()
    end)

    local y = -80
    local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 22, y - 4)
    lbl:SetText("Theme")
    local t1 = button(page, "WoW Gold", 96, function() applyTheme(db, "wow") end)
    t1:SetPoint("TOPLEFT", 84, y)
    local t2 = button(page, "Treasure Map", 96, function() applyTheme(db, "treasure") end)
    t2:SetPoint("TOPLEFT", 184, y)
    local t3 = button(page, "Modern", 96, function() applyTheme(db, "modern") end)
    t3:SetPoint("TOPLEFT", 284, y)
    tooltip(t1, "WoW Gold", "Gilded gold line with a dark border and a red X at the destination.")
    tooltip(t2, "Treasure Map", "Ink footprints across the map, ending in a red X.")
    tooltip(t3, "Modern", "Glowing dashed line with a pulsing marker.")
    y = y - 34

    header(page, "Style", y); y = y - 22
    choice(page, 20, y, 66, { { "solid", "Solid" }, { "dashed", "Dashed" }, { "dotted", "Dotted" },
        { "gilded", "Gilded" }, { "footprints", "Prints" } },
        function() return db.style end, function(v) db.style = v end)
    y = y - 32
    colorRow(page, "Line color", 20, y, function() return db.color end)
    y = y - 42
    slider(page, "Thickness", 20, y, 170, 1, 12, 0.5, function(v) return ("%.1f"):format(v) end,
        function() return db.thickness end, function(v) db.thickness = v end)
    slider(page, "Opacity", 210, y, 170, 0.1, 1, 0.05, pct,
        function() return db.opacity end, function(v) db.opacity = v end)
    y = y - 50
    checkbox(page, "Glow", 20, y, function() return db.glow end, function(v) db.glow = v end)
    checkbox(page, "Animate", 110, y, function() return db.animate end, function(v) db.animate = v end,
        "Dashes, dots and footprints move toward your target.",
        function() return db.style ~= "solid" and db.style ~= "gilded" end)
    slider(page, "Glow strength", 210, y + 8, 170, 0, 1, 0.05, pct,
        function() return db.glowStrength end, function(v) db.glowStrength = v end,
        function() return db.glow end)
    y = y - 40

    local hasOutline = function() return db.outline and db.style ~= "footprints" end
    checkbox(page, "Outline", 20, y, function() return db.outline end, function(v) db.outline = v end,
        "A border around the line so it stands out on bright maps.", function() return db.style ~= "footprints" end)
    y = y - 28
    colorRow(page, "Outline color", 20, y, function() return db.outlineColor end, hasOutline)
    y = y - 42
    slider(page, "Outline size", 20, y, 170, 0.5, 4, 0.5, function(v) return ("%.1f"):format(v) end,
        function() return db.outlineSize end, function(v) db.outlineSize = v end, hasOutline)
    slider(page, "Outline opacity", 210, y, 170, 0.1, 1, 0.05, pct,
        function() return db.outlineOpacity end, function(v) db.outlineOpacity = v end, hasOutline)
    y = y - 48

    header(page, "Destination marker", y); y = y - 22
    choice(page, 20, y, 84, { { "glow", "Glow" }, { "x", "X" } },
        function() return db.markerStyle end, function(v) db.markerStyle = v end)
    y = y - 32
    colorRow(page, "X color", 20, y, function() return db.markerColor end, function() return db.markerStyle == "x" end)
end

---------------------------------------------------------------------------
-- Tab: Compass
---------------------------------------------------------------------------
local function buildCompassTab(page, db)
    local hasCompass = function() return db.compassStyle ~= "none" end
    local y = -6
    header(page, "Compass", y); y = y - 20
    checkbox(page, "Show compass", 20, y, function() return db.compass end, function(v) db.compass = v end,
        "Turn the whole compass and arrow off or on. Shift-click on the minimap button does the same.")
    checkbox(page, "Lock position", 210, y, function() return db.compassLocked end, function(v) db.compassLocked = v end,
        "Locked: it can't be dragged and clicks pass through it.")
    y = y - 26
    checkbox(page, "Hide when idle", 20, y, function() return db.compassHideIdle end, function(v) db.compassHideIdle = v end,
        "Hide it when no quest is selected.")
    checkbox(page, "Show text", 210, y, function() return db.compassText end, function(v) db.compassText = v end,
        "Quest name, target and distance underneath.")
    y = y - 26
    checkbox(page, "Show estimated times", 20, y, function() return db.showTimes end, function(v) db.showTimes = v end,
        "Travel time to the next stop and for the whole trip. Flight times are estimates unless the flight has been timed before.",
        function() return db.compassText end)
    y = y - 34

    header(page, "Style", y); y = y - 22
    choice(page, 20, y, 84, { { "gold", "WoW Gold" }, { "modern", "Modern" }, { "bar", "Bar" }, { "none", "None" } },
        function() return db.compassStyle end, function(v) db.compassStyle = v end)
    y = y - 30
    local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 22, y - 4)
    lbl:SetText("Arrow")
    choice(page, 90, y, 92, { { "inside", "Inside" }, { "above", "Above" }, { "below", "Below" } },
        function() return db.arrowPlacement end, function(v) db.arrowPlacement = v end)
    y = y - 32
    checkbox(page, "N / E / S / W", 20, y, function() return db.compassLetters end, function(v) db.compassLetters = v end, nil, hasCompass)
    checkbox(page, "Background", 210, y, function() return db.compassBg end, function(v) db.compassBg = v end, nil, hasCompass)
    y = y - 32
    colorRow(page, "Compass color", 20, y, function() return db.compassColor end,
        function() return db.compassStyle == "modern" or db.compassStyle == "bar" end)
    y = y - 42
    slider(page, "Overall size", 20, y, 170, 0.5, 2, 0.05, pct,
        function() return db.compassScale end, function(v) db.compassScale = v end)
    slider(page, "Compass opacity", 210, y, 170, 0.1, 1, 0.05, pct,
        function() return db.compassOpacity end, function(v) db.compassOpacity = v end, hasCompass)
    y = y - 46
    slider(page, "Background opacity", 20, y, 170, 0, 1, 0.05, pct,
        function() return db.compassBgOpacity end, function(v) db.compassBgOpacity = v end,
        function() return hasCompass() and db.compassBg end)
    slider(page, "Arrived within", 210, y, 170, 3, 40, 1, function(v) return v .. " yd" end,
        function() return db.arriveDistance end, function(v) db.arriveDistance = v end)
    y = y - 50

    header(page, "Position", y); y = y - 20
    checkbox(page, "Snap to screen centre while dragging", 20, y, function() return db.compassSnap end, function(v) db.compassSnap = v end)
    y = y - 30
    local b1 = button(page, "Centre horizontally", 120, function() ns:CenterCompass(true) end)
    b1:SetPoint("TOPLEFT", 20, y)
    local b2 = button(page, "Centre on screen", 120, function() ns:CenterCompass(false) end)
    b2:SetPoint("TOPLEFT", 146, y)
    local b3 = button(page, "Reset", 106, function() db.compassPos = nil; changed() end)
    b3:SetPoint("TOPLEFT", 272, y)
end

---------------------------------------------------------------------------
-- Tab: Arrow
---------------------------------------------------------------------------
local function buildArrowTab(page, db)
    local y = -6
    header(page, "Arrow shape", y); y = y - 22
    choice(page, 20, y, 112, { { "arrow", "Arrow" }, { "chevron", "Chevron" }, { "needle", "Needle" } },
        function() return db.arrowStyle end, function(v) db.arrowStyle = v end)
    y = y - 40

    header(page, "Arrow color", y); y = y - 20
    local tinted = function() return db.arrowStyle ~= "needle" end
    checkbox(page, "Same color as route line", 20, y, function() return db.arrowUseLineColor end,
        function(v) db.arrowUseLineColor = v end, "The needle keeps its own red and white colors.", tinted)
    y = y - 30
    colorRow(page, "Arrow color", 20, y, function() return db.arrowColor end,
        function() return tinted() and not db.arrowUseLineColor end)
    y = y - 34
    colorRow(page, "When arrived", 20, y, function() return db.arrivedColor end)
    y = y - 42
    slider(page, "Arrow size", 20, y, 170, 0.5, 2, 0.05, pct,
        function() return db.arrowScale end, function(v) db.arrowScale = v end)
    slider(page, "Arrow opacity", 210, y, 170, 0.1, 1, 0.05, pct,
        function() return db.arrowOpacity end, function(v) db.arrowOpacity = v end)
    y = y - 50
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 22, y)
    note:SetWidth(W - 44)
    note:SetJustifyH("LEFT")
    note:SetText("Where the arrow sits (inside, above or below the compass) is on the Compass tab. With the Bar style and 'Inside', the arrow is shown as a marker on the bar.")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Resets settings only. Learned data (roads, boat routes, scans) is kept.
local function resetAll(db)
    local keepButton = db.minimapButton
    local keepPos = db.compassPos
    for k, v in pairs(ns.defaults) do
        if type(v) == "table" then
            db[k] = {}
            for k2, v2 in pairs(v) do db[k][k2] = v2 end
        else
            db[k] = v
        end
    end
    db.minimapButton = keepButton
    db.compassPos = keepPos
    changed()
end

local function build()
    local db = ns.db
    win = CreateFrame("Frame", "QuestRouteOptions", UIParent, "BackdropTemplate")
    win:SetSize(W, H + 70)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    tinsert(UISpecialFrames, "QuestRouteOptions")

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("QuestRoute")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- tabs
    local pages, tabs = {}, {}
    local function selectTab(i)
        for j, p in ipairs(pages) do p:SetShown(i == j) end
        for j, t in ipairs(tabs) do
            if i == j then t:LockHighlight() else t:UnlockHighlight() end
        end
    end
    local tabNames = { "General", "Line", "Compass", "Arrow" }
    for i, name in ipairs(tabNames) do
        local t = button(win, name, 86, function() selectTab(i) end)
        t:SetPoint("TOPLEFT", 20 + (i - 1) * 90, -44)
        tabs[i] = t
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", 0, -74)
        page:SetSize(W, H - 40)
        pages[i] = page
    end
    buildGeneralTab(pages[1], db)
    buildLineTab(pages[2], db)
    buildCompassTab(pages[3], db)
    buildArrowTab(pages[4], db)
    selectTab(1)
    win.selectTab = selectTab

    local reset = button(win, "Reset all settings", 150, function() resetAll(db) end)
    reset:SetPoint("BOTTOMLEFT", 20, 34)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 18)
    hint:SetText("/qroute  ·  /qroute toggle  ·  /qroute compass  ·  /qroute debug")

    win:SetScript("OnShow", function()
        ns.optionsOpen = true
        refreshAll()
        ns:NotifyChanged()
    end)
    win:SetScript("OnHide", function()
        ns.optionsOpen = false
        ns:NotifyChanged()
    end)
    win:Hide()
end

-- forceShow: true = show, false = hide, nil = toggle. tab: optional tab to open (1 line, 2 compass, 3 arrow)
function ns:ToggleOptions(forceShow, tab)
    if not self.db then return end
    if not win then build() end
    local show
    if forceShow == nil then show = not win:IsShown() else show = forceShow end
    if show then
        win:Show()
        if tab and win.selectTab then win.selectTab(tab) end
    else
        win:Hide()
        self.optionsFromEditMode = false
    end
end

-- Also list QuestRoute in Blizzard's AddOns options with a button that opens our window.
function ns:InitOptions()
    pcall(function()
        local panel = CreateFrame("Frame")
        panel.name = "QuestRoute"
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(220, 26)
        b:SetPoint("TOPLEFT", 16, -16)
        b:SetText("Open QuestRoute settings")
        b:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
            ns:ToggleOptions(true)
        end)
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, "QuestRoute")
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end
