-- EasyFishing loot log: the window the Fishing Log, the Reagent Log and the Salvage Log share, the
-- rules they keep a session by, and the loot window's reader. Retail and WoW: Forever alike.
--
-- A log is a session: it counts time only while you're at it (each activity adds the time since
-- the one before, up to the log's `idle` seconds, so a break doesn't lower the per-hour numbers),
-- and an activity after `gap` seconds of nothing starts a new one, the old one going to History.
-- Times are time() seconds, so a session carries over a /reload or a relog.
--
-- Money shows each coin in its own colour.
--
-- The window: title bar (icon, title, timer, close), three stat tiles, up to two skill bars with
-- the gain this session, the latest item (its quality colour, scaled in when new, a glow for rare
-- and better), the items (icon in a quality border, item tooltip on hover, Shift-click links it),
-- a footer line and buttons. Movable; its position is EasyFishingDB[posKey]. Made on first use,
-- never at load. Its History button opens a panel under it (above it when there's no room below):
-- the past sessions newest first, one card each (when it started, the log's own line and how long
-- it lasted, its items as icons with their counts and a tooltip each), scrolled with the mouse
-- wheel; closed with the button, its own close button, or the window.

local _, ns = ...

local CYAN = ns.CYAN
local C = ns.COLORS
local WIDTH = 300
local PAD = 10
local TITLE_H = 30
local TILE_H = 44
local SKILL_H = 26
local LATEST_H = 46
local ALSO_H = 24       -- the latest card's row of what else came with it
local ALSO_MAX = 7
local ROW_H = 22
local MAX_ROWS = 10
local MAX_SKILLS = 2
local HIST_H = 300      -- the History panel
local HIST_ROW = 66     -- one past session
local HIST_ICONS = 8    -- the items a History entry keeps (S.Archive)

-----------------------------
-- Sessions (pure: the tests run them)
-----------------------------
local S = {}
ns.LootSession = S

function S.New(now)
    return { start = now, last = now, active = 0, items = {}, order = {} }
end

-- An activity at `now`: the time since the last one counts, up to `idle`.
function S.Touch(s, now, idle)
    local d = now - (s.last or now)
    if d > 0 then s.active = (s.active or 0) + math.min(d, idle) end
    s.last = now
end

-- Seconds of the session so far, the stretch since the last activity counted up to `idle`.
function S.Elapsed(s, now, idle)
    local d = now - (s.last or now)
    return (s.active or 0) + math.max(0, math.min(d, idle))
end

function S.Stale(s, now, gap)
    return s == nil or now - (s.last or 0) > gap
end

-- Adds `count` of an item ({ id, link, name, icon, quality }).
function S.Add(s, item, count, now)
    local e = s.items[item.id]
    if not e then
        e = { n = item.name, i = item.icon, q = item.quality, l = item.link, c = 0 }
        s.items[item.id] = e
        s.order[#s.order + 1] = item.id
    end
    e.c = e.c + count
    if item.link then e.l = item.link end
    if item.name then e.n = item.name end
    if item.icon then e.i = item.icon end
    if item.quality then e.q = item.quality end
end

-- The session's items as display rows, the most found first.
function S.Rows(s)
    local rows = {}
    for _, id in ipairs(s.order) do
        local e = s.items[id]
        if e then
            rows[#rows + 1] = { id = id, link = e.l, name = e.n, icon = e.i, quality = e.q, count = e.c }
        end
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- A finished session as a History entry (the top items only).
function S.Archive(s, now, idle, extra)
    local rows = S.Rows(s)
    local items = {}
    for i = 1, math.min(#rows, 8) do
        local r = rows[i]
        items[i] = { n = r.name, i = r.icon, q = r.quality, c = r.count }
    end
    local entry = { date = s.start, elapsed = S.Elapsed(s, s.last or now, idle), items = items }
    for k, v in pairs(extra or {}) do entry[k] = v end
    return entry
end

-----------------------------
-- Quality
-----------------------------
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 } }
local function QualityColor(q)
    q = tonumber(q) or 1
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    c = QUALITY[q] or QUALITY[1]
    return c[1], c[2], c[3]
end

-- "Rare", "Epic"... in the player's language.
local QUALITY_WORDS = { [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom" }
local function QualityWord(q)
    local w = _G["ITEM_QUALITY" .. tostring(q) .. "_DESC"]
    return type(w) == "string" and w ~= "" and w or QUALITY_WORDS[tonumber(q)] or "Rare"
end

-----------------------------
-- The loot window, and the cast it follows
-----------------------------
local LOOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1

-- The items in the open loot window ({ item = { id, link, name, icon, quality }, count }) and the
-- best of them (highest quality, the first on a tie). Money, currency and secret links left out.
function ns.LootWindowItems()
    local found, best = {}, nil
    for slot = 1, (GetNumLootItems() or 0) do
        local okType, kind = pcall(GetLootSlotType, slot)
        if okType and kind == LOOT_ITEM then
            local link = ns.Unsecret(GetLootSlotLink(slot))
            if type(link) == "string" then
                local id = tonumber(link:match("|Hitem:(%d+)"))
                if id then
                    local icon, name, qty, _, quality = GetLootSlotInfo(slot)
                    local f = {
                        item = { id = id, link = link, name = ns.Unsecret(name), icon = ns.Unsecret(icon),
                            quality = tonumber(ns.Unsecret(quality)) or 1 },
                        count = math.max(1, tonumber(ns.Unsecret(qty)) or 1),
                    }
                    found[#found + 1] = f
                    if not best or f.item.quality > best.item.quality then best = f end
                end
            end
        end
    end
    return found, best
end

-- The latest find: everything one loot window (or one salvage cast) brought, each item once,
-- the best first on the card and the rest beside it, better ones first. Saved in the session as
-- { id, c, at, also = { { id, c } } }; the names and icons come from the session's items.
function ns.LootLatest(found, best, now)
    local byId, list = {}, {}
    for _, f in ipairs(found) do
        local e = byId[f.item.id]
        if e then
            e.c = e.c + f.count
        else
            e = { id = f.item.id, c = f.count, q = f.item.quality or 1, n = #list }
            byId[f.item.id] = e
            list[#list + 1] = e
        end
    end
    local top = byId[best.item.id]
    local also = {}
    for _, e in ipairs(list) do
        if e ~= top then also[#also + 1] = e end
    end
    table.sort(also, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.n < b.n end)
    for i, e in ipairs(also) do also[i] = { id = e.id, c = e.c } end
    return { id = top.id, c = top.c, at = now, also = also }
end

-- The window's latest card from a session's latest find; `word` is "find" or "catch".
function ns.LootLatestCard(s, word)
    local l = s and s.latest
    if type(l) ~= "table" or type(s.items) ~= "table" then return nil end
    local function Row(id, c)
        local e = s.items[id]
        if type(e) ~= "table" then return nil end
        return { id = id, link = e.l, name = e.n, icon = e.i, quality = tonumber(e.q) or 1, count = tonumber(c) or 1 }
    end
    local card = Row(l.id, l.c)
    if not card then return nil end
    card.at = l.at
    card.label = card.quality >= 3 and (QualityWord(card.quality) .. " " .. word) or ("Latest " .. word)
    card.also = {}
    for _, o in ipairs(type(l.also) == "table" and l.also or {}) do
        local r = type(o) == "table" and Row(o.id, o.c)
        if r then card.also[#card.also + 1] = r end
    end
    return card
end

-- A log closed with its X stays closed for the rest of its session (a find, catch or salvage every
-- minute or so would otherwise bring it straight back). Said once a session, the first time it's
-- closed, so the player knows why it doesn't open and how to get it back (Oct 2026: closed at the
-- Auction House, the Reagent Log stayed shut on the way back out with nothing saying why).
function ns.LootLogClosed(s, title, kind, command)
    if type(s) ~= "table" then return end
    s.hidden = true
    if s.closeSaid then return end
    s.closeSaid = true
    ns.Print((ns.TAG .. " %s closed until your next %s session. Type %s to open it."):format(title, kind, command))
end

-----------------------------
-- Words and numbers
-----------------------------
local function Commas(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- Each coin in its colour, as the game shows money: "|cffffd7004g|r |cffc7c7cf12s|r".
local GOLD, SILVER, COPPER = "|cffffd700", "|cffc7c7cf", "|cffeda55f"
function ns.LootLogMoney(copper)
    if not copper then return "--" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local gs = GOLD .. Commas(g) .. "g|r"
    if g >= 100 then return gs end
    if g > 0 then return s > 0 and (gs .. " " .. SILVER .. s .. "s|r") or gs end
    if s > 0 then return SILVER .. s .. "s|r" end
    return COPPER .. c .. "c|r"
end

local function Clock(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h, m, s = math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

local function Ago(t, now)
    local d = math.max(0, (now or time()) - (t or 0))
    if d < 60 then return "just now" end
    if d < 3600 then return ("%d min ago"):format(math.floor(d / 60)) end
    return ("%d h ago"):format(math.floor(d / 3600))
end

-- Per hour, once there's a minute to go by.
function ns.LootLogPerHour(n, secs)
    if not n or not secs or secs < 60 then return nil end
    return n / secs * 3600
end

-- A profession's skill as { name, cur, max }: retail's current-expansion tier (`tier`, a skill line
-- such as Midnight Fishing), else the profession itself (WoW: Forever's 1-300 skill). nil when the
-- character doesn't have it.
function ns.LootLogSkill(line, tier)
    if tier and not ns.IS_FOREVER and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, tier)
        if ok and type(info) == "table" and (tonumber(info.skillLevel) or 0) > 0 then
            return { name = info.professionName or "", cur = info.skillLevel, max = info.maxSkillLevel or info.skillLevel }
        end
    end
    if not GetProfessions or not GetProfessionInfo then return nil end
    local list = { pcall(GetProfessions) }
    if not list[1] then return nil end
    for k = 2, 11 do   -- WoW: Forever leaves a gap (nil) for each profession not learned
        local idx = list[k]
        if idx then
            local ok, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
            if ok and skillLine == line and tonumber(rank) then
                return { name = name or "", cur = rank, max = tonumber(maxRank) or rank }
            end
        end
    end
end

-- "Oct 21, 2:17 AM": a session's start in History.
local function StartDate(t)
    local d = date("*t", t or 0)
    local h = d.hour % 12
    if h == 0 then h = 12 end
    return ("%s %d, %d:%02d %s"):format(date("%b", t or 0), d.day, h, d.min, d.hour < 12 and "AM" or "PM")
end

-- "7 min", "1 h 12 min": how long a session lasted.
local function Duration(secs)
    local m = math.floor((tonumber(secs) or 0) / 60)
    if m < 1 then return "under a minute" end
    if m < 60 then return m .. " min" end
    return ("%d h %d min"):format(math.floor(m / 60), m % 60)
end

-----------------------------
-- The window
-----------------------------
local function Fill(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a or 1) end

local function Text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

-- An icon in a 1px border of its quality's colour.
local function QualityIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size + 2, size + 2)
    holder.border = holder:CreateTexture(nil, "BACKGROUND")
    holder.border:SetAllPoints()
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("TOPLEFT", 1, -1)
    holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function holder:Set(icon, quality)
        self.icon:SetTexture(icon or 134400)   -- the question-mark icon
        local r, g, b = QualityColor(quality)
        local a = (tonumber(quality) or 1) <= 1 and 0.35 or 0.9
        Fill(self.border, r, g, b, a)
    end
    return holder
end

-- The item's own tooltip.
local function ItemTooltip(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.item.link then GameTooltip:SetHyperlink(self.item.link)
    elseif self.item.id then GameTooltip:SetItemByID(self.item.id) end
    GameTooltip:Show()
end

-- Shift-click and the game's other item clicks link it; a plain click does nothing.
local function ItemClick(self)
    local link = self.item and self.item.link
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

local function HistoryIconTip(self)
    local it = self.it
    if not it then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(it.n or it.name or "?", QualityColor(it.q))
    GameTooltip:AddLine("x" .. (it.c or it.count or 0), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- opts: name, title, icon, posKey, buttons = { { text, width, onClick, history } } (a button with
-- `history` opens the History panel), history = { title, get () -> entries, describe (entry) -> its
-- line }, onShow, onHide, onClose (the close button). Returns the log: :Show(), :Hide(), :IsShown(),
-- :Set(model), :Celebrate(quality).
-- model: timer (seconds), stats = { { label, value, tip } x3 }, skills = { { name, cur, max, gain } },
-- latest = { item row, label, at, also = { item rows } }, items (rows from S.Rows), footer, empty.
function ns.CreateLootLog(opts)
    local log = {}
    local f
    local hist, histSig   -- the History panel, made on first open; what it last drew

    local function BuildHistory()
        hist = CreateFrame("Frame", opts.name .. "History", f, "BackdropTemplate")
        hist:SetSize(WIDTH, HIST_H)
        ns.ApplyPanelBackdrop(hist)
        hist:EnableMouse(true)
        hist.title = Text(hist, "GameFontNormal", CYAN.r, CYAN.g, CYAN.b)
        hist.title:SetPoint("TOPLEFT", PAD, -9)
        hist.title:SetText(opts.history.title)
        local close = CreateFrame("Button", nil, hist, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, -1)
        close:SetScript("OnClick", function() hist:Hide() end)
        hist.count = Text(hist, "GameFontHighlightSmall", 0.6, 0.6, 0.65)
        hist.count:SetPoint("RIGHT", close, "LEFT", -4, 0)
        local sf = CreateFrame("ScrollFrame", nil, hist, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", PAD, -TITLE_H)
        sf:SetPoint("BOTTOMRIGHT", -28, PAD)
        local child = CreateFrame("Frame", nil, sf)
        child:SetSize(WIDTH - PAD - 28, 1)
        sf:SetScrollChild(child)
        hist.scroll, hist.child, hist.rows = sf, child, {}
        hist.empty = Text(hist, "GameFontDisableSmall")
        hist.empty:SetPoint("TOP", hist, "TOP", 0, -TITLE_H - 24)
        hist.empty:SetText("Your past sessions show here.")
        hist:Hide()
    end

    local function HistoryRow(i)
        if hist.rows[i] then return hist.rows[i] end
        local r = CreateFrame("Frame", nil, hist.child)
        r:SetSize(WIDTH - PAD - 28, HIST_ROW - 4)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        Fill(bg, C.bgCard[1], C.bgCard[2], C.bgCard[3], 0.55)
        r.when = Text(r, "GameFontHighlightSmall")
        r.when:SetPoint("TOPLEFT", 6, -5)
        r.line = Text(r, "GameFontDisableSmall")
        r.line:SetPoint("TOPLEFT", 6, -19)
        r.line:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.line:SetJustifyH("LEFT")
        r.line:SetWordWrap(false)
        r.icons = {}
        for k = 1, HIST_ICONS do
            local b = CreateFrame("Button", nil, r)
            b:SetSize(22, 22)
            b:SetPoint("BOTTOMLEFT", 5 + (k - 1) * 30, 5)
            b.icon = QualityIcon(b, 20)
            b.icon:SetPoint("CENTER")
            b.count = Text(b, "NumberFontNormalSmall")
            b.count:SetPoint("BOTTOMRIGHT", 3, -1)
            b:SetScript("OnEnter", HistoryIconTip)
            b:SetScript("OnLeave", GameTooltip_Hide)
            r.icons[k] = b
        end
        hist.rows[i] = r
        return r
    end

    local function HistoryList()
        local list = opts.history.get and opts.history.get()
        return type(list) == "table" and list or {}
    end

    local function DrawHistory()
        local list = HistoryList()
        histSig = #list .. ":" .. tostring(list[1] and list[1].date)
        hist.count:SetText(#list == 1 and "1 session" or (#list .. " sessions"))
        for i, e in ipairs(list) do
            local r = HistoryRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * HIST_ROW)
            r.when:SetText(StartDate(e.date))
            local line = opts.history.describe and opts.history.describe(e)
            local long = Duration(e.elapsed)
            r.line:SetText((line and line ~= "") and (line .. " · " .. long) or long)
            local items = type(e.items) == "table" and e.items or {}
            for k, b in ipairs(r.icons) do
                local it = items[k]
                if it then
                    local n = tonumber(it.c or it.count) or 0
                    b.it = it
                    b.icon:Set(it.i or it.icon, it.q)
                    b.count:SetText(n > 1 and tostring(n) or "")
                    b:Show()
                else
                    b.it = nil
                    b:Hide()
                end
            end
            r:Show()
        end
        for i = #list + 1, #hist.rows do hist.rows[i]:Hide() end
        hist.child:SetHeight(math.max(1, #list * HIST_ROW))
        hist.empty:SetShown(#list == 0)
    end

    -- Under the window, or above it when there's no room below.
    local function ToggleHistory()
        if not hist then BuildHistory() end
        if hist:IsShown() then hist:Hide(); return end
        hist:ClearAllPoints()
        local bottom = f:GetBottom()
        if bottom and bottom < HIST_H + 20 then
            hist:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
        else
            hist:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
        end
        DrawHistory()
        if hist.scroll.SetVerticalScroll then hist.scroll:SetVerticalScroll(0) end
        hist:Show()
    end

    local function Build()
        f = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
        f:SetSize(WIDTH, 200)
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -220)
        ns.ApplyPanelBackdrop(f)
        f:SetFrameStrata("MEDIUM")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            ns.DB()[opts.posKey] = { point, relPoint, x, y }
        end)
        local pos = ns.DB()[opts.posKey]
        if type(pos) == "table" and pos[1] then
            f:ClearAllPoints()
            f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
        if ns.CreateCyanAccentLine then ns.CreateCyanAccentLine(f) end
        f:SetScript("OnShow", function() if opts.onShow then opts.onShow() end end)
        f:SetScript("OnHide", function()
            if hist then hist:Hide() end   -- the next open starts without them
            if opts.onHide then opts.onHide() end
        end)

        -- Title bar
        local bar = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        bar:SetPoint("TOPLEFT", 1, -3)
        bar:SetPoint("TOPRIGHT", -1, -3)
        bar:SetHeight(TITLE_H - 3)
        Fill(bar, 0.07, 0.10, 0.12, 0.9)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", PAD, -8)
        icon:SetTexture(opts.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local title = Text(f, "GameFontNormal", CYAN.r, CYAN.g, CYAN.b)
        title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        title:SetText(opts.title)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, -1)
        close:SetScript("OnClick", function()
            if opts.onClose then opts.onClose() end   -- the player closed it (not the UI hiding)
            f:Hide()
        end)
        f.timer = Text(f, "GameFontHighlightSmall", 0.6, 0.6, 0.65)
        f.timer:SetPoint("RIGHT", close, "LEFT", -21, 0)

        -- Stat tiles
        f.tiles = {}
        local tileW = (WIDTH - PAD * 2 - 12) / 3
        for i = 1, 3 do
            local t = CreateFrame("Frame", nil, f)
            t:SetSize(tileW, TILE_H)
            t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + 6), -(TITLE_H + 6))
            local bg = t:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            Fill(bg, C.bgCard[1], C.bgCard[2], C.bgCard[3], 0.55)
            t.label = Text(t, "GameFontDisableSmall")
            t.label:SetPoint("TOPLEFT", 7, -6)
            t.value = Text(t, "GameFontHighlightLarge")
            t.value:SetPoint("BOTTOMLEFT", 7, 6)
            t.value:SetPoint("RIGHT", t, "RIGHT", -4, 0)
            t.value:SetJustifyH("LEFT")
            t.value:SetWordWrap(false)
            t:SetScript("OnEnter", function(self)
                if not self.tip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.label:GetText() or "", 1, 1, 1)
                GameTooltip:AddLine(self.tip, 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            t:SetScript("OnLeave", GameTooltip_Hide)
            f.tiles[i] = t
        end

        -- Skill bars
        f.skills = {}
        for i = 1, MAX_SKILLS do
            local s = CreateFrame("Frame", nil, f)
            s:SetSize(WIDTH - PAD * 2, SKILL_H)
            s.name = Text(s, "GameFontHighlightSmall", 0.85, 0.85, 0.87)
            s.name:SetPoint("TOPLEFT", 0, 0)
            s.gain = Text(s, "GameFontHighlightSmall")
            s.gain:SetPoint("TOPRIGHT", 0, 0)
            s.bar = CreateFrame("StatusBar", nil, s)
            s.bar:SetPoint("TOPLEFT", 0, -15)
            s.bar:SetPoint("TOPRIGHT", 0, -15)
            s.bar:SetHeight(6)
            s.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            s.bar:SetStatusBarColor(CYAN.r, CYAN.g, CYAN.b, 0.85)
            local bg = s.bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            Fill(bg, 0.12, 0.13, 0.16, 1)
            f.skills[i] = s
        end

        -- The latest item
        local card = CreateFrame("Button", nil, f)
        card:SetSize(WIDTH - PAD * 2, LATEST_H - 6)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        Fill(cbg, C.bgCard[1], C.bgCard[2], C.bgCard[3], 0.55)
        card.accent = card:CreateTexture(nil, "ARTWORK")
        card.accent:SetPoint("TOPLEFT")
        card.accent:SetPoint("BOTTOMLEFT")
        card.accent:SetWidth(2)
        card.icon = QualityIcon(card, 28)
        card.icon:SetPoint("TOPLEFT", 9, -(LATEST_H - 6 - 28) / 2)
        card.name = Text(card, "GameFontNormal")
        card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -2)
        card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.sub = Text(card, "GameFontDisableSmall")
        card.sub:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 8, 2)
        card.glow = card:CreateTexture(nil, "OVERLAY")
        card.glow:SetAllPoints()
        card.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        card.glow:SetBlendMode("ADD")
        card.glow:SetAlpha(0)
        card:SetScript("OnEnter", ItemTooltip)
        card:SetScript("OnLeave", GameTooltip_Hide)
        card:SetScript("OnClick", ItemClick)
        -- what else came with it, under the name: icons with their counts
        card.also = {}
        for k = 1, ALSO_MAX do
            local b = CreateFrame("Button", nil, card)
            b:SetSize(22, 22)
            b:SetPoint("TOPLEFT", card, "TOPLEFT", 45 + (k - 1) * 28, -(LATEST_H - 6) + 2)
            b.icon = QualityIcon(b, 20)
            b.icon:SetPoint("CENTER")
            b.count = Text(b, "NumberFontNormalSmall")
            b.count:SetPoint("BOTTOMRIGHT", 3, -1)
            b:SetScript("OnEnter", ItemTooltip)
            b:SetScript("OnLeave", GameTooltip_Hide)
            b:SetScript("OnClick", ItemClick)
            b:Hide()
            card.also[k] = b
        end
        card.more = Text(card, "GameFontDisableSmall")
        local pop = card:CreateAnimationGroup()
        local fade = pop:CreateAnimation("Alpha")
        fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.25)
        local grow = pop:CreateAnimation("Scale")
        if grow.SetScaleFrom then grow:SetScaleFrom(0.94, 0.94); grow:SetScaleTo(1, 1) end
        grow:SetDuration(0.25)
        card.pop = pop
        local shine = card.glow:CreateAnimationGroup()
        local sh = shine:CreateAnimation("Alpha")
        sh:SetFromAlpha(0.45); sh:SetToAlpha(0); sh:SetDuration(1.4)
        shine:SetScript("OnFinished", function() card.glow:SetAlpha(0) end)
        card.shine = shine
        f.card = card

        -- Item rows
        f.rows = {}
        for i = 1, MAX_ROWS do
            local r = CreateFrame("Button", nil, f)
            r:SetSize(WIDTH - PAD * 2, ROW_H)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            Fill(hl, 1, 1, 1, 0.05)
            r.icon = QualityIcon(r, 18)
            r.icon:SetPoint("LEFT", 0, 0)
            r.count = Text(r, "GameFontHighlightSmall", 0.6, 0.6, 0.65)
            r.count:SetPoint("RIGHT", -2, 0)
            r.name = Text(r, "GameFontHighlightSmall")
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
            r.name:SetJustifyH("LEFT")
            r.name:SetWordWrap(false)
            r:SetScript("OnEnter", ItemTooltip)
            r:SetScript("OnLeave", GameTooltip_Hide)
            r:SetScript("OnClick", ItemClick)
            f.rows[i] = r
        end
        f.more = Text(f, "GameFontDisableSmall")
        f.empty = Text(f, "GameFontDisableSmall")
        f.empty:SetJustifyH("CENTER")

        -- Footer
        f.divider = f:CreateTexture(nil, "ARTWORK")
        f.divider:SetHeight(1)
        Fill(f.divider, C.divider[1], C.divider[2], C.divider[3], C.divider[4])
        f.footer = Text(f, "GameFontDisableSmall")
        local prev
        for i = #opts.buttons, 1, -1 do
            local spec = opts.buttons[i]
            local b = ns.CreateThemedButton(f, spec.text, spec.width or 70, 20, "secondary")
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("BOTTOMRIGHT", -PAD, PAD) end
            b:SetScript("OnClick", spec.history and ToggleHistory or spec.onClick)
            prev = b
        end
        f:Hide()
    end

    function log:IsShown() return f ~= nil and f:IsShown() end
    function log:Show() if not f then Build() end f:Show() end
    function log:Hide() if f then f:Hide() end end

    function log:Set(m)
        if not f then Build() end
        f.timer:SetText(Clock(m.timer))
        for i, t in ipairs(f.tiles) do
            local st = m.stats[i] or {}
            t.label:SetText(st.label or "")
            t.value:SetText(st.value or "--")
            t.value:SetTextColor(1, 1, 1)   -- money brings its own coin colours
            t.tip = st.tip
        end
        local y = -(TITLE_H + 6 + TILE_H + 10)
        for i, s in ipairs(f.skills) do
            local sk = m.skills and m.skills[i]
            if sk then
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", PAD, y)
                s.name:SetText(("%s |cffffffff%d|r / %d"):format(sk.name, sk.cur, sk.max))
                if sk.gain and sk.gain > 0 then
                    s.gain:SetText(("+%d this session"):format(sk.gain))
                    s.gain:SetTextColor(0.12, 1, 0)
                elseif sk.cur >= sk.max then
                    s.gain:SetText("Maxed")
                    s.gain:SetTextColor(0.5, 0.5, 0.55)
                else
                    s.gain:SetText("")
                end
                s.bar:SetMinMaxValues(0, math.max(1, sk.max))
                s.bar:SetValue(sk.cur)
                s:Show()
                y = y - SKILL_H
            else
                s:Hide()
            end
        end
        local card = f.card
        if m.latest then
            local it = m.latest
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", PAD, y - 2)
            card.item = it
            local r, g, b = QualityColor(it.quality)
            card.accent:SetColorTexture(r, g, b, 1)
            card.glow:SetVertexColor(r, g, b)
            card.icon:Set(it.icon, it.quality)
            card.name:SetText((it.name or "?") .. ((it.count or 1) > 1 and (" |cffaaaaaax" .. it.count .. "|r") or ""))
            card.name:SetTextColor(r, g, b)
            card.sub:SetText(it.label .. " · " .. Ago(it.at))
            local also = it.also or {}
            for k, b in ipairs(card.also) do
                local o = also[k]
                if o then
                    b.item = o
                    b.icon:Set(o.icon, o.quality)
                    b.count:SetText((o.count or 1) > 1 and o.count or "")
                    b:Show()
                else
                    b.item = nil
                    b:Hide()
                end
            end
            if #also > ALSO_MAX then
                card.more:ClearAllPoints()
                card.more:SetPoint("LEFT", card.also[ALSO_MAX], "RIGHT", 6, 0)
                card.more:SetText("+" .. (#also - ALSO_MAX))
                card.more:Show()
            else
                card.more:Hide()
            end
            local h = LATEST_H + (#also > 0 and ALSO_H or 0)
            card:SetHeight(h - 6)
            card:Show()
            y = y - h
        else
            card:Hide()
        end
        local items = m.items or {}
        for i, row in ipairs(f.rows) do
            local it = items[i]
            if it then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", PAD, y)
                row.item = it
                row.icon:Set(it.icon, it.quality)
                row.name:SetText(it.name or "?")
                row.name:SetTextColor(QualityColor(it.quality))
                row.count:SetText("x" .. it.count)
                row:Show()
                y = y - ROW_H
            else
                row:Hide()
            end
        end
        local more = #items - MAX_ROWS
        if more > 0 then
            f.more:ClearAllPoints()
            f.more:SetPoint("TOPLEFT", PAD, y - 2)
            f.more:SetText(("+%d more"):format(more))
            f.more:Show()
            y = y - 18
        else
            f.more:Hide()
        end
        if #items == 0 and not m.latest then
            f.empty:ClearAllPoints()
            f.empty:SetPoint("TOP", f, "TOP", 0, y - 10)
            f.empty:SetText(m.empty or "")
            f.empty:Show()
            y = y - 36
        else
            f.empty:Hide()
        end
        y = y - 6
        f.divider:ClearAllPoints()
        f.divider:SetPoint("TOPLEFT", PAD, y)
        f.divider:SetPoint("TOPRIGHT", -PAD, y)
        f.footer:ClearAllPoints()
        f.footer:SetPoint("TOPLEFT", PAD, y - 8)
        f.footer:SetText(m.footer or "")
        f:SetHeight(-y + 8 + 14 + 6 + 20 + PAD)
        -- a session that went to History while it's open: drawn again (only then, not every second)
        if hist and hist:IsShown() then
            local list = HistoryList()
            if #list .. ":" .. tostring(list[1] and list[1].date) ~= histSig then DrawHistory() end
        end
    end

    -- A new item: the card scales in, with a glow for rare and better.
    function log:Celebrate(quality)
        if not (f and f:IsShown() and f.card:IsShown()) then return end
        f.card.pop:Stop()
        f.card.pop:Play()
        if (tonumber(quality) or 0) >= 3 then
            f.card.shine:Stop()
            f.card.glow:SetAlpha(0.45)
            f.card.shine:Play()
        end
    end

    return log
end
