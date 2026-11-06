local _, ns = ...

-- Login startup and the /easyfishing command. Each feature starts on its own (pcall), so one that
-- fails is reported and the ones after it still start.

local function Say(msg)
    ns.Print(ns.TAG .. ": " .. msg)
end

local function Start(name, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        Say(name .. " failed: " .. tostring(err))
    end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    local db = ns.DB()
    -- runs with the switch off too, to put back sound and interact settings a session left behind
    Start("SetFishing", ns.SetFishing, db.fishing)
    Start("SetFishingLog", ns.SetFishingLog, db.fishingLog ~= false)
end)

local function ShowHelp()
    Say("Commands:")
    Say("  /easyfishing - open the options")
    Say("  /easyfishing on | off - turn Easy Fishing on or off")
    Say("  /easyfishing show | hide | toggle - show, hide or toggle the Fishing Log")
    Say("  /easyfishing help - show this list")
end

local function SetFishingState(on)
    ns.DB().fishing = on
    Start("SetFishing", ns.SetFishing, on)
    Say("Easy Fishing is " .. (on and "on" or "off") .. ".")
end

SLASH_EASYFISHING1 = "/easyfishing"
SLASH_EASYFISHING2 = "/ef"
SlashCmdList.EASYFISHING = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "" then
        Start("OpenOptions", ns.OpenOptions)
    elseif cmd == "on" then
        SetFishingState(true)
    elseif cmd == "off" then
        SetFishingState(false)
    elseif cmd == "show" then
        Start("FishingLogShow", ns.FishingLogShow)
    elseif cmd == "toggle" then
        Start("FishingLogToggle", ns.FishingLogToggle)
    elseif cmd == "hide" then
        Start("FishingLogHide", ns.FishingLogHide)
    else
        ShowHelp()
    end
end
