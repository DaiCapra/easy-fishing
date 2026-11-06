-- EasyFishing Fishing Log (Professions tab, Fishing section, both menus, both games)
-- What you catch, in a window: catches, catches per hour, your Fishing skill with what it
-- gained, the latest catch and everything caught. Fishing loot is told apart by the loot window
-- itself (IsFishingLoot, what Blizzard's own loot window checks), with Auto Loot on or off, read at
-- LOOT_READY or LOOT_OPENED, once per window. Casts count at the start of a Fishing channel (ns.IsFishingChannel),
-- whether or not Easy Fishing cast it.
--
-- The window opens by itself at a cast while the log is on (`fishingLog`, default on), and once
-- closed stays closed for that session (`/ef show` opens it again). The session is the character's
-- (EasyFishingCharDB.fishingSession): time counts while fishing (IDLE), 15 minutes without a cast or a
-- catch starts a new one at the next, the old one going to History (EasyFishingCharDB.fishingHistory,
-- the last 50). Events only while the log is on.

local addonName, ns = ...

local IDLE = 90        -- seconds between casts that still count as fishing
local GAP = 900        -- seconds without fishing before the next cast starts a new session
local HISTORY = 50
local FISHING_LINE = 356
local FISHING_TIER = 2911  -- Midnight Fishing; retail's current expansion (update with the next one)
local S = ns.LootSession
local CharDB = ns.CharDB

local ev, win, ticker
local lootSeen = false    -- this loot window has been read

local function Now() return time() end

-- A finished session as its History entry.
local function Entry(s, now)
    return S.Archive(s, now, IDLE, { catches = s.catches, casts = s.casts, gain = s.gain })
end

local function Archive(s)
    if not s or (s.catches or 0) == 0 then return end
    local db = CharDB()
    local hist = type(db.fishingHistory) == "table" and db.fishingHistory or {}
    table.insert(hist, 1, Entry(s, Now()))
    while #hist > HISTORY do table.remove(hist) end
    db.fishingHistory = hist
end

-- The session now; a stale one goes to History and a new one starts (when `start` is set).
local function Session(start)
    local db = CharDB()
    local s = db.fishingSession
    if type(s) ~= "table" or type(s.items) ~= "table" then s = nil end
    if start and S.Stale(s, Now(), GAP) then
        Archive(s)
        s = S.New(Now())
        s.casts, s.catches = 0, 0
        db.fishingSession = s
    end
    return s
end

local function Skill(s)
    local sk = ns.LootLogSkill(FISHING_LINE, FISHING_TIER)
    if not sk then return nil end
    if s then
        if not s.skill0 or s.skillName ~= sk.name then s.skill0, s.skillName = sk.cur, sk.name end
        s.gain = sk.cur - s.skill0
        sk.gain = s.gain
    end
    return sk
end

local function Model()
    local s = Session(false) or S.New(Now())
    local now = Now()
    local elapsed = S.Elapsed(s, now, IDLE)
    local rows = S.Shares(S.Rows(s, "count"))   -- each catch's share of everything caught
    local perHour = ns.LootLogPerHour(s.catches, elapsed)
    local latest = ns.LootLatestCard(s, "catch")
    local footer
    if (s.casts or 0) > 0 then
        footer = ("%d %s · %d%% caught"):format(s.casts, s.casts == 1 and "cast" or "casts",
            math.floor(math.min(1, (s.catches or 0) / s.casts) * 100 + 0.5))
    end
    local skill = Skill(s)
    return {
        timer = elapsed,
        stats = {
            { label = "Catches", value = tostring(s.catches or 0) },
            { label = "Per hour", value = perHour and tostring(math.floor(perHour + 0.5)) or "--" },
        },
        skills = skill and { skill } or nil,
        latest = latest,
        items = rows,
        footer = footer,
        empty = "Cast to start your log.",
    }
end

local function Refresh()
    if win and win:IsShown() then win:Set(Model()) end
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function NewSession()
    Archive(Session(false))
    local s = S.New(Now())
    s.casts, s.catches = 0, 0
    CharDB().fishingSession = s
    Refresh()
end

local function Window()
    if win then return win end
    win = ns.CreateLootLog({
        name = "EasyFishingLog", title = "Fishing", icon = "Interface\\Icons\\Trade_Fishing",
        posKey = "fishingLogPos",
        gear = { tab = "professions", section = "fishing", tip = "Fishing settings" },
        buttons = {
            { text = "History", width = 56, history = true },
            { text = "New session", width = 80, onClick = NewSession },
        },
        history = {
            title = "Fishing History",
            get = function() return CharDB().fishingHistory end,
            describe = function(e)
                local line = ("%d %s"):format(e.catches or 0, (e.catches or 0) == 1 and "catch" or "catches")
                if (e.gain or 0) > 0 then line = line .. (" · Fishing +%d"):format(e.gain) end
                return line
            end,
        },
        onShow = function()
            if not ticker then ticker = ns.Ticker.New(1, Refresh) end
        end,
        onHide = StopTicker,
        onClose = function() ns.LootLogClosed(Session(false), "Fishing Log", "fishing", "/ef show") end,
    })
    return win
end

local function Open(force)
    local s = Session(false)
    if s and s.hidden and not force then return end
    if s then s.hidden = nil end
    local w = Window()
    w:Set(Model())
    w:Show()
end

function ns.FishingLogToggle()
    if win and win:IsShown() then
        local s = Session(false)
        if s then s.hidden = true end
        win:Hide()
    else
        Open(true)
    end
end

function ns.FishingLogShow() Open(true) end

function ns.FishingLogHide()
    if win and win:IsShown() then
        local s = Session(false)
        if s then s.hidden = true end
        win:Hide()
    end
end

-- A Fishing channel began.
local function OnCast()
    local s = Session(true)
    S.Touch(s, Now(), IDLE)
    s.casts = (s.casts or 0) + 1
    Skill(s)
    Open(false)
    Refresh()
end

-- A fishing loot window: every item in it, the best of them the latest catch.
local function OnLoot()
    local s = Session(true)
    local now = Now()
    S.Touch(s, now, IDLE)
    s.catches = (s.catches or 0) + 1
    local found, best = ns.LootWindowItems()
    for _, f in ipairs(found) do S.Add(s, f.item, f.count, now) end
    if best then s.latest = ns.LootLatest(found, best, now) end
    Skill(s)
    Open(false)
    Refresh()
    if best and win then win:Celebrate(best.item.quality) end
end

local function OnEvent(_, event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if ns.IsFishingChannel and ns.IsFishingChannel(spellID) then OnCast() end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        -- whichever comes first with the window's fishing flag set (Blizzard's loot window reads
        -- it at LOOT_OPENED), once per window
        if lootSeen then return end
        local ok, fishing = pcall(IsFishingLoot)
        if not (ok and fishing) then return end
        lootSeen = true
        OnLoot()
    elseif event == "LOOT_CLOSED" then
        lootSeen = false
    elseif event == "SKILL_LINES_CHANGED" then
        Refresh()
    end
end

function ns.SetFishingLog(on)
    if on then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", OnEvent)
        end
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        ev:RegisterEvent("LOOT_READY")
        ev:RegisterEvent("LOOT_OPENED")
        ev:RegisterEvent("LOOT_CLOSED")
        ev:RegisterEvent("SKILL_LINES_CHANGED")
    else
        if ev then ev:UnregisterAllEvents() end
        lootSeen = false
        if win then win:Hide() end
    end
end

-----------------------------
-- Settings (in the Fishing section, both menus)
-----------------------------
local LOG_LABEL = "Fishing Log"
local LOG_DESC = "A window that opens when you fish: what you catch, catches per hour and your Fishing skill. Also /ef show and /ef hide."

-- Adds the switch and an Open button under `anchor`; returns the last element.
function ns.BuildFishingLogRow(content, anchor)
    local AddCB, GetLast, SetLast = ns.MakeCheckboxFactory(content, anchor)
    AddCB("FishingLog", "fishingLog", LOG_LABEL, LOG_DESC, ns.SetFishingLog)
    local open = ns.CreateThemedButton(content, "Open Fishing Log", 130, 22, "secondary")
    open:SetPoint("TOPLEFT", GetLast(), "BOTTOMLEFT", 0, -8)
    open:SetScript("OnClick", function() Open(true) end)
    SetLast(open)
    return GetLast()
end
