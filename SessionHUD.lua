local ADDON, ns = ...

-- (built when the saved variables are there: its measures come from the theme, which can be changed)
ns.AfterLoad(function()
local L = ns.L
local W = ns.W
local C = W.C
local Ease, LerpColor, Hex = W.Ease, W.LerpColor, W.Hex

-- Session overlay. A table with one row per creature: name and status, the loot
-- it dropped this session as icons, kills this session, kills in total (with a
-- slim progress bar towards the drop chances) and value. A click unfolds a row
-- (where, what it has dropped so far, everything it can drop); the creature
-- fought last is unfolded by itself. Every fact appears once: the progress is in
-- the row, the unfolded part only adds what the row cannot show.
--
-- The window can be resized at the bottom right corner; columns drop out as it
-- gets narrower (loot icons first, then the value).

local HUD = {}
ns.HUD = HUD
-- In the Blizzard style the cards sit at the top of the window with pause and end beside them (the room above them is not needed: the
-- round icon and the buttons of the other windows are in the title bar). This is decided when the addon loads (a change of the window
-- style needs a reload for this window).
HUD.compact = true

local DEFAULT_W, DEFAULT_H = HUD.compact and 560 or 520, 470 -- (the compact layout has less room for the cards: a little wider)
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 280, 820, 900
local TAB_TOP = ns.Theme.Get("hud", "tabTop") - (HUD.compact and 60 or 0)
-- (compact layout: the same space, 8, between the cards, the line, the tabs and the table)
local TAB_Y = HUD.compact and 7 or 2 -- the tabs hang this far below TAB_TOP
local HEAD_ROW_TOP = TAB_TOP + (HUD.compact and 39 or 32)
local LIST_TOP = HEAD_ROW_TOP + 22
local LIST_BOTTOM = HUD.compact and 34 or 16 -- room for the resize grip (compact layout: for the footer, too)
local ROW_H = ns.Theme.Get("hud", "rowH")

-- column sizes (measured from the right edge of a row)
local VAL_W, TOT_W, AVG_W = ns.Theme.Get("hud", "valW"), ns.Theme.Get("hud", "totW"), ns.Theme.Get("hud", "avgW")
local ICO_SIZE, ICO_STEP, ICO_MAX = ns.Theme.Get("hud", "icoSize"), ns.Theme.Get("hud", "icoStep"), 6
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local QUEST_CLASS = 12
local LEVEL_W = ns.Theme.Get("hud", "levelW") -- the column for a creature's level before its name
local COUNT_COLOR = { 0.72, 0.66, 0.54 } -- the count after a name
-- the status ring before a creature's name: dots that light up, a filled centre when it is full
local RING_DOTS, RING_R = 10, 6.5
local RING_ON = { 0.38, 0.76, 0.38, 0.95 } -- the green of the herbalism group
local NAME_X = ns.Theme.Get("hud", "nameX") -- entries start as far from the left edge as the value ends from the right
local NAME_MIN = 150

local JADE_TXT = "|cff66dbb0"
local MUTED_TXT = Hex(C.muted)
-- muted fills so bars sit in the theme instead of glowing
local FILL_GOLD = { 0.62, 0.49, 0.22 }
local FILL_JADE = { 0.27, 0.58, 0.47 }
local STATUS_GOLD = { 0.82, 0.66, 0.32 }

local mode = "sources" -- "sources" (enemies) | "gather" | "loot" | "route" | "stats"
local openKey = nil    -- the one unfolded row (nil / false = none)
local scroll, target, maxScroll, viewH = 0, 0, 0, 300
local dirty = true

local U = {} -- helpers (kept in a table: Render has too many upvalues otherwise)
U.compact = HUD.compact

-- the text typed into the search box, one per tab
local queries = { sources = "", loot = "", stats = "", board = "", route = "" }
function U.Query()
    local q = queries[mode]
    return (q and q ~= "") and q:lower() or nil
end
function U.Matches(q, ...)
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if s and tostring(s):lower():find(q, 1, true) then return true end
    end
    return false
end
function U.ItemName(gi) return gi and gi.link and gi.link:match("%[(.-)%]") end
function U.ItemNames(gm)
    local t = {}
    for id in pairs(ns.MergedItems(gm)) do
        local n = U.ItemName(ns.db.items[id])
        if n then t[#t + 1] = n end
    end
    return table.concat(t, " ")
end

-- animations (a setting): new rows fade in, numbers count up and flash
function U.AnimOn() return not (ns.db and ns.db.settings and ns.db.settings.animations == false) end
local A = { known = {}, first = true, visited = {}, noAnim = true, rows = {}, itemOwners = {} } -- what was shown before; no animation on the first pass
local PULSE = { 0.45, 0.9, 0.7 }

-- sorting the sources: click a column title. Each title has its own cycle; after
-- the last step the list goes back to "latest first" (the default).
local SORT_CYCLE = {
    name = { { "name", true }, { "name", false } },
    icons = { { "loot", false }, { "loot", true } },
    value = { { "value", false }, { "value", true } },
    total = { { "session", false }, { "session", true } },
    avg = { { "avg", false }, { "avg", true } },
}
local function SortState()
    -- (one for the list of the enemies / of what is gathered, one for the list of the loot)
    local field = mode == "loot" and "hudSortLoot" or "hudSort"
    local s = ns.db[field]
    if not s then
        s = mode == "loot" and { key = "value", asc = false } or { key = "recent", asc = false }
        ns.db[field] = s
    end
    return s
end
function U.TotalTitle() return L["Count"] end

local f = CreateFrame("Frame", "ForeverCompanionHUD", UIParent, W.TEMPLATE)
HUD.frame = f
f:SetSize(DEFAULT_W, DEFAULT_H)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
-- same layer as the journal: the window you clicked last is in front (SetToplevel)
f:SetFrameStrata("MEDIUM")
f:SetToplevel(true)
f:SetMovable(true)
f:SetResizable(true)
if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
else f:SetMinResize(MIN_W, MIN_H); f:SetMaxResize(MAX_W, MAX_H) end
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop(W.PLATE_BACKDROP)
f:SetBackdropColor(0.055, 0.045, 0.038, 1)
f:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
f:Hide()

-- the journal's dialog frame, drawn just outside the window so the content does not
-- move; switched by the frame style setting
local deco = CreateFrame("Frame", nil, f, W.TEMPLATE)
deco:SetPoint("TOPLEFT", -10, 10)
deco:SetPoint("BOTTOMRIGHT", 10, -10)
deco:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32 })
deco:SetFrameLevel(f:GetFrameLevel() + 40)
deco:EnableMouse(false)

-- a plain fill that reaches the window's edge (the dialog frame sits over it)
local fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
fill:SetAllPoints()
fill:SetColorTexture(0.055, 0.045, 0.038, 1)

function HUD.ApplyFrameStyle()
    local ornate = false
    local blizz = W.BlizzSkin(f, true, W.ICON.session, nil, "hud")
    deco:SetShown(ornate)
    fill:SetShown(ornate)
    if ornate or blizz then
        f:SetBackdrop(nil)
    else
        f:SetBackdrop(W.PLATE_BACKDROP)
        f:SetBackdropColor(0.055, 0.045, 0.038, 1)
        f:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    end
end

f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.hud = { point, rel, x, y }
end)
f:SetScript("OnSizeChanged", function() dirty = true end)

-- resize grip, bottom right
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
local MIN_SCALE, MAX_SCALE = 0.6, 1.6
U.gripOpts = { -- (kept: the limits for the size change while the window is folded up)
    defaultSize = { DEFAULT_W, DEFAULT_H }, minSize = { MIN_W, MIN_H }, maxSize = { MAX_W, MAX_H }, topInset = 54,
    gridSize = { 20, ROW_H }, gridScale = 0.05,
    minScale = MIN_SCALE, maxScale = MAX_SCALE,
    saveSize = function() if ns.db then ns.db.hudSize = { f:GetWidth(), A.collapsed and (A.expandedH or f:GetHeight()) or f:GetHeight() } end end,
    saveScale = function() if ns.db then ns.db.hudScale = f:GetScale() end end,
    savePos = function()
        if ns.db then
            local point, _, rel, px, py = f:GetPoint()
            ns.db.hud = { point, rel, px, py }
        end
    end,
}
W.AttachScaleGrip(f, grip, U.gripOpts)

-- header ------------------------------------------------------------------
-- The title hangs on a banner of its own, like the journal's (in the ornate style); the
-- banner sits above the window's frame.
local bannerFrame = CreateFrame("Frame", nil, f)
bannerFrame:SetAllPoints(f)
bannerFrame:SetFrameLevel(f:GetFrameLevel() + 45)
local banner = bannerFrame:CreateTexture(nil, "ARTWORK")
banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
banner:SetSize(240, 64)
banner:SetPoint("TOP", deco, "TOP", 0, 12) -- the dialog frame (deco) is what the plate hangs on
local title = bannerFrame:CreateFontString(nil, "OVERLAY")
title:SetFontObject(ns.UI and ns.UI.bannerFontObject or "GameFontNormalLarge")
title:SetJustifyH("CENTER")
title:SetPoint("CENTER", banner, "CENTER", 0, 12)
title:SetText(L["Kills & Loot"])
title:SetTextColor(1, 0.85, 0.4)
local pausedLabel = bannerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pausedLabel:SetPoint("TOP", title, "BOTTOM", 0, -1)

-- the plain style has no banner: the title sits at the top edge
local applyFrameStyle = HUD.ApplyFrameStyle
function HUD.ApplyFrameStyle()
    applyFrameStyle()
    local blizzOn = W.BlizzSkin(f, true, W.ICON.session, title:GetText(), "hud")
    title:SetAlpha(blizzOn and 0 or 1) -- (the frame's own title is shown instead)
    local ornate = false
    banner:SetShown(ornate)
    title:ClearAllPoints()
    pausedLabel:ClearAllPoints()
    if ornate then
        title:SetPoint("CENTER", banner, "CENTER", 0, 12)
        pausedLabel:SetPoint("TOP", title, "BOTTOM", 0, -1)
    else
        title:SetPoint("TOP", f, "TOP", 0, f.blizzFrame and f.blizzFrame:IsShown() and 42 or -11)
        pausedLabel:SetPoint("LEFT", title, "RIGHT", 8, -1)
    end
end
pausedLabel:SetTextColor(0.93, 0.65, 0.37)
pausedLabel:SetText(L["paused"])
pausedLabel:Hide()

local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
f.closeBtn = close
close:SetPoint("TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() HUD.Hide() end)
local opacityBtn = W.NewOpacityButton(f, "hud", f, 20)
opacityBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
f.opacityBtn = opacityBtn
-- minimize: only the top part (value, per hour, session) stays
local minBtn = W.NewButton(f, "–", 20, 20, "GameFontNormal")
minBtn:SetPoint("RIGHT", opacityBtn, "LEFT", -4, 0)
minBtn:SetScript("OnClick", function() U.SetCollapsed(not A.collapsed) end)
minBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(A.collapsed and L["Restore"] or L["Minimize"], 1, 0.85, 0.4)
    GameTooltip:AddLine(L["Shows only value, per hour and session."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
minBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
f.skinMinimize = { button = minBtn, get = function() return A.collapsed end, set = function(on) U.SetCollapsed(on) end }
local journal = W.NewIconButton(f, W.ICON.journal, 20)
journal:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8) -- left: the other windows, as in the journal
journal:SetTip(L["Journal"], L["Open the full journal."])
journal:SetScript("OnClick", function() ns.UI.Toggle() end)
local mapBtn = W.NewIconButton(f, W.ICON.map, 20)
mapBtn:SetPoint("LEFT", journal, "RIGHT", 4, 0)
mapBtn:SetTip(L["Loot map"], L["Open the loot map in a window of its own."])
mapBtn:SetScript("OnClick", function() if ns.MapMain then ns.MapMain.Toggle() end end)
local accountBtn = W.NewIconButton(f, W.ICON.account, 20)
accountBtn:SetPoint("LEFT", mapBtn, "RIGHT", 4, 0)
accountBtn:SetTip(L["Account"], L["All your characters: equipment, bags, professions, mail."])
accountBtn:SetScript("OnClick", function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end)
local settingsBtn = W.NewIconButton(f, W.ICON.settings, 20) -- the last of the window buttons
settingsBtn:SetPoint("LEFT", accountBtn, "RIGHT", 4, 0)
settingsBtn:SetTip(L["Settings"], L["Open the settings."])
settingsBtn:SetScript("OnClick", function() if ns.Settings then ns.Settings.Toggle() end end)
f.skinRowAll = { journal, mapBtn, accountBtn, settingsBtn }
local endBtn = W.NewIconButton(f, W.ICON.clear, 20)
endBtn:SetSize(22, 22)
endBtn:SetTip(L["End session"], L["Saves the session to the history. The lists start empty and a new session begins with your next loot."])
endBtn:SetScript("OnClick", function()
    ns.EndSession()
    scroll, target, openKey = 0, 0, nil
end)
local pauseBtn = W.NewIconButton(f, W.ICON.pause, 20)
pauseBtn:SetSize(22, 22)
pauseBtn:SetScript("OnClick", function() ns.TogglePause() end)

-- the same three stat cards as in the journal (re-spaced when the window is resized)
local CARD_H = ns.Theme.Get("hud", "cardH")
local cards = {}
-- (compact layout: the third card is the experience per hour; the session's time is in the title bar)
function U.XpTip()
    GameTooltip:AddLine(L["XP/hour"], 1, 0.82, 0.3)
    local gained, perHour, missing, eta = ns.XPInfo()
    if gained > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["XP gained"], ns.ShortNumber(gained), 0.8, 0.8, 0.8, 1, 1, 1)
        if missing then GameTooltip:AddDoubleLine(L["To next level"], ns.ShortNumber(missing), 0.8, 0.8, 0.8, 1, 1, 1) end
        if eta then GameTooltip:AddDoubleLine(L["Time to level"], W.Duration(eta), 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Session"], W.Duration(ns.SessionElapsed()), 0.8, 0.8, 0.8, 1, 1, 1)
    local snap = ns.snap
    if snap then
        GameTooltip:AddLine(L["%d kills"]:format(snap.kills), 0.8, 0.8, 0.8)
        if (snap.gathered or 0) > 0 then GameTooltip:AddLine(L["%d gathered"]:format(snap.gathered), 0.8, 0.8, 0.8) end
    end
end
for i = 1, 3 do
    if HUD.compact and i == 3 then
        cards[i] = W.NewStatCard(f, "Interface\\Icons\\XP_Icon", U.XpTip)
    else
        cards[i] = W.NewStatCard(f, W.STAT_ICONS[i], W.StatCardTip(i))
    end
    cards[i]:SetHeight(CARD_H)
    if HUD.compact then W.CompactStatCard(cards[i]) end
end

-- The footer (compact layout): a line under the list and the time of the session below it. It is there while the window is not folded up.
if HUD.compact then
    local footer = CreateFrame("Frame", nil, f)
    footer:SetFrameLevel(f:GetFrameLevel() + 3)
    footer:SetAllPoints(f)
    footer:EnableMouse(false)
    local line = footer:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 10, 24)
    line:SetPoint("BOTTOMRIGHT", -10, 24)
    line:SetHeight(1)
    line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.4)
    U.timeText = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    U.timeText:SetPoint("BOTTOMLEFT", 14, 7)
    U.footer = footer

    -- A timer for an alarm, at the right of the footer: a click on the bell gives the times; while it runs the time left is shown. When it
    -- is up there is a sound, a message in the chat and on the screen. It is kept over a reload (ns.db.hudAlarmEnd, a point in time).
    local cog = W.NewIconButton(footer, W.ICON.settings, 18)
    cog:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 3)
    cog:SetTip(L["Settings"], L["Some settings to switch here, and the way to all of them."])
    local bell = W.NewIconButton(footer, "Interface\\Icons\\INV_Misc_Bell_01", 18)
    bell:SetPoint("RIGHT", cog, "LEFT", -6, 0)
    bell:SetTip(L["Timer"], L["Sets an alarm: click and choose the time."])
    U.alarmText = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    U.alarmText:SetPoint("RIGHT", bell, "LEFT", -6, 0)
    local menu = W.NewDropdown(f, { level = f:GetFrameLevel() + 60, width = 170, strata = "FULLSCREEN_DIALOG" })

    -- what was looted or gathered last, and what it is worth: between the time and the timer; it gives way (is cut off) when there is no room
    U.findText = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    U.findText:SetPoint("LEFT", U.timeText, "RIGHT", 18, 0)
    U.findText:SetPoint("RIGHT", U.alarmText, "LEFT", -12, 0)
    U.findText:SetJustifyH("LEFT")
    U.findText:SetWordWrap(false)
    U.findText:SetTextColor(0.72, 0.66, 0.54)
    function U.FooterFind()
        local fnd = ns.lastFind
        if not fnd then U.findText:SetText("") return end
        local what = fnd.money and L["Money"] or (fnd.link or "")
        local qty = (fnd.qty and fnd.qty > 1) and (" ×" .. fnd.qty) or ""
        local val = fnd.value > 0 and ("  " .. ns.Value.Format(fnd.value)) or ""
        U.findText:SetText(L["Last"] .. "  " .. what .. qty .. val)
    end

    function U.AlarmTick()
        local endAt = ns.db and ns.db.hudAlarmEnd
        if not endAt then
            if not U.alarmDone then U.alarmText:SetText("") end
            return
        end
        local left = endAt - time()
        if left > 0 then
            U.alarmDone = nil
            U.alarmText:SetTextColor(0.93, 0.74, 0.30)
            U.alarmText:SetText("|TInterface\\Icons\\INV_Misc_Bell_01:12:12:0:0:64:64:5:59:5:59|t " .. W.Duration(left))
            return
        end
        -- up
        ns.db.hudAlarmEnd = nil
        U.alarmDone = true
        U.alarmText:SetTextColor(0.93, 0.65, 0.37)
        U.alarmText:SetText(L["Timer is up!"])
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) or 12867)
        print("|cffffd100Forever Companion:|r " .. L["Timer is up!"])
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, L["Timer is up!"], ChatTypeInfo["RAID_WARNING"])
        end
        C_Timer.After(12, function() if U.alarmDone and not ns.db.hudAlarmEnd then U.alarmDone = nil; U.alarmText:SetText("") end end)
    end
    function U.AlarmStart(seconds)
        if seconds and seconds > 0 then ns.db.hudAlarmEnd = time() + math.floor(seconds) else ns.db.hudAlarmEnd = nil end
        U.alarmDone = nil
        U.AlarmTick()
        if not U.alarmTicker then U.alarmTicker = C_Timer.NewTicker(0.5, U.AlarmTick) end
    end
    if ns.db and ns.db.hudAlarmEnd then U.AlarmStart(ns.db.hudAlarmEnd - time()) end -- (kept over a reload; one that ran out meanwhile goes off now)

    StaticPopupDialogs["FOREVERCOMPANION_ALARM"] = {
        text = L["Minutes:"], button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
        OnShow = function(self) (self.editBox or self.EditBox):SetText("10"); (self.editBox or self.EditBox):HighlightText() end,
        OnAccept = function(self) U.AlarmStart((tonumber((self.editBox or self.EditBox):GetText()) or 0) * 60) end,
        EditBoxOnEnterPressed = function(box)
            U.AlarmStart((tonumber(box:GetText()) or 0) * 60)
            box:GetParent():Hide()
        end,
    }
    local function Rows()
        local out = { { kind = "header", label = L["Timer"] } }
        for _, m in ipairs({ 5, 10, 15, 20, 30, 45, 60 }) do
            out[#out + 1] = { kind = "action", label = L["%d min"]:format(m), close = true, onClick = function() U.AlarmStart(m * 60) end }
        end
        out[#out + 1] = { kind = "action", label = L["Own time…"], close = true, onClick = function() StaticPopup_Show("FOREVERCOMPANION_ALARM") end }
        if ns.db.hudAlarmEnd or U.alarmDone then
            out[#out + 1] = { kind = "separator" }
            out[#out + 1] = { kind = "action", label = L["Stop timer"], close = true, onClick = function() U.AlarmStart(nil) end }
        end
        return out
    end
    bell:SetScript("OnClick", function(self)
        if menu:IsShown() and menu.owner == self then menu:Close() else menu:Open(self, Rows, true) end
    end)

    -- the settings button: the switches of the window and of the recording, and the way to the settings (the first page of the loot)
    local function Switch(label, icon, get, set)
        return { kind = "check", state = get() and "all" or "none", label = label, icon = icon, onClick = function() set(not get()); ns.Refresh() end }
    end
    local function SettingsRows()
        local st = ns.db.settings
        local out = { { kind = "header", label = L["Settings"] } }
        out[#out + 1] = Switch(L["Open the session window by itself"], "Interface\\Icons\\INV_Misc_Bag_10",
            function() return st.autoOpenSession == true end, function(on) st.autoOpenSession = on end)
        out[#out + 1] = Switch(L["Not in dungeons and raids"], "Interface\\Icons\\INV_Misc_Key_03",
            function() return st.pauseInstances ~= false end, function(on) st.pauseInstances = on end)
        out[#out + 1] = Switch(L["Not while in a group"], "Interface\\Icons\\INV_Misc_GroupLooking",
            function() return st.pauseGroup == true end, function(on) st.pauseGroup = on end)
        out[#out + 1] = Switch(L["Keep session after reload"], W.ICON.session,
            function() return st.keepSession and true or false end, function(on) st.keepSession = on end)
        out[#out + 1] = Switch(L["Hide gray items"], "Interface\\Icons\\INV_Misc_Bone_01",
            function() return st.hideGray and true or false end, function(on) st.hideGray = on end)
        out[#out + 1] = Switch(L["Count looted money"], "Interface\\Icons\\INV_Misc_Coin_01",
            function() return ns.MoneyOn() end, function(on) st.countMoney = on end)
        out[#out + 1] = { kind = "separator" }
        out[#out + 1] = { kind = "action", label = L["All settings ..."], icon = W.ICON.settings, close = true,
            onClick = function() if ns.Settings then ns.Settings.Show("sources") end end }
        return out
    end
    -- (a menu of its own, wide enough for the texts)
    local setMenu = W.NewDropdown(f, { level = f:GetFrameLevel() + 60, width = 330, strata = "FULLSCREEN_DIALOG" })
    cog:SetScript("OnClick", function(self)
        if setMenu:IsShown() and setMenu.owner == self then setMenu:Close() else menu:Close(); setMenu:Open(self, SettingsRows, true) end
    end)
end

-- tabs ---------------------------------------------------------------------
local rule = f:CreateTexture(nil, "ARTWORK")
rule:SetPoint("TOPLEFT", 10, -(TAB_TOP - 2))
rule:SetPoint("TOPRIGHT", -10, -(TAB_TOP - 2))
rule:SetHeight(1)
rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.4)

local tabs = {}
local SyncSearch
-- The tabs are buttons with a picture and their name, side by side (the active one glows and has a brighter text, no gilded edge). When
-- the window is too narrow for them and a search box of some size, they are only the picture (U.LayoutTabs).
U.tabsEnd = 10
local function MakeTab(id, icon, label)
    local t = W.NewButton(f, label, 80, 24)
    t.noActiveBorder = true
    t.id, t.label = id, label
    t.pic = t:CreateTexture(nil, "OVERLAY")
    t.pic:SetSize(16, 16)
    t.pic:SetTexture(icon)
    t.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", 28, 0)
    t.fullW = 28 + t.text:GetStringWidth() + 11
    function t:SetActive(on) self:SetSelected(on) end
    t:HookScript("OnEnter", function(self)
        if not self.iconOnly then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.label, 1, 0.85, 0.4)
        GameTooltip:Show()
    end)
    t:HookScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", function()
        mode, scroll, target = id, 0, 0
        SyncSearch()
        dirty = true
    end)
    tabs[#tabs + 1] = t
end
function U.LayoutTabs()
    local full = 10
    for _, t in ipairs(tabs) do full = full + t.fullW + 6 end
    local iconOnly = f:GetWidth() < full + 150 -- (150: the least a search box needs, with its margins)
    local x = 10
    for _, t in ipairs(tabs) do
        t.iconOnly = iconOnly
        t.text:SetShown(not iconOnly)
        t.pic:ClearAllPoints()
        t.pic:SetPoint("LEFT", iconOnly and 4 or 7, 0)
        t:SetWidth(iconOnly and 24 or t.fullW)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -TAB_TOP - TAB_Y)
        x = x + t:GetWidth() + 6
    end
    U.tabsEnd = x
end
MakeTab("sources", W.ICON.skull, L["Enemies"])
MakeTab("gather", "Interface\\Icons\\Trade_Mining", L["Gathering"])
MakeTab("loot", W.ICON.loot, L["Loot"])
-- (the route tab is not offered any more: it is to become a window of its own; its code is still here)
MakeTab("stats", W.ICON.stats, L["Statistics"])
local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
countLabel:SetPoint("LEFT", tabs[#tabs], "RIGHT", 12, 0)
countLabel:SetTextColor(unpack(C.muted))

-- search / filter for the open tab: lists are filtered, statistics and the map highlight
local searchBox = CreateFrame("EditBox", nil, f, W.TEMPLATE)
searchBox:SetHeight(22)
searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -TAB_TOP - TAB_Y - 1)
searchBox:SetBackdrop(W.PLATE_BACKDROP)
searchBox:SetBackdropColor(unpack(C.inset))
searchBox:SetBackdropBorderColor(unpack(C.goldDim))
searchBox:SetFontObject("GameFontHighlightSmall")
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(30)
searchBox:SetTextInsets(8, 22, 0, 0)
local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
searchHint:SetPoint("LEFT", 8, 0)
searchHint:SetTextColor(unpack(C.muted))
local searchClear = CreateFrame("Button", nil, searchBox)
searchClear:SetSize(16, 16)
searchClear:SetPoint("RIGHT", -4, 0)
searchClear.text = searchClear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
searchClear.text:SetPoint("CENTER")
searchClear.text:SetText("×")
searchClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus() end)
searchClear:Hide()

function U.LayoutSearch()
    -- the tabs show their names while the window is wide enough for them and a search box of some size; otherwise only their pictures
    U.LayoutTabs()
    local free = f:GetWidth() - U.tabsEnd - 16
    searchBox:SetWidth(math.max(60, math.min(170, free))) -- (not wider than a filter needs, however much room is left)
    countLabel:Hide() -- (the count of the entries is not shown: the room is the search box's)
end

SyncSearch = function()
    searchBox:SetText(queries[mode] or "")
    searchHint:SetText(mode == "stats" and L["Highlight…"] or L["Filter…"])
    searchHint:SetShown((queries[mode] or "") == "")
    searchClear:SetShown((queries[mode] or "") ~= "")
end
searchBox:SetScript("OnTextChanged", function(self, userInput)
    local text = self:GetText()
    queries[mode] = text
    searchHint:SetShown(text == "")
    searchClear:SetShown(text ~= "")
    if userInput then scroll, target = 0, 0 end
    dirty = true
end)
searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.gold)) end)
searchBox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.goldDim)) end)
SyncSearch()

-- column header ---------------------------------------------------------------
local headBg = f:CreateTexture(nil, "BACKGROUND")
headBg:SetPoint("TOPLEFT", 8, -HEAD_ROW_TOP)
headBg:SetPoint("TOPRIGHT", -8, -HEAD_ROW_TOP)
headBg:SetHeight(22)
headBg:SetColorTexture(0.13, 0.095, 0.06, 1) -- a warm brown plate, set off from the rows by a gilded rule
local headRule = f:CreateTexture(nil, "BORDER")
headRule:SetPoint("BOTTOMLEFT", headBg, "BOTTOMLEFT", 4, 0) -- inside the head: the rows' frames would paint over it below
headRule:SetPoint("BOTTOMRIGHT", headBg, "BOTTOMRIGHT", -4, 0)
headRule:SetHeight(1)
headRule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.45)

local head = {}
for _, key in ipairs({ "name", "icons", "total", "value", "avg" }) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(0.72, 0.66, 0.54)
    head[key] = fs
end

-- scroll area --------------------------------------------------------------
local sf = CreateFrame("ScrollFrame", nil, f)
sf:SetPoint("TOPLEFT", 8, -LIST_TOP)
sf:SetPoint("TOPRIGHT", -8, -LIST_TOP)
sf:SetHeight(ROW_H * 6)
sf:EnableMouseWheel(true)
local content = CreateFrame("Frame", nil, sf)
content:SetSize(300, 1)
sf:SetScrollChild(content)

-- a darker well behind the rows, so the rows read against it
local well = f:CreateTexture(nil, "BACKGROUND")
well:SetPoint("TOPLEFT", sf)
well:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, LIST_BOTTOM) -- down to the frame, whatever the row steps
-- warm brown, a little lighter towards the top, like the rest of the window's face
well:SetColorTexture(1, 1, 1, 1) -- white base: the gradient multiplies it
well:SetGradient("VERTICAL", CreateColor(0.040, 0.033, 0.026, 1), CreateColor(0.062, 0.051, 0.040, 1))

-- the lane the scroll thumb runs in, beside the rows: a slightly lighter strip with a thin line
-- on its left, so the room the thumb needs reads as a scroll bar and not as a gap
A.lane = f:CreateTexture(nil, "BACKGROUND", nil, 1)
A.lane:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
A.lane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, LIST_BOTTOM)
A.lane:SetWidth(8)
A.lane:SetColorTexture(0.075, 0.059, 0.044, 1)
A.laneLine = f:CreateTexture(nil, "BACKGROUND", nil, 2)
A.laneLine:SetPoint("TOPLEFT", A.lane, "TOPLEFT", 0, 0)
A.laneLine:SetPoint("BOTTOMLEFT", A.lane, "BOTTOMLEFT", 0, 0)
A.laneLine:SetWidth(1)
A.laneLine:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.2)

-- the gilded frame round the column heads and the rows
local listBorder = W.NewListBorder(f, headBg, sf, sf:GetFrameLevel() + 12)
-- as wide as the cards and the tabs, and reaching the bottom of the window (the rows move
-- in steps when it is resized, the frame does not)
listBorder:ClearAllPoints()
listBorder:SetPoint("TOPLEFT", headBg, "TOPLEFT", 0, 0)
listBorder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, LIST_BOTTOM)

-- the thumb sits in its own frame above the rows, in the gutter beside them
local thumbFrame = CreateFrame("Frame", nil, f)
thumbFrame:SetFrameLevel(sf:GetFrameLevel() + 20)
thumbFrame:SetWidth(4)
local thumb = thumbFrame:CreateTexture(nil, "OVERLAY")
thumb:SetAllPoints()
thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)
thumbFrame:Hide()

local empty = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
empty:SetPoint("CENTER", 0, 20)
empty:SetTextColor(unpack(C.muted))

local contentH = 0
local function UpdateThumb()
    if contentH > viewH then
        local th = math.max(24, viewH * viewH / contentH)
        local off = scroll / (contentH - viewH) * (viewH - th)
        thumbFrame:ClearAllPoints()
        thumbFrame:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -off)
        thumbFrame:SetHeight(th)
        thumbFrame:Show()
    else
        thumbFrame:Hide()
    end
end
local scrolling = false
local function ApplyScroll(_, v)
    if math.abs(v - target) < 0.5 then scrolling = false end
    scroll = v
    sf:SetVerticalScroll(v)
    UpdateThumb()
end
sf:SetScript("OnMouseWheel", function(_, delta)
    -- the wheel also reaches windows that are covered by another one: only the one on top scrolls
    if not W.TopFrameIs(f) then return end
    -- scrolling moves by whole rows, so a row is never cut off
    local step = math.floor((target - delta * ROW_H * 2) / ROW_H + 0.5) * ROW_H
    target = math.max(0, math.min(maxScroll, step))
    scrolling = true
    Ease(sf, "scroll", target, 14, ApplyScroll, scroll)
end)

-- layout: which columns fit at the current width ----------------------------------
local function Metrics()
    local inner = sf:GetWidth() - 8
    local m = { inner = inner }
    m.showValue = inner >= 320
    local right = 8
    m.totR = right
    right = right + 2
    m.valR = right
    if m.showValue then right = right + VAL_W + 4 end
    m.showAvg = inner >= 470
    m.avgR = right
    if m.showAvg then right = right + AVG_W + 4 end
    m.icoR = right + 6
    local space = inner - NAME_X - NAME_MIN - right - 14
    m.nIcons = math.max(0, math.min(ICO_MAX, math.floor(space / ICO_STEP)))
    m.nameW = inner - NAME_X - right - m.nIcons * ICO_STEP - 10
    return m
end

-- rows -----------------------------------------------------------------------
local mobRows, details, itemRows = {}, {}, {}
local seen, flashAt = {}, {}

local function ApplyHl(r, v) r.hl:SetAlpha(v * 0.55) end
local function ApplyFlash(r, v) r.flash:SetAlpha(v) end

-- shared look of a row: zebra background, hover glow, flash, a separator line
local function RowBase(r, h)
    r:SetHeight(h)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetTexture(W.HILITE_TEX)
    r.hl:SetBlendMode("ADD")
    r.hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    r.hl:SetAlpha(0)
    r.flash = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.flash:SetAllPoints()
    r.flash:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    r.flash:SetBlendMode("ADD")
    r.flash:SetAlpha(0)
    r.sep = r:CreateTexture(nil, "BORDER")
    r.sep:SetPoint("BOTTOMLEFT", 4, 0)
    r.sep:SetPoint("BOTTOMRIGHT", -4, 0)
    r.sep:SetHeight(1)
    r.sep:SetColorTexture(1, 1, 1, 0.1)
    -- a soft light that sweeps over the row when something arrives
    r.shine = r:CreateTexture(nil, "ARTWORK", nil, 3)
    r.shine:SetTexture(W.HILITE_TEX)
    r.shine:SetBlendMode("ADD")
    r.shine:SetVertexColor(1, 0.92, 0.65)
    r.shine:SetSize(110, h)
    r.shine:SetAlpha(0)
end

local function Zebra(r, index, open)
    -- as subtle as the journal's lists
    if open then r.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.07)
    elseif index % 2 == 0 then r.bg:SetColorTexture(1, 1, 1, 0.025)
    else r.bg:SetColorTexture(1, 1, 1, 0) end
end

-- group headers -----------------------------------------------------------------
-- One header per kind of source (creatures, herbalism, mining, ...). Clicking
-- one folds its group. While scrolling, the header of the group at the top of
-- the list stays pinned there until the next group's header pushes it away.

local GROUP_H = ROW_H -- headers, rows and unfolded parts all sit on the same grid
local groupCollapsed = {}
local headerRows = {}

local function NewGroupHeader(parent)
    local g = CreateFrame("Button", nil, parent)
    g:SetHeight(GROUP_H)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.17, 0.125, 0.08, 0.5)
    g.top = g:CreateTexture(nil, "BORDER")
    g.top:SetPoint("TOPLEFT", 4, 0)
    g.top:SetPoint("TOPRIGHT", -4, 0)
    g.top:SetHeight(1)
    g.top:SetColorTexture(1, 1, 1, 0.12)
    g.bottom = g:CreateTexture(nil, "BORDER")
    g.bottom:SetPoint("BOTTOMLEFT", 4, 0)
    g.bottom:SetPoint("BOTTOMRIGHT", -4, 0)
    g.bottom:SetHeight(1)
    g.bottom:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
    g.hl = g:CreateTexture(nil, "BACKGROUND", nil, 1)
    g.hl:SetAllPoints()
    g.hl:SetTexture(W.HILITE_TEX)
    g.hl:SetBlendMode("ADD")
    g.hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    g.hl:SetAlpha(0)
    g.arrow = g:CreateTexture(nil, "OVERLAY")
    g.arrow:SetSize(12, 12)
    g.arrow:SetPoint("LEFT", 6, 0)
    g.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    g.arrow:SetVertexColor(0.8, 0.72, 0.5)
    g.label = g:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    g.label:SetPoint("LEFT", 26, 0)
    g.count = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.count:SetPoint("LEFT", g.label, "RIGHT", 6, 0)
    g.count:SetTextColor(unpack(C.muted))
    g.total = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.total:SetJustifyH("RIGHT")
    g.value = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.value:SetJustifyH("RIGHT")
    g:SetScript("OnEnter", function(self) Ease(self, "hl", 1, 16, function(o, v) o.hl:SetAlpha(v * 0.35) end) end)
    g:SetScript("OnLeave", function(self) Ease(self, "hl", 0, 16, function(o, v) o.hl:SetAlpha(v * 0.35) end) end)
    g:SetScript("OnClick", function(self)
        if self.cat then
            groupCollapsed[self.key] = not groupCollapsed[self.key]
            dirty = true
        end
    end)
    return g
end

local function FillGroupHeader(g, hd, m)
    g.cat, g.key = hd.cat, hd.key
    g:SetWidth(m.inner)
    g.arrow:SetRotation(groupCollapsed[hd.key] and 0 or math.rad(-90))
    g.label:SetText((hd.prefix and (hd.prefix .. " – ") or "") .. ns.CAT[hd.cat].label)
    -- the category's colour, lightened, so a group reads at a glance
    local cc = ns.CAT[hd.cat].color
    g.label:SetTextColor(0.5 + cc[1] * 0.5, 0.5 + cc[2] * 0.5, 0.5 + cc[3] * 0.5)
    g.bottom:SetColorTexture(cc[1], cc[2], cc[3], 0.55)
    g.count:SetText("(" .. hd.entries .. ")")
    g.total:ClearAllPoints()
    g.total:SetPoint("RIGHT", g, "RIGHT", -m.totR, 0)
    g.total:SetText("")
    g.total:SetTextColor(unpack(C.muted))
    g.value:ClearAllPoints()
    g.value:SetPoint("RIGHT", g, "RIGHT", -m.valR, 0)
    g.value:SetShown(m.showValue)
    g.value:SetText(ns.Value.Format(hd.value))
    g.value:SetTextColor(unpack(C.muted))
end

local function NewMobRow()
    local r = CreateFrame("Button", nil, content)
    RowBase(r, ROW_H)
    -- the status before a creature's name: a dotted ring that lights up with the kills
    -- towards the drop chances, and a tick once there is enough data
    r.clock = CreateFrame("Button", nil, r)
    r.clock:SetSize(16, 16)
    r.clock:SetPoint("LEFT", NAME_X, 0)
    r.clock.dots = {}
    for i = 1, RING_DOTS do
        local dot = r.clock:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        dot:SetSize(3.2, 3.2)
        local theta = 2 * math.pi * (i - 1) / RING_DOTS -- clockwise from the top
        dot:SetPoint("CENTER", r.clock, "CENTER", RING_R * math.sin(theta), RING_R * math.cos(theta))
        r.clock.dots[i] = dot
    end
    r.clock.core = r.clock:CreateTexture(nil, "ARTWORK")
    r.clock.core:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    r.clock.core:SetSize(7, 7)
    r.clock.core:SetPoint("CENTER")
    r.clock.core:SetVertexColor(RING_ON[1], RING_ON[2], RING_ON[3], 0.85)
    r.clock.core:Hide()
    r.clock:SetScript("OnMouseUp", function(self) self:GetParent():Click() end)
    r.clock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Unlock progress"], 1, 0.85, 0.4)
        GameTooltip:AddLine((self.kills or 0) .. " / " .. (self.need or 0), 0.8, 0.8, 0.8)
        if (self.kills or 0) >= (self.need or 0) then
            GameTooltip:AddLine(L["Unlocked: enough kills for drop chances, rankings and more."], 0.4, 0.86, 0.66, true)
        else
            GameTooltip:AddLine(L["%d kills until unlocked"]:format(self.need - self.kills), 0.82, 0.66, 0.32, true)
        end
        GameTooltip:Show()
    end)
    r.clock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetTextColor(unpack(C.text))
    r.name:SetPoint("LEFT", NAME_X, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.res = CreateFrame("Frame", nil, r)
    r.res:SetSize(18, 18)
    r.res:SetPoint("LEFT", NAME_X, 0)
    -- round, so a resource does not look like a loot icon: a thin gold ring around a round picture
    local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    r.res.edge = r.res:CreateTexture(nil, "BACKGROUND")
    r.res.edge:SetAllPoints()
    r.res.edge:SetTexture(ROUND)
    r.res.edge:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.85)
    r.res.tex = r.res:CreateTexture(nil, "ARTWORK")
    r.res.tex:SetPoint("TOPLEFT", 1.5, -1.5)
    r.res.tex:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    r.res.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if r.res.CreateMaskTexture then
        local mask = r.res:CreateMaskTexture()
        mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(r.res.tex)
        r.res.tex:AddMaskTexture(mask)
    end
    r.res:Hide()
    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.level:SetWidth(LEVEL_W - 4)
    r.level:SetJustifyH("LEFT")

    r.icons = {}
    for i = 1, ICO_MAX do
        local b = W.NewIcon(r)
        b.count:SetFontObject("NumberFontNormalSmall")
        -- clicks on an icon unfold the row like clicks anywhere else on it
        b:SetScript("OnMouseUp", function(self) self:GetParent():Click() end)
        r.icons[i] = b
    end

    r.total = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.total:SetJustifyH("RIGHT")
    r.total:SetTextColor(unpack(C.text))
    r.countGlow = r:CreateTexture(nil, "ARTWORK", nil, 3)
    r.countGlow:SetTexture(W.HILITE_TEX)
    r.countGlow:SetBlendMode("ADD")
    r.countGlow:SetVertexColor(0.45, 0.9, 0.7)
    r.countGlow:SetAlpha(0)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetJustifyH("RIGHT")
    r.avg = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.avg:SetJustifyH("RIGHT")
    r.avg:SetTextColor(0.72, 0.66, 0.54)

    r:SetScript("OnClick", function(self)
        -- only one row is unfolded at a time; a second click folds it again
        if self.key then
            if self.isOpen then openKey = false else openKey = self.key; A.ensure = true end
            dirty = true
        end
    end)
    return r
end

-- the unfolded part: only what the row does not already show
local function NewDetail()
    local d = CreateFrame("Frame", nil, content)
    d:SetClipsChildren(true) -- while it grows open, what is not revealed yet stays hidden
    d.bg = d:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()
    d.bg:SetColorTexture(0.028, 0.022, 0.017, 0.55) -- a darker inset in the list's brown, the tiles sit on it as plates
    d.sep = d:CreateTexture(nil, "BORDER")
    d.sep:SetPoint("BOTTOMLEFT", 4, 0)
    d.sep:SetPoint("BOTTOMRIGHT", -4, 0)
    d.sep:SetHeight(1)
    d.sep:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.22)
    d.where = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.where:SetJustifyH("LEFT")
    d.where:SetWordWrap(false)
    d.where:SetTextColor(unpack(C.muted))
    d.tiles = {}
    -- money, loot and what skinning gave: each with its own label and icon grid
    d.sec = {}
    for i = 1, 3 do
        local plate = W.NewPlate(d, { 0.06, 0.049, 0.039, 1 })
        -- the label belongs to the plate: a child frame is drawn over its parent's text
        local label = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetTextColor(unpack(C.muted))
        label:SetJustifyH("LEFT")
        d.sec[i] = { plate = plate, label = label, grid = W.NewIconGrid(d, 26, 3, 20, 4) }
    end
    -- quick actions, right to left: journal, guide, show on the map, visible on the maps
    d.open = W.NewIconButton(d, W.ICON.journal, 22)
    d.open:SetTip(L["Open in journal"])
    d.open:SetScript("OnClick", function(self)
        if self.page then ns.UI.OpenEntry(self.page, self.key) end
    end)
    d.guide = W.NewIconButton(d, "Interface\\Icons\\INV_Misc_Map_01", 22)
    d.guide:SetPoint("RIGHT", d.open, "LEFT", -4, 0)
    d.guide:SetTip(L["Lead me to the nearest spot"], L["The guide arrow takes you there."])
    d.guide:SetScript("OnClick", function(self)
        local gm = ns.db.mobs[self.srcKey]
        local spot = gm and ns.Spots and ns.Spots.Nearest(gm)
        if spot then
            ns.Routes.GoTo(gm.name or self.srcKey, spot, gm.zone)
        else
            print("|cffffd100ForeverCompanion:|r " .. L["No saved spots yet."])
        end
    end)
    d.mapBtn = W.NewIconButton(d, W.ICON.map, 22)
    d.mapBtn:SetPoint("RIGHT", d.guide, "LEFT", -4, 0)
    d.mapBtn:SetTip(L["Show on the map"], L["Opens the loot map and highlights it."])
    d.mapBtn:SetScript("OnClick", function(self) U.ShowOnMap(self.srcKey) end)
    d.vis = W.NewIconButton(d, "Interface\\Icons\\INV_Misc_Eye_01", 22)
    d.vis:SetPoint("RIGHT", d.mapBtn, "LEFT", -4, 0)
    d.vis:SetScript("OnClick", function(self)
        local on = not ns.MapSourceVisible(self.srcKey, self.group)
        ns.MapSetSourceSel(self.srcKey, on, self.group)
        ns.Refresh()
    end)
    return d
end

local function NewItemRow()
    local r = CreateFrame("Button", nil, content)
    RowBase(r, ROW_H)
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.rank:SetPoint("LEFT", 4, 0)
    r.rank:SetWidth(18)
    r.rank:SetJustifyH("CENTER")
    r.rank:SetTextColor(unpack(C.muted))
    -- the item tooltip belongs to the icon only, not to the whole row
    r.iconBtn = W.NewIcon(r)
    r.iconBtn:SetPoint("LEFT", 24, 0)
    r.iconBtn:SetScript("OnMouseUp", function(self) self:GetParent():Click() end)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", 58, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("BOTTOMLEFT", 58, 6)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.sub:SetTextColor(unpack(C.muted))
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetJustifyH("LEFT")
    r.count:SetTextColor(unpack(C.text))
    r.countGlow = r:CreateTexture(nil, "ARTWORK", nil, 3)
    r.countGlow:SetTexture(W.HILITE_TEX)
    r.countGlow:SetBlendMode("ADD")
    r.countGlow:SetVertexColor(0.45, 0.9, 0.7)
    r.countGlow:SetAlpha(0)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetJustifyH("RIGHT")
    r.avg = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.avg:SetJustifyH("RIGHT")
    r.avg:SetTextColor(0.72, 0.66, 0.54)
    return r
end

function U.Colored(link)
    local color, name = link:match("|c(%x%x%x%x%x%x%x%x)|Hitem:.-|h%[(.-)%]|h")
    return color and ("|c" .. color .. name .. "|r") or link
end

function U.ApplyFade(o, v) o:SetAlpha(v) end
local function ApplyShine(r, v)
    r.shine:ClearAllPoints()
    r.shine:SetPoint("LEFT", r, "LEFT", v * (r:GetWidth() + 160) - 130, 0)
    r.shine:SetAlpha(0.32 * (1 - v))
end
local function ApplyValueText(o, v) o.value:SetText(ns.Value.Format(math.floor(v + 0.5))) end

-- a row that appears for the first time fades in
function U.Arrive(r, key)
    if r.arriveKey == key then return end
    r.arriveKey = key
    W.CancelEase(r, "fade")
    if U.AnimOn() and not A.noAnim and not A.known[key] then
        r:SetAlpha(0)
        Ease(r, "fade", 1, 5, U.ApplyFade, 0)
    else
        r:SetAlpha(1)
    end
    A.known[key] = true
end

-- text that lights up and settles back
local function Bump(r, slot, fs, base)
    Ease(r, slot, 0, 2.5, function(_, v) fs:SetTextColor(LerpColor(base, PULSE, v)) end, 1)
end

-- Bump a number's text when it grew since the row last showed this entry
function U.Track(r, slot, key, sig, fs, base)
    base = base or C.text
    local kf, sf_ = slot .. "Key", slot .. "Sig"
    if r[kf] ~= key then
        r[kf], r[sf_] = key, sig
        W.CancelEase(r, slot)
        W.CancelEase(r, slot .. "g")
        fs:SetTextColor(unpack(base))
        if r.countGlow then r.countGlow:SetAlpha(0) end
    else
        if sig > r[sf_] and U.AnimOn() and not A.noAnim then
            Bump(r, slot, fs, base)
            -- a soft gradient lights up behind the number and fades
            if r.countGlow then
                Ease(r, slot .. "g", 0, 2.2, function(o, v) o.countGlow:SetAlpha(v * 0.7) end, 1)
            end
        end
        r[sf_] = sig
    end
end

-- the value counts up to its new number
function U.SetValue(r, key, value, m)
    r.value:SetShown(m.showValue)
    if r.valKey ~= key then
        r.valKey, r.valTarget = key, value
        W.CancelEase(r, "val")
        W.CancelEase(r, "vp")
        r.value:SetText(ns.Value.Format(value))
        r.value:SetTextColor(unpack(C.text))
        return
    end
    if value > r.valTarget and U.AnimOn() and not A.noAnim then
        local cur = r._ease and r._ease.val and r._ease.val.cur or r.valTarget
        Ease(r, "val", value, 7, ApplyValueText, cur)
        Bump(r, "vp", r.value, C.text)
    elseif value ~= r.valTarget then
        W.CancelEase(r, "val")
        r.value:SetText(ns.Value.Format(value))
    end
    r.valTarget = value
end

function U.Flash(r, key, activity, now)
    local prev = seen[key]
    seen[key] = activity
    if not U.AnimOn() then r.flash:SetAlpha(0); r.shine:SetAlpha(0); return end
    if (prev and activity > prev) or (not prev and not A.noAnim) then
        flashAt[key] = now
        Ease(r, "shine", 1, 3.2, ApplyShine, 0)
    end
    local at = flashAt[key]
    local v = at and 0.4 * math.exp(-2.6 * (now - at)) or 0
    if v > 0.02 then Ease(r, "flash", 0, 2.6, ApplyFlash, v) else flashAt[key] = nil; r.flash:SetAlpha(0) end
end

-- fill ------------------------------------------------------------------------
local function SortedItems(map, sessionMap)
    local list = {}
    local hideGray = ns.db.settings.hideGray
    for id, count in pairs(map) do
        local gi = ns.db.items[id]
        local q = gi and gi.quality or 1
        if not (hideGray and q == 0) then
            list[#list + 1] = { id = id, link = gi and gi.link, quality = q, count = count, new = sessionMap and sessionMap[id] }
        end
    end
    table.sort(list, function(a, b)
        local am, bm = a.id == "money", b.id == "money"
        if am ~= bm then return am end
        if (a.new and 1 or 0) ~= (b.new and 1 or 0) then return a.new ~= nil end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.count ~= b.count then return a.count > b.count end
        return a.id < b.id
    end)
    return list
end

local function SessionMap(e)
    local map = {}
    for id, c in pairs(e.sm.items) do map[id] = c end
    for id, c in pairs(e.skinItems or {}) do map[id] = (map[id] or 0) + c end
    -- the coins this creature gave: an item of its own
    if ns.MoneyOn() and (e.sm.money or 0) > 0 then map.money = e.sm.money end
    return map
end

-- returns the height of the unfolded part
local function ChanceText(p)
    return p >= 10 and string.format("%d%%", p + 0.5) or string.format("%.1f%%", p)
end

-- small figures with a label above them
local TILE_GAP, TILE_H = ns.Theme.Get("hud", "tileGap"), ns.Theme.Get("hud", "tileH")
local function NewTile(parent)
    local t = W.NewPlate(parent, { 0.06, 0.049, 0.039, 1 }) -- the same gilded plate as the stat cards
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.label:SetPoint("TOPLEFT", 8, -5)
    t.label:SetTextColor(unpack(C.muted))
    t.label:SetWordWrap(false)
    t.label:SetJustifyH("LEFT")
    t.value = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.value:SetPoint("BOTTOMLEFT", 8, 6)
    t.value:SetTextColor(unpack(C.text))
    return t
end

local function FillDetail(d, key, gm, e, m, pad)
    local T = ns.Threshold()
    local isMob = gm.cat == "mob"
    local fmt = ns.Value.Format
    d:SetWidth(m.inner)
    local avail = m.inner - 2 * NAME_X
    local top = 10 + (pad or 0)
    local skinRec0 = ns.SkinRecord(gm)

    -- the head: where and what, and the quick actions on the right
    local where = gm.zone or ""
    local lt = ns.LevelText(gm)
    if lt then where = where .. (where ~= "" and " · " or "") .. lt end
    local kindTag = isMob and ns.KindText(gm)
    if kindTag then where = kindTag .. (where ~= "" and (" · " .. where) or "") end
    d.where:ClearAllPoints()
    d.where:SetPoint("TOPLEFT", NAME_X, -(top + 7))
    d.where:SetWidth(math.max(40, avail - 112))
    d.where:SetText(where)

    local group = ns.MapGroupOf(gm.cat, gm.kind)
    local visible = ns.MapSourceVisible(key, group)
    for _, b in ipairs({ d.vis, d.mapBtn, d.guide, d.open }) do b.srcKey, b.group = key, group end
    d.open:ClearAllPoints()
    d.open:SetPoint("TOPRIGHT", d, "TOPRIGHT", -NAME_X, -top)
    d.open.page = isMob and "bestiary" or "gathering"
    d.open.key = key
    d.vis:SetActive(visible)
    d.vis:SetTip(visible and L["Hide from the maps"] or L["Show on the maps"], L["On the map and the minimap."])
    local y = top + 30

    local gridTop = y

    -- Three parts, kept apart: money, loot, and what skinning gave. What was looted this
    -- session is in full colour with its count; what was seen in earlier sessions stays
    -- greyed out until it drops again. Uncommon (green) and quest items are only listed
    -- when they were looted this session; otherwise they would crowd the list.
    local skinRec = ns.SkinRecord(gm)
    local hideGray = ns.db.settings.hideGray

    local function Collect(items, mine, rec)
        local list = {}
        for id, total in pairs(items) do
            local gi = ns.db.items[id]
            local q = gi and gi.quality or 1
            local got = mine[id]
            local clutter = q == 2 or select(6, GetInstant(id)) == QUEST_CLASS
            if not (hideGray and q == 0) and (got ~= nil or not clutter) then
                list[#list + 1] = { id = id, link = gi and gi.link, quality = q, count = got or 0, total = total,
                    new = got ~= nil, rec = rec }
            end
        end
        table.sort(list, function(x, y)
            if x.new ~= y.new then return x.new end
            if x.quality ~= y.quality then return x.quality > y.quality end
            local xc, yc = x.new and x.count or x.total, y.new and y.count or y.total
            if xc ~= yc then return xc > yc end
            return x.id < y.id
        end)
        return list
    end

    -- the coins are the first item of the loot, without a chance
    local lootList = Collect(gm.items, e.sm.items, gm)
    if ns.MoneyOn() and (gm.money or 0) > 0 then
        local got = e.sm.money
        table.insert(lootList, 1, { id = "money", quality = 1, count = got or 0, total = gm.money, new = got ~= nil })
    end
    local sections = {
        { title = L["Loot"], list = lootList },
        { title = L["Skinning"], list = skinRec and Collect(skinRec.items, e.skinItems or {}, skinRec) or {} },
    }
    local shownSections = 0
    for _, s in ipairs(sections) do
        if #s.list > 0 then shownSections = shownSections + 1 end
    end

    -- fill one grid; returns its height. The drop chance of an item comes from the record
    -- that dropped it (the creature or its skinning) once that has enough kills (unlocked).
    local PLATE_PAD = 8 -- inside a plate: left, right
    local perRow = math.max(1, math.floor((m.inner - 2 * NAME_X - 2 * PLATE_PAD) / 29))
    local function FillGrid(grid, list, top, left, cols)
        local anyChance = false
        for _, it in ipairs(list) do
            local rec = it.rec
            if it.id ~= "money" and rec then
                if gm.cat ~= "mob" then
                    -- a plant or a vein always gives something: the average amount says more than a chance
                    local qty = rec.items[it.id]
                    if qty and (rec.kills or 0) > 0 then
                        it.avg = qty / rec.kills
                        anyChance = true
                    end
                elseif (rec.kills or 0) >= 1 then -- before the threshold it is an estimate, in another colour
                    it.pct, it.exact, it.drops, it.corpses = ns.DropChance(rec, it.id)
                    if it.pct then anyChance = true end
                end
            end
        end
        grid.cols = cols
        -- room for the chance under each icon only when there are chances to show
        local extra = anyChance and 12 or 0
        grid.rowExtra = extra
        grid:Set(list)
        for i, it in ipairs(list) do
            local b = grid.icons[i]
            if b and b:IsShown() then
                W.TintIcon(b, it.new)
                b:SetAlpha(it.new and 1 or 0.38)

                if not b.caption then
                    b.caption = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                    b.caption:SetPoint("TOP", b, "BOTTOM", 0, -1)
                end
                local rec = it.rec
                local pct, exact, drops, corpses = it.pct, it.exact, it.drops, it.corpses
                if it.id == "money" then
                    b.caption:SetText("")
                    local total, got = gm.money or 0, it.count
                    b.tipExtra = function()
                        local fmt = ns.Value.Format
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine(L["Total looted"], fmt(total), 0.8, 0.8, 0.8, 1, 1, 1)
                        if got > 0 then GameTooltip:AddDoubleLine(L["Session"], fmt(got), 0.8, 0.8, 0.8, 1, 1, 1) end
                        if gm.kills > 0 then GameTooltip:AddDoubleLine(L["Money per kill"], fmt(total / gm.kills), 0.8, 0.8, 0.8, 1, 1, 1) end
                    end
                elseif it.avg then
                    b.caption:SetText(string.format("%.1f", it.avg))
                    b.caption:SetTextColor(unpack(C.text))
                    local id, got, avg = it.id, it.count, it.avg
                    b.tipExtra = function()
                        local fmt = ns.Value.Format
                        local unit = ns.Value.Get(id)
                        local function line(label, value)
                            GameTooltip:AddDoubleLine(label, value, 0.8, 0.8, 0.8, 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        line(L["Average amount"], string.format("%.1f", avg))
                        if fmt(unit) ~= "" then line(L["Value each"], fmt(unit)) end
                        if unit > 0 and fmt(unit * avg) ~= "" then line(L["Value per action"], fmt(unit * avg)) end
                        line(L["Total looted"], (rec.items[id] or 0) .. " (" .. L["%d this session"]:format(got) .. ")")
                    end
                elseif pct then
                    local text = ChanceText(pct)
                    b.caption:SetText(text)
                    b.caption:SetTextColor(unpack(exact and C.text or { 0.93, 0.65, 0.37 }))
                    local id, got = it.id, it.count
                    b.tipExtra = function()
                        local fmt = ns.Value.Format
                        local quantity = rec.items[id] or 0
                        local unit = ns.Value.Get(id)
                        local function line(label, value)
                            GameTooltip:AddDoubleLine(label, value, 0.8, 0.8, 0.8, 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine(L["Drop chance"], text, 0.8, 0.8, 0.8, 0.4, 0.86, 0.66)
                        GameTooltip:AddLine(L["%d of %d kills"]:format(drops, corpses), 0.6, 0.6, 0.6)
                        if drops > 0 and quantity > 0 then line(L["Average amount"], string.format("%.1f", quantity / drops)) end
                        if fmt(unit) ~= "" then line(L["Value each"], fmt(unit)) end
                        if unit > 0 and rec.kills > 0 and quantity > 0 and fmt(unit * quantity / rec.kills) ~= "" then
                            line(L["Value per kill"], fmt(unit * quantity / rec.kills))
                        end
                        line(L["Total looted"], quantity .. " (" .. L["%d this session"]:format(got) .. ")")

                        -- where else this item drops, best chance first
                        local others = {}
                        local gi = ns.db.items[id]
                        for otherKey in pairs(gi and gi.sources or {}) do
                            local other = ns.db.mobs[otherKey]
                            if other and other ~= gm and other ~= skinRec and ns.CatOn(other.cat) then
                                local p = ns.DropChance(other, id)
                                if p then
                                    local name = other.name or otherKey
                                    if other.cat ~= "mob" then name = name .. " (" .. ns.CAT[other.cat].label .. ")" end
                                    others[#others + 1] = { name = name, pct = p }
                                end
                            end
                        end
                        if #others > 0 then
                            table.sort(others, function(x, y) return x.pct > y.pct end)
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(L["Also drops from"], 1, 0.85, 0.4)
                            for i = 1, math.min(4, #others) do
                                GameTooltip:AddDoubleLine(others[i].name, ChanceText(others[i].pct), 0.85, 0.85, 0.85, 1, 1, 1)
                            end
                            if #others > 4 then GameTooltip:AddLine(L["and %d more"]:format(#others - 4), 0.6, 0.6, 0.6) end
                        end
                        if not exact then
                            GameTooltip:AddLine(L["A rough estimate; it firms up with more kills."], 0.6, 0.6, 0.6, true)
                        end
                    end
                else
                    b.caption:SetText("")
                    b.tipExtra = nil
                end
            end
        end
        grid.frame:ClearAllPoints()
        grid.frame:SetPoint("TOPLEFT", left, -top)
        local shown = math.min(#list, cols * grid.maxRows)
        local rows = math.max(1, math.ceil(shown / cols))
        grid.frame:SetSize(cols * 29, grid.maxRows * (29 + extra))
        grid.frame:Show()
        return rows * (29 + extra) + 4
    end

    -- Loot and skinning are a plate each, side by side. Skinning is only as wide as what it has
    -- (two icons at least) and loot takes the rest; when loot would get too narrow, they sit
    -- one above the other, each across the full width.
    local avail = m.inner - 2 * NAME_X
    local items = {}
    for i, s in ipairs(sections) do
        local part = d.sec[i]
        if #s.list == 0 then
            part.grid.frame:Hide()
            part.label:Hide()
            part.plate:Hide()
        else
            part.label:SetText(s.title)
            items[#items + 1] = { part = part, list = s.list, labelW = part.label:GetStringWidth() }
        end
    end
    local lines = {}
    if #items == 2 then
        local skin = items[2]
        local skinW = math.max(2, math.min(#skin.list, perRow)) * 29 + 2 * PLATE_PAD
        skinW = math.max(skinW, skin.labelW + 2 * PLATE_PAD)
        local lootW = avail - skinW - TILE_GAP
        if lootW >= 2 * 29 + 2 * PLATE_PAD then
            items[1].w, skin.w = lootW, skinW
            lines[1] = { items[1], skin }
        else
            items[1].w, skin.w = avail, avail
            lines[1], lines[2] = { items[1] }, { skin }
        end
    elseif #items == 1 then
        items[1].w = avail
        lines[1] = { items[1] }
    end
    local yy = gridTop
    for _, line in ipairs(lines) do
        local xx, lineH = 0, 0
        for _, item in ipairs(line) do
            local part = item.part
            local cols = math.max(1, math.min(#item.list, math.floor((item.w - 2 * PLATE_PAD) / 29)))
            part.label:ClearAllPoints()
            part.label:SetPoint("TOPLEFT", d, "TOPLEFT", NAME_X + xx + PLATE_PAD, -(yy + 7))
            part.label:Show()
            local gh = FillGrid(part.grid, item.list, yy + 7 + 15, NAME_X + xx + PLATE_PAD, cols)
            local plateH = 7 + 15 + gh + 3
            part.plate:ClearAllPoints()
            part.plate:SetPoint("TOPLEFT", d, "TOPLEFT", NAME_X + xx, -yy)
            part.plate:SetSize(item.w, plateH)
            part.plate:Show()
            lineH = math.max(lineH, plateH + TILE_GAP)
            xx = xx + item.w + TILE_GAP
        end
        yy = yy + lineH
    end
    if #lines > 0 then yy = yy - TILE_GAP end
    y = math.max(yy, gridTop + 4) + 6

    -- figures of the source, from everything known about it
    local allItems = ns.MergedItems(gm)
    local totalValue, totalQty = 0, 0
    for id, q in pairs(allItems) do
        totalValue = totalValue + ns.Value.Get(id) * q
        totalQty = totalQty + q
    end
    local money = ns.MoneyOn() and (gm.money or 0) or 0
    totalValue = totalValue + money
    local sessionKills = e.sm.kills > 0 and e.sm.kills or e.skins
    -- few tiles, each with a second figure in brackets
    local tiles = { { L["Total (session)"], gm.kills .. " " .. W.Hex(C.muted) .. "(" .. sessionKills .. ")|r" } }
    if gm.kills > 0 and (totalQty > 0 or money > 0) then
        local v = fmt(totalValue / gm.kills)
        if v ~= "" then
            local label = isMob and L["Value per kill"] or L["Value per action"]
            if money > 0 then
                label = label .. " (" .. L["money"] .. ")"
                v = v .. " " .. W.Hex(C.muted) .. "(" .. fmt(money / gm.kills) .. ")|r"
            end
            tiles[#tiles + 1] = { label, v }
        end
        tiles[#tiles + 1] = { isMob and L["Items per kill"] or L["Items per action"], string.format("%.1f", totalQty / gm.kills), extra = true }
    end
    if skinRec0 and skinRec0.kills > 0 then tiles[#tiles + 1] = { L["Skinned"], tostring(skinRec0.kills), extra = true } end
    if isMob then
        -- experience of a kill at your level (and the last level at which it still gives any)
        local xp, how = ns.XPEstimate(gm)
        if xp then
            local text
            if how == "gray" then
                text = L["%d XP"]:format(0)
            else
                text = (how == "measured" and L["%d XP"] or L["est. %d XP"]):format(xp + 0.5)
            end
            local gray = ns.XPGrayLevel(gm)
            if gray and gray > 1 then text = text .. " " .. W.Hex(C.muted) .. "(" .. (gray - 1) .. ")|r" end
            tiles[#tiles + 1] = { L["XP per kill (to level)"], text }
        end
    end
    -- A small window shows the essentials only; the extra figures and the two charts come with
    -- room (a window about 620 pixels tall or more).
    local roomy = f:GetHeight() >= 620
    if not roomy then
        local essential = {}
        for _, t in ipairs(tiles) do
            if not t.extra then essential[#essential + 1] = t end
        end
        tiles = essential
    end
    local per = math.max(1, math.min(#tiles, math.floor((avail + TILE_GAP) / (112 + TILE_GAP))))
    local tileW = (avail - (per - 1) * TILE_GAP) / per
    for i, t in ipairs(tiles) do
        local tile = d.tiles[i]
        if not tile then tile = NewTile(d); d.tiles[i] = tile end
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", d, "TOPLEFT", NAME_X + col * (tileW + TILE_GAP), -(y + row * (TILE_H + TILE_GAP)))
        tile:SetSize(tileW, TILE_H)
        tile.label:SetWidth(math.max(20, tileW - 14))
        tile.value:SetWidth(math.max(20, tileW - 14))
        tile.value:SetWordWrap(false)
        tile.value:SetJustifyH("LEFT")
        tile.label:SetJustifyH("LEFT")
        tile.label:SetText(t[1])
        tile.value:SetText(t[2])
        tile:Show()
    end
    for i = #tiles + 1, #d.tiles do d.tiles[i]:Hide() end
    y = y + math.ceil(#tiles / per) * (TILE_H + TILE_GAP) + 4

    return y
end

-- one entry per creature; its skinning (a separate source) is folded in
local function BuildSources(snap)
    local list, byKey = {}, {}
    for key, src in pairs(snap.sources) do
        local gm = ns.db.mobs[key]
        if gm then
            local mobKey = gm.cat == "skin" and gm.name or key
            local mgm = ns.db.mobs[mobKey]
            if mgm and (gm.cat ~= "skin" or mgm.cat == "mob") then
                local e = byKey[mobKey]
                if not e then
                    e = { key = mobKey, gm = mgm, sm = ns.session.mobs[mobKey] or { kills = 0, items = {}, last = 0 },
                        value = 0, last = 0, skins = 0, skinItems = {} }
                    e.zone = e.sm.zone or mgm.zone
                    e.sub = e.sm.sub
                    byKey[mobKey] = e
                    list[#list + 1] = e
                end
                e.value = e.value + src.value
                local sm = ns.session.mobs[key]
                if sm then
                    e.last = math.max(e.last, sm.last)
                    if gm.cat == "skin" then
                        e.skins = sm.kills
                        e.skinItems = sm.items
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.last > b.last end)
    return list
end

-- a row stays with its creature, so it can glide to a new place when the order changes
function U.AssignPool(pool, owners, entries, new)
    for _, r in ipairs(pool) do r.inUse = false end
    for _, e in ipairs(entries) do
        local r = owners[e.key]
        if r then r.inUse = true end
        e.row = r
    end
    for _, e in ipairs(entries) do
        if not e.row then
            local r
            for _, cand in ipairs(pool) do
                if not cand.inUse then r = cand break end
            end
            if not r then r = new(); pool[#pool + 1] = r end
            if r.owner then owners[r.owner] = nil end
            r.owner, r.placedY = e.key, nil
            owners[e.key] = r
            r.inUse = true
            e.row = r
        end
    end
end

function U.HidePool(pool, owners, all)
    for _, r in ipairs(pool) do
        if all or not r.inUse then
            r:Hide()
            if not all and r.owner then owners[r.owner] = nil; r.owner = nil end
        end
    end
end

function U.AssignRows(visible) U.AssignPool(mobRows, A.rows, visible, NewMobRow) end
function U.HideRows(all) U.HidePool(mobRows, A.rows, all) end

function U.ResetRows()
    wipe(A.rows)
    wipe(A.itemOwners)
    for _, r in ipairs(mobRows) do r.owner, r.placedY, r.arriveKey = nil, nil, nil end
    for _, r in ipairs(itemRows) do r.owner, r.placedY, r.arriveKey = nil, nil, nil end
end

-- move a frame to a row position: it glides there when it was already on screen
function U.PlaceAt(fr, y)
    if fr.placedY == y then return end
    local first = fr.placedY == nil
    fr.placedY = y
    if first or A.noAnim or not U.AnimOn() or not fr:IsShown() then
        W.CancelEase(fr, "gy")
        fr:ClearAllPoints()
        fr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        fr.curY = y
    else
        Ease(fr, "gy", y, 11, function(o, v)
            o.curY = v
            o:ClearAllPoints()
            o:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -v)
        end, fr.curY or y)
    end
end

-- what one kill (or gathering) is worth on average: its loot and coins, all time
function U.AvgValue(e)
    if e.avgValue then return e.avgValue end
    local gm = e.gm
    local v = 0
    for id, q in pairs(ns.MergedItems(gm)) do v = v + ns.Value.Get(id) * q end
    if ns.MoneyOn() then v = v + (gm.money or 0) end
    e.avgValue = gm.kills > 0 and v / gm.kills or 0
    return e.avgValue
end

-- sort the loot list by the chosen column (the item's name, its total value or the value of one piece)
function U.SortLoot(list)
    local s = SortState()
    local key, asc = s.key, s.asc
    for _, e in ipairs(list) do
        if key == "name" then
            e.sv = (e.id == "money" and L["Money"] or U.ItemName(e.gi) or ""):lower()
        elseif key == "avg" then
            e.sv = (e.id ~= "money" and e.it.count > 0) and e.it.value / e.it.count or 0
        else
            e.sv = e.it.value
        end
    end
    table.sort(list, function(a, b)
        if a.sv ~= b.sv then
            if asc then return a.sv < b.sv end
            return a.sv > b.sv
        end
        return a.it.last > b.it.last
    end)
end

-- sort the entries of one group by the chosen column
function U.SortList(list)
    local s = SortState()
    if s.key == "recent" then return end
    for _, e in ipairs(list) do
        if s.key == "name" then e.sv = (e.gm.name or e.key):lower()
        elseif s.key == "value" then e.sv = e.value
        elseif s.key == "avg" then e.sv = U.AvgValue(e)
        elseif s.key == "total" then e.sv = e.gm.kills
        elseif s.key == "session" then e.sv = e.sm.kills > 0 and e.sm.kills or e.skins
        else
            local n = 0
            for id, c in pairs(SessionMap(e)) do
                if id ~= "money" then n = n + c end
            end
            e.sv = n
        end
    end
    local asc = s.asc
    table.sort(list, function(a, b)
        if a.sv ~= b.sv then
            if asc then return a.sv < b.sv end
            return a.sv > b.sv
        end
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
end

local function FillMobRow(r, e, index, open, now, m)
    local gm, sm = e.gm, e.sm
    local isMob = gm.cat == "mob"
    local T = ns.Threshold()
    r:SetWidth(m.inner)
    r.key, r.isOpen = e.key, open
    Zebra(r, index, open)
    U.Arrive(r, e.key)

    local name = gm.name or e.key
    local kindTag = isMob and ns.KindText(gm)
    if kindTag then name = name .. "  " .. kindTag end
    r.name:SetText(name)

    -- the clock: kills so far out of what the drop chances need
    local clock = r.clock
    r.name:ClearAllPoints()
    local resource = (not isMob) and ns.SourceMapIcon and ns.SourceMapIcon(gm) or nil
    local lead = isMob and (22 + LEVEL_W) or (resource and 24 or 0)
    r.res:SetShown(resource ~= nil)
    if resource then r.res.tex:SetTexture(resource) end
    r.name:SetPoint("LEFT", NAME_X + lead, 0)
    r.name:SetWidth(m.nameW - lead - 36)
    r.level:ClearAllPoints()
    r.level:SetPoint("LEFT", NAME_X + 22, 0)
    r.level:SetText(isMob and (ns.LevelTag(gm) or "") or "")
    if isMob then
        local full = gm.kills >= T
        clock.kills, clock.need = gm.kills, T
        clock:Show()
        clock.core:SetShown(full)
        local lit = math.floor(math.min(gm.kills / T, 1) * RING_DOTS)
        for i, dot in ipairs(clock.dots) do
            if i <= lit then dot:SetVertexColor(unpack(RING_ON)) else dot:SetVertexColor(1, 1, 1, 0.2) end
        end
    else
        clock:Hide()
    end

    -- this session's loot as icons (as many as fit)
    local sessionMap = SessionMap(e)
    local list = SortedItems(sessionMap, sessionMap)
    -- at most five items, and the coins always last, at the far right; an unfolded row
    -- leaves the loot to the part below it
    local money
    for i, it in ipairs(list) do
        if it.id == "money" then money = table.remove(list, i) break end
    end
    local shownList = {}
    if not open and m.nIcons > 0 then
        local room = math.min(5, m.nIcons - (money and 1 or 0))
        for i = 1, math.min(#list, math.max(0, room)) do shownList[i] = list[i] end
        if money then shownList[#shownList + 1] = money end
    end
    local n = #shownList
    for i = 1, ICO_MAX do
        local b = r.icons[i]
        local it = shownList[i]
        if it and i <= n then
            W.SetIcon(b, it.id, it.link, it.quality, it.count, ICO_SIZE)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", r, "RIGHT", -(m.icoR + (n - i) * ICO_STEP), 0)
        else
            b:Hide()
        end
    end

    -- the name gets everything the shown loot icons leave: a row with few icons (or none,
    -- as when it is unfolded) does not pay for the room of the widest row
    r.name:SetWidth(math.max(60, m.nameW + (m.nIcons - n) * ICO_STEP - lead - 36))

    -- what happened this session; the total is in the unfolded entry
    local sessionKills = sm.kills > 0 and sm.kills or e.skins
    r.total:SetFontObject("GameFontHighlightSmall")
    r.total:SetJustifyH("LEFT")
    r.total:SetText(sessionKills > 0 and ("×" .. sessionKills) or "")
    r.total:ClearAllPoints()
    r.total:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), r.name:GetWidth()) + 8, 0)
    r.countGlow:ClearAllPoints()
    r.countGlow:SetPoint("TOPLEFT", r.total, "TOPLEFT", -10, 5)
    r.countGlow:SetPoint("BOTTOMRIGHT", r.total, "BOTTOMRIGHT", 10, -5)

    r.value:ClearAllPoints()
    r.value:SetPoint("RIGHT", r, "RIGHT", -m.valR, 0)
    U.SetValue(r, e.key, e.value, m)
    U.Track(r, "tp", e.key, sessionKills, r.total, COUNT_COLOR)
    r.avg:ClearAllPoints()
    r.avg:SetPoint("RIGHT", r, "RIGHT", -m.avgR, 0)
    r.avg:SetShown(m.showAvg)
    if m.showAvg then
        local avg = U.AvgValue(e)
        r.avg:SetText(avg > 0 and ns.Value.Format(avg) or "")
    end

    local itemSum = 0
    for _, c in pairs(sessionMap) do itemSum = itemSum + c end
    U.Flash(r, "s" .. e.key, sm.kills + e.skins + itemSum, now)
end

local headBtn = {}
local sortArrow = f:CreateTexture(nil, "OVERLAY")
sortArrow:SetSize(10, 10)
sortArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
sortArrow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
sortArrow:Hide()
for key, fs in pairs(head) do
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 5)
    b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -5)
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 0.9, 0.6)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Sort"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Click to sort. More clicks reverse it, then go back to latest first."], 0.8, 0.8, 0.8, true)
        if key == "total" then GameTooltip:AddLine(L["Total kills first, then this session's."], 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(0.72, 0.66, 0.54)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        local s = SortState()
        local cycle, idx = SORT_CYCLE[key], 0
        for i, step in ipairs(cycle) do
            if step[1] == s.key and step[2] == s.asc then idx = i end
        end
        idx = idx + 1
        if idx > #cycle then s.key, s.asc = (mode == "loot" and "value" or "recent"), false
        else s.key, s.asc = cycle[idx][1], cycle[idx][2] end
        scroll, target = 0, 0
        dirty = true
    end)
    headBtn[key] = b
end

function U.SyncHead(on)
    local s = SortState()
    for key, b in pairs(headBtn) do b:SetShown(on and head[key]:IsShown()) end
    sortArrow:Hide()
    if not on or s.key == "recent" then return end
    local key = ({ name = "name", loot = "icons", value = "value", avg = "avg" })[s.key] or "total"
    local fs = head[key]
    if not fs:IsShown() then return end
    sortArrow:ClearAllPoints()
    if key == "name" then sortArrow:SetPoint("LEFT", fs, "RIGHT", 5, 0)
    else sortArrow:SetPoint("RIGHT", fs, "LEFT", -4, 0) end
    sortArrow:SetRotation(s.asc and math.pi / 2 or -math.pi / 2)
    sortArrow:Show()
end

local function LayoutHeader(m, sourcesMode)
    local top = -HEAD_ROW_TOP - 6
    local rowRight = 16 -- window edge to a row's right edge
    local function At(fs, justify, point, x)
        fs:ClearAllPoints()
        fs:SetJustifyH(justify)
        fs:SetPoint(point, f, "TOPRIGHT", x, top)
    end
    head.name:ClearAllPoints()
    head.name:SetJustifyH("LEFT")
    head.name:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + NAME_X, top)
    At(head.total, "RIGHT", "TOPRIGHT", -(rowRight + m.totR))
    At(head.value, "RIGHT", "TOPRIGHT", -(rowRight + m.valR))
    At(head.avg, "RIGHT", "TOPRIGHT", -(rowRight + m.avgR))
    head.avg:SetShown(m.showAvg and true or false)
    At(head.icons, "RIGHT", "TOPRIGHT", -(rowRight + m.icoR))
    head.value:SetShown(m.showValue)
    head.icons:SetShown(m.nIcons > 0 and sourcesMode)
    head.name:Show()
    head.total:Hide() -- the count follows the name
    U.SyncHead(true)
end

-- statistics tab ---------------------------------------------------------------
-- Lines on the same row grid as the lists: section headers, label/value rows,
-- one row per source category (with a share bar) and a value-over-time chart.

local CHART_ROWS = 4
local statRows, sectionRows, catRows = {}, {}, {}
local chart

local function NewSectionRow()
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0.17, 0.125, 0.08, 0.5)
    r.top = r:CreateTexture(nil, "BORDER")
    r.top:SetPoint("TOPLEFT", 4, 0)
    r.top:SetPoint("TOPRIGHT", -4, 0)
    r.top:SetHeight(1)
    r.top:SetColorTexture(1, 1, 1, 0.12)
    r.bottom = r:CreateTexture(nil, "BORDER")
    r.bottom:SetPoint("BOTTOMLEFT", 4, 0)
    r.bottom:SetPoint("BOTTOMRIGHT", -4, 0)
    r.bottom:SetHeight(1)
    r.bottom:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", 12, 0)
    r.label:SetTextColor(0.9, 0.84, 0.68)
    return r
end

local function NewStatRow()
    local r = CreateFrame("Frame", nil, content)
    RowBase(r, ROW_H)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", NAME_X, 0)
    r.label:SetTextColor(0.8, 0.74, 0.62)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.value:SetPoint("RIGHT", -14, 0)
    r.value:SetJustifyH("RIGHT")
    r.value:SetTextColor(unpack(C.text))
    return r
end

local function NewCatRow()
    local r = CreateFrame("Frame", nil, content)
    RowBase(r, ROW_H)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", NAME_X, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.label:SetTextColor(unpack(C.text))
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.value:SetPoint("RIGHT", -14, 0)
    r.value:SetJustifyH("RIGHT")
    r.value:SetTextColor(unpack(C.text))
    r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.pct:SetJustifyH("RIGHT")
    r.pct:SetTextColor(unpack(C.muted))
    r.track = r:CreateTexture(nil, "ARTWORK")
    r.track:SetHeight(8)
    r.track:SetColorTexture(0, 0, 0, 0.4)
    r.fill = r:CreateTexture(nil, "OVERLAY")
    r.fill:SetHeight(8)
    r.fill:SetPoint("LEFT", r.track, "LEFT")
    return r
end

local function NewChart()
    local c = CreateFrame("Frame", nil, content)
    c:SetHeight(CHART_ROWS * ROW_H)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(1, 1, 1, 0.02)
    c.bars = {}
    c.max = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.max:SetPoint("TOPRIGHT", -14, -8)
    c.max:SetTextColor(unpack(C.muted))
    c.from = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.from:SetPoint("BOTTOMLEFT", 14, 6)
    c.from:SetTextColor(unpack(C.muted))
    c.to = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.to:SetPoint("BOTTOMRIGHT", -14, 6)
    c.to:SetTextColor(unpack(C.muted))
    c.empty = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.empty:SetPoint("CENTER")
    c.empty:SetTextColor(unpack(C.muted))
    return c
end

function U.NewBar(parent)
    local b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.04)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("BOTTOMLEFT")
    b.fill:SetPoint("BOTTOMRIGHT")
    b.fill:SetHeight(1)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 1, 1, 1)
    b.glow:SetBlendMode("ADD")
    b.glow:SetAlpha(0)
    b:SetScript("OnEnter", function(self)
        Ease(self, "hv", 1, 18, function(o, v) o.glow:SetAlpha(v * 0.18) end)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.when or "", 1, 0.85, 0.4)
        GameTooltip:AddLine(self.what or "", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        Ease(self, "hv", 0, 18, function(o, v) o.glow:SetAlpha(v * 0.18) end)
        GameTooltip:Hide()
    end)
    return b
end

local function FillChart(c, m, y)
    c:SetWidth(m.inner)
    local s = ns.session
    local width = m.inner - 28
    local n = math.max(6, math.min(30, math.floor(width / 12)))
    local bw = math.max(3, math.floor((width - (n - 1) * 2) / n))
    local barsH = CHART_ROWS * ROW_H - 36
    local nowBucket = s.start and (math.floor(ns.SessionElapsed() / ns.TIMELINE_BUCKET) + 1) or 1
    local first = math.max(1, nowBucket - n + 1)
    local max = 0
    for i = 1, n do max = math.max(max, s.timeline[first + i - 1] or 0) end
    for i = 1, n do
        local b = c.bars[i]
        if not b then b = U.NewBar(c); c.bars[i] = b end
        local bucket = first + i - 1
        local v = s.timeline[bucket] or 0
        b:SetSize(bw, barsH)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14 + (i - 1) * (bw + 2), 22)
        local frac = max > 0 and v / max or 0
        local col = (v == max and max > 0) and FILL_JADE or FILL_GOLD
        b.fill:SetColorTexture(col[1], col[2], col[3], 1)
        b.fill:SetHeight(math.max(1, frac * (barsH - 2)))
        b.fill:SetAlpha(v > 0 and 1 or 0)
        local minutes = (bucket - 1) * ns.TIMELINE_BUCKET / 60
        b.when = string.format("%d–%d min", minutes, minutes + ns.TIMELINE_BUCKET / 60)
        b.what = v > 0 and ns.Value.Format(v) or L["nothing yet"]
        b:Show()
    end
    for i = n + 1, #c.bars do c.bars[i]:Hide() end
    c.max:SetText(max > 0 and ns.Value.Format(max) or "")
    c.from:SetText(string.format("%d min", (first - 1) * ns.TIMELINE_BUCKET / 60))
    c.to:SetText(L["now"])
    c.empty:SetText(max == 0 and L["Loot something to see the curve."] or "")
end

local function StatLines(snap)
    local s = ns.session
    local elapsed = ns.SessionElapsed()
    local hours = elapsed / 3600
    local fmt = ns.Value.Format
    local lines = {}
    local function sec(label) lines[#lines + 1] = { kind = "section", label = label } end
    local function stat(label, value) lines[#lines + 1] = { kind = "stat", label = label, value = value } end

    local gathered = 0
    for key, sm in pairs(s.mobs) do
        local gm = ns.db.mobs[key]
        if gm and gm.cat ~= "mob" and gm.cat ~= "skin" and ns.CatOn(gm.cat) then gathered = gathered + sm.kills end
    end
    local mobValue = (snap.catValue.mob or 0) + (snap.catValue.skin or 0)
    local perHour = elapsed >= 60

    sec(L["Value over time"])
    lines[#lines + 1] = { kind = "chart" }

    sec(L["By source"])
    local total = 0
    for _, cat in ipairs(ns.CATS) do total = total + (snap.catValue[cat] or 0) end
    local any = false
    for _, cat in ipairs(ns.CATS) do
        local v = snap.catValue[cat] or 0
        if v > 0 then
            any = true
            lines[#lines + 1] = { kind = "cat", cat = cat, value = v, share = total > 0 and v / total or 0 }
        end
    end
    if not any then stat(L["nothing yet"], "") end

    sec(L["Highlights"])
    local bestItem
    local quality = { 0, 0, 0 }
    for id, it in pairs(snap.items) do
        local gi = ns.db.items[id]
        if gi and (not bestItem or it.value > bestItem.value) and it.value > 0 then
            bestItem = { name = gi.link and gi.link:gsub("^.-%[", "["):gsub("%].*$", "]") or "?", link = gi.link, value = it.value, count = it.count }
        end
        local q = gi and gi.quality or 1
        if q == 2 then quality[1] = quality[1] + it.count elseif q == 3 then quality[2] = quality[2] + it.count elseif q >= 4 then quality[3] = quality[3] + it.count end
    end
    if bestItem then
        local color, name = bestItem.link:match("|c(%x%x%x%x%x%x%x%x)|Hitem:.-|h%[(.-)%]|h")
        local shown = color and ("|c" .. color .. name .. "|r") or bestItem.name
        stat(L["Most valuable drop"], shown .. " ×" .. bestItem.count .. "  " .. fmt(bestItem.value))
    else
        stat(L["Most valuable drop"], "-")
    end
    local mostKilled, bestMob
    for key, sm in pairs(s.mobs) do
        local gm = ns.db.mobs[key]
        if gm and gm.cat == "mob" and ns.CatOn("mob") then
            if not mostKilled or sm.kills > mostKilled.n then mostKilled = { name = gm.name or key, n = sm.kills } end
            local src = snap.sources[key]
            if src and src.value > 0 and (not bestMob or src.value > bestMob.value) then
                bestMob = { name = gm.name or key, value = src.value }
            end
        end
    end
    stat(L["Most killed"], mostKilled and (mostKilled.name .. " ×" .. mostKilled.n) or "-")
    stat(L["Best creature"], bestMob and (bestMob.name .. "  " .. fmt(bestMob.value)) or "-")
    stat(L["Uncommon / rare / epic drops"], quality[1] .. " / " .. quality[2] .. " / " .. quality[3])

    -- the plain numbers come last
    sec(L["Session"])
    stat(L["Duration"], W.Duration(elapsed) .. (s.paused and ("  " .. L["paused"]) or ""))
    stat(L["Kills"], tostring(snap.kills))
    stat(L["Kills per hour"], perHour and string.format("%.0f", snap.kills / hours) or "-")
    stat(L["Gathered"], tostring(gathered))
    stat(L["Items looted"], tostring(snap.looted))
    if snap.money > 0 then stat(L["Looted money"], fmt(snap.money)) end
    stat(L["Items per hour"], perHour and string.format("%.0f", snap.looted / hours) or "-")
    stat(L["Per hour"], (perHour and fmt(snap.value / hours) ~= "") and fmt(snap.value / hours) or "-")
    stat(L["Total value"], snap.value > 0 and fmt(snap.value) or "-")
    stat(L["Value per kill"], (snap.kills > 0 and mobValue > 0) and fmt(mobValue / snap.kills) or "-")
    stat(L["Last loot"], s.lastLoot and L["%s ago"]:format(W.Duration(GetTime() - s.lastLoot)) or "-")
    return lines
end

local function HideStats()
    for _, r in ipairs(statRows) do r:Hide() end
    for _, r in ipairs(sectionRows) do r:Hide() end
    for _, r in ipairs(catRows) do r:Hide() end
    if chart then chart:Hide() end
end

-- returns the content height used
local function RenderStats(snap, m)
    local lines = StatLines(snap)
    local q = U.Query()
    local secHit = true
    local nStat, nSec, nCat = 0, 0, 0
    local y = 0
    for _, ln in ipairs(lines) do
        if ln.kind == "section" then
            nSec = nSec + 1
            local r = sectionRows[nSec]
            if not r then r = NewSectionRow(); sectionRows[nSec] = r end
            r:SetWidth(m.inner)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            r.label:SetText(ln.label)
            r:Show()
            secHit = not q or U.Matches(q, ln.label)
            y = y + ROW_H
        elseif ln.kind == "stat" then
            nStat = nStat + 1
            local r = statRows[nStat]
            if not r then r = NewStatRow(); statRows[nStat] = r end
            r:SetWidth(m.inner)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local hit = q and U.Matches(q, ln.label, ln.value)
            Zebra(r, nStat, hit and true or false)
            r:SetAlpha((not q or hit) and 1 or 0.3)
            r.label:SetText(ln.label)
            r.value:SetText(ln.value)
            r:Show()
            y = y + ROW_H
        elseif ln.kind == "cat" then
            nCat = nCat + 1
            local r = catRows[nCat]
            if not r then r = NewCatRow(); catRows[nCat] = r end
            r:SetWidth(m.inner)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local cat = ns.CAT[ln.cat]
            local hit = q and U.Matches(q, cat.label, ns.Value.Format(ln.value))
            Zebra(r, nCat, hit and true or false)
            r:SetAlpha((not q or hit) and 1 or 0.3)
            r.icon:SetTexture(cat.icon)
            r.label:SetText(cat.label)
            r.value:SetText(ns.Value.Format(ln.value))
            r.pct:ClearAllPoints()
            r.pct:SetPoint("RIGHT", r, "RIGHT", -110, 0)
            r.pct:SetText(string.format("%d%%", ln.share * 100 + 0.5))
            local barW = math.max(40, m.inner - 360)
            r.track:ClearAllPoints()
            r.track:SetPoint("RIGHT", r, "RIGHT", -150, 0)
            r.track:SetWidth(barW)
            r.fill:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 0.85)
            r.fill:SetWidth(math.max(1, barW * ln.share))
            r.track:SetShown(m.inner > 400); r.fill:SetShown(m.inner > 400)
            r:Show()
            y = y + ROW_H
        elseif ln.kind == "chart" then
            if not chart then chart = NewChart() end
            chart:ClearAllPoints(); chart:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            FillChart(chart, m, y)
            chart:SetAlpha((not q or secHit) and 1 or 0.3)
            chart:Show()
            y = y + CHART_ROWS * ROW_H
        end
    end
    for i = nStat + 1, #statRows do statRows[i]:Hide() end
    for i = nSec + 1, #sectionRows do sectionRows[i]:Hide() end
    for i = nCat + 1, #catRows do catRows[i]:Hide() end
    return y
end

-- quick action of an unfolded entry: the loot map (a window of its own), filtered to this source
function U.ShowOnMap(key)
    if ns.MapMain then ns.MapMain.ShowSource(key) end
end

-- Regionboard ------------------------------------------------------------------------------
-- The creatures of one zone, best first: by what a kill is worth on average, and by the
-- experience a kill gives at your level. Every row has quick actions.

local boardCtl, boardRows, boardSecs = {}, {}, {}
boardCtl.prev = W.NewIconButton(f, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", 20)
boardCtl.prev:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -HEAD_ROW_TOP - 1)
boardCtl.prev:SetTip(L["Previous zone"])
boardCtl.next = W.NewIconButton(f, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 20)
boardCtl.next:SetPoint("LEFT", boardCtl.prev, "RIGHT", 3, 0)
boardCtl.next:SetTip(L["Next zone"])
boardCtl.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
boardCtl.label:SetTextColor(0.9, 0.84, 0.68)
-- which ranking: by value or by experience
boardCtl.valueBtn = W.NewButton(f, L["Value"], 86, 20)
boardCtl.valueBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -HEAD_ROW_TOP - 1)
boardCtl.xpBtn = W.NewButton(f, L["Experience"], 86, 20)
boardCtl.xpBtn:SetPoint("RIGHT", boardCtl.valueBtn, "LEFT", -4, 0)
boardCtl.valueBtn:SetScript("OnClick", function() A.boardMode = "value"; dirty = true end)
boardCtl.xpBtn:SetScript("OnClick", function() A.boardMode = "xp"; dirty = true end)

function U.ShowBoardControls(on)
    for _, w in pairs(boardCtl) do w:SetShown(on) end
end
U.ShowBoardControls(false)

local function BoardZones()
    local counts = {}
    for _, gm in pairs(ns.db.mobs) do
        if gm.cat == "mob" and gm.zone and gm.kills > 0 then counts[gm.zone] = (counts[gm.zone] or 0) + gm.kills end
    end
    local list = {}
    for zone, n in pairs(counts) do list[#list + 1] = { zone = zone, n = n } end
    table.sort(list, function(x, y) return x.n > y.n end)
    local zones = {}
    for i, e in ipairs(list) do zones[i] = e.zone end
    return zones
end

local function StepBoardZone(delta)
    local zones = BoardZones()
    if #zones == 0 then return end
    local idx = 1
    for i, zone in ipairs(zones) do
        if zone == A.boardZone then idx = i end
    end
    A.boardZone = zones[(idx - 1 + delta) % #zones + 1]
    dirty = true
end
boardCtl.prev:SetScript("OnClick", function() StepBoardZone(-1) end)
boardCtl.next:SetScript("OnClick", function() StepBoardZone(1) end)

local function NewBoardRow()
    local r = CreateFrame("Frame", nil, content)
    RowBase(r, ROW_H)
    r.bar = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.bar:SetHeight(ROW_H - 14)
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.rank:SetPoint("LEFT", 8, 0)
    r.rank:SetWidth(22)
    r.rank:SetJustifyH("RIGHT")
    r.rank:SetTextColor(unpack(C.muted))
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.val = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.val:SetJustifyH("RIGHT")
    r.val:SetWidth(100)
    r.journal = W.NewIconButton(r, W.ICON.journal, 20)
    r.journal:SetPoint("RIGHT", -10, 0)
    r.journal:SetTip(L["Open in journal"])
    r.journal:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        if key then ns.UI.OpenEntry("bestiary", key) end
    end)
    r.guide = W.NewIconButton(r, "Interface\\Icons\\INV_Misc_Map_01", 20)
    r.guide:SetPoint("RIGHT", r.journal, "LEFT", -4, 0)
    r.guide:SetTip(L["Lead me to the nearest spot"], L["The guide arrow takes you there."])
    r.guide:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        local gm = key and ns.db.mobs[key]
        local spot = gm and ns.Spots and ns.Spots.Nearest(gm)
        if spot then
            ns.Routes.GoTo(gm.name or key, spot, gm.zone)
        else
            print("|cffffd100ForeverCompanion:|r " .. L["No saved spots yet."])
        end
    end)
    r.mapBtn = W.NewIconButton(r, W.ICON.map, 20)
    r.mapBtn:SetPoint("RIGHT", r.guide, "LEFT", -4, 0)
    r.mapBtn:SetTip(L["Show on the map"], L["Opens the loot map and highlights it."])
    r.mapBtn:SetScript("OnClick", function(self) U.ShowOnMap(self:GetParent().key) end)
    return r
end

function U.HideBoard()
    for _, r in ipairs(boardRows) do r:Hide() end
    for _, r in ipairs(boardSecs) do r:Hide() end
end

function U.RenderBoard(snap, m)
    local zones = BoardZones()
    local zone = A.boardZone
    local known = false
    for _, z in ipairs(zones) do
        if z == zone then known = true end
    end
    if not known then
        zone = nil
        local here = GetZoneText()
        for _, z in ipairs(zones) do
            if z == here then zone = here end
        end
        zone = zone or zones[1]
        A.boardZone = zone
    end
    boardCtl.label:ClearAllPoints()
    if #zones > 1 then boardCtl.label:SetPoint("LEFT", boardCtl.next, "RIGHT", 10, 0)
    else boardCtl.label:SetPoint("LEFT", boardCtl.prev, "LEFT", 2, 0) end
    boardCtl.prev:SetShown(#zones > 1)
    boardCtl.next:SetShown(#zones > 1)
    boardCtl.label:SetText(zone or L["No data yet"])

    local q = U.Query()
    local byValue, byXP = {}, {}
    if zone then
        for key, gm in pairs(ns.db.mobs) do
            if gm.cat == "mob" and gm.zone == zone and gm.kills >= ns.Threshold() and ns.CatOn("mob")
                and (not q or U.Matches(q, gm.name, gm.kind and ns.KINDS[gm.kind].label)) then
                local v = U.AvgValue({ gm = gm })
                if v > 0 then byValue[#byValue + 1] = { key = key, gm = gm, v = v } end
                local xp, how = ns.XPEstimate(gm)
                if xp and xp > 0 then byXP[#byXP + 1] = { key = key, gm = gm, v = xp, how = how } end
            end
        end
    end
    local function Better(x, y)
        if x.v ~= y.v then return x.v > y.v end
        return (x.gm.name or "") < (y.gm.name or "")
    end
    table.sort(byValue, Better)
    table.sort(byXP, Better)
    for i = #byValue, 16, -1 do byValue[i] = nil end
    for i = #byXP, 16, -1 do byXP[i] = nil end

    local y, nSec, nRow = 0, 0, 0
    local function Section(title)
        nSec = nSec + 1
        local r = boardSecs[nSec]
        if not r then r = NewSectionRow(); boardSecs[nSec] = r end
        r:SetWidth(m.inner)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        r.label:SetText(title)
        r:Show()
        y = y + ROW_H
    end
    local function Row()
        nRow = nRow + 1
        local r = boardRows[nRow]
        if not r then r = NewBoardRow(); boardRows[nRow] = r end
        r:SetWidth(m.inner)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        r:Show()
        y = y + ROW_H
        return r
    end
    local function Rows(list, asXP)
        if #list == 0 then
            local r = Row()
            r.key = nil
            r.rank:SetText("")
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", 38, 0)
            r.name:SetText(MUTED_TXT .. L["Nothing with calculated drop chances yet."] .. "|r")
            r.val:SetText("")
            r.bar:Hide()
            r.mapBtn:Hide()
            r.guide:Hide()
            r.journal:Hide()
            return
        end
        local top = list[1].v
        for i, ent in ipairs(list) do
            local r = Row()
            local gm = ent.gm
            Zebra(r, i, false)
            r.key = ent.key
            r.rank:SetText(i)
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", 38, 0)
            r.name:SetWidth(math.max(60, m.inner - 38 - 100 - 88))
            local tag, kind = ns.LevelTag(gm), ns.KindText(gm)
            r.name:SetText((tag and (tag .. "  ") or "") .. (gm.name or ent.key) .. (kind and ("  " .. kind) or ""))
            r.val:ClearAllPoints()
            r.val:SetPoint("RIGHT", r, "RIGHT", -88, 0)
            r.val:SetText(asXP and string.format("%d XP", ent.v + 0.5) or ns.Value.Format(ent.v))
            r.val:SetTextColor(unpack((asXP and ent.how ~= "measured") and C.muted or C.text))
            -- the share of the best one, as a quiet bar behind the figure
            local c = asXP and FILL_JADE or FILL_GOLD
            r.bar:ClearAllPoints()
            r.bar:SetPoint("RIGHT", r, "RIGHT", -86, 0)
            r.bar:SetWidth(math.max(2, 104 * ent.v / top))
            r.bar:SetColorTexture(c[1], c[2], c[3], 0.3)
            r.bar:Show()
            r.mapBtn:Show()
            r.guide:Show()
            r.journal:Show()
        end
    end
    local byXPMode = A.boardMode == "xp"
    for _, b in ipairs({ boardCtl.valueBtn, boardCtl.xpBtn }) do
        local on = (b == boardCtl.xpBtn) == byXPMode
        b:SetSelected(on)
    end
    if byXPMode then
        Section(L["Most experience"] .. "  " .. MUTED_TXT .. L["at level %d, all sessions"]:format(UnitLevel("player") or 0) .. "|r")
        Rows(byXP, true)
    else
        Section(L["Most valuable creatures"] .. "  " .. MUTED_TXT .. L["value per kill, all sessions"] .. "|r")
        Rows(byValue, false)
    end
    for i = nSec + 1, #boardSecs do boardSecs[i]:Hide() end
    for i = nRow + 1, #boardRows do boardRows[i]:Hide() end
    return y
end

-- Auto route --------------------------------------------------------------------------------
-- A lap through all plants, or one kind of vein or plant, on the map you are on. It says how
-- long a lap takes and when the places should have grown back, so a circle can be farmed.

A.route = { cat = "herb", type = 0, ready = false }
local ROUTE_CATS = { "herb", "ore", "object" }
local routePanel = W.NewPlate(f, C.page)
routePanel:Hide()
routePanel.title = routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
routePanel.title:SetPoint("TOPLEFT", 14, -12)
routePanel.title:SetTextColor(0.9, 0.84, 0.68)
routePanel.cats = {}
for i, cat in ipairs(ROUTE_CATS) do
    local b = W.NewButton(routePanel, ns.CAT[cat].label, 90, 26)
    b.cat = cat
    b:SetScript("OnClick", function() A.route.cat, A.route.type = cat, 0; dirty = true end)
    routePanel.cats[i] = b
end
routePanel.typePrev = W.NewIconButton(routePanel, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", 22)
routePanel.typeNext = W.NewIconButton(routePanel, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 22)
routePanel.typeLabel = routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
routePanel.typeLabel:SetJustifyH("LEFT")
routePanel.typeLabel:SetWordWrap(false)
routePanel.ready = W.NewToggle(routePanel, L["Only spots that should be ready"], nil,
    function() return A.route.ready end, function(on) A.route.ready = on end, 300)
routePanel.info = routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
routePanel.info:SetJustifyH("LEFT")
routePanel.info:SetJustifyV("TOP")
routePanel.list = routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
routePanel.list:SetJustifyH("LEFT")
routePanel.list:SetJustifyV("TOP")
routePanel.list:SetTextColor(unpack(C.muted))
routePanel.create = W.NewButton(routePanel, L["Create route"], 150, 28)
routePanel.go = W.NewButton(routePanel, L["Create and guide me"], 190, 28)

local function MakeAutoRoute(startNav)
    local plan = routePanel.plan
    if not plan then return end
    local route = ns.Spots.CreateRoute(plan, routePanel.planName)
    if startNav then ns.Routes.StartNav(route, 1) end
    print("|cffffd100ForeverCompanion:|r " .. L["Route created: %s"]:format(routePanel.planName))
end
routePanel.create:SetScript("OnClick", function() MakeAutoRoute(false) end)
routePanel.go:SetScript("OnClick", function() MakeAutoRoute(true) end)
routePanel.typePrev:SetScript("OnClick", function() A.route.type = A.route.type - 1; dirty = true end)
routePanel.typeNext:SetScript("OnClick", function() A.route.type = A.route.type + 1; dirty = true end)

function U.HideRoute() routePanel:Hide() end

function U.RenderRoute(m)
    local top = LIST_TOP + 3
    local availH = f:GetHeight() - LIST_TOP - LIST_BOTTOM - 8
    local width = f:GetWidth() - 16
    local inner = width - 28
    routePanel:ClearAllPoints()
    routePanel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -top)
    routePanel:SetSize(width, availH)
    routePanel:Show()

    local mapID = ns.PlayerPos()
    local zoneName = GetZoneText()
    local cfg = ns.CAT[A.route.cat]
    routePanel.title:SetText(L["Auto route"] .. "  " .. MUTED_TXT .. zoneName .. "|r")

    -- the kinds of the chosen category that were seen on this map
    local types = {}
    for key, gm in pairs(ns.db.mobs) do
        if gm.cat == A.route.cat and ns.CatOn(gm.cat) and gm.spots then
            local n = 0
            for _, sp in pairs(gm.spots) do
                if sp.m == mapID then n = n + 1 end
            end
            if n > 0 then types[#types + 1] = { key = key, name = gm.name or key, n = n } end
        end
    end
    table.sort(types, function(x, y)
        if x.n ~= y.n then return x.n > y.n end
        return x.name < y.name
    end)
    local count = #types
    A.route.type = count > 0 and A.route.type % (count + 1) or 0

    local bw = (inner - 12) / 3
    for i, b in ipairs(routePanel.cats) do
        local on = b.cat == A.route.cat
        b:SetWidth(bw)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 14, 0)
        b:SetPoint("TOPLEFT", routePanel, "TOPLEFT", 14 + (i - 1) * (bw + 6), -38)
        b:SetSelected(on)
    end
    routePanel.typePrev:ClearAllPoints()
    routePanel.typePrev:SetPoint("TOPLEFT", routePanel, "TOPLEFT", 14, -74)
    routePanel.typeNext:ClearAllPoints()
    routePanel.typeNext:SetPoint("TOPRIGHT", routePanel, "TOPRIGHT", -14, -74)
    routePanel.typePrev:SetShown(count > 0)
    routePanel.typeNext:SetShown(count > 0)
    routePanel.typeLabel:ClearAllPoints()
    routePanel.typeLabel:SetPoint("LEFT", routePanel.typePrev, "RIGHT", 10, 0)
    routePanel.typeLabel:SetWidth(inner - 70)
    local chosen = A.route.type > 0 and types[A.route.type] or nil
    routePanel.typeLabel:SetText(chosen and (chosen.name .. "  " .. MUTED_TXT .. "(" .. chosen.n .. ")|r")
        or (count > 0 and L["All %s here"]:format(cfg.label) or MUTED_TXT .. L["Nothing of this kind saved here."] .. "|r"))
    routePanel.ready:SetWidth(math.min(inner, 340))
    routePanel.ready:ClearAllPoints()
    routePanel.ready:SetPoint("TOPLEFT", routePanel, "TOPLEFT", 14, -104)
    routePanel.ready:Refresh()

    -- the plan
    local keys = {}
    if chosen then keys[1] = chosen.key
    else for _, t in ipairs(types) do keys[#keys + 1] = t.key end end
    local plan, why
    if #keys > 0 then plan, why = ns.Spots.Plan(keys, { onlyReady = A.route.ready })
    else why = L["Nothing of this kind saved here."] end
    routePanel.plan = plan
    routePanel.planName = cfg.label .. " · " .. zoneName .. (chosen and (" · " .. chosen.name) or "")

    routePanel.info:ClearAllPoints()
    routePanel.info:SetPoint("TOPLEFT", routePanel, "TOPLEFT", 14, -146)
    routePanel.info:SetWidth(inner)
    routePanel.list:ClearAllPoints()
    routePanel.list:SetPoint("TOPLEFT", routePanel, "TOPLEFT", 14, -222)
    routePanel.list:SetWidth(inner)
    if plan then
        local lines = {
            L["%d spots · %d yd for a lap · about %s"]:format(#plan.points, plan.loop + 0.5, W.Duration(plan.lapTime)),
            L["Respawn: about %s"]:format(W.Duration(plan.minRespawn)) .. "  " .. MUTED_TXT
                .. (plan.basis > 0 and L["(measured, %d gaps)"]:format(plan.basis) or L["(typical value, too little data)"]) .. "|r",
            L["%d of %d spots should be ready."]:format(plan.ready, #plan.points),
        }
        if plan.lapTime >= plan.minRespawn * 0.9 then
            lines[#lines + 1] = JADE_TXT .. L["A lap takes about as long as the respawn: farming in a circle works."] .. "|r"
        else
            lines[#lines + 1] = "|cffd9a35c" .. L["A lap is shorter than the respawn: some places will not be back yet."] .. "|r"
        end
        routePanel.info:SetText(table.concat(lines, "\n"))
        local rows = {}
        local maxLines = math.max(2, math.floor((availH - 222 - 56) / 14))
        for i = 1, math.min(#plan.points, maxLines) do
            local p = plan.points[i]
            local status = p.ready and (JADE_TXT .. L["ready"] .. "|r") or (MUTED_TXT .. L["in %s"]:format(W.Duration(p.wait)) .. "|r")
            rows[#rows + 1] = string.format("%2d   %s   %d yd   %s", i, p.gm.name or "?", p.leg + 0.5, status)
        end
        if #plan.points > maxLines then rows[#rows + 1] = L["and %d more"]:format(#plan.points - maxLines) end
        routePanel.list:SetText(table.concat(rows, "\n"))
    else
        routePanel.info:SetText(MUTED_TXT .. (why or "") .. "|r")
        routePanel.list:SetText("")
    end
    routePanel.create:ClearAllPoints()
    routePanel.create:SetPoint("BOTTOMLEFT", routePanel, "BOTTOMLEFT", 14, 12)
    routePanel.go:ClearAllPoints()
    routePanel.go:SetPoint("BOTTOMRIGHT", routePanel, "BOTTOMRIGHT", -14, 12)
    routePanel.create:SetEnabled(plan ~= nil)
    routePanel.go:SetEnabled(plan ~= nil)
    routePanel.create:SetAlpha(plan and 1 or 0.4)
    routePanel.go:SetAlpha(plan and 1 or 0.4)
end

-- Minimized: the window is only as tall as the top part (the three figures); everything below it is
-- hidden and Render leaves it alone. The size from before is put back when it is restored.
local COLLAPSED_H = 94 - (HUD.compact and 40 or 0) -- (compact layout: the footer stays)
function U.SetCollapsed(on)
    on = on and true or false
    if on == (A.collapsed or false) then return end
    A.collapsed = on
    if ns.db then ns.db.hudCollapsed = on end
    local lower = { rule, countLabel, searchBox, headBg, headRule, sf, well, A.lane, A.laneLine, listBorder, thumbFrame, grip }
    if on then
        A.expandedH = f:GetHeight()
        f:SetHeight(COLLAPSED_H)
        for _, t in ipairs(tabs) do t:Hide() end
        for _, w in ipairs(lower) do w:Hide() end
        U.SyncHead(false) -- the sort arrow and the buttons of the column heads, too
        if U.footer then -- the footer and its grip stay: the window can be made wider, not higher
            grip:Show()
            U.gripOpts.minSize, U.gripOpts.maxSize = { MIN_W, COLLAPSED_H }, { MAX_W, COLLAPSED_H }
            U.gripOpts.defaultSize = { DEFAULT_W, COLLAPSED_H } -- (shift + right-click on the grip: the width only, it stays folded up)
        end
        for _, fs in pairs(head) do fs:Hide() end
        U.ShowBoardControls(false)
        U.HideBoard()
        U.HideRoute()
        HideStats()
    else
        f:SetHeight(math.max(MIN_H, A.expandedH or DEFAULT_H))
        for _, t in ipairs(tabs) do t:Show() end
        rule:Show(); countLabel:Show(); searchBox:Show(); grip:Show() -- the rest returns with the next Render
        U.gripOpts.minSize, U.gripOpts.maxSize = { MIN_W, MIN_H }, { MAX_W, MAX_H }
        U.gripOpts.defaultSize = { DEFAULT_W, DEFAULT_H }
    end
    minBtn.text:SetText(on and "+" or "–")
    W.SkinSyncMinimized(f, on)
    dirty = true
end

local function Render()
    if not ns.db or not ns.session then return end
    local snap = ns.BuildSnapshot()
    local s = ns.session
    local elapsed = ns.SessionElapsed()
    local now = GetTime()
    -- the list shows whole rows only: its height is rounded down to a row multiple
    local avail = f:GetHeight() - LIST_TOP - LIST_BOTTOM
    sf:SetHeight(math.max(ROW_H, math.floor(avail / ROW_H) * ROW_H))
    viewH = sf:GetHeight()
    local m = Metrics()
    content:SetWidth(m.inner)
    empty:SetWidth(math.max(80, m.inner - 40))

    W.SyncPauseButton(pauseBtn)
    banner:SetWidth(math.max(150, math.min(240, f:GetWidth() - 170)))

    -- pause and end sit stacked to the right of the cards, as in the journal; in the compact layout side by side at the left, with the
    -- cards at the top, to the right of them
    local cardW = (f:GetWidth() - 16 - 12 - 28) / 3
    local cardsLeft, cardsTop = 8, -34
    pauseBtn:ClearAllPoints()
    endBtn:ClearAllPoints()
    if U.compact then
        -- the cards reach up beside the round icon, just under the title bar (the frame stands 28 above the window's edge); pause and end
        -- are stacked at the right, level with the cards
        cardsLeft, cardsTop = 56, 24
        cardW = (f:GetWidth() - cardsLeft - 8 - 12 - 28) / 3
        pauseBtn:SetSize(22, 22)
        endBtn:SetSize(22, 22)
        pauseBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, cardsTop)
        endBtn:SetPoint("BOTTOMRIGHT", pauseBtn, "BOTTOMRIGHT", 0, -24)
    else
        pauseBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -34)
        endBtn:SetPoint("BOTTOMRIGHT", pauseBtn, "BOTTOMRIGHT", 0, -24)
    end
    for i, card in ipairs(cards) do
        card:SetWidth(cardW)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", f, "TOPLEFT", cardsLeft + (i - 1) * (cardW + 6), cardsTop)
    end
    pausedLabel:Hide() -- a paused session pulses instead (see U.PausePulse)
    W.UpdateStatCards(cards, snap, false, U.compact)
    if U.timeText then
        U.timeText:SetText("|TInterface\\Icons\\INV_Misc_PocketWatch_01:14:14:0:0:64:64:5:59:5:59|t " .. W.Duration(elapsed)
            .. (s.paused and ("   |TInterface\\TimeManager\\PauseButton:13:13|t " .. L["paused"]) or ""))
        if U.FooterFind then U.FooterFind() end
        U.timeText:SetTextColor(unpack(s.paused and { 0.93, 0.65, 0.37 } or { 0.58, 0.54, 0.47 })) -- (amber while paused)
    end
    if A.collapsed then return end

    for _, t in ipairs(tabs) do
        t:SetActive(t.id == mode)
    end

    -- the search box takes what the tab row has left
    U.LayoutSearch()

    if A.knownFor ~= ns.session then A.knownFor = ns.session; wipe(A.known); U.ResetRows() end
    A.noAnim = A.first or not A.visited[mode]

    local usedMob, usedDetail, usedItem, usedHeader = 0, 0, 0, 0
    local y = 0
    local count = 0

    -- which parts of the panel belong to this tab
    local listMode = mode == "sources" or mode == "gather" or mode == "loot"
    sf:SetShown(mode ~= "route")
    listBorder:SetShown(mode ~= "route")
    well:SetShown(mode ~= "route")
    A.lane:SetShown(mode ~= "route")
    A.laneLine:SetShown(mode ~= "route")
    headBg:SetShown(listMode or mode == "board" or mode == "route")
    headRule:SetShown(headBg:IsShown())
    if not listMode then for _, fs in pairs(head) do fs:Hide() end; U.SyncHead(false) end
    if mode ~= "stats" then HideStats() end
    U.ShowBoardControls(mode == "board")
    if mode ~= "board" then U.HideBoard() end
    if mode ~= "route" then U.HideRoute() end

    A.openSpan = nil
    if mode == "sources" or mode == "gather" then
        head.name:SetText(L["Name"])
        head.icons:SetText(L["Loot"])
        head.total:SetText(U.TotalTitle())
        head.value:SetText(L["Total value"])
        head.avg:SetText(L["Avg. value"])
        LayoutHeader(m, true)

        local list = BuildSources(snap)
        -- while an entry is unfolded, fighting something else moves the unfolded part to
        -- that creature (nothing unfolds by itself when all are folded)
        local latest = list[1] and list[1].key
        if latest ~= A.latestKey then
            if A.latestKey and latest and openKey then openKey = latest end
            A.latestKey = latest
        end
        local q = U.Query()
        if q then
            local kept = {}
            for _, e in ipairs(list) do
                local gm = e.gm
                if U.Matches(q, gm.name, gm.zone, ns.CAT[gm.cat].label, gm.kind and ns.KINDS[gm.kind].label) or U.Matches(q, U.ItemNames(gm)) then
                    kept[#kept + 1] = e
                end
            end
            list = kept
        end
        -- the enemies, or what is gathered (herbs, ore and the rest that is not a creature), as one list each: no groups
        local kept = {}
        for _, e in ipairs(list) do
            local cat = e.gm.cat
            if cat ~= "skin" and ns.CAT[cat] and ((mode == "sources") == (cat == "mob")) then kept[#kept + 1] = e end
        end
        list = kept
        count = #list
        U.SortList(list)
        U.AssignRows(list)

        do
            do
                for i, e in ipairs(list) do
                    local open = openKey == e.key

                    local r = e.row
                    local rowY = y
                    U.PlaceAt(r, y)
                    FillMobRow(r, e, i, open, now, m)
                    r:Show()
                    y = y + ROW_H

                    if open then
                        usedDetail = usedDetail + 1
                        local d = details[usedDetail]
                        if not d then d = NewDetail(); details[usedDetail] = d end
                        if d.openKey ~= e.key then d.placedY = nil end
                        U.PlaceAt(d, y)
                        -- whole rows only; what is left over is split above and below
                        local need = FillDetail(d, e.key, e.gm, e, m, 0)
                        local dh = math.ceil(need) -- exactly what the content needs, no air above and below
                        local pad = math.floor((dh - need) / 2)
                        if pad > 0 then FillDetail(d, e.key, e.gm, e, m, pad) end
                        -- it opens downwards at the pace the rows below make room (same easing),
                        -- so the two never overlap
                        local fresh = d.heightKey ~= e.key
                        if fresh then d:SetHeight(1) end
                        if U.AnimOn() and not A.noAnim then
                            Ease(d, "h", dh, 11, function(o, v) o:SetHeight(math.max(1, v)) end, fresh and 1 or nil)
                        else
                            W.CancelEase(d, "h")
                            d:SetHeight(dh)
                        end
                        d.heightKey = e.key
                        d:Show()
                        if d.openKey ~= e.key then
                            d.openKey = e.key
                            W.CancelEase(d, "fade")
                            if U.AnimOn() and not A.noAnim then
                                d:SetAlpha(0)
                                Ease(d, "fade", 1, 8, U.ApplyFade, 0)
                            else
                                d:SetAlpha(1)
                            end
                        end
                        y = y + dh
                    end
                    if open then A.openSpan = { rowY, y } end
                end
            end
        end
        empty:SetText(count == 0 and (q and L["Nothing matches."] or L["Nothing recorded yet. Go hunt!"]) or "")
    elseif mode == "loot" then
        head.name:SetText(L["Item"])
        head.value:SetText(L["Total value"])
        head.avg:SetText(L["Avg. value"])
        LayoutHeader(m, false)

        local list = {}
        local q = U.Query()
        for id, it in pairs(snap.items) do
            local gi = ns.db.items[id]
            if gi and gi.link and not (ns.db.settings.hideGray and (gi.quality or 1) == 0) then
                local keep = true
                if q then
                    keep = U.Matches(q, U.ItemName(gi))
                    if not keep then
                        for key in pairs(it.sources) do
                            local gm = ns.db.mobs[key]
                            if U.Matches(q, gm and gm.name or key) then keep = true break end
                        end
                    end
                end
                if keep then list[#list + 1] = { id = id, gi = gi, it = it } end
            end
        end
        -- the looted money, a row like any item
        if snap.money > 0 and ns.MoneyOn() then
            local srcs, last = {}, 0
            for key, sm in pairs(ns.session.mobs) do
                local gm = ns.db.mobs[key]
                if gm and ns.CatOn(gm.cat) and (sm.money or 0) > 0 then
                    srcs[key] = sm.money
                    last = math.max(last, sm.last)
                end
            end
            local keep = true
            if q then
                keep = U.Matches(q, L["Money"])
                if not keep then
                    for key in pairs(srcs) do
                        local gm = ns.db.mobs[key]
                        if U.Matches(q, gm and gm.name or key) then keep = true break end
                    end
                end
            end
            if keep then
                list[#list + 1] = { id = "money", gi = { quality = 1 },
                    it = { count = snap.money, value = snap.money, sources = srcs, last = last } }
            end
        end
        U.SortLoot(list)
        count = #list
        local nameW = m.inner - 58 - (m.icoR - 6) - 4
        for _, e in ipairs(list) do e.key = "i" .. e.id end
        U.AssignPool(itemRows, A.itemOwners, list, NewItemRow)
        for i, e in ipairs(list) do
            local r = e.row
            U.PlaceAt(r, y)
            r:SetWidth(m.inner)
            Zebra(r, i, false)
            U.Arrive(r, "i" .. e.id)
            r.itemID = e.id
            r.rank:SetText(i)
            W.SetIcon(r.iconBtn, e.id, e.gi.link, e.gi.quality or 1, nil, 26)
            r.iconBtn.copper = e.id == "money" and e.it.count or nil
            r.name:SetWidth(nameW - 36)
            r.name:SetText(e.id == "money" and ("|cffffd100" .. L["Money"] .. "|r") or U.Colored(e.gi.link))
            r.count:SetText(e.id == "money" and "" or ("×" .. e.it.count))
            r.count:ClearAllPoints()
            r.count:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), r.name:GetWidth()) + 8, 0)
            r.countGlow:ClearAllPoints()
            r.countGlow:SetPoint("TOPLEFT", r.count, "TOPLEFT", -10, 5)
            r.countGlow:SetPoint("BOTTOMRIGHT", r.count, "BOTTOMRIGHT", 10, -5)
            r.avg:ClearAllPoints()
            r.avg:SetPoint("RIGHT", r, "RIGHT", -m.avgR, 0)
            r.avg:SetShown(m.showAvg)
            if m.showAvg then
                local each = (e.id ~= "money" and e.it.count > 0) and e.it.value / e.it.count or 0
                r.avg:SetText(each > 0 and ns.Value.Format(each) or "")
            end
            r.value:ClearAllPoints()
            r.value:SetPoint("RIGHT", r, "RIGHT", -m.valR, 0)
            U.SetValue(r, "i" .. e.id, e.it.value, m)
            U.Track(r, "cp", e.id, e.it.count, r.count, COUNT_COLOR)
            U.Flash(r, "i" .. e.id, e.it.count, now)
            r:Show()
            y = y + ROW_H
        end
        empty:SetText(count == 0 and (q and L["Nothing matches."] or L["Loot something to see it here."]) or "")
    elseif mode == "stats" then
        empty:SetText("")
        y = RenderStats(snap, m)
    elseif mode == "board" then
        empty:SetText("")
        y = U.RenderBoard(snap, m)
    elseif mode == "route" then
        empty:SetText("")
        U.RenderRoute(m)
    end
    countLabel:SetText("")

    U.HideRows(mode ~= "sources" and mode ~= "gather")
    for i = usedHeader + 1, #headerRows do headerRows[i]:Hide() end
    for i = usedDetail + 1, #details do details[i]:Hide(); details[i].openKey = nil; details[i].heightKey = nil end
    U.HidePool(itemRows, A.itemOwners, mode ~= "loot")

    contentH = y
    content:SetHeight(math.max(y, 1))
    maxScroll = math.max(0, y - viewH)
    target = math.min(target, maxScroll)
    if scroll > maxScroll then scroll = maxScroll end
    -- an entry that was just unfolded scrolls into view, row and details
    if A.ensure and A.openSpan and (mode == "sources" or mode == "gather") then
        A.ensure = false
        local top, bottom = A.openSpan[1], A.openSpan[2]
        local want = scroll
        if top < scroll then
            want = top
        elseif bottom > scroll + viewH then
            want = math.min(top, math.ceil((bottom - viewH) / ROW_H) * ROW_H)
        end
        want = math.max(0, math.min(maxScroll, want))
        if want ~= scroll then
            target, scrolling = want, true
            Ease(sf, "scroll", want, 14, ApplyScroll, scroll)
        end
    end
    if not scrolling then
        -- at rest the list sits exactly on a row boundary
        local snapped = math.max(0, math.min(maxScroll, math.floor(scroll / ROW_H + 0.5) * ROW_H))
        scroll, target = snapped, snapped
    end
    sf:SetVerticalScroll(scroll)
    UpdateThumb()
    A.first = false
    A.visited[mode] = true
end

-- hover: icons inside a row take the mouse from it, so the glow follows the cursor
local function Poll()
    local inside = W.TopFrameIs(sf)
    for _, pool in ipairs({ mobRows, itemRows }) do
        for _, r in ipairs(pool) do
            if r:IsShown() then
                local over = inside and r:IsMouseOver() or false
                if over ~= (r.over or false) then
                    r.over = over
                    Ease(r, "hl", over and 1 or 0, 16, ApplyHl)
                end
            end
        end
    end
end

local acc = 0
-- The session card (time and kills) breathes while the session is paused, and the play button
-- glows softly; without animations it only turns amber.
local PAUSE_AMBER = { 0.93, 0.65, 0.37 }
local wasPaused = false
function U.PausePulse()
    local paused = ns.session and ns.session.paused and true or false
    local card = cards[3]
    if U.compact then
        -- (the third card is the experience: it does not show the pause; the pause button pulses, the time in the footer is amber)
        if paused then
            wasPaused = true
            if U.AnimOn() and not W.TopFrameIs(pauseBtn) then
                pauseBtn.glow:SetAlpha(0.15 + 0.5 * (0.5 + 0.5 * math.sin(GetTime() * 2.6)))
            end
        elseif wasPaused then
            wasPaused = false
            pauseBtn.glow:SetAlpha(0)
        end
        return
    end
    if paused then
        wasPaused = true
        card.value:SetTextColor(unpack(PAUSE_AMBER))
        if U.AnimOn() then
            local k = 0.5 + 0.5 * math.sin(GetTime() * 2.6)
            card.value:SetAlpha(0.45 + 0.55 * k)
            card.label:SetAlpha(0.55 + 0.45 * k)
            if not W.TopFrameIs(pauseBtn) then pauseBtn.glow:SetAlpha(0.15 + 0.5 * k) end
        else
            card.value:SetAlpha(1)
            card.label:SetAlpha(1)
        end
    elseif wasPaused then
        wasPaused = false
        card.value:SetTextColor(unpack(C.text))
        card.value:SetAlpha(1)
        card.label:SetAlpha(1)
        pauseBtn.glow:SetAlpha(0)
    end
end

f:SetScript("OnUpdate", function(_, elapsed)
    W.Step(elapsed)
    if f.fcMoving then return end -- (nothing is drawn again while the window is dragged: it follows the mouse without a hitch)
    U.PausePulse()
    acc = acc + elapsed
    if (dirty and acc > 0.05) or acc > 1 then
        acc, dirty = 0, false
        Render()
    end
    Poll()
end)
f:SetScript("OnShow", function() dirty = true end)
-- the journal shows or hides its session numbers depending on this window
f:HookScript("OnShow", function() if ns.UI then ns.UI.Dirty() end end)
f:HookScript("OnHide", function() if ns.UI then ns.UI.Dirty() end end)

local prevRefresh = ns.Refresh
function ns.Refresh()
    dirty = true
    prevRefresh()
end

-- back to the default place and size
function HUD.ResetWindow()
    U.SetCollapsed(false)
    if ns.db then ns.db.hud, ns.db.hudSize, ns.db.hudScale = nil, nil, nil end
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    f:SetSize(DEFAULT_W, DEFAULT_H)
    HUD.Show()
    dirty = true
end

function HUD.Show()
    f:Show()
    if ns.db then ns.db.hudShown = true end
end
function HUD.Hide()
    f:Hide()
    if ns.db then ns.db.hudShown = false end
end
function HUD.Toggle()
    if f:IsShown() then HUD.Hide() else HUD.Show() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    HUD.ApplyFrameStyle()
    W.SetWindowAlpha(f, W.WindowAlpha("hud"))
    if ns.db and ns.db.hudScale then f:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, ns.db.hudScale))) end
    local size = ns.db and ns.db.hudSize
    if size then f:SetSize(math.max(MIN_W, math.min(MAX_W, size[1])), math.max(MIN_H, math.min(MAX_H, size[2]))) end
    local pos = ns.db and ns.db.hud
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    if ns.db and ns.db.hudCollapsed then U.SetCollapsed(true) end
    if not ns.db or ns.db.hudShown ~= false then f:Show() end
end)
end)
