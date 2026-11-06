-- Stub of the WoW client API for loading EasyFishing outside the game.
--
-- Written in Lua 5.1 style (no goto, no integer division, no bitwise ops) so it also runs under
-- LuaJIT / 5.1-compatible builds. The runtime here is lupa, which may be a newer Lua.
--
-- Scripted state lives in the global WOWTEST table (tests may read or change it before/after load):
--   WOWTEST.toc          value returned as the 4th result of GetBuildInfo()
--   WOWTEST.locale      GetLocale()
--   WOWTEST.playerName  UnitName("player")
--   WOWTEST.playerGUID  UnitGUID("player")
--   WOWTEST.combat      InCombatLockdown()
--   WOWTEST.flying      IsFlying()
--   WOWTEST.now         GetTime() (fake clock, advanced by advance_timers)
--   WOWTEST.cvars       backing table for GetCVar/SetCVar
--   WOWTEST.chat        every line printed to DEFAULT_CHAT_FRAME / print()
--   WOWTEST.errors      errors raised by handlers during fire_event / advance_timers
--   WOWTEST.lootSlots   list of { name=, link=, quantity=, quality=, locked=, isQuest=, lootType= }
--   WOWTEST.items       [itemID] = { name=, link=, quality=, classID=, subclassID=, icon=, itemType=, subType= }
--   WOWTEST.spellNames  [spellID] = name
--   WOWTEST.equipped    [invSlot] = itemID
--   WOWTEST.sounds      list of PlaySound ids played
--   WOWTEST.hooks       list of { target=, name= } from hooksecurefunc
--   WOWTEST.frames      every frame created, in creation order
--   WOWTEST.secretValues  keys whose values issecretvalue() reports as secret (set to true)
--
-- Frames: CreateFrame returns a FrameMock. Methods are resolved through a metatable: capitalised
-- keys are methods, lowercase keys are plain fields. Method calls are recorded per frame in
-- WOWTEST_CALLS[frame] as { method, args... }.

-- WoW has unpack as a global (Lua 5.1); lupa may be 5.2+ where it only lives in table.unpack
unpack = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end

WOWTEST = {
    toc = 11500,
    locale = "enUS",
    playerName = "Tester",
    playerGUID = "Player-1234-00000001",
    combat = false,
    flying = false,
    now = 1000,
    cvars = {},
    chat = {},
    errors = {},
    lootSlots = {},
    items = {},
    spellNames = {},
    equipped = {},
    sounds = {},
    hooks = {},
    frames = {},
    secretValues = {},
    bindings = {},
}

-- per-frame state: { events = {}, scripts = {}, calls = {}, shown = false, w = 100, h = 30, ... }
local STATE = setmetatable({}, { __mode = "k" })
WOWTEST_CALLS = setmetatable({}, { __mode = "k" })
local TIMERS = {}
local timerSeq = 0

local function stateOf(frame)
    return STATE[frame]
end

local function record(frame, method, ...)
    local calls = WOWTEST_CALLS[frame]
    if not calls then
        calls = {}
        WOWTEST_CALLS[frame] = calls
    end
    local entry = pack(...)
    entry[0] = method
    calls[#calls + 1] = entry
end

local function callsOf(frame, method)
    local out = {}
    for _, entry in ipairs(WOWTEST_CALLS[frame] or {}) do
        if entry[0] == method then out[#out + 1] = entry end
    end
    return out
end
WOWTEST_CALLS_OF = callsOf

local function newFrame(objectType, name, parent)
    local frame = {}
    STATE[frame] = {
        objectType = objectType or "Frame",
        name = name,
        parent = parent,
        events = {},
        scripts = {},
        attrs = {},
        anims = {},
        shown = false,      -- frames start hidden; Show() on a hidden frame fires OnShow
        enabled = true,
        w = 100, h = 30,
        level = 1,
        text = "",
        value = 0,
        checked = false,
        id = 1,
        alpha = 1,
    }
    WOWTEST.frames[#WOWTEST.frames + 1] = frame
    setmetatable(frame, FrameMeta)
    return frame
end

-- Calls every handler stored under `key` for a frame, collecting errors instead of stopping.
local function runScripts(frame, scriptName, ...)
    local st = STATE[frame]
    local handlers = st and st.scripts[scriptName]
    if not handlers then return end
    for _, fn in ipairs(handlers) do
        local ok, err = pcall(fn, frame, ...)
        if not ok then
            WOWTEST.errors[#WOWTEST.errors + 1] = scriptName .. ": " .. tostring(err)
        end
    end
end

-- Methods with specific behaviour. Anything else falls back to the prefix rules in FrameMeta.
local M = {}

M.SetScript = function(self, name, fn)
    record(self, "SetScript", name)
    local st = stateOf(self)
    st.scripts[name] = fn and { fn } or nil
    return self
end
M.HookScript = function(self, name, fn)
    record(self, "HookScript", name)
    local st = stateOf(self)
    st.scripts[name] = st.scripts[name] or {}
    table.insert(st.scripts[name], fn)
    return self
end
M.GetScript = function(self, name)
    local h = stateOf(self).scripts[name]
    return h and h[1] or nil
end

M.RegisterEvent = function(self, event)
    record(self, "RegisterEvent", event)
    stateOf(self).events[event] = true
    return self
end
M.RegisterUnitEvent = function(self, event, ...)
    record(self, "RegisterUnitEvent", event, ...)
    stateOf(self).events[event] = true
    return self
end
M.UnregisterEvent = function(self, event)
    record(self, "UnregisterEvent", event)
    stateOf(self).events[event] = nil
    return self
end
M.UnregisterAllEvents = function(self)
    record(self, "UnregisterAllEvents")
    stateOf(self).events = {}
    return self
end
M.IsEventRegistered = function(self, event)
    return stateOf(self).events[event] and true or false
end

M.SetText = function(self, text)
    record(self, "SetText", text)
    stateOf(self).text = text == nil and "" or tostring(text)
    return self
end
M.GetText = function(self) return stateOf(self).text or "" end
M.SetFormattedText = M.SetText

M.SetWidth = function(self, w) record(self, "SetWidth", w); stateOf(self).w = w; return self end
M.SetHeight = function(self, h) record(self, "SetHeight", h); stateOf(self).h = h; return self end
M.SetSize = function(self, w, h) record(self, "SetSize", w, h); local st = stateOf(self); st.w = w; st.h = h; return self end
M.GetWidth = function(self) return stateOf(self).w end
M.GetHeight = function(self) return stateOf(self).h end
M.GetSize = function(self) local st = stateOf(self); return st.w, st.h end
M.GetLeft = function() return 0 end
M.GetRight = function(self) return stateOf(self).w end
M.GetTop = function(self) return stateOf(self).h end
M.GetBottom = function() return 0 end
M.GetCenter = function(self) local st = stateOf(self); return st.w / 2, st.h / 2 end
M.GetStringWidth = function(self) return #(stateOf(self).text or "") * 6 end
M.GetStringHeight = function() return 12 end
M.GetFrameLevel = function(self) return stateOf(self).level end
M.SetFrameLevel = function(self, lvl) record(self, "SetFrameLevel", lvl); stateOf(self).level = lvl; return self end
M.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
M.GetNumPoints = function() return 1 end
M.GetParent = function(self) return stateOf(self).parent end
M.GetName = function(self) return stateOf(self).name end
M.GetObjectType = function(self) return stateOf(self).objectType end
M.GetID = function(self) return stateOf(self).id end
M.SetID = function(self, id) stateOf(self).id = id; return self end
M.GetValue = function(self) return stateOf(self).value end
M.SetValue = function(self, v) record(self, "SetValue", v); stateOf(self).value = v; return self end
M.GetMinMaxValues = function() return 0, 100 end
M.GetChecked = function(self) return stateOf(self).checked end
M.SetChecked = function(self, v) record(self, "SetChecked", v); stateOf(self).checked = v and true or false; return self end
M.GetAlpha = function(self) return stateOf(self).alpha end
M.SetAlpha = function(self, a) record(self, "SetAlpha", a); stateOf(self).alpha = a; return self end
M.GetAttribute = function(self, k) return stateOf(self).attrs[k] end
M.SetAttribute = function(self, k, v) record(self, "SetAttribute", k, v); stateOf(self).attrs[k] = v; return self end
M.GetItem = function() return nil end
M.GetSpell = function() return nil end
M.GetUnit = function() return nil end
M.GetThumbTexture = function(self) return self:CreateTexture() end
M.GetNormalTexture = function(self) return self:CreateTexture() end

M.Show = function(self)
    record(self, "Show")
    local st = stateOf(self)
    if not st.shown then
        st.shown = true
        runScripts(self, "OnShow")
    end
    return self
end
M.Hide = function(self)
    record(self, "Hide")
    local st = stateOf(self)
    if st.shown then
        st.shown = false
        runScripts(self, "OnHide")
    end
    return self
end
M.SetShown = function(self, on)
    if on then return self:Show() end
    return self:Hide()
end
M.IsShown = function(self) return stateOf(self).shown end
M.IsVisible = function(self) return stateOf(self).shown end
M.IsEnabled = function(self) return stateOf(self).enabled end
M.Enable = function(self) record(self, "Enable"); stateOf(self).enabled = true; return self end
M.Disable = function(self) record(self, "Disable"); stateOf(self).enabled = false; return self end
M.SetEnabled = function(self, on) record(self, "SetEnabled", on); stateOf(self).enabled = on and true or false; return self end

M.SetOwner = function(self, owner, anchor) record(self, "SetOwner", owner, anchor); return self end
M.AddMessage = function(self, msg)
    record(self, "AddMessage", msg)
    table.insert(WOWTEST.chat, tostring(msg))
    return self
end

-- Animation: a looping group (ns.Ticker) reschedules its OnLoop script on the fake clock.
M.Play = function(self)
    record(self, "Play")
    local st = stateOf(self)
    if st.objectType == "AnimationGroup" and st.looping == "REPEAT" then
        local interval = 0.01
        for _, anim in ipairs(st.anims) do
            local d = stateOf(anim).duration or 0
            if d > 0 then interval = d end
        end
        self:Stop()
        scheduleTimer(interval, function(handle) runScripts(self, "OnLoop") end, interval, self)
    end
    return self
end
M.Stop = function(self)
    record(self, "Stop")
    local st = stateOf(self)
    for _, t in ipairs(TIMERS) do
        if t.owner == self then t.cancelled = true end
    end
    return self
end
M.SetLooping = function(self, mode) record(self, "SetLooping", mode); stateOf(self).looping = mode; return self end
M.SetDuration = function(self, d) record(self, "SetDuration", d); stateOf(self).duration = d; return self end

M.CreateFontString = function(self) return newFrame("FontString", nil, self) end
M.CreateTexture = function(self) return newFrame("Texture", nil, self) end
M.CreateMaskTexture = function(self) return newFrame("MaskTexture", nil, self) end
M.CreateAnimationGroup = function(self)
    local g = newFrame("AnimationGroup", nil, self)
    table.insert(stateOf(self).anims, g)
    return g
end
M.CreateAnimation = function(self, kind)
    local a = newFrame("Animation", nil, self)
    table.insert(stateOf(self).anims, a)
    return a
end

-- Any capitalised key not listed above: Get* -> 0, Is*/Has*/Can* -> false, Create* -> new frame,
-- anything else (Set*, Register*, Clear*, Add*, ...) records the call and returns the frame itself.
local function fallback(key)
    if key:match("^Get") then
        return function(self) return 0 end
    elseif key:match("^Is") or key:match("^Has") or key:match("^Can") then
        return function(self) return false end
    elseif key:match("^Create") then
        return function(self) return newFrame("Frame", nil, self) end
    else
        return function(self, ...)
            record(self, key, ...)
            return self
        end
    end
end

FrameMeta = {
    __index = function(frame, key)
        if type(key) ~= "string" or not key:match("^%u") then return nil end
        local m = M[key]
        if m then
            return function(self, ...)
                return m(self, ...)
            end
        end
        return fallback(key)
    end,
    __tostring = function(frame)
        local st = STATE[frame]
        return "FrameMock(" .. tostring(st and st.name or st and st.objectType or "?") .. ")"
    end,
}

-- Every frame that has a registered OnEvent script and this event fires it.
function fire_event(event, ...)
    local errs = {}
    local snapshot = {}
    for i, f in ipairs(WOWTEST.frames) do snapshot[i] = f end
    for _, frame in ipairs(snapshot) do
        local st = STATE[frame]
        if st and st.events[event] and st.scripts.OnEvent then
            local ok, err = pcall(function(...)
                for _, fn in ipairs(st.scripts.OnEvent) do fn(frame, event, ...) end
            end, ...)
            if not ok then
                errs[#errs + 1] = (st.name or st.objectType or "frame") .. " " .. event .. ": " .. tostring(err)
            end
        end
    end
    if #errs > 0 then
        for _, e in ipairs(errs) do WOWTEST.errors[#WOWTEST.errors + 1] = e end
        error(table.concat(errs, "\n"), 0)
    end
end

-- Timers ---------------------------------------------------------------------------------------

function scheduleTimer(delay, fn, interval, owner, iterations)
    timerSeq = timerSeq + 1
    local t = {
        seq = timerSeq,
        due = WOWTEST.now + (delay or 0),
        interval = interval,
        fn = fn,
        owner = owner,
        remaining = iterations,
        cancelled = false,
    }
    t.handle = {
        Cancel = function(self) t.cancelled = true end,
        IsCancelled = function(self) return t.cancelled end,
    }
    TIMERS[#TIMERS + 1] = t
    return t
end

-- Advances the fake clock by `dt` seconds (default 0) and runs every timer that comes due, in
-- order. Tickers repeat at their interval. Returns how many callbacks ran. Errors raised by
-- callbacks are collected into WOWTEST.errors and re-raised at the end.
function advance_timers(dt)
    dt = dt or 0
    local target = WOWTEST.now + dt
    local fired, errs, guard = 0, {}, 0
    while true do
        local best
        for _, t in ipairs(TIMERS) do
            if not t.cancelled and t.due <= target then
                if not best or t.due < best.due or (t.due == best.due and t.seq < best.seq) then
                    best = t
                end
            end
        end
        if not best then break end
        guard = guard + 1
        if guard > 100000 then error("advance_timers: too many timer callbacks (runaway ticker?)", 0) end
        if best.due > WOWTEST.now then WOWTEST.now = best.due end
        if best.interval then
            if best.remaining then
                best.remaining = best.remaining - 1
                if best.remaining <= 0 then best.cancelled = true end
            end
            best.due = best.due + math.max(best.interval, 0.001)
        else
            best.cancelled = true
        end
        fired = fired + 1
        local ok, err = pcall(best.fn, best.handle)
        if not ok then
            local msg = "timer: " .. tostring(err)
            errs[#errs + 1] = msg
            WOWTEST.errors[#WOWTEST.errors + 1] = msg
        end
    end
    WOWTEST.now = target
    -- drop finished timers
    local kept = {}
    for _, t in ipairs(TIMERS) do
        if not t.cancelled then kept[#kept + 1] = t end
    end
    TIMERS = kept
    if #errs > 0 then error(table.concat(errs, "\n"), 0) end
    return fired
end

-- Globals --------------------------------------------------------------------------------------

function CreateFrame(frameType, name, parent, template)
    local frame = newFrame(frameType or "Frame", name, parent)
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
STATE[UIParent].shown = true
STATE[UIParent].w, STATE[UIParent].h = 1920, 1080
WorldFrame = CreateFrame("Frame", "WorldFrame")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
DEFAULT_CHAT_FRAME = CreateFrame("ScrollingMessageFrame", "DEFAULT_CHAT_FRAME", UIParent)
ChatFrame1 = DEFAULT_CHAT_FRAME

function GameTooltip_Hide() end

-- Timers as the C_Timer namespace
C_Timer = {}
function C_Timer.After(seconds, fn)
    scheduleTimer(seconds, function() fn() end)
end
function C_Timer.NewTimer(seconds, fn)
    local t = scheduleTimer(seconds, function(handle) fn(handle) end)
    return t.handle
end
function C_Timer.NewTicker(seconds, fn, iterations)
    local t = scheduleTimer(seconds, function(handle) fn(handle) end, math.max(seconds or 0, 0.001), nil, iterations)
    return t.handle
end

-- Spells, items, tooltips, auction house ----------------------------------------------------------

C_Spell = {}
function C_Spell.GetSpellName(spellID)
    return WOWTEST.spellNames[spellID] or ("Spell " .. tostring(spellID))
end
function C_Spell.GetSpellInfo(spellID)
    local name = C_Spell.GetSpellName(spellID)
    return { name = name, spellID = spellID, iconID = 136243 }
end
function C_Spell.IsSpellKnown() return false end

C_Item = {}
function C_Item.GetItemInfoInstant(itemID)
    local it = WOWTEST.items[itemID]
    if not it then return nil end
    return itemID, it.itemType or "Weapon", it.subType or "Fishing Poles", it.equipLoc or "INVTYPE_WEAPONMAINHAND",
        it.icon or 136245, it.classID or 2, it.subclassID or 20
end
function C_Item.GetItemNameByID(itemID)
    local it = WOWTEST.items[itemID]
    return it and it.name or nil
end
function C_Item.GetItemInfo(itemID)
    local it = WOWTEST.items[itemID]
    if not it then return nil end
    return it.name, it.link, it.quality or 1, 0, 0, it.itemType, it.subType, 1, it.equipLoc, it.icon
end
function C_Item.GetItemIconByID(itemID)
    local it = WOWTEST.items[itemID]
    return it and it.icon or 134400
end
function C_Item.RequestLoadItemDataByID() end
function C_Item.IsItemDataCachedByID() return true end

function GetItemInfo(itemID) return C_Item.GetItemInfo(itemID) end
function GetItemInfoInstant(itemID) return C_Item.GetItemInfoInstant(itemID) end

C_TooltipInfo = {}
function C_TooltipInfo.GetWorldCursor() return nil end
function C_TooltipInfo.GetItemByID(itemID) return { lines = {} } end
function C_TooltipInfo.GetInventoryItem() return nil end
function C_TooltipInfo.GetSpellByID() return { lines = {} } end

C_Texture = {}
function C_Texture.GetAtlasInfo(atlas) return nil end

-- The auction house: every call the addon makes, with empty results. Unknown calls go to a noop.
C_AuctionHouse = setmetatable({
    MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0 } end,
    GetNumItemSearchResults = function(itemKey) return 0 end,
    GetItemSearchResultInfo = function(itemKey, index) return nil end,
    GetNumCommoditySearchResults = function(itemID) return 0 end,
    GetCommoditySearchResultInfo = function(itemID, index) return nil end,
    GetBrowseResults = function() return {} end,
    HasFullBrowseResults = function() return true end,
    IsThrottledMessageSystemReady = function() return true end,
    GetAvailablePostCount = function() return 0 end,
    SearchForItemKeys = function() return true end,
    SendSearchQuery = function() end,
    SendBrowseQuery = function() end,
    RequestMoreBrowseResults = function() end,
    ReplicateItems = function() end,
    SendSellSearchQuery = function() end,
}, {
    __index = function(t, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end,
})

-- Enums and constants ---------------------------------------------------------------------------

local function autoTable(defaultValue)
    return setmetatable({}, {
        __index = function(t, k)
            if type(k) ~= "string" then return nil end
            local v = defaultValue
            rawset(t, k, v)
            return v
        end,
    })
end

Enum = setmetatable({}, {
    __index = function(t, k)
        local sub = autoTable(0)
        rawset(t, k, sub)
        return sub
    end,
})
Enum.AuctionHouseSortOrder = { Price = 0, Name = 1, Quantity = 2 }
Enum.ItemClass = { Weapon = 2, Consumable = 0, Reagent = 5, Tradegoods = 7, Miscellaneous = 15 }
Enum.ItemWeaponSubclass = { Fishingpole = 20 }
Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
Enum.SoftTargetEnableFlags = { Any = 3, Gamepad = 1, Keyboard = 2 }

SOUNDKIT = autoTable(0)
SOUNDKIT.IG_MAINMENU_OPEN = 850
SOUNDKIT.IG_MAINMENU_CLOSE = 851
SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK = 9999

INVSLOT_MAINHAND = 16
INVSLOT_OFFHAND = 17
ITEM_QUALITY_COLORS = {}
for q = 0, 7 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end

-- Settings (Options > AddOns) -------------------------------------------------------------------

local categoryMeta = {
    __index = function(t, k)
        if k == "GetID" then return function(self) return self.id end end
        return nil
    end,
}
local nextCategoryID = 0
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        nextCategoryID = nextCategoryID + 1
        return setmetatable({ frame = frame, name = name, id = nextCategoryID }, categoryMeta)
    end,
    RegisterAddOnCategory = function(category)
        WOWTEST.registeredCategories = (WOWTEST.registeredCategories or 0) + 1
    end,
    OpenToCategory = function(id)
        WOWTEST.openedCategory = id
        return true
    end,
}

-- Chat, slash commands, print --------------------------------------------------------------------

SlashCmdList = {}

function print(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    table.insert(WOWTEST.chat, table.concat(parts, " "))
end

-- Client state -----------------------------------------------------------------------------------

function GetTime() return WOWTEST.now end
function GetBuildInfo() return "1.15.0", "1", "Nov 1 2026", WOWTEST.toc end
function GetLocale() return WOWTEST.locale end
function InCombatLockdown() return WOWTEST.combat and true or false end
function IsFlying() return WOWTEST.flying and true or false end
function IsMounted() return false end
function IsSwimming() return false end
function IsMouselooking() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsModifierKeyDown() return false end
function IsMetaKeyDown() return false end
function UnitName(unit) if unit == "player" then return WOWTEST.playerName end return nil end
function UnitGUID(unit) if unit == "player" then return WOWTEST.playerGUID end return nil end
function UnitExists(unit) return unit == "player" end
function GetInventoryItemID(unit, slot) return WOWTEST.equipped[slot] end
-- Values listed in WOWTEST.secretValues (as keys) count as secret, as the client hides some values from addons.
function issecretvalue(v) return v ~= nil and WOWTEST.secretValues[v] == true end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetCursorPosition() return 0, 0 end
function GetSpellInfo(spellID)
    local name = C_Spell.GetSpellName(spellID)
    return name, nil, 136243
end
function GetBindingAction(key) return "" end
-- Override bindings are recorded in WOWTEST.bindings (key = command) but never acted on.
function ClearOverrideBindings(owner) WOWTEST.bindings = {} end
function SetOverrideBinding(owner, isPriority, key, command) WOWTEST.bindings[key] = command end
function SetOverrideBindingClick(owner, isPriority, key, button, mouseButton)
    WOWTEST.bindings[key] = "CLICK " .. tostring(button)
end
function GetBindingKey(action) return nil end
function SecureCmdOptionParse(cmd) return cmd end
function PlaySound(id, ...)
    table.insert(WOWTEST.sounds, id)
    return true, 1
end
function PlaySoundFile(path) return true, 1 end
function StopSound() end

function GetCVar(name)
    local v = WOWTEST.cvars[name]
    if v == nil then return nil end
    return tostring(v)
end
function GetCVarBool(name)
    local v = GetCVar(name)
    return v == "1"
end
function SetCVar(name, value)
    WOWTEST.cvars[name] = tostring(value)
    return true
end

-- Loot window -------------------------------------------------------------------------------------

function GetNumLootItems() return #WOWTEST.lootSlots end
function GetLootSlotInfo(slot)
    local s = WOWTEST.lootSlots[slot]
    if not s then return nil end
    return s.icon or 134400, s.name, s.quantity or 1, s.quality or 1, s.locked or false, s.isQuest or false, s.lootType or 1
end
function GetLootSlotLink(slot)
    local s = WOWTEST.lootSlots[slot]
    return s and s.link or nil
end
function LootSlot(slot)
    WOWTEST.lootedSlots = WOWTEST.lootedSlots or {}
    table.insert(WOWTEST.lootedSlots, slot)
end
-- true while WOWTEST.fishingLoot is set: the open loot window came from a bobber
function IsFishingLoot() return WOWTEST.fishingLoot == true end
function LootAll() end
function CloseLoot() end

-- Lua utilities that WoW defines as globals --------------------------------------------------------

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
tinsert = table.insert
tremove = table.remove

function strsplit(delim, s, ...)
    if delim == nil or delim == "" then delim = " " end
    s = tostring(s or "")
    local parts, pos = {}, 1
    while true do
        local i, j = string.find(s, delim, pos, true)
        if not i then
            parts[#parts + 1] = string.sub(s, pos)
            break
        end
        parts[#parts + 1] = string.sub(s, pos, i - 1)
        pos = j + 1
    end
    return unpack(parts)
end
function strtrim(s) return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1")) end
function strjoin(delim, ...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    return table.concat(parts, delim or "")
end
strlen = string.len
strlower = string.lower
strupper = string.upper
format = string.format
function mod(a, b) return a % b end
time = os.time
date = os.date
function debugstack() return "" end

function Mixin(obj, ...)
    for i = 1, select("#", ...) do
        local src = select(i, ...)
        for k, v in pairs(src) do obj[k] = v end
    end
    return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

function hooksecurefunc(a, b, c)
    local target, name, hook
    if type(a) == "string" then
        target, name, hook = _G, a, b
    else
        target, name, hook = a, b, c
    end
    table.insert(WOWTEST.hooks, { target = target, name = name })
    local orig = target[name]
    if type(orig) ~= "function" then return end
    target[name] = function(...)
        local res = pack(orig(...))
        hook(...)
        return unpack(res, 1, res.n)
    end
end

-- Keep table.getn-style helpers out of the way: WoW has no table.getn in 5.1 either.
-- Spelled out here so that a stray `unpack` call in the addon fails the same way it would in-game.
