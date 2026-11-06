local _, ns = ...

-- The Options > AddOns panel for EasyFishing: a title, then the module's own settings (ns.BuildFishingPanel)
-- in a scroll frame. The rows are built on the first show, so load order doesn't matter.

local CATEGORY_NAME = "EasyFishing"

local panel = CreateFrame("Frame", "EasyFishingOptions")
panel.name = CATEGORY_NAME
local category
local built = false
local scroll, content

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText(CATEGORY_NAME)

scroll = CreateFrame("ScrollFrame", "EasyFishingOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -8, -12)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)

local function Build()
    if built then return end
    built = true

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max(scroll:GetWidth(), 560), 900)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)

    -- the module's description is the anchor the settings hang from (Fishing.lua: ns.BuildFishingPanel)
    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -8)
    desc:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.55, 0.55, 0.6)
    desc:SetText(ns.FishingDescription and ns.FishingDescription() or "")

    local last = ns.BuildFishingPanel and ns.BuildFishingPanel(content, desc)
    local top = content:GetTop()
    local bottom = last and last:GetBottom()
    if top and bottom then
        content:SetHeight(top - bottom + 24)
    end

    -- Blizzard lays the canvas out again once the content exists
    if category and Settings and Settings.OpenToCategory then
        C_Timer.After(0, function()
            Settings.OpenToCategory(category:GetID())
        end)
    end
end

panel:SetScript("OnShow", function()
    Build()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, CATEGORY_NAME)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    -- legacy Options panel (no Settings API)
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- the legacy panel needs a second call to scroll to it
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
