local _, ns = ...

-- Shared helpers for EasyFishing: client check, colours, backdrops, saved-table access, the toggle
-- switch, button and slider widgets, the checkbox row factory and the saved-variable defaults.

-----------------------------
-- Client
-----------------------------
do
    local _, _, _, tocVersion = GetBuildInfo()
    ns.IS_FOREVER = type(tocVersion) == "number" and tocVersion < 20000
end

ns.CYAN = { r = 0.220, g = 0.741, b = 0.973 }   -- Tailwind sky-400 (#38bdf8)
local CYAN = ns.CYAN
ns.COLORS = {
    -- Surface elevation layers (7% → 11% → 16-19% luminance staircase)
    bgFrame      = { 0.09, 0.09, 0.12, 0.97 },   -- frame chrome
    bgCard       = { 0.16, 0.16, 0.19, 1.00 },   -- elevated card surface

    -- Controls
    bgControl    = { 0.08, 0.08, 0.10, 1.00 },
    bgControlHov = { 0.12, 0.12, 0.15, 1.00 },

    -- Borders (barely visible — elevation does the work)
    border      = { 0.20, 0.20, 0.24, 0.30 },

    -- Toggle
    toggleOffBg   = { 0.06, 0.06, 0.08, 1.00 },
    toggleOffKnob = { 0.50, 0.50, 0.53 },
    toggleOnBg    = { 0.031, 0.184, 0.286, 1.00 },   -- Tailwind sky-950-ish

    -- Text hierarchy
    textLabel  = { 0.85, 0.85, 0.87 },

    -- Dividers
    divider = { 0.18, 0.18, 0.22, 0.40 },
}
local C = ns.COLORS
local THIN_EDGE = "Interface\\Buttons\\WHITE8X8"
ns.BACKDROP_PANEL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = THIN_EDGE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
function ns.IsSecretV(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Shared helpers: one place for the saved tables, the chat tag and the panel backdrop.
ns.TAG = "|cff38BDF8EasyFishing|r"

function ns.DB()
    EasyFishingDB = EasyFishingDB or {}
    return EasyFishingDB
end

function ns.CharDB()
    EasyFishingCharDB = EasyFishingCharDB or {}
    return EasyFishingCharDB
end

-- v, or nil while the client hides it from addons (a "secret" value)
function ns.Unsecret(v)
    if ns.IsSecretV(v) then return nil end
    return v
end

-- the dark panel look: bgFrame fill, border at 0.8
function ns.ApplyPanelBackdrop(frame)
    frame:SetBackdrop(ns.BACKDROP_PANEL)
    frame:SetBackdropColor(C.bgFrame[1], C.bgFrame[2], C.bgFrame[3], C.bgFrame[4])
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.8)
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if not (frame and frame.AddMessage) then return end
    local n = select("#", ...)
    if n == 1 then
        frame:AddMessage(tostring((...)))
    else
        local parts = {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        frame:AddMessage(table.concat(parts, " "))
    end
end

-- BEGIN Ticker (plain API only)
ns.Ticker = {}
function ns.Ticker.New(interval, fn)
    local host = CreateFrame("Frame")
    local ag = host:CreateAnimationGroup()
    local anim = ag:CreateAnimation("Animation")
    anim:SetDuration(interval)
    ag:SetLooping("REPEAT")
    local t = { _ag = ag, _host = host }
    function t:Cancel()
        self._cancelled = true
        ag:Stop()
    end
    ag:SetScript("OnLoop", function()
        if not t._cancelled then fn(t) end
    end)
    ag:Play()
    return t
end
-- END Ticker
ns.BACKDROP_CONTROL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = THIN_EDGE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
ns.SWITCH_TEXT_X = 44 + 8

function ns.CreateToggleSwitch(parent, globalName)
    local TRACK_W, TRACK_H = 44, 22
    local KNOB_SIZE = 18
    local KNOB_OFF_X, KNOB_ON_X = 2, TRACK_W - KNOB_SIZE - 2
    local R = TRACK_H / 2

    local sw = CreateFrame("Button", globalName, parent)
    sw:SetSize(TRACK_W, TRACK_H)
    sw:RegisterForClicks("LeftButtonUp")

    -- Pill-shaped track: left cap (circle) + center fill + right cap (circle)
    local trackCenter = sw:CreateTexture(nil, "BACKGROUND")
    trackCenter:SetPoint("TOPLEFT", R, 0)
    trackCenter:SetPoint("BOTTOMRIGHT", -R, 0)

    local trackLeft = sw:CreateTexture(nil, "BACKGROUND")
    trackLeft:SetSize(TRACK_H, TRACK_H)
    trackLeft:SetPoint("LEFT", 0, 0)
    local maskLeft = sw:CreateMaskTexture()
    maskLeft:SetAllPoints(trackLeft)
    maskLeft:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackLeft:AddMaskTexture(maskLeft)

    local trackRight = sw:CreateTexture(nil, "BACKGROUND")
    trackRight:SetSize(TRACK_H, TRACK_H)
    trackRight:SetPoint("RIGHT", 0, 0)
    local maskRight = sw:CreateMaskTexture()
    maskRight:SetAllPoints(trackRight)
    maskRight:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackRight:AddMaskTexture(maskRight)

    local function SetTrackColor(r, g, b, a)
        trackLeft:SetColorTexture(r, g, b, a)
        trackCenter:SetColorTexture(r, g, b, a)
        trackRight:SetColorTexture(r, g, b, a)
    end

    -- Knob (circular via mask)
    local knob = CreateFrame("Frame", nil, sw)
    knob:SetSize(KNOB_SIZE, KNOB_SIZE)
    knob:SetPoint("LEFT", sw, "LEFT", KNOB_OFF_X, 0)
    knob:SetFrameLevel(sw:GetFrameLevel() + 2)
    local knobMask = knob:CreateMaskTexture()
    knobMask:SetAllPoints()
    knobMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local knobTex = knob:CreateTexture(nil, "ARTWORK")
    knobTex:SetAllPoints()
    knobTex:SetColorTexture(C.toggleOffKnob[1], C.toggleOffKnob[2], C.toggleOffKnob[3], 1)
    knobTex:AddMaskTexture(knobMask)

    -- Label (positioned right of toggle, matching old checkbox .Text)
    sw.Text = sw:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sw.Text:SetPoint("LEFT", sw, "RIGHT", 8, 0)   -- TRACK_W + 8 = ns.SWITCH_TEXT_X

    -- State
    local checked = false
    local currentKnobX = KNOB_OFF_X
    local animTicker = nil
    local isHovered = false

    -- Optional per-switch accent (e.g. class color for class-gated features);
    -- defaults to the EasyFishing theme color.
    local accentR, accentG, accentB = CYAN.r, CYAN.g, CYAN.b
    local accentBg = C.toggleOnBg

    local function UpdateVisual(animate)
        local targetX
        if checked then
            SetTrackColor(accentBg[1], accentBg[2], accentBg[3], accentBg[4])
            knobTex:SetColorTexture(accentR, accentG, accentB, 1)
            targetX = KNOB_ON_X
        else
            if isHovered then
                SetTrackColor(C.bgControlHov[1], C.bgControlHov[2], C.bgControlHov[3], C.bgControlHov[4])
            else
                SetTrackColor(C.toggleOffBg[1], C.toggleOffBg[2], C.toggleOffBg[3], C.toggleOffBg[4])
            end
            knobTex:SetColorTexture(C.toggleOffKnob[1], C.toggleOffKnob[2], C.toggleOffKnob[3], 1)
            targetX = KNOB_OFF_X
        end
        if animate and targetX ~= currentKnobX then
            if animTicker then animTicker:Cancel() end
            animTicker = C_Timer.NewTicker(0.016, function()
                local diff = targetX - currentKnobX
                if math.abs(diff) < 0.5 then
                    currentKnobX = targetX
                    knob:ClearAllPoints()
                    knob:SetPoint("LEFT", sw, "LEFT", currentKnobX, 0)
                    animTicker:Cancel()
                    animTicker = nil
                    return
                end
                currentKnobX = currentKnobX + diff * 0.35
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", sw, "LEFT", currentKnobX, 0)
            end)
        else
            -- An instant set also stops a slide still running (e.g. a click's handler set the
            -- switch straight back): the slide would otherwise carry the knob to the old side.
            if animTicker then animTicker:Cancel(); animTicker = nil end
            currentKnobX = targetX
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", sw, "LEFT", targetX, 0)
        end
    end

    function sw:GetChecked() return checked end
    function sw:SetChecked(val)
        checked = val and true or false
        UpdateVisual() -- instant (no animation for loading from DB)
    end

    -- OnClick interception: factory calls SetScript("OnClick", handler) AFTER creation.
    -- We store the user handler and call it after toggling internal state.
    local userOnClick = nil
    local origSetScript = sw.SetScript

    origSetScript(sw, "OnClick", function(self)
        checked = not checked
        UpdateVisual(true) -- animated slide
        if userOnClick then userOnClick(self) end
    end)

    sw.SetScript = function(self, scriptType, handler)
        if scriptType == "OnClick" then
            userOnClick = handler
        else
            origSetScript(self, scriptType, handler)
        end
    end

    -- GetScript override: return user handler, not internal handler
    local origGetScript = sw.GetScript
    sw.GetScript = function(self, scriptType)
        if scriptType == "OnClick" then
            return userOnClick
        else
            return origGetScript(self, scriptType)
        end
    end

    -- HookScript support
    local origHookScript = sw.HookScript
    sw.HookScript = function(self, scriptType, handler)
        if scriptType == "OnClick" then
            local prev = userOnClick
            userOnClick = function(s)
                if prev then prev(s) end
                handler(s)
            end
        else
            origHookScript(self, scriptType, handler)
        end
    end

    -- Enabled state
    function sw:SetEnabled(val)
        if val then
            self:EnableMouse(true)
            self:SetAlpha(1.0)
        else
            self:EnableMouse(false)
            self:SetAlpha(0.5)
        end
    end

    -- Hover
    origSetScript(sw, "OnEnter", function(self)
        isHovered = true
        if not checked then
            SetTrackColor(C.bgControlHov[1], C.bgControlHov[2], C.bgControlHov[3], C.bgControlHov[4])
        end
    end)
    origSetScript(sw, "OnLeave", function(self)
        isHovered = false
        UpdateVisual()
    end)

    UpdateVisual()
    return sw
end
-- BEGIN StyleSlider (uses only CYAN and C)
function ns.StyleSlider(slider)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(CYAN.r, CYAN.g, CYAN.b, 0.9)
        thumb:SetSize(12, 20)
    end
    -- Style the track background
    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -8)
    bg:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 8)
    bg:SetColorTexture(C.bgControl[1], C.bgControl[2], C.bgControl[3], 0.8)
    -- NOTE: do NOT anchor anything to the slider THUMB. A thumb's rect is recomputed
    -- by the C widget continuously; anchoring dependents to it forces per-frame layout
    -- re-resolution for every slider in the panel, which makes menus lag when opened and
    -- dragged. An accent fill would need an OnValueChanged-driven width instead.
    -- Style text labels
    local name = slider:GetName()
    if name then
        local low = _G[name .. "Low"]
        local high = _G[name .. "High"]
        local text = _G[name .. "Text"]
        if low then low:SetTextColor(0.5, 0.5, 0.55) end
        if high then high:SetTextColor(0.5, 0.5, 0.55) end
        -- (the thumb carries the accent as the active-value indicator)
        if text then text:SetTextColor(CYAN.r, CYAN.g, CYAN.b) end
    end
end
-- END StyleSlider
function ns.CreateThemedButton(parent, text, width, height, style)
    width = width or 100
    height = height or 24
    style = style or "secondary"

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop(ns.BACKDROP_CONTROL)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text)

    local normalBg, normalBorder, normalText
    local hoverBg, hoverBorder, hoverText

    if style == "primary" then
        normalBg     = { CYAN.r * 0.15, CYAN.g * 0.15, CYAN.b * 0.15, 1.0 }
        normalBorder = { CYAN.r, CYAN.g, CYAN.b, 0.35 }
        normalText   = { CYAN.r, CYAN.g, CYAN.b }
        hoverBg      = { CYAN.r * 0.22, CYAN.g * 0.22, CYAN.b * 0.22, 1.0 }
        hoverBorder  = { CYAN.r, CYAN.g, CYAN.b, 0.60 }
        hoverText    = { 1, 1, 1 }
    elseif style == "danger" then
        normalBg     = { 0.18, 0.06, 0.06, 1.0 }
        normalBorder = { 0.50, 0.15, 0.15, 0.40 }
        normalText   = { 0.90, 0.40, 0.40 }
        hoverBg      = { 0.25, 0.08, 0.08, 1.0 }
        hoverBorder  = { 0.70, 0.20, 0.20, 0.60 }
        hoverText    = { 1, 0.5, 0.5 }
    else -- secondary
        normalBg     = { 0.14, 0.14, 0.17, 1.0 }
        normalBorder = { 0.24, 0.24, 0.28, 0.40 }
        normalText   = { C.textLabel[1], C.textLabel[2], C.textLabel[3] }
        hoverBg      = { 0.18, 0.18, 0.21, 1.0 }
        hoverBorder  = { 0.30, 0.30, 0.35, 0.60 }
        hoverText    = { CYAN.r, CYAN.g, CYAN.b }
    end

    btn:SetBackdropColor(unpack(normalBg))
    btn:SetBackdropBorderColor(unpack(normalBorder))
    btn.label:SetTextColor(unpack(normalText))

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(hoverBg))
        self:SetBackdropBorderColor(unpack(hoverBorder))
        self.label:SetTextColor(unpack(hoverText))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(normalBg))
        self:SetBackdropBorderColor(unpack(normalBorder))
        self.label:SetTextColor(unpack(normalText))
    end)

    btn.SetText = function(self, t) self.label:SetText(t) end
    btn.GetText = function(self) return self.label:GetText() end

    return btn
end
function ns.AddSettingsSlider(panel, anchor, namePrefix, dbKey, label, desc, minVal, maxVal, step, fmt, onChanged, csSyncControls)
    local sl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sl:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16); sl:SetText(label); sl:SetTextColor(0.85, 0.85, 0.87)
    local sd = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sd:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -2); sd:SetWidth(350); sd:SetJustifyH("LEFT"); sd:SetTextColor(0.55, 0.55, 0.6); sd:SetText(desc)
    local gname = "EasyFishing" .. namePrefix .. dbKey
    -- minus / slider / plus row, so users can micro-adjust
    local minus = ns.CreateThemedButton(panel, "-", 24, 24, "secondary")
    minus:SetPoint("TOPLEFT", sd, "BOTTOMLEFT", 6, -18)
    local slider = CreateFrame("Slider", gname, panel, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", minus, "RIGHT", 6, 0); slider:SetWidth(200)
    slider:SetMinMaxValues(minVal, maxVal); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true)
    if ns.StyleSlider then ns.StyleSlider(slider) end
    local plus = ns.CreateThemedButton(panel, "+", 24, 24, "secondary")
    plus:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    local cur = EasyFishingDB[dbKey]; if cur == nil then cur = (minVal + maxVal) / 2 end
    slider:SetValue(cur)
    if _G[gname .. "Low"] then _G[gname .. "Low"]:SetText(fmt(minVal)) end
    if _G[gname .. "High"] then _G[gname .. "High"]:SetText(fmt(maxVal)) end
    if _G[gname .. "Text"] then _G[gname .. "Text"]:SetText(fmt(cur)); _G[gname .. "Text"]:SetTextColor(CYAN.r, CYAN.g, CYAN.b) end
    -- the settings search finds it by its label (a module has no search)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        EasyFishingDB[dbKey] = value
        if _G[gname .. "Text"] then _G[gname .. "Text"]:SetText(fmt(value)) end
        if onChanged then onChanged() end
    end)
    minus:SetScript("OnClick", function()
        local v = slider:GetValue() - step
        if v >= minVal then slider:SetValue(v) end
    end)
    plus:SetScript("OnClick", function()
        local v = slider:GetValue() + step
        if v <= maxVal then slider:SetValue(v) end
    end)
    if csSyncControls then
        table.insert(csSyncControls, { refresh = function() local v = EasyFishingDB[dbKey]; if v == nil then v = (minVal + maxVal) / 2 end; slider:SetValue(v) end })
    end
    local spacer = CreateFrame("Frame", nil, panel)
    spacer:SetSize(1, 1); spacer:SetPoint("TOPLEFT", minus, "BOTTOMLEFT", -6, -10)
    return spacer
end
function ns.CreateCyanAccentLine(parent)
    local line = parent:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
    line:SetColorTexture(CYAN.r, CYAN.g, CYAN.b, 0.8)
    return line
end

-----------------------------
-- Checkbox factory (the Fishing Log row's switch)
-----------------------------
-- factory(content, anchor) -> AddCB, GetLast, SetLast. AddCB(name, key, label, desc, setter) puts
-- a toggle under the last element, saves EasyFishingDB[key] and calls setter(checked).
function ns.MakeCheckboxFactory(content, anchor)
    local last = anchor
    local function GetLast() return last end
    local function SetLast(el) last = el end
    local function AddCB(name, key, label, desc, setter)
        local cb = ns.CreateToggleSwitch(content, "EasyFishing" .. name .. "CB")
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(0.8, 0.8, 0.8)
        cb:SetChecked(EasyFishingDB and EasyFishingDB[key] ~= false and EasyFishingDB[key] ~= nil)
        cb:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            EasyFishingDB = EasyFishingDB or {}
            EasyFishingDB[key] = on
            if setter then setter(on) end
        end)
        local d = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT", cb.Text, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        d:SetJustifyH("LEFT")
        d:SetTextColor(0.55, 0.55, 0.6)
        d:SetText(desc or "")
        local below = CreateFrame("Frame", nil, content)
        below:SetSize(1, 1)
        below:SetPoint("TOPLEFT", d, "BOTTOMLEFT", -ns.SWITCH_TEXT_X, 0)
        last = below
        return cb
    end
    return AddCB, GetLast, SetLast
end

-----------------------------
-- SavedVariables defaults
-----------------------------
local EASYFISHING_DEFAULTS = {
    fishing = true, fishingLoud = true, fishingLoudBoost = 3, fishingMute = false,
    fishingBackground = true, fishingIcon = true, fishingLog = true,
}
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EasyFishing" then return end
    self:UnregisterEvent("ADDON_LOADED")
    EasyFishingDB = EasyFishingDB or {}
    EasyFishingCharDB = EasyFishingCharDB or {}
    for k, v in pairs(EASYFISHING_DEFAULTS) do
        if EasyFishingDB[k] == nil then EasyFishingDB[k] = v end
    end
end)
