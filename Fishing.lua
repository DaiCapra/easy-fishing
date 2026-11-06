-- EasyFishing (retail and WoW: Forever)
-- One key casts Fishing, reels the bobber in, and takes the loot when Auto Loot is off. Every
-- press is the player's own: nothing tells an addon that a fish bit, and nothing here acts on its
-- own.
--
-- The key: an override binding on our own owner frame (the player's keybinds are never written),
-- changed only out of combat. What it does, first match wins (Wanted):
--   loot  a loot window is open during a session: CLICK EasyFishingLoot (takes every slot)
--   reel  the soft-interact target is the bobber: INTERACTTARGET, Blizzard's Interact Key
--   point the bobber is past that reach but under the cursor: TURNORACTION, the right-click action
--         (the binding Blizzard gives the right mouse button: interact with what's under the
--         cursor; INTERACTMOUSEOVER only reaches units)
--   cast  otherwise: CLICK EasyFishingCast, a secure button whose macro casts Fishing by name
--         (WoW: Forever casts the highest rank known) unless in combat, flying (a dismount would
--         drop the player), stealthed, swimming or in a vehicle
-- TURNORACTION starts mouselook on the press and acts on the release, so the binding never leaves
-- "point" while the player is mouselooking: the release has to reach it.
--
-- The bobber: GameObject entry 35591, summoned by every Fishing channel in both games (SpellEffect
-- 50 or 171, misc 35591), Ice Fishing and Void Hole Fishing included. Soft target: the GUID of
-- PLAYER_SOFT_INTERACT_CHANGED. Under the cursor: C_TooltipInfo.GetWorldCursor() on
-- WORLD_CURSOR_TOOLTIP_UPDATE, by its id or GUID, else its tooltip's first line against the
-- bobber's name (learned from the soft target, English by default). Both events are registered
-- only while a channel runs, the cursor's only where the client has it (WatchCursor). Its last
-- readings are kept in the Fishing Log's stats (fishingStats.cursor), to check the fields in game.
--
-- Reach: retail's bobber lands 12-15 yd out (131476, "Min Range 12, 15"), past the Interact Key's
-- default reach, so a session raises SoftTargetInteractRange to REACH, widens the arc and turns
-- the key on for keyboards (SoftTargetInteract 3). WoW: Forever's lands 10-20 yd out (7620,
-- "Short Range" 10-20); players reported its client capping soft-target reach whatever the CVar
-- says (1.60.1, Oct 2026), but measured on the owner's beta character on Oct 21 2026 with REACH
-- 30, 29 of 29 casts were in reach. Point-and-press and the out-of-reach cue stay for a bobber
-- that isn't. With Icon Over the Bobber on
-- (`fishingIcon`) the soft-target icon is on during a session, so the player sees when the key can
-- reach the bobber; off, the player's own icon settings are left alone.
--
-- Louder Splash (`fishingLoud`): WoW has no volume per sound, and the splash is a sound effect, so
-- effects play at `fishingLoudBoost` times the player's own loudness, and the Effects switch is
-- turned on if it was off. Effects take the multiple first; past 100% Master takes the rest, as
-- far as it goes, and every other volume under Master comes down by the same factor, so music,
-- ambience, dialog, pings and encounter cues play exactly as loud as before (the owner's call,
-- Oct 2026: never turn the player's other sounds down, as Better Fishing and Angleur do; they max
-- Master and Effects and mute the rest). The loudest anything plays is Master and Effects at 100%;
-- nothing goes past it. That holds while the game treats each volume as a plain multiplier.
-- Mute Other Sounds (`fishingMute`, off by default) is the player's own choice to mute music,
-- ambience, dialog and pet sounds while fishing: their volumes to 0 (a volume coming back doesn't
-- restart the music, as its switch would every cast) and the pet sounds switch, which has none.
-- They stay muted for as long as a fishing pole is equipped (SyncMute), not just during casts.
-- Sound in Background (`fishingBackground`, on by
-- default) keeps the game's sound on while it's in the background, so the splash is heard from
-- another window.
--
-- A session is one cast: it starts at the cast button's PreClick or any Fishing channel and ends
-- the moment the channel does (as Better Fishing and Angleur do), or CAST_WAIT s after a press
-- whose cast never started, so a cast that didn't go off never leaves the sound changed (heard
-- from another window, it would pass for fishing). The loot key doesn't depend on it: the loot
-- window is watched whenever Easy Fishing is on, so the loot can wait as long as the player likes. What it changed is kept in EasyFishingDB.fishingRestore
-- ({ [cvar] = { o = old, s = set } }) and put back at its end, at logout, or at the next login
-- after a crash, only where the CVar still holds our value.
--
-- WoW: Forever can't fish without a pole, so there the key is taken only while one is equipped.
--
-- The EasyFishing addon: this file, with the Fishing Log (FishingLog.lua, LootLog.lua),
-- runs on Core.lua. Its Options > AddOns panel is ns.BuildFishingPanel: the key,
-- the switches under Easy Fishing and the Fishing Log's row, without Easy Fishing's own switch.

local _, ns = ...

local CAST_BUTTON = "EasyFishingCast"
local LOOT_BUTTON = "EasyFishingLoot"
local BOBBER_ID = 35591
local REACH = 30                -- SoftTargetInteractRange during a session (yards)
local INTERACT_ANY = 3          -- Enum.SoftTargetEnableFlags.Any: keyboard and gamepad
local WIDE_ARC = 2              -- SoftTargetInteractArc: anywhere in front, so a small turn keeps the bobber
local CAST_WAIT = 3             -- seconds after a press for its cast to start before its session ends
-- The out-of-reach cue waits as long as the bobber has lately taken to come into the Interact
-- Key's reach, and a second more, CUE_MIN to CUE_MAX s after the cast (CueDelay). At a flat 1.5 s
-- it said "out of reach" on casts the key went on to reel in (WoW: Forever, Oct 22 2026: 109 of
-- 111 casts came into reach, some of them after the cue).
local CUE_MIN, CUE_MAX, CUE_MARGIN = 3, 6, 1
local REACH_SAMPLES = 10        -- the casts whose time to come into reach the cue goes by
local RECHECK = 0.2             -- seconds between checks while a mouselook holds the "point" binding
local BOOST_MIN, BOOST_MAX, BOOST_DEFAULT = 1.5, 5, 3   -- Louder Splash: times the player's Effects volume
local CAST_CONDITIONS = "[nocombat,noflying,nostealth,noswimming,novehicleui]"
local MAIN_HAND = INVSLOT_MAINHAND or 16
local WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local FISHING_POLE = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
-- Fishing channels: retail's (131474 the button, 131476 / 131490 the channel, 377895 Ice Fishing,
-- 1224771 Void Hole Fishing, older expansions' own), Forever's ranks. Any other spell named
-- Fishing counts too (IsFishingChannel).
local CHANNEL_IDS = {
    [131476] = true, [131490] = true, [377895] = true, [1224771] = true,
    [33095] = true, [51294] = true, [88868] = true, [110410] = true, [158743] = true,
    [7620] = true, [7731] = true, [7732] = true, [18248] = true,
}
local SFX, MASTER = "Sound_SFXVolume", "Sound_MasterVolume"
-- The volumes Master scales besides Effects ("Gameplay Sound Effects" is encounter audio cues,
-- a channel of its own). A client without one has no such CVar, and it's skipped.
local OTHER_VOLUMES = { "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume",
    "Sound_GameplaySFX", "Sound_PingVolume", "Sound_EncounterWarningsVolume" }
local MUTE_VOLUMES = { "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }
local MUTE_SWITCHES = { "Sound_EnablePetSounds" }
local MUTE_ALL = {}
for _, cvar in ipairs(MUTE_VOLUMES) do MUTE_ALL[cvar] = true end
for _, cvar in ipairs(MUTE_SWITCHES) do MUTE_ALL[cvar] = true end
-- Every sound CVar a session may change: Louder Splash and Mute share the volumes, so a sound
-- switch turned mid-session puts all of them back and sets them again.
local SOUND_ALL = { Sound_EnableSFX = true, [SFX] = true, [MASTER] = true,
    Sound_EnableSoundWhenGameIsInBG = true }
for _, cvar in ipairs(OTHER_VOLUMES) do SOUND_ALL[cvar] = true end
for _, cvar in ipairs(MUTE_SWITCHES) do SOUND_ALL[cvar] = true end
local ICON_CVARS = { SoftTargetIconGameObject = true, SoftTargetIconInteract = true }
-- The switches under Easy Fishing, and what each is before the player sets it.
local SUB_DEFAULTS = { fishingLoud = true, fishingMute = false, fishingBackground = true, fishingIcon = true }

-----------------------------
-- State
-----------------------------
local ev, owner, castBtn, lootBtn
local enabled = false
local channeling = false          -- a Fishing channel runs
local inReach = false             -- the soft-interact target is the bobber
local pointing = false            -- the bobber is under the cursor
local lootOpen = false            -- a loot window is open during a session
local applied, appliedKey         -- the binding we hold: nil | "loot" | "reel" | "point" | "cast", and its key
local cursorWatched = false       -- WORLD_CURSOR_TOOLTIP_UPDATE is registered
local sessionOn = false
local regenWork = false           -- something waits for combat to end
local recheckOn = false
local endTimer, cueTimer
local boostUsed                   -- the Louder Splash multiple this session's Effects volume was set with
local reachedThisCast, pointedThisCast, cuedThisCast = false, false, false
local lostThisCast = false        -- the bobber left the Interact Key's reach after coming into it ("back": and returned)
local castAt = 0                  -- GetTime() when this cast's channel started
local LOG_SAMPLES = 5

local DB = ns.DB

-- Two CVar values count as the same when they're equal, or numbers within a thousandth.
local function SameCVar(a, b)
    if a == b then return true end
    return tonumber(a) ~= nil and tonumber(b) ~= nil and math.abs(tonumber(a) - tonumber(b)) < 0.001
end

local function CancelTimer(t)
    if t then t:Cancel() end
    return nil
end

-- EasyFishingDB.fishingStats: running counts (casts, reached = the Interact Key could reach the
-- bobber, pointed = the bobber was under the cursor while out of reach, cues = the out-of-reach cue
-- shown, cuesEarly = shown on a cast the key reached afterwards, lost = a bobber in reach that
-- left it while the channel ran and lostBack = one that came back, recasts = the key cast again
-- while a channel ran and recastsReached = on a cast whose bobber had been in reach: Nov 2026, in
-- Classic Era the key recast instead of reeling after the player came back from another window,
-- and these tell whether the game dropped the soft target), the seconds the last
-- REACH_SAMPLES casts took to come into reach (reachTimes, which the cue goes by) and the last few
-- world-cursor readings while fishing ({ t = type, i = id, g = GUID kind, x = first line }), so the
-- reach and the cursor data's fields can be read from the saved variables after playing.
--
-- They were kept in EasyFishingDB.fishingLog until Oct 2026, which is also the Fishing Log's switch:
-- each cast put the counts over it, so a Fishing Log turned off came back on at the next login.
-- Moved out here once (the switch reads on again: what the counts had made it).
local function MoveStats(db)
    if type(db.fishingLog) == "table" then
        if type(db.fishingStats) ~= "table" then db.fishingStats = db.fishingLog end
        db.fishingLog = true
    end
end
local function Log()
    local db = DB()
    MoveStats(db)
    local log = type(db.fishingStats) == "table" and db.fishingStats or {}
    db.fishingStats = log
    return log
end
local function Count(field)
    local log = Log()
    log[field] = (tonumber(log[field]) or 0) + 1
end

-- A cast came into reach this many seconds after its channel started.
local function NoteReachTime(seconds)
    local log = Log()
    local times = type(log.reachTimes) == "table" and log.reachTimes or {}
    times[#times + 1] = math.floor(seconds * 10 + 0.5) / 10
    while #times > REACH_SAMPLES do table.remove(times, 1) end
    log.reachTimes = times
end

-- Seconds after a cast before saying its bobber is out of reach: the longest the last casts took
-- to come into reach, and CUE_MARGIN more.
local function CueDelay()
    local times = Log().reachTimes
    local longest = 0
    if type(times) == "table" then
        for _, t in ipairs(times) do
            if type(t) == "number" and t > longest then longest = t end
        end
    end
    return math.max(CUE_MIN, math.min(CUE_MAX, longest + CUE_MARGIN))
end


local function PoleOnly() return ns.IS_FOREVER == true end

local function SubOn(key)
    local v = DB()[key]
    if v == nil then return SUB_DEFAULTS[key] end
    return v ~= false
end

-- How many times the player's own Effects volume Louder Splash plays at.
local function Boost()
    local b = tonumber(DB().fishingLoudBoost) or BOOST_DEFAULT
    return math.max(BOOST_MIN, math.min(BOOST_MAX, b))
end

local function FishingName()
    local get = C_Spell and C_Spell.GetSpellName
    if not get then return nil end
    return get(ns.IS_FOREVER and 7620 or 131474) or get(7620)
end

local function IsFishingChannel(spellID)
    if ns.IsSecretV(spellID) or type(spellID) ~= "number" then return false end
    if CHANNEL_IDS[spellID] then return true end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return name ~= nil and name == FishingName()
end
ns.IsFishingChannel = IsFishingChannel

local function PoleEquipped()
    local id = GetInventoryItemID("player", MAIN_HAND)
    if not id then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    return classID == WEAPON and subclassID == FISHING_POLE
end

local function IsBobber(guid)
    if ns.IsSecretV(guid) or type(guid) ~= "string" then return false end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind == "GameObject" and tonumber(id) == BOBBER_ID
end

-- The bobber's name in the player's language: learned from the soft target, English until then.
local function BobberName()
    local name = DB().fishingBobberName
    if type(name) == "string" and name ~= "" then return name end
    local locale = GetLocale and GetLocale()
    if type(locale) == "string" and locale:sub(1, 2) == "en" then return "Fishing Bobber" end
end

local function LearnBobberName()
    local ok, name = pcall(UnitName, "softinteract")
    if ok and not ns.IsSecretV(name) and type(name) == "string" and name ~= "" then
        DB().fishingBobberName = name
    end
end

local function Field(v) return not ns.IsSecretV(v) and v or nil end

-- Whether the world object under the cursor is the bobber.
local function CursorOnBobber()
    local get = C_TooltipInfo and C_TooltipInfo.GetWorldCursor
    if not get then return false end
    local ok, data = pcall(get)
    if not ok or type(data) ~= "table" then return false end
    local id, guid = Field(data.id), Field(data.guid)
    local line = type(data.lines) == "table" and data.lines[1]
    local text = type(line) == "table" and Field(line.leftText) or nil
    local sample = { t = Field(data.type), i = id, x = text,
        g = type(guid) == "string" and (guid:match("^(%a+)") or "?") or nil }
    local samples = type(Log().cursor) == "table" and Log().cursor or {}
    local last = samples[#samples]
    if not (last and last.t == sample.t and last.i == sample.i and last.g == sample.g and last.x == sample.x) then
        samples[#samples + 1] = sample
        while #samples > LOG_SAMPLES do table.remove(samples, 1) end
        Log().cursor = samples
    end
    if id == BOBBER_ID or IsBobber(guid) then return true end
    local name = BobberName()
    return type(text) == "string" and name ~= nil and text == name
end

-- The cursor's event, only where the client has the cursor data: Classic Era (the test copy,
-- copy-addon.ps1 -ClassicEra) has neither, and registering or unregistering an event a client lacks
-- is an error. That error stopped every cast's setup halfway (no reach read, no cue) and every
-- channel's end before the key went back to casting.
local function WatchCursor(on)
    if not ev or on == cursorWatched then return end
    if on then
        if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return end
        cursorWatched = pcall(ev.RegisterEvent, ev, "WORLD_CURSOR_TOOLTIP_UPDATE")
    else
        cursorWatched = false
        pcall(ev.UnregisterEvent, ev, "WORLD_CURSOR_TOOLTIP_UPDATE")
    end
end

-- "SHIFT-F" as the game writes it for the player ("Shift-F" in English).
local function KeyText(key)
    if not key or key == "" then return nil end
    local ok, text = pcall(GetBindingText, key)
    return ok and type(text) == "string" and text ~= "" and text or key
end

-----------------------------
-- Frames (made on first use, never at load)
-----------------------------
local OnEvent
local function EnsureFrames()
    if ev then return end
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event, ...) OnEvent(event, ...) end)
    owner = CreateFrame("Frame")
end

local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- Louder Splash's volumes, once a session (or again after the slider moved): Effects take the
-- multiple first; past 100%, Master takes the rest as far as it goes, and every other volume under
-- it comes down by the same factor, so it plays as loud as before.
local function LouderSplash(Change, saved)
    local sfx = tonumber(GetCVar(SFX))
    if not sfx or sfx <= 0 then return end            -- effects at 0 are the player's choice
    local want = sfx * boostUsed
    local sfxNew = math.min(1, Round(want))
    Change(SFX, function() return sfxNew end)
    local master = tonumber(GetCVar(MASTER))
    if want <= sfxNew or not master or master <= 0 or master >= 1 then return end
    local masterNew = math.min(1, Round(master * want / sfxNew))
    Change(MASTER, function() return masterNew end)
    if not saved[MASTER] then return end              -- Master didn't move: the others stay
    local factor = masterNew / master
    for _, cvar in ipairs(OTHER_VOLUMES) do
        Change(cvar, function(old)
            local v = tonumber(old)
            if not v or v <= 0 then return nil end
            return Round(v / factor)
        end)
    end
end

local function BeginSession()
    if InCombatLockdown() then return end
    local db = DB()
    local saved = db.fishingRestore or {}
    local function Change(cvar, value)
        if saved[cvar] then return end            -- already ours this session
        local old = GetCVar(cvar)
        if old == nil then return end              -- not in this client
        local v = value(old)
        if v == nil then return end
        v = tostring(v)
        if SameCVar(old, v) then return end
        if pcall(SetCVar, cvar, v) then saved[cvar] = { o = old, s = v } end
    end
    local function AtLeast(n) return function(old) return (tonumber(old) or 0) < n and n or nil end end
    local function Exactly(n) return function(old) return tonumber(old) ~= n and n or nil end end
    Change("SoftTargetInteract", Exactly(INTERACT_ANY))
    Change("SoftTargetInteractRange", AtLeast(REACH))
    Change("SoftTargetInteractArc", AtLeast(WIDE_ARC))
    if SubOn("fishingIcon") then
        Change("SoftTargetIconGameObject", Exactly(1))
        Change("SoftTargetIconInteract", Exactly(1))
    end
    -- Mute first: a volume it takes to 0 isn't Louder Splash's to lower.
    if SubOn("fishingMute") then
        for _, cvar in ipairs(MUTE_VOLUMES) do
            Change(cvar, function(old) return (tonumber(old) or 0) > 0 and 0 or nil end)
        end
        for _, cvar in ipairs(MUTE_SWITCHES) do Change(cvar, Exactly(0)) end
    end
    if SubOn("fishingLoud") then
        Change("Sound_EnableSFX", Exactly(1))
        if not boostUsed then
            boostUsed = Boost()
            LouderSplash(Change, saved)
        end
    end
    if SubOn("fishingBackground") then Change("Sound_EnableSoundWhenGameIsInBG", Exactly(1)) end
    db.fishingRestore = next(saved) and saved or nil
    if not sessionOn then
        sessionOn = true
        EnsureFrames()
        ev:RegisterEvent("PLAYER_LOGOUT")
    end
end

-- Puts back what a session changed (only the CVars `only` names, when given), where the CVar still
-- holds what we set: a volume the player moved meanwhile is theirs.
local function RestoreCVars(only, keep)
    local db = DB()
    local saved = db.fishingRestore
    if not saved then return end
    for cvar, e in pairs(saved) do
        if (not only or only[cvar]) and not (keep and keep[cvar]) then
            if SameCVar(GetCVar(cvar), e.s) then pcall(SetCVar, cvar, e.o) end
            saved[cvar] = nil
        end
    end
    db.fishingRestore = next(saved) and saved or nil
end

-- Mute Other Sounds also holds while the pole is equipped, between casts: the mute volumes stay
-- ours until the pole comes off (or the switch or Easy Fishing goes off), so a session's end
-- leaves them alone.
local function PoleMuteWanted()
    return enabled and SubOn("fishingMute") and PoleEquipped()
end

local WatchRegen, Apply

-- Brings the mute CVars in line with the pole: muted while it's equipped (or a session is on),
-- put back otherwise.
local function SyncMute()
    if InCombatLockdown() then WatchRegen(); return end
    if PoleMuteWanted() or (sessionOn and enabled and SubOn("fishingMute")) then
        local db = DB()
        local saved = db.fishingRestore or {}
        local function Change(cvar, value)
            if saved[cvar] then return end
            local old = GetCVar(cvar)
            if old == nil then return end
            local v = value(old)
            if v == nil then return end
            v = tostring(v)
            if SameCVar(old, v) then return end
            if pcall(SetCVar, cvar, v) then saved[cvar] = { o = old, s = v } end
        end
        for _, cvar in ipairs(MUTE_VOLUMES) do
            Change(cvar, function(old) return (tonumber(old) or 0) > 0 and 0 or nil end)
        end
        for _, cvar in ipairs(MUTE_SWITCHES) do
            Change(cvar, function(old) return tonumber(old) ~= 0 and 0 or nil end)
        end
        db.fishingRestore = next(saved) and saved or nil
        if not sessionOn and db.fishingRestore then
            EnsureFrames()
            ev:RegisterEvent("PLAYER_LOGOUT")
        end
    else
        RestoreCVars(MUTE_ALL)
    end
end

local function EndSession()
    endTimer = CancelTimer(endTimer)
    if InCombatLockdown() then WatchRegen(); return end
    RestoreCVars(nil, PoleMuteWanted() and MUTE_ALL or nil)
    if sessionOn then
        sessionOn = false
        boostUsed = nil
        if ev then ev:UnregisterEvent("PLAYER_LOGOUT") end
    end
end

local function RunSessionEnd()
    endTimer = nil
    if not channeling then EndSession() end
end

local function EndSessionLater()
    endTimer = CancelTimer(endTimer)
    endTimer = C_Timer.NewTimer(CAST_WAIT, RunSessionEnd)
end

-----------------------------
-- The key
-----------------------------
local function Wanted()
    local key = DB().fishingKey
    if not enabled or type(key) ~= "string" or key == "" then return nil end
    if PoleOnly() and not PoleEquipped() then return nil end
    if lootOpen then return "loot", key end
    if channeling and inReach then return "reel", key end
    if channeling and pointing then return "point", key end
    return "cast", key
end

local function EnsureCastButton()
    if not castBtn then
        castBtn = CreateFrame("Button", CAST_BUTTON, nil, "SecureActionButtonTemplate")
        castBtn:RegisterForClicks("AnyDown")      -- one cast per press, never on release
        castBtn:SetAttribute("useOnKeyDown", true)
        castBtn:SetAttribute("type", "macro")
        -- Raise the reach before the bobber lands (the channel starts it too).
        castBtn:SetScript("PreClick", function()
            -- the macro's own conditions: a press it won't cast on starts no session
            local castable = not SecureCmdOptionParse or SecureCmdOptionParse(CAST_CONDITIONS .. " 1")
            if enabled and channeling then
                Count("recasts")
                if reachedThisCast then Count("recastsReached") end
            end
            if enabled and castable then
                BeginSession()
                if not channeling then EndSessionLater() end
            end
        end)
    end
    local name = FishingName()
    local text = name and ("/cast " .. CAST_CONDITIONS .. " " .. name)
    if text and castBtn:GetAttribute("macrotext") ~= text then castBtn:SetAttribute("macrotext", text) end
end

-- Takes everything in the open loot window (a plain button: looting isn't protected).
local function LootAll()
    for i = (GetNumLootItems() or 0), 1, -1 do LootSlot(i) end
end

local function EnsureLootButton()
    if lootBtn then return end
    lootBtn = CreateFrame("Button", LOOT_BUTTON)
    lootBtn:RegisterForClicks("AnyDown")
    lootBtn:SetScript("OnClick", LootAll)
end

local function RunRecheck()
    recheckOn = false
    Apply()
end

function Apply()
    local want, key = Wanted()
    if want == applied and key == appliedKey then return end
    -- The right-click action's release must reach it: hold "point" while the press mouselooks.
    if applied == "point" and IsMouselooking and IsMouselooking() then
        if not recheckOn then recheckOn = true; C_Timer.After(RECHECK, RunRecheck) end
        return
    end
    if InCombatLockdown() then WatchRegen(); return end
    if owner then ClearOverrideBindings(owner) end
    if want then
        EnsureFrames()
        if want == "reel" then
            SetOverrideBinding(owner, true, key, "INTERACTTARGET")
        elseif want == "point" then
            SetOverrideBinding(owner, true, key, "TURNORACTION")
        elseif want == "loot" then
            EnsureLootButton()
            SetOverrideBindingClick(owner, true, key, LOOT_BUTTON, "LeftButton")
        else
            EnsureCastButton()
            SetOverrideBindingClick(owner, true, key, CAST_BUTTON, "LeftButton")
        end
    end
    applied, appliedKey = want, want and key or nil
end

function WatchRegen()
    if regenWork then return end
    regenWork = true
    EnsureFrames()
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-----------------------------
-- Events
-----------------------------
local function SetReach(guid)
    local was = inReach
    inReach = IsBobber(guid)
    -- once a cast each: lost (in reach, then not), lostBack (in reach again after that)
    if channeling and was and not inReach and not lostThisCast then
        lostThisCast = true
        Count("lost")
    elseif channeling and inReach and not was and lostThisCast == true then
        lostThisCast = "back"
        Count("lostBack")
    end
    if inReach then
        LearnBobberName()
        if channeling and not reachedThisCast then
            reachedThisCast = true
            Count("reached")
            local took = math.max(0, GetTime() - castAt)
            NoteReachTime(took)
            if cuedThisCast then Count("cuesEarly") end
        end
    end
    Apply()
end

local function SetPointing()
    pointing = channeling and CursorOnBobber() or false
    if pointing and not inReach and not pointedThisCast then
        pointedThisCast = true
        Count("pointed")
    end
    Apply()
end

local function RunReachCue()
    cueTimer = nil
    if not channeling or reachedThisCast then return end
    -- the soft target as it is now, not only as the last event said
    local ok, guid = pcall(UnitGUID, "softinteract")
    if ok then SetReach(guid) end   -- never a truth test on a possibly-secret GUID
    if reachedThisCast then return end
    local want, key = Wanted()
    if not want or not UIErrorsFrame then return end
    local k = KeyText(key)
    -- pointing needs the cursor's data (WatchCursor); without it, a click on the bobber still reels
    local text = cursorWatched
        and ("Bobber out of reach. Point at it and press %s, or press %s to cast again."):format(k, k)
        or ("Bobber out of reach. Right-click it, or press %s to cast again."):format(k)
    UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
    cuedThisCast = true
    Count("cues")
end

local function ChannelStart()
    channeling = true
    reachedThisCast, pointedThisCast, cuedThisCast, lostThisCast = false, false, false, false
    inReach = false   -- the last cast's bobber (a recast can start a channel before the old one's end)
    castAt = GetTime()
    Count("casts")
    endTimer = CancelTimer(endTimer)
    if InCombatLockdown() then WatchRegen() else BeginSession() end
    ev:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
    WatchCursor(true)
    pointing = CursorOnBobber()
    local ok, guid = pcall(UnitGUID, "softinteract")
    if ok then SetReach(guid) else SetReach(nil) end   -- never a truth test on a possibly-secret GUID
    cueTimer = CancelTimer(cueTimer)
    cueTimer = C_Timer.NewTimer(CueDelay(), RunReachCue)
end

local function ChannelStop()
    channeling, inReach, pointing = false, false, false
    if ev then ev:UnregisterEvent("PLAYER_SOFT_INTERACT_CHANGED") end
    WatchCursor(false)
    cueTimer = CancelTimer(cueTimer)
    Apply()
    if sessionOn or DB().fishingRestore then EndSession() end   -- the cast is over: back at once
end

function OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if IsFishingChannel(spellID) then ChannelStart() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local _, _, spellID = ...
        if channeling and (IsFishingChannel(spellID) or ns.IsSecretV(spellID)) then ChannelStop() end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if channeling then
            local _, newTarget = ...
            SetReach(newTarget)
        end
    elseif event == "WORLD_CURSOR_TOOLTIP_UPDATE" then
        if channeling then SetPointing() end
    elseif event == "LOOT_OPENED" then
        local autoLoot = ...
        local ok, fishing = pcall(IsFishingLoot)
        if not (ok and fishing) then return end   -- a chest, a corpse: not ours to take
        -- Always take the fish ourselves, whatever Auto Loot says (harmless if the game already
        -- did: the window then has no slots).
        LootAll()
        return
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        Apply()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == MAIN_HAND then Apply(); SyncMute() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Apply()   -- the equipped pole can't always be read when the settings first apply at load
        SyncMute()
    elseif event == "PLAYER_REGEN_ENABLED" then
        regenWork = false
        ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Apply()
        if channeling then
            BeginSession()
        elseif (sessionOn or DB().fishingRestore) and not endTimer then
            EndSession()
        end
        SyncMute()
    elseif event == "PLAYER_LOGOUT" then
        RestoreCVars()
    end
end

-----------------------------
-- Public
-----------------------------
local uiRefreshers = {}
local function RefreshUI()
    for _, fn in ipairs(uiRefreshers) do pcall(fn) end
end

-- The events the key listens to while it's on; the pole's two only while a pole is required.
local CHANNEL_EVENTS = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }
local LOOT_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED" }
local POLE_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }
local ALL_KEY_EVENTS = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_SOFT_INTERACT_CHANGED" }

local function SetEvents(on, list)
    for _, e in ipairs(list) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
end

function ns.SetFishing(on)
    if type(EasyFishingDB) == "table" then MoveStats(EasyFishingDB) end
    enabled = on and true or false
    if enabled then
        EnsureFrames()
        for _, e in ipairs(CHANNEL_EVENTS) do ev:RegisterUnitEvent(e, "player") end
        SetEvents(true, LOOT_EVENTS)
        SetEvents(true, POLE_EVENTS)   -- the key needs the pole on Forever; Mute holds while it's equipped
    else
        if ev then SetEvents(false, ALL_KEY_EVENTS) end
        WatchCursor(false)
        cueTimer = CancelTimer(cueTimer)
        channeling, inReach, pointing, lootOpen = false, false, false, false
    end
    Apply()
    -- Turned off, or a session the game closed mid-way (a crash, Alt-F4): put the CVars back.
    if (not enabled and sessionOn) or (not sessionOn and DB().fishingRestore) then EndSession() end
    SyncMute()
end

function ns.SetFishingKey(key)
    if type(key) ~= "string" or key == "" then key = nil end
    DB().fishingKey = key
    Apply()
    RefreshUI()
end

-- A switch under Easy Fishing turned mid-session: on joins the session at once, off puts back
-- what it changed (combat waits for the session's end).
local function SetSub(key, on, cvars)
    DB()[key] = on and true or false
    if not sessionOn or InCombatLockdown() then return end
    RestoreCVars(cvars)
    if cvars == SOUND_ALL then boostUsed = nil end
    BeginSession()
end

function ns.SetFishingLoud(on) SetSub("fishingLoud", on, SOUND_ALL) end

-- The slider moved (its own handler has saved the value): mid-session, the volumes are put back
-- and set again by the new multiple. A slider set to the value in use changes nothing.
function ns.FishingLoudBoostChanged()
    if not sessionOn or not SubOn("fishingLoud") or boostUsed == Boost() then return end
    if InCombatLockdown() then return end
    RestoreCVars(SOUND_ALL)
    boostUsed = nil
    BeginSession()
end

function ns.SetFishingMute(on)
    SetSub("fishingMute", on, SOUND_ALL)
    if not sessionOn then SyncMute() end
end
function ns.SetFishingBackground(on) SetSub("fishingBackground", on, SOUND_ALL) end
function ns.SetFishingIcon(on) SetSub("fishingIcon", on, ICON_CVARS) end

-----------------------------
-- Settings
-----------------------------
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
-- Mouse buttons that can be a fishing key. Left and right stay the mouse's: they cancel.
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The binding string for a key pressed now, modifiers held included ("ALT-CTRL-SHIFT-F").
local function KeyChord(key)
    if type(key) ~= "string" or key == "" or MODIFIERS[key] then return nil end
    local parts = {}
    if IsAltKeyDown() then parts[#parts + 1] = "ALT" end
    if IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
    if IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
    if IsMetaKeyDown and IsMetaKeyDown() then parts[#parts + 1] = "META" end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

-- What the key does in the player's own keybinds, for the warning under it.
local function BoundTo(key)
    local ok, action = pcall(GetBindingAction, key)
    if not ok or type(action) ~= "string" or action == "" then return nil end
    local name = _G["BINDING_NAME_" .. action]
    if type(name) == "string" and name ~= "" then return name end
    local kind, rest = action:match("^(%u+) (.+)$")
    if kind == "SPELL" or kind == "ITEM" or kind == "MACRO" then return rest end
    return ""
end

local TOGGLE_DESC = "Press your fishing key to cast, then press it again to reel in when a fish bites. With Auto Loot off, the next press takes the loot."
local TOGGLE_DESC_POLE = "While a fishing pole is equipped, press your fishing key to cast, then press it again to reel in when a fish bites. If the bobber lands too far away, point at it and press the key. With Auto Loot off, the next press takes the loot."
local KEY_LABEL = "Fishing Key"
local KEY_DESC = "Click, then press a key, a mouse button or a controller button. Escape cancels."
local LOUD_LABEL = "Louder Splash"
local LOUD_DESC = "While you fish, your sound effects play louder so you can hear the splash. Your other sounds stay as loud as they are."
local BOOST_LABEL = "How Much Louder"
local BOOST_DESC = "Times your own sound effects, up to the loudest the game can play."
local MUTE_LABEL = "Mute Other Sounds"
local MUTE_DESC = "While you fish, and while a fishing pole is equipped, music, ambient sounds, dialog and pet sounds are muted."
local BG_LABEL = "Sound in Background"
local BG_DESC = "While you fish, the game's sound keeps playing when you switch to another window, so you can hear the splash from there."
local ICON_LABEL = "Icon Over the Bobber"
local ICON_DESC = "While you fish, show an icon over your bobber when your fishing key can reach it."

local function KeyNote(key)
    if not key then return "" end
    local bound = BoundTo(key)
    if not bound then return "" end
    local when = PoleOnly() and " while a fishing pole is equipped" or ""
    if bound == "" then
        return ("This key has another binding. Easy Fishing uses it%s."):format(when)
    end
    return ("This key is also bound to %s. Easy Fishing uses it%s."):format(bound, when)
end

-- The next key while a fishing key is being picked goes to this frame, shown only then. A frame
-- with a key script has its keyboard turned on by the game and, shown, takes every key: on the
-- picker button itself it swallowed Escape (and every other key) while the options panel showed. Shown, it keeps keys from the game (propagation is never turned on, so
-- nothing here is restricted in combat); hidden, it takes none.
local capFrame, capKey, capStop
local function CaptureFrame()
    if capFrame then return capFrame end
    capFrame = CreateFrame("Frame", nil, UIParent)
    capFrame:SetFrameStrata("TOOLTIP")
    capFrame:SetSize(1, 1)
    capFrame:SetPoint("TOPLEFT")
    capFrame:Hide()
    capFrame:SetScript("OnKeyDown", function(_, key) if capKey then capKey(key) end end)
    capFrame:SetScript("OnGamePadButtonDown", function(_, button) if capKey then capKey(button, true) end end)
    if not InCombatLockdown() then
        pcall(capFrame.EnableKeyboard, capFrame, true)
        if capFrame.EnableGamePadButton then pcall(capFrame.EnableGamePadButton, capFrame, true) end
    end
    return capFrame
end

-- What Easy Fishing does, as its switch says it.
local function Description()
    return PoleOnly() and TOGGLE_DESC_POLE or TOGGLE_DESC
end
ns.FishingDescription = Description

local DIM = { 0.55, 0.55, 0.6 }
local WARN = { 0.85, 0.7, 0.3 }

-- A wrapped, left-aligned line `gap` below `above`, across the panel less its 16 px gutter.
local function DescLine(content, above, gap, text, color)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, gap)
    fs:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetText(text)
    return fs
end

-- The Options > AddOns panel, under `anchor` (its description): the key,
-- the switches under Easy Fishing and the Fishing Log's row.
function ns.BuildFishingPanel(panel, anchor)
    -- The key: one button that shows the key and, clicked, waits for the next one.
    local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keyLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    keyLabel:SetText(KEY_LABEL)
    keyLabel:SetTextColor(0.85, 0.85, 0.87)
    local keyDesc = DescLine(panel, keyLabel, -2, KEY_DESC, DIM)

    local keyBtn = ns.CreateThemedButton(panel, "Not set", 160, 24, "secondary")
    keyBtn:SetPoint("TOPLEFT", keyDesc, "BOTTOMLEFT", 0, -8)
    keyBtn:RegisterForClicks("AnyUp")
    local clearBtn = ns.CreateThemedButton(panel, "Clear", 70, 24, "secondary")
    clearBtn:SetPoint("LEFT", keyBtn, "RIGHT", 8, 0)
    local note = DescLine(panel, keyBtn, -6, "", WARN)

    local capturing = false
    local function Show()
        local key = DB().fishingKey
        if capturing then
            keyBtn:SetText("Press a key...")
        else
            keyBtn:SetText(KeyText(key) or "Not set")
        end
        clearBtn:SetShown(key ~= nil and not capturing)
        note:SetText(capturing and "" or KeyNote(key))
    end
    local OnKey
    local function StopCapture()
        if not capturing then return end
        capturing = false
        if capKey == OnKey then
            capKey, capStop = nil, nil
            capFrame:Hide()
        end
        Show()
    end
    local function Take(key)
        StopCapture()
        if key then ns.SetFishingKey(key) end
    end
    function OnKey(key, pad)
        if not pad and key == "ESCAPE" then StopCapture(); return end
        local chord = KeyChord(key)
        if chord then Take(chord) end
    end

    keyBtn:SetScript("OnClick", function(_, button)
        if capturing then
            -- a middle / side button picks itself; left and right cancel
            local key = MOUSE_KEYS[button]
            if key then Take(KeyChord(key)) else StopCapture() end
            return
        end
        if button ~= "LeftButton" then return end
        if capStop then capStop() end           -- another picker was waiting
        capturing = true
        capKey, capStop = OnKey, StopCapture
        CaptureFrame():Show()
        Show()
    end)
    keyBtn:SetScript("OnHide", StopCapture)
    clearBtn:SetScript("OnClick", function() ns.SetFishingKey(nil) end)

    uiRefreshers[#uiRefreshers + 1] = Show
    Show()

    local keySpacer = CreateFrame("Frame", nil, panel)
    keySpacer:SetSize(1, 1)
    keySpacer:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, 0)   -- the note lines up with the label: one anchor

    -- Each switch's description sits under it; the frame returned is where the next control
    -- starts (at the switch's left edge, under its description).
    local function AddSub(name, key, label, desc, setter, after)
        local cb = ns.CreateToggleSwitch(panel, "EasyFishing" .. name)
        cb:SetPoint("TOPLEFT", after, "BOTTOMLEFT", 0, -10)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(0.8, 0.8, 0.8)
        cb:SetChecked(SubOn(key))
        cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
        local d = DescLine(panel, cb.Text, -2, desc, DIM)
        local below = CreateFrame("Frame", nil, panel)
        below:SetSize(1, 1)
        below:SetPoint("TOPLEFT", d, "BOTTOMLEFT", -ns.SWITCH_TEXT_X, 0)
        return below
    end

    local loudBelow = AddSub("FishingLoudCB", "fishingLoud", LOUD_LABEL, LOUD_DESC, ns.SetFishingLoud, keySpacer)
    if DB().fishingLoudBoost == nil then DB().fishingLoudBoost = BOOST_DEFAULT end  -- the slider starts where Boost() does
    local boostBelow = ns.AddSettingsSlider(panel, loudBelow, "", "fishingLoudBoost", BOOST_LABEL, BOOST_DESC,
        BOOST_MIN, BOOST_MAX, 0.5, function(v) return (v % 1 == 0 and "%dx" or "%.1fx"):format(v) end,
        ns.FishingLoudBoostChanged)
    local muteBelow = AddSub("FishingMuteCB", "fishingMute", MUTE_LABEL, MUTE_DESC, ns.SetFishingMute, boostBelow)
    local bgBelow = AddSub("FishingBackgroundCB", "fishingBackground", BG_LABEL, BG_DESC, ns.SetFishingBackground, muteBelow)
    local iconBelow = AddSub("FishingIconCB", "fishingIcon", ICON_LABEL, ICON_DESC, ns.SetFishingIcon, bgBelow)

    local spacer = CreateFrame("Frame", nil, panel)
    spacer:SetSize(1, 1)
    spacer:SetPoint("TOPLEFT", iconBelow, "BOTTOMLEFT", 0, 0)
    -- the Fishing Log's switch and Open button (FishingLog.lua)
    if ns.BuildFishingLogRow then
        return ns.BuildFishingLogRow(panel, spacer)
    end
    return spacer
end
