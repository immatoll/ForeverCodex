local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C

-- The settings, in a window of their own: categories on the left, the options of the open one on
-- the right, in a list that scrolls. Every option can have a short description underneath; the
-- button in the header shows or hides all of them.

local S = {}
ns.Settings = S

local WIN_W, WIN_H = 660, 520
local NAV_W = 150
local EDGE, TOP, BOTTOM = 10, 50, 16
local GAP = 6
local STEPS = { 10, 20, 30, 50, 100 }
local CW = WIN_W - EDGE - NAV_W - 8 - EDGE - 10 - 20 -- width of the option list

local f = CreateFrame("Frame", "ForeverCodexSettings", UIParent, W.TEMPLATE)
S.frame = f
f:SetSize(WIN_W, WIN_H)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("MEDIUM")
f:SetToplevel(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop(W.PLATE_BACKDROP)
f:SetBackdropColor(0.055, 0.045, 0.038, 1)
f:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
f:Hide()

-- the same dialog frame and hanging banner as the other windows
local deco = CreateFrame("Frame", nil, f, W.TEMPLATE)
deco:SetPoint("TOPLEFT", -10, 10)
deco:SetPoint("BOTTOMRIGHT", 10, -10)
deco:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32 })
deco:SetFrameLevel(f:GetFrameLevel() + 40)
deco:EnableMouse(false)
local fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
fill:SetAllPoints()
fill:SetColorTexture(0.055, 0.045, 0.038, 1)
local bannerFrame = CreateFrame("Frame", nil, f)
bannerFrame:SetAllPoints(f)
bannerFrame:SetFrameLevel(f:GetFrameLevel() + 45)
local banner = bannerFrame:CreateTexture(nil, "ARTWORK")
banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
banner:SetSize(240, 64)
banner:SetPoint("TOP", deco, "TOP", 0, 12)
local title = bannerFrame:CreateFontString(nil, "OVERLAY")
title:SetFontObject(UI.bannerFontObject or "GameFontNormalLarge")
title:SetJustifyH("CENTER")
title:SetText(L["Settings"])
title:SetTextColor(1, 0.85, 0.4)

function S.ApplyFrameStyle()
    local ornate = (ns.db and ns.db.settings.frameStyle or "ornate") == "ornate"
    local blizz = W.BlizzSkin(f, (ns.db and ns.db.settings.frameStyle or "ornate") == "blizzard", W.ICON.settings, title:GetText(), "settings")
    title:SetAlpha(blizz and 0 or 1) -- (the frame's own title is shown instead)
    deco:SetShown(ornate)
    fill:SetShown(ornate)
    banner:SetShown(ornate)
    title:ClearAllPoints()
    if ornate then
        f:SetBackdrop(nil)
        title:SetPoint("CENTER", banner, "CENTER", 0, 12)
    elseif blizz then
        f:SetBackdrop(nil)
        title:SetPoint("TOP", f, "TOP", 0, 42)
    else
        f:SetBackdrop(W.PLATE_BACKDROP)
        f:SetBackdropColor(0.055, 0.045, 0.038, 1)
        f:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
        title:SetPoint("TOP", f, "TOP", 0, -11)
    end
end

local function SavePosition()
    if not ns.db then return end
    local point, _, rel, x, y = f:GetPoint()
    ns.db.settingsWin = { pos = { point, rel, x, y }, scale = f:GetScale() }
end
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

-- window buttons: the other windows on the left, as everywhere
local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
f.closeBtn = close
close:SetPoint("TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() S.Hide() end)
local opacityBtn = W.NewOpacityButton(f, "settings", f, 20)
opacityBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
f.opacityBtn = opacityBtn
local journalBtn = W.NewIconButton(f, W.ICON.journal, 20)
journalBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
journalBtn:SetTip(L["Journal"], L["Open the full journal."])
journalBtn:SetScript("OnClick", function() ns.UI.Toggle() end)
local sessionBtn = W.NewIconButton(f, W.ICON.session, 20)
sessionBtn:SetPoint("LEFT", journalBtn, "RIGHT", 4, 0)
sessionBtn:SetTip(L["Kills & Loot"], L["Show or hide the small session overlay."])
sessionBtn:SetScript("OnClick", function() if ns.HUD then ns.HUD.Toggle() end end)
local mapBtn = W.NewIconButton(f, W.ICON.map, 20)
mapBtn:SetPoint("LEFT", sessionBtn, "RIGHT", 4, 0)
mapBtn:SetTip(L["Loot map"], L["Open the loot map in a window of its own."])
mapBtn:SetScript("OnClick", function() if ns.MapMain then ns.MapMain.Toggle() end end)

local accountBtn = W.NewIconButton(f, W.ICON.account, 20)
accountBtn:SetPoint("LEFT", mapBtn, "RIGHT", 4, 0)
accountBtn:SetTip(L["Account"], L["All your characters: equipment, bags, professions, mail."])
accountBtn:SetScript("OnClick", function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end)
f.skinRowAll = { journalBtn, sessionBtn, mapBtn, accountBtn }

-- the corner grip scales the whole window (its layout is fixed)
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(f:GetFrameLevel() + 50)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
W.AttachScaleGrip(f, grip, { scaleOnly = true, minScale = 0.6, maxScale = 1.6, gridScale = 0.05,
    saveScale = SavePosition, savePos = SavePosition })

-- the page: header with the title and the switch for descriptions, then the scrolling list ------
local body = W.NewPlate(f, C.page)
body:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + NAV_W + 8, -TOP)
body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, BOTTOM)

local pageTitle = body:CreateFontString(nil, "OVERLAY")
pageTitle:SetFontObject(UI.titleFontObject or "GameFontNormalLarge")
pageTitle:SetPoint("TOPLEFT", 14, -12)
pageTitle:SetTextColor(1, 0.88, 0.5)
local helpBtn = W.NewButton(body, L["Descriptions"], 112, 22)
helpBtn:SetPoint("TOPRIGHT", -12, -10)
helpBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Descriptions"], 1, 0.85, 0.4)
    GameTooltip:AddLine(L["Shows a short explanation under every option."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
helpBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
local rule = body:CreateTexture(nil, "ARTWORK")
rule:SetPoint("TOPLEFT", 12, -38)
rule:SetPoint("TOPRIGHT", -12, -38)
rule:SetHeight(1)
rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

local sf = CreateFrame("ScrollFrame", nil, body)
sf:SetPoint("TOPLEFT", 12, -46)
sf:SetPoint("BOTTOMRIGHT", -20, 10)
sf:EnableMouseWheel(true)
local thumb = body:CreateTexture(nil, "OVERLAY")
thumb:SetWidth(4)
thumb:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
thumb:Hide()

function S.HelpOn() return not (ns.db and ns.db.settings.showHelp == false) end

local pages, order, current = {}, {}, nil

local function UpdateThumb()
    local p = pages[current]
    local viewH = sf:GetHeight()
    if not p or p.height <= viewH + 1 then thumb:Hide() return end
    local range = p.height - viewH
    local h = math.max(24, viewH * viewH / p.height)
    local off = (sf:GetVerticalScroll() / range) * (viewH - h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 12, -off)
    thumb:SetHeight(h)
    thumb:Show()
end

sf:SetScript("OnMouseWheel", function(self, delta)
    if not W.TopFrameIs(f) then return end
    local p = pages[current]
    if not p then return end
    local maxScroll = math.max(0, p.height - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 44)))
    UpdateThumb()
end)

-- rows -----------------------------------------------------------------------------------------
local function NewPage(id, label)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(CW, 10)
    content:Hide()
    local p = { id = id, label = label, content = content, rows = {}, height = 0 }
    pages[id] = p
    order[#order + 1] = id
    return p
end

local function Describe(p, row, text)
    if not text then return end
    row.desc = p.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWidth(CW - 12)
    row.desc:SetTextColor(unpack(C.muted))
    row.desc:SetText(text)
    row.desc:Hide()
end

local function AddRow(p, row, desc)
    Describe(p, row, desc)
    p.rows[#p.rows + 1] = row
    return row
end

local function Toggle(p, label, icon, get, set, desc)
    local t = W.NewToggle(p.content, label, icon, get, function(on) set(on); S.Refresh() end, CW)
    return AddRow(p, { frame = t, h = 32, update = function() t:Refresh() end }, desc)
end

local function Selected(b, on) b:SetSelected(on) end

local function Label(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(C.muted))
    fs:SetText(text)
    return fs
end

-- a choice between a few values, as buttons side by side
local function Choice(p, label, options, get, set, desc)
    local fr = CreateFrame("Frame", nil, p.content)
    fr:SetSize(CW, 48)
    Label(fr, label):SetPoint("TOPLEFT", 0, 0)
    local bw = (CW - (#options - 1) * GAP) / #options
    local btns = {}
    for i, o in ipairs(options) do
        local b = W.NewButton(fr, o[2], bw, 28)
        b:SetPoint("TOPLEFT", (i - 1) * (bw + GAP), -18)
        b:SetScript("OnClick", function() set(o[1]); S.Refresh() end)
        btns[i] = b
    end
    return AddRow(p, { frame = fr, h = 48, update = function()
        local cur = get()
        for i, b in ipairs(btns) do Selected(b, options[i][1] == cur) end
    end }, desc)
end

-- a number with minus and plus
local function Stepper(p, label, text, step, desc)
    local fr = CreateFrame("Frame", nil, p.content)
    fr:SetSize(CW, 48)
    Label(fr, label):SetPoint("TOPLEFT", 0, 0)
    local minus = W.NewButton(fr, "–", 30, 28, "GameFontNormalLarge")
    minus:SetPoint("TOPLEFT", 0, -18)
    local plus = W.NewButton(fr, "+", 30, 28, "GameFontNormalLarge")
    plus:SetPoint("LEFT", minus, "RIGHT", 120, 0)
    local value = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    value:SetWidth(120)
    value:SetJustifyH("CENTER")
    minus:SetScript("OnClick", function() step(-1); S.Refresh() end)
    plus:SetScript("OnClick", function() step(1); S.Refresh() end)
    return AddRow(p, { frame = fr, h = 48, update = function() value:SetText(text()) end }, desc)
end

-- opts.confirm: a second click is needed; opts.gold: stands out; opts.visible(); opts.alpha()
local function Button(p, label, onClick, opts, desc)
    opts = opts or {}
    local b = W.NewButton(p.content, label, CW, 28)
    local armed
    b:SetScript("OnClick", function(self)
        if opts.confirm and not armed then
            armed = true
            self.text:SetText(L["Sure? Click again"])
            self.text:SetTextColor(unpack(C.red))
            C_Timer.After(3, function()
                if armed then
                    armed = nil
                    self.text:SetText(label)
                    self.text:SetTextColor(unpack(C.text))
                end
            end)
            return
        end
        armed = nil
        self.text:SetText(label)
        onClick()
        S.Refresh()
    end)
    if opts.gold then Selected(b, true) end
    return AddRow(p, { frame = b, h = 28, visible = opts.visible,
        update = function() if opts.alpha then b:SetAlpha(opts.alpha()) end end }, desc)
end

-- a line of text; the text can be a function (it is asked again whenever the page is shown)
local function Note(p, text)
    local fs = p.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(CW)
    fs:SetTextColor(unpack(C.muted))
    fs:SetText(type(text) == "string" and text or "")
    return AddRow(p, { frame = fs, h = 14, hfn = function() return fs:GetStringHeight() end,
        update = function() if type(text) == "function" then fs:SetText(text()) end end })
end

local function Heading(p, text)
    local fs = p.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(1, 0.88, 0.5)
    fs:SetText(text)
    return AddRow(p, { frame = fs, h = 16, pre = 12 })
end

local function Layout(p)
    local help = S.HelpOn()
    local y = 0
    for _, row in ipairs(p.rows) do
        local show = not row.visible or row.visible()
        row.frame:SetShown(show)
        if row.desc then row.desc:Hide() end
        if show then
            if row.pre and y > 0 then y = y + row.pre end
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
            y = y + (row.hfn and row.hfn() or row.h)
            if row.desc and help then
                row.desc:ClearAllPoints()
                row.desc:SetPoint("TOPLEFT", p.content, "TOPLEFT", 4, -(y + 3))
                row.desc:Show()
                y = y + 3 + row.desc:GetStringHeight()
            end
            y = y + GAP + 2
        end
    end
    p.height = y
    p.content:SetHeight(math.max(1, y))
end

-- the pages -------------------------------------------------------------------------------------
local function Say(text) print("|cffffd100ForeverCodex:|r " .. text) end

local function ResetMinimapButton()
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.minimapPos = nil
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if icon then pcall(icon.Refresh, icon, "ForeverCodex", ns.db.minimap) end
end

-- sources
do
    local p = NewPage("sources", L["Sources"])
    Note(p, L["Switched-off sources are neither listed nor counted in the value."])
    Heading(p, L["Which sources count"])
    for _, cat in ipairs(ns.CATS) do
        Toggle(p, ns.CAT[cat].label, ns.CAT[cat].icon,
            function() return ns.CatOn(cat) end,
            function(on) ns.db.settings.cats[cat] = on; ns.Refresh() end)
    end
    Heading(p, L["Session list"])
    Toggle(p, L["Group by zone"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return ns.db.settings.groupZone ~= false end,
        function(on) ns.db.settings.groupZone = on; ns.Refresh() end,
        L["Creatures are listed per zone when you change zone during a session."])
    Toggle(p, L["Also by subzone"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return ns.db.settings.groupSub == true end,
        function(on) ns.db.settings.groupSub = on; ns.Refresh() end,
        L["Splits the zone groups further, by subzone."])
end

-- loot & value
do
    local p = NewPage("loot", L["Loot & value"])
    Toggle(p, L["Hide gray items"], "Interface\\Icons\\INV_Misc_Bone_01",
        function() return ns.db.settings.hideGray end,
        function(on) ns.db.settings.hideGray = on; ns.Refresh() end,
        L["Gray items are hidden in the lists."])
    Toggle(p, L["Count looted money"], "Interface\\Icons\\INV_Misc_Coin_01",
        function() return ns.MoneyOn() end,
        function(on) ns.db.settings.countMoney = on; ns.Refresh() end,
        L["Coins from corpses add to the value of a source."])
    Heading(p, L["Prices"])
    Choice(p, L["Price source"], { { "vendor", L["vendor"] }, { "auction", L["auction"] } },
        function() return ns.db.valueSource end,
        function(mode)
            ns.db.settings.priceTouched = true
            ns.db.valueSource = mode
            ns.Value.Reset()
            ns.Refresh()
        end,
        L["What turns loot into value: what a vendor pays, or what the auction house pays where a price is known."])
    Note(p, function()
        local hasAH = Auctionator and Auctionator.API and Auctionator.API.v1 and true
        if ns.AH.Enabled() then
            return hasAH and L["Auction prices come from your own scans; Auctionator fills the gaps."]
                or L["Auction prices come from your own scans; the vendor price fills the gaps."]
        end
        return hasAH and L["Auction prices come from Auctionator."]
            or L["Auction prices need the Auctionator addon; vendor price is used otherwise."]
    end)
    Toggle(p, L["Collect auction prices myself"], "Interface\\Icons\\INV_Misc_Coin_02",
        function() return ns.AH.Enabled() end,
        function(on) ns.db.settings.ownAuction = on; ns.Value.Reset(); ns.Refresh() end,
        L["Scans the auction house when you open it and keeps the lowest prices. They are used before Auctionator."])
    Note(p, function() return ns.AH.Status() end)
    Button(p, L["Scan the auction house now"], function()
        local ok, why = ns.AH.Scan()
        if not ok then Say(why) end
    end, { alpha = function() return (ns.AH.IsOpen() and not ns.AH.Scanning()) and 1 or 0.5 end })
    Heading(p, L["Drop chances"])
    Stepper(p, L["Show drop chances from"], function() return L["%d kills"]:format(ns.Threshold()) end,
        function(dir)
            local cur, idx = ns.Threshold(), 1
            for i, v in ipairs(STEPS) do if v <= cur then idx = i end end
            ns.db.settings.threshold = STEPS[math.max(1, math.min(#STEPS, idx + dir))]
            ns.Refresh()
        end,
        L["Kills needed before a drop chance is a firm figure; with fewer it is an estimate in another colour."])
end

-- display
do
    local p = NewPage("display", L["Display"])
    Toggle(p, L["Click sounds"], nil,
        function() return ns.db.settings.clickSound ~= false end,
        function(on) ns.db.settings.clickSound = on end,
        L["Plays the game's button click when you click one of this addon's buttons."])
    Toggle(p, L["Minimap button"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return not (ns.db.minimap and ns.db.minimap.hide) end,
        function(on)
            ns.db.minimap = ns.db.minimap or {}
            ns.db.minimap.hide = not on
            local icon = LibStub and LibStub("LibDBIcon-1.0", true)
            if icon then
                if on then icon:Show("ForeverCodex") else icon:Hide("ForeverCodex") end
            end
        end, L["The addon's button at the minimap."])
    Toggle(p, L["Animations"], "Interface\\Icons\\Spell_Holy_BorrowedTime",
        function() return ns.db.settings.animations ~= false end,
        function(on) ns.db.settings.animations = on end,
        L["Rows fade in, numbers count up and flash when something changes."])
    Toggle(p, L["Small map window"], "Interface\\Icons\\INV_Misc_Spyglass_02",
        function() return ns.MapWindow and ns.MapWindow.IsShown() end,
        function(on)
            if ns.MapWindow then
                if on then ns.MapWindow.Show() else ns.MapWindow.Hide() end
            end
        end, L["A small map that follows you, with the filter of the loot map."])
    Toggle(p, L["Show the whole map"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return ns.db.settings.mapReveal ~= false end,
        function(on) ns.db.settings.mapReveal = on end,
        L["Draws the whole zone map, also the parts you have not explored yet."])
    local function ApplyStyles()
        UI.ApplyFrameStyle()
        ns.HUD.ApplyFrameStyle()
        ns.MapMain.ApplyFrameStyle()
        S.ApplyFrameStyle()
        if ns.AccountWindow and ns.AccountWindow.ApplyFrameStyle then ns.AccountWindow.ApplyFrameStyle() end
        if ns.ItemInfo then ns.ItemInfo.ApplyFrameStyle() end
        ns.Refresh()
    end
    Choice(p, L["Window style"], { { "ornate", L["ornate"] }, { "plain", L["plain"] }, { "blizzard", L["Blizzard"] } },
        function() return ns.db.settings.frameStyle or "ornate" end,
        function(mode)
            ns.db.settings.frameStyle = mode
            ApplyStyles()
            if ns.HUD and ns.HUD.compact ~= (mode == "blizzard") then print("|cffffd100Forever Codex:|r " .. L["The layout of Kills & Loot follows the window style after a reload."]) end
        end, L["Ornate: the dialog frame with a banner. Plain: a slim gilded frame. Blizzard: the frame of the game's own windows."])
    Choice(p, L["Panel transparency"], { { "1", L["solid"] }, { "0.85", L["slight"] }, { "0.7", L["medium"] }, { "0.55", L["strong"] } },
        function() return tostring(ns.db.settings.panelAlpha or 1) end,
        function(v)
            ns.db.settings.panelAlpha = tonumber(v) or 1
            W.SetPanelAlpha(ns.db.settings.panelAlpha)
        end, L["How see-through the plates, buttons and boxes in the windows are."])
    Choice(p, L["Blizzard background"], { { "standard", L["standard"] }, { "dark", L["dark"] }, { "black", L["very dark"] }, { "talents", L["Talent window"] } },
        function() return ns.db.settings.blizzBg or "standard" end,
        function(mode)
            ns.db.settings.blizzBg = mode
            ApplyStyles()
        end, L["How dark the background of the Blizzard window style is."])
    Choice(p, L["Language"], { { "auto", L["Auto (client)"] }, { "deDE", "Deutsch" }, { "enUS", "English" } },
        function() return ns.LangSetting or "auto" end,
        function(value) ns.SetLanguage(value); ns.Refresh() end,
        L["Applied after a reload."])
    -- only offered when the chosen language differs from the one in use
    Button(p, L["Reload now"], function() ReloadUI() end,
        { visible = function() return ns.ResolveLanguage(ns.LangSetting or "auto") ~= ns.Lang end })
end

-- notifications
do
    local p = NewPage("notify", L["Notifications"])
    Note(p, L["A short notice at the top of the screen. Choose what you want to be told about."])
    Toggle(p, L["Sound"], "Interface\\Icons\\INV_Misc_Bell_01",
        function() return ns.db.settings.notifySound ~= false end,
        function(on) ns.db.settings.notifySound = on end,
        L["A sound with every notice."])
    Heading(p, L["Tell me about"])
    for _, kind in ipairs(ns.NOTIFY_KINDS) do
        Toggle(p, kind.label, "Interface\\Icons\\INV_Misc_Note_01",
            function() return ns.NotifyOn(kind.id) end,
            function(on)
                ns.db.settings.notify = ns.db.settings.notify or {}
                ns.db.settings.notify[kind.id] = on
            end)
    end
end

-- tooltips
do
    local p = NewPage("tooltip", L["Tooltips"])
    Note(p, L["Added to the game's tooltips. Every line can be switched on and off."])
    local DESC = {
        master = L["Turns every line below on or off at once."],
        shiftOnly = L["The extra lines only show when Shift is held as the tooltip appears."],
        header = L["A line with the addon's name above the extra lines."],
        itemVendor = L["What a vendor pays for the item."],
        itemAuction = L["The auction price, from your own scans or from Auctionator."],
        itemStack = L["Prices are for one piece; hold Shift to see them for the whole stack."],
        itemAge = L["How long ago your own scan saw the price."],
        itemDiff = L["How much more (or less) the auction price is than the vendor price, in percent."],
        itemOwned = L["How many you looted this session and in total, and what that is worth."],
        itemSources = L["The creatures that drop the item most often, with their chance."],
        itemAlts = L["Which of your characters have the item, and where."],
        itemTrend = L["The auction price and the amount on offer of the last week as small bars, from your own scans."],
        itemDisenchant = L["What disenchanting a green, blue or purple weapon or armor gives: the materials with chance and amount, what they are worth and how that compares with selling the item. The data comes from the addon DisenchantBuddy."],
        itemCraft = L["The professions that use the item as a material or make it (as pictures, with the number of recipes), and which of your characters need it, know how to make it or could still learn it."],
        mobKills = L["Kills this session and in total."],
        mobProgress = L["How many kills you have towards reliable drop chances."],
        mobTop = L["The three drops worth the most per kill, with chance and price."],
        mobAvg = L["What a kill brings on average."],
    }
    local HEAD = { general = L["General"], item = L["On items"], mob = L["On creatures"] }
    local lastGroup
    for _, o in ipairs(ns.TIP_OPTIONS) do
        local id, label, _, group = o[1], o[2], o[3], o[4]
        if group ~= lastGroup then Heading(p, HEAD[group]); lastGroup = group end
        Toggle(p, label, nil, function() return ns.TipOn(id) end, function(on) ns.TipSet(id, on) end, DESC[id])
    end
end

-- account
do
    local p = NewPage("account", L["Account"])
    Note(p, L["Your characters, kept in the saved variables so that one window shows all of them."])
    Toggle(p, L["Remember my characters"], W.ICON.account,
        function() return ns.Acc.Enabled() end,
        function(on) ns.db.settings.accTrack = on end,
        L["Reads level, equipment, bags, professions and more of every character you log in with. Nothing is read while this is off."])
    Toggle(p, L["Show the surname"], nil,
        function() return ns.db.settings.accSurname ~= false end,
        function(on) ns.db.settings.accSurname = on; ns.Refresh() end,
        L["Adds the second part of a character's name (a surname or title the game gives it) in the account window."])
    Button(p, L["Open the account window"], function() ns.AccountWindow.Show() end)
    Heading(p, L["What is read, and when"])
    Note(p, L["The character, equipment, bags and professions: when you log in and while you play."])
    Note(p, L["The bank: when you open it. The mail: at a mailbox. Recipes: when you open a profession window."])
    Note(p, L["Auctions: when you visit the auction house. Time played: once per login."])
end

-- windows & data
do
    local p = NewPage("windows", L["Windows & data"])
    Heading(p, L["Windows"])
    Note(p, L["Put a window back to its default position and size."])
    local function Reset(label, action, gold)
        Button(p, label, function() action(); Say(L["Window reset."]); ns.Refresh() end, { gold = gold })
    end
    Reset(L["Reset session window"], function() ns.HUD.ResetWindow() end)
    Reset(L["Reset journal"], function() UI.ResetWindow() end)
    Reset(L["Reset map window"], function() ns.MapMain.ResetWindow() end)
    Reset(L["Reset settings window"], function() S.ResetWindow() end)
    Reset(L["Reset account window"], function() ns.AccountWindow.ResetWindow() end)
    Reset(L["Reset navigation arrow"], function() if ns.Routes then ns.Routes.ResetNav() end end)
    Reset(L["Reset minimap button"], ResetMinimapButton)
    Reset(L["Reset all windows"], function()
        ns.HUD.ResetWindow()
        UI.ResetWindow()
        ns.MapMain.ResetWindow()
        S.ResetWindow()
        ns.AccountWindow.ResetWindow()
        if ns.Routes then ns.Routes.ResetNav() end
        ResetMinimapButton()
    end, true)
    Heading(p, L["Data"])
    Toggle(p, L["Keep session after reload"], W.ICON.session,
        function() return ns.db.settings.keepSession end,
        function(on) ns.db.settings.keepSession = on end,
        L["The running session survives a reload or relog and goes on where it stopped."])
    Button(p, L["End session"], function()
        ns.EndSession()
        Say(L["Session ended."])
    end, nil, L["Saves the session to the history; the next loot starts a new one."])
    Button(p, L["Delete all data"], function()
        ns.ResetAll()
        Say(L["All data deleted."])
    end, { confirm = true }, L["Deletes every source, item and history entry. This cannot be undone."])
end

-- the category list -----------------------------------------------------------------------------
local navButtons = {}
for i, id in ipairs(order) do
    local b = W.NewButton(f, pages[id].label, NAV_W, 32)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -TOP - (i - 1) * 38)
    b.id = id
    b:SetScript("OnClick", function() S.Select(id) end)
    navButtons[i] = b
end

function S.Refresh()
    local p = pages[current]
    if not p then return end
    for _, b in ipairs(navButtons) do Selected(b, b.id == current) end
    Selected(helpBtn, S.HelpOn())
    for _, row in ipairs(p.rows) do
        if row.update then row.update() end
    end
    Layout(p)
    local maxScroll = math.max(0, p.height - sf:GetHeight())
    if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
    UpdateThumb()
end

function S.Select(id)
    if not pages[id] then id = order[1] end
    if current and pages[current] then pages[current].content:Hide() end
    current = id
    if ns.db then ns.db.settingsPage = id end
    local p = pages[id]
    p.content:Show()
    sf:SetScrollChild(p.content)
    sf:SetVerticalScroll(0)
    pageTitle:SetText(p.label)
    S.Refresh()
end

helpBtn:SetScript("OnClick", function()
    ns.db.settings.showHelp = not S.HelpOn()
    S.Refresh()
end)

local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    W.Step(dt)
    acc = acc + dt
    if acc > 0.5 then
        acc = 0
        S.Refresh()
    end
end)
f:SetScript("OnShow", function()
    if not current then S.Select(ns.db and ns.db.settingsPage or order[1]) else S.Refresh() end
end)

function S.Show(page)
    f:Show()
    if page then S.Select(page) end
end
function S.Hide() f:Hide() end
function S.Toggle()
    if f:IsShown() then S.Hide() else S.Show() end
end

function S.ResetWindow()
    if ns.db then ns.db.settingsWin = nil end
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    S.ApplyFrameStyle()
    local saved = ns.db and ns.db.settingsWin
    if saved and saved.scale then f:SetScale(math.max(0.6, math.min(1.6, saved.scale))) end
    if saved and saved.pos then
        f:ClearAllPoints()
        f:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
    end
    W.SetWindowAlpha(f, W.WindowAlpha("settings"))
end)

SLASH_FOREVERCODEXSETTINGS1 = "/fcsettings"
SLASH_FOREVERCODEXSETTINGS2 = "/fklsettings"
SlashCmdList.FOREVERCODEXSETTINGS = function() S.Toggle() end
