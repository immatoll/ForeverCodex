local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C

-- The settings, in a window of their own: the pages in groups on the left (with a count of the options
-- that are not at their standard), the options of the open page on the right, in cards, in a list that
-- scrolls. A search over all options, "reset this page", and a short description under every option
-- (the button in the header shows or hides all of them).

local S = {}
ns.Settings = S

local WIN_W, WIN_H = 980, 600
local NAV_W = 176
local EDGE, TOP, BOTTOM = 10, 50, 16
local GAP = 6
local STEPS = { 10, 20, 30, 50, 100 }
local CW_FULL = WIN_W - EDGE - NAV_W - 8 - EDGE - 32 - 24 - 4 -- width of the options in a card (the card is 24 wider)
local SIDE_W = 350 -- the room at the right of the pages that have a preview
local CW = CW_FULL -- (the width the pages are built with; the pages with a preview are built narrower)

local f = CreateFrame("Frame", "ForeverCompanionSettings", UIParent, W.TEMPLATE)
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
    local ornate = false
    local blizz = W.BlizzSkin(f, true, W.ICON.settings, title:GetText(), "settings")
    title:SetAlpha(blizz and 0 or 1) -- (the frame's own title is shown instead)
    if S.Arrange then S.Arrange(blizz and true or false) end
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
body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, BOTTOM)

local pageTitle = body:CreateFontString(nil, "OVERLAY")
pageTitle:SetFontObject(UI.titleFontObject or "GameFontNormalLarge")
pageTitle:SetPoint("TOPLEFT", 14, -12)
pageTitle:SetTextColor(1, 0.88, 0.5)
local resetBtn = W.NewButton(body, L["Reset this page"], 150, 22)
resetBtn:SetPoint("TOPRIGHT", -12, -10)
local searchBox = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
searchBox:SetSize(190, 20)
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(40)
searchBox:SetFontObject("GameFontHighlightSmall")
local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 2, 0)
searchHint:SetText(L["Search options"])
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

function S.HelpOn() return false end -- (the descriptions are shown when the mouse is over an option)

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
-- A page is a column of cards (a plate with a title and the options that belong together). The rows are made in order: a heading starts a card.
local function NewPage(id, label, opts)
    opts = opts or {}
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(CW + 24, 10)
    content:Hide()
    local p = { id = id, label = label, content = content, rows = {}, height = 0, cards = {}, cw = CW,
        cols = opts.cols, preview = opts.preview, side = opts.preview and SIDE_W or 0 }
    pages[id] = p
    order[#order + 1] = id
    return p
end

local function Describe(p, row, text)
    if not text then return end
    row.descText = text
    -- (in a frame of its own: a text cannot change its parent, and the search moves the options to another page)
    row.descBox = CreateFrame("Frame", nil, p.content)
    row.descBox:SetSize(CW - 12, 1)
    row.desc = row.descBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetPoint("TOPLEFT")
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWidth(CW - 12)
    row.desc:SetTextColor(unpack(C.muted))
    row.desc:SetText(text)
    row.descBox:Hide()
end

-- the description of an option appears as a tooltip while the mouse is over it (over the frame, or the buttons in it)
local function HoverTip(row)
    local function Hook(fr)
        if not (fr.HookScript and fr.EnableMouse) then return end
        fr:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(row.label or "", 1, 0.85, 0.4)
            GameTooltip:AddLine(row.descText, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        fr:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local fr = row.frame
    if fr:GetObjectType() == "FontString" then return end
    if fr:GetObjectType() == "Frame" then fr:EnableMouse(true) end
    Hook(fr)
    for _, ch in ipairs({ fr:GetChildren() }) do Hook(ch) end
end

local function AddRow(p, row, desc)
    Describe(p, row, desc)
    if desc and row.frame then HoverTip(row) end
    row.page = p
    p.rows[#p.rows + 1] = row
    return row
end

-- def: the standard value of the option (for the count of what was changed and for "reset this page")
local function Toggle(p, label, icon, get, set, desc, def)
    local half = p.cols == 2
    local w = half and math.floor((CW - GAP * 2) / 2) or CW
    local t = W.NewToggle(p.content, label, icon, get, function(on) set(on); S.Refresh() end, w)
    local row = AddRow(p, { frame = t, h = 32, label = label, update = function() t:Refresh() end, def = def, cur = get,
        half = half, w = w, reset = def ~= nil and function() set(def) end or nil }, desc)
    if half and row.desc then
        row.desc:SetWidth(w - 12)
        row.descBox:SetSize(w - 12, 1)
    end
    return row
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
local function Choice(p, label, options, get, set, desc, def)
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
    return AddRow(p, { frame = fr, h = 48, label = label, def = def, cur = get, reset = def ~= nil and function() set(def) end or nil,
        update = function()
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
    return AddRow(p, { frame = fr, h = 48, label = label, update = function() value:SetText(text()) end }, desc)
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
    return AddRow(p, { frame = b, h = 28, label = label, visible = opts.visible,
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
    return AddRow(p, { frame = fs, h = 16, heading = true })
end

local PADX = 12
-- a card is drawn with textures of the page itself: they lie under everything that is a frame on the page, whatever the levels are
local function CardOf(p, i)
    local c = p.cards[i]
    if not c then
        local parent = p.content
        local gd = C.goldDim
        local bg = parent:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetColorTexture(0.03, 0.025, 0.02, 0.6)
        local edges = {}
        for k = 1, 4 do
            edges[k] = parent:CreateTexture(nil, "BACKGROUND", nil, -5)
            edges[k]:SetColorTexture(gd[1], gd[2], gd[3], 0.7)
        end
        c = { bg = bg, edges = edges }
        function c:Place(top, w, h)
            self.bg:ClearAllPoints()
            self.bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
            self.bg:SetSize(w, h)
            local e = self.edges
            e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", self.bg); e[1]:SetPoint("TOPRIGHT", self.bg); e[1]:SetHeight(1)
            e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", self.bg); e[2]:SetPoint("BOTTOMRIGHT", self.bg); e[2]:SetHeight(1)
            e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", self.bg); e[3]:SetPoint("BOTTOMLEFT", self.bg); e[3]:SetWidth(1)
            e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", self.bg); e[4]:SetPoint("BOTTOMRIGHT", self.bg); e[4]:SetWidth(1)
            self.bg:Show()
            for _, t in ipairs(e) do t:Show() end
        end
        function c:Hide()
            self.bg:Hide()
            for _, t in ipairs(self.edges) do t:Hide() end
        end
        p.cards[i] = c
    end
    return c
end

-- the rows of a page in cards: a heading begins a card; what comes before the first heading is in a card without a title
local function Layout(p)
    local help = S.HelpOn()
    local cw = p.cw or CW
    local y, top, n = 0, nil, 0
    local function Close(bottom)
        if top then
            p.cards[n]:Place(top, cw + 24, math.max(10, bottom - top))
        end
    end
    local function Open()
        n = n + 1
        CardOf(p, n)
        top = y
        y = y + 10
    end
    local function Height(row)
        local h = row.hfn and row.hfn() or row.h
        if row.desc and help then h = h + 3 + row.desc:GetStringHeight() end
        return h
    end
    local function Put(row, x, yy)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -yy)
        if row.desc and help then
            row.descBox:ClearAllPoints()
            row.descBox:SetPoint("TOPLEFT", p.content, "TOPLEFT", x + 4, -(yy + (row.hfn and row.hfn() or row.h) + 3))
            row.descBox:Show()
        end
    end
    local pending -- a row of the left column that waits for its neighbour
    local function Flush()
        if pending then
            y = y + Height(pending) + GAP + 2
            pending = nil
        end
    end
    for _, row in ipairs(p.rows) do
        local show = not row.visible or row.visible()
        row.frame:SetShown(show)
        if row.descBox then row.descBox:Hide() end
        if show then
            if row.heading then
                Flush()
                if top then Close(y + 2); y = y + 12 end
                Open()
            elseif not top then
                Open()
            end
            if row.half then
                if pending then
                    Put(row, PADX + math.floor(cw / 2) + GAP, y)
                    y = y + math.max(Height(pending), Height(row)) + GAP + 2
                    pending = nil
                else
                    Put(row, PADX, y)
                    pending = row
                end
            else
                Flush()
                Put(row, PADX, y)
                y = y + Height(row) + GAP + (row.heading and 4 or 2)
            end
        end
    end
    Flush()
    Close(y + 4)
    for i = n + 1, #p.cards do p.cards[i]:Hide() end
    p.height = y + 8
    p.content:SetHeight(math.max(1, p.height))
end

-- the pages -------------------------------------------------------------------------------------
local function Say(text) print("|cffffd100ForeverCompanion:|r " .. text) end

local function ResetMinimapButton()
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.minimapPos = nil
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if icon then pcall(icon.Refresh, icon, "ForeverCompanion", ns.db.minimap) end
end

-- General -----------------------------------------------------------------------------------------
do
    local p = NewPage("display", L["Basics"], { cols = 2 })
    Heading(p, L["Behaviour"])
    Toggle(p, L["Click sounds"], nil,
        function() return ns.db.settings.clickSound ~= false end,
        function(on) ns.db.settings.clickSound = on end,
        L["Plays the game's button click when you click one of this addon's buttons."], true)
    Toggle(p, L["Animations"], "Interface\\Icons\\Spell_Holy_BorrowedTime",
        function() return ns.db.settings.animations ~= false end,
        function(on) ns.db.settings.animations = on end,
        L["Rows fade in, numbers count up and flash when something changes."], true)
    Toggle(p, L["Minimap button"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return not (ns.db.minimap and ns.db.minimap.hide) end,
        function(on)
            ns.db.minimap = ns.db.minimap or {}
            ns.db.minimap.hide = not on
            local icon = LibStub and LibStub("LibDBIcon-1.0", true)
            if icon then
                if on then icon:Show("ForeverCompanion") else icon:Hide("ForeverCompanion") end
            end
        end, L["The addon's button at the minimap."], true)
    Heading(p, L["Language"])
    Choice(p, L["Language"], { { "auto", L["Auto (client)"] }, { "deDE", "Deutsch" }, { "enUS", "English" } },
        function() return ns.LangSetting or "auto" end,
        function(value) ns.SetLanguage(value); ns.Refresh() end,
        L["Applied after a reload."], "auto")
    -- only offered when the chosen language differs from the one in use
    Button(p, L["Reload now"], function() ReloadUI() end,
        { visible = function() return ns.ResolveLanguage(ns.LangSetting or "auto") ~= ns.Lang end })
end

do
    local p = NewPage("style", L["Appearance"])
    local function ApplyStyles()
        UI.ApplyFrameStyle()
        ns.HUD.ApplyFrameStyle()
        ns.MapMain.ApplyFrameStyle()
        S.ApplyFrameStyle()
        if ns.AccountWindow and ns.AccountWindow.ApplyFrameStyle then ns.AccountWindow.ApplyFrameStyle() end
        if ns.ItemInfo then ns.ItemInfo.ApplyFrameStyle() end
        if ns.AuctionWindow then ns.AuctionWindow.ApplyFrameStyle() end
        ns.Refresh()
    end
    Heading(p, L["Background"])
    Choice(p, L["Blizzard background"], { { "standard", L["standard"] }, { "dark", L["dark"] }, { "black", L["very dark"] }, { "talents", L["Talent window"] } },
        function() return ns.db.settings.blizzBg or "standard" end,
        function(mode)
            ns.db.settings.blizzBg = mode
            ApplyStyles()
        end, L["How dark the background of the Blizzard window style is."], "standard")
    Heading(p, L["Transparency"])
    Choice(p, L["Panel transparency"], { { "1", L["solid"] }, { "0.85", L["slight"] }, { "0.7", L["medium"] }, { "0.55", L["strong"] } },
        function() return tostring(ns.db.settings.panelAlpha or 1) end,
        function(v)
            ns.db.settings.panelAlpha = tonumber(v) or 1
            W.SetPanelAlpha(ns.db.settings.panelAlpha)
        end, L["How see-through the plates, buttons and boxes in the windows are."], "1")
end

do
    local p = NewPage("map", L["Map"], { cols = 2 })
    Heading(p, L["Map"])
    Toggle(p, L["Small map window"], "Interface\\Icons\\INV_Misc_Spyglass_02",
        function() return ns.MapWindow and ns.MapWindow.IsShown() end,
        function(on)
            if ns.MapWindow then
                if on then ns.MapWindow.Show() else ns.MapWindow.Hide() end
            end
        end, L["A small map that follows you, with the filter of the loot map."])
    Heading(p, L["In the world"])
    Toggle(p, L["Sparkle at herbs and ore"], "Interface\\Icons\\INV_Misc_Gem_Variety_02",
        function() return ns.db.settings.worldGlow == true end,
        function(on)
            ns.db.settings.worldGlow = on
            local ok, err = true, nil
            if ns.WorldGlow then ok, err = pcall(ns.WorldGlow.Refresh, on) end
            Say(L["Sparkle at herbs and ore"] .. ": " .. (on and L["on"] or L["off"]) .. (ok and "" or (" - " .. tostring(err))))
        end,
        L["Sparkles over the plant or vein near you. It uses the interaction target of the game (the object nearest in front of you, up to about 15 yards, the limit of the game). It needs the game's option \"Enable Interact Key\" (and the interaction icons on objects): switching this on sets both for you, switching it off puts everything back. Do not use it together with another addon that does the same."])
    local glowOn = function() return ns.db.settings.worldGlow == true end
    Toggle(p, L["Only for my professions"], "Interface\\Icons\\Trade_Herbalism",
        function() return ns.db.settings.worldGlowOnlyMine ~= false end,
        function(on) ns.db.settings.worldGlowOnlyMine = on; if ns.WorldGlow then ns.WorldGlow.Refresh() end end,
        L["Herbs only sparkle with Herbalism, veins with Mining, animals with Skinning."], true)
    Toggle(p, L["Skinnable animals too"], "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
        function() return ns.db.settings.worldGlowSkin ~= false end,
        function(on) ns.db.settings.worldGlowSkin = on; if ns.WorldGlow then ns.WorldGlow.Refresh() end end,
        L["Dead animals that you can skin sparkle too, until they are skinned (with Skinning)."], true)
    Toggle(p, L["Hide the game's nameplate"], "Interface\\Icons\\INV_Misc_Spyglass_03",
        function() return ns.db.settings.worldGlowHidePlate ~= false end,
        function(on)
            ns.db.settings.worldGlowHidePlate = on
            if ns.WorldGlow then ns.WorldGlow.Refresh() end
        end,
        L["The game shows a nameplate (name, health bar) over the object that sparkles. With this on it is made see-through; the sparkle stays."], true)
    Choice(p, L["Height"], { { "25", L["high"] }, { "45", L["normal"] }, { "65", L["low"] }, { "90", L["lower"] } },
        function() return tostring(ns.db.settings.worldGlowDrop or 45) end,
        function(v) ns.db.settings.worldGlowDrop = tonumber(v) or 45; if ns.WorldGlow then ns.WorldGlow.Refresh() end end,
        L["Where the effect sits against the game's nameplate of the object: higher or lower on the plant."], "45")
    for k = 0, 3 do p.rows[#p.rows - k].enabled = glowOn end -- (the four options above only matter while the sparkle is on)
    Heading(p, L["Map"])
    Toggle(p, L["Show the whole map"], "Interface\\Icons\\INV_Misc_Map_01",
        function() return ns.db.settings.mapReveal ~= false end,
        function(on) ns.db.settings.mapReveal = on end,
        L["Draws the whole zone map, also the parts you have not explored yet."], true)
end

-- Loot -------------------------------------------------------------------------------------------
do
    local p = NewPage("sources", L["Sources"], { cols = 2 })
    Note(p, L["Switched-off sources are neither listed nor counted in the value."])
    Heading(p, L["Which sources count"])
    for _, cat in ipairs(ns.CATS) do
        Toggle(p, ns.CAT[cat].label, ns.CAT[cat].icon,
            function() return ns.CatOn(cat) end,
            function(on) ns.db.settings.cats[cat] = on; ns.Refresh() end, nil, true)
    end
end

do
    local p = NewPage("session", L["Kills & Loot"])
    Heading(p, L["Window"])
    Toggle(p, L["Open the session window by itself"], "Interface\\Icons\\INV_Misc_Bag_10",
        function() return ns.db.settings.autoOpenSession ~= false end,
        function(on) ns.db.settings.autoOpenSession = on end,
        L["The window opens when you loot or gather something, if it is closed."], true)
    Heading(p, L["Recording"])
    Toggle(p, L["Not in dungeons and raids"], "Interface\\Icons\\INV_Misc_Key_03",
        function() return ns.db.settings.pauseInstances ~= false end,
        function(on) ns.db.settings.pauseInstances = on end,
        L["Inside dungeons and raids the game hides the names of creatures from addons, so their loot cannot be assigned. With this on, nothing is recorded there."], true)
    Toggle(p, L["Not while in a group"], "Interface\\Icons\\INV_Misc_GroupLooking",
        function() return ns.db.settings.pauseGroup ~= false end,
        function(on) ns.db.settings.pauseGroup = on end,
        L["In a group the game may hide the names of creatures too. With this on, nothing is recorded while you are grouped."], true)
    Heading(p, L["Session"])
    Toggle(p, L["Keep session after reload"], W.ICON.session,
        function() return ns.db.settings.keepSession end,
        function(on) ns.db.settings.keepSession = on end,
        L["The running session survives a reload or relog and goes on where it stopped."])
    Button(p, L["End session"], function()
        ns.EndSession()
        Say(L["Session ended."])
    end, nil, L["Saves the session to the history; the next loot starts a new one."])
end

do
    local p = NewPage("value", L["Loot & value"])
    Heading(p, L["Loot"])
    Toggle(p, L["Hide gray items"], "Interface\\Icons\\INV_Misc_Bone_01",
        function() return ns.db.settings.hideGray end,
        function(on) ns.db.settings.hideGray = on; ns.Refresh() end,
        L["Gray items are hidden in the lists."])
    Toggle(p, L["Count looted money"], "Interface\\Icons\\INV_Misc_Coin_01",
        function() return ns.MoneyOn() end,
        function(on) ns.db.settings.countMoney = on; ns.Refresh() end,
        L["Coins from corpses add to the value of a source."], true)
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

do
    local p = NewPage("notify", L["Notifications"], { cols = 2 })
    Note(p, L["A short notice at the top of the screen. Choose what you want to be told about."])
    Toggle(p, L["Sound"], "Interface\\Icons\\INV_Misc_Bell_01",
        function() return ns.db.settings.notifySound ~= false end,
        function(on) ns.db.settings.notifySound = on end,
        L["A sound with every notice."], true)
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

-- a tooltip with made-up data: at the right of the pages of the tooltip options, it follows the options at once
local pv = W.NewPlate(body, C.inset)
pv:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -46)
pv:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
pv:SetWidth(SIDE_W - 28)
pv:Hide()
local pvTitle = pv:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pvTitle:SetPoint("TOPLEFT", 12, -10)
pvTitle:SetTextColor(1, 0.88, 0.5)
pvTitle:SetText(L["Preview"])
local pvTip = CreateFrame("GameTooltip", "ForeverCompanionTipPreview", pv, "GameTooltipTemplate")
pvTip:SetFrameStrata(pv:GetFrameStrata())
pvTip:SetFrameLevel(pv:GetFrameLevel() + 3)
pvTip:EnableMouse(false)
local pvSig
pv:HookScript("OnHide", function() pvSig = nil end)
-- The scale of the tooltip is fixed for each kind: once, with every option on (the largest it can get, unseen), it is worked out how
-- much the tooltip has to be made smaller to fit the field. After that lines only come and go.
local pvScale, pvMeasuring = {}, false
local function Place()
    pvTip:SetOwner(pv, "ANCHOR_NONE")
    pvTip:ClearAllPoints()
    pvTip:SetPoint("TOP", pv, "TOP", 0, -36)
end
local function UpdatePreview(p)
    local kind = p and p.preview
    pv:SetShown(kind ~= nil)
    if not kind or pvMeasuring then return end
    if not pvScale[kind] then
        pvMeasuring = true
        pvTip:SetAlpha(0)
        pvTip:SetScale(1)
        Place()
        ns.TipPreview(pvTip, kind, true)
        C_Timer.After(0, function()
            local h, w = pvTip:GetHeight(), pvTip:GetWidth()
            if h and h > 0 and w and w > 0 and pv:GetHeight() > 60 then
                pvScale[kind] = math.max(0.5, math.min(1, (pv:GetHeight() - 46) / h, (pv:GetWidth() - 16) / w))
            end
            pvTip:SetAlpha(1)
            pvMeasuring = false
            pvSig = nil
            if current and pages[current] then UpdatePreview(pages[current]) end
        end)
        return
    end
    local parts = { kind }
    for _, o in ipairs(ns.TIP_OPTIONS) do parts[#parts + 1] = tostring(ns.TipOn(o[1])) end
    local key = table.concat(parts, ",")
    if key == pvSig then return end
    pvSig = key
    pvTip:SetScale(pvScale[kind])
    Place()
    ns.TipPreview(pvTip, kind)
end
S.UpdatePreview = UpdatePreview

do
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
        nodeVisited = L["Whether this spot has been gathered before and how often, how many spots of the resource are known, and when it was last gathered."],
        nodeGathered = L["How often the resource was gathered, and what a gathering brings on average."],
        nodeDrops = L["The three things it gives that are worth the most, with chance and price."],
    }
    local HEAD = { general = L["General"], item = L["On items"], mob = L["On creatures"], node = L["On resources"] }
    -- one page for every group of the options, each with the example tooltip above
    for _, def in ipairs({ { "tipgen", L["General"], "general", "item" }, { "tipitem", L["Items"], "item", "item" },
        { "tipmob", L["Creatures"], "mob", "mob" }, { "tipnode", L["Resources"], "node", "node" } }) do
        CW = CW_FULL - SIDE_W -- (the page has the preview at its right)
        local p = NewPage(def[1], def[2], { preview = def[4] })
        if def[3] == "general" then
            Note(p, L["The preview shows an item with made-up data. The lines of the Shift option are always shown here."])
        end
        -- the options of the items in cards like the blocks of the tooltip
        local SUB = { itemVendor = L["Prices"], itemTrend = L["Auction trend"], itemOwned = L["Your loot"], itemSources = L["Drops from"],
            itemDisenchant = L["Disenchanting"], itemCraft = L["Crafting"], itemAlts = L["Your characters"] }
        if def[3] ~= "item" then Heading(p, HEAD[def[3]]) end
        for _, o in ipairs(ns.TIP_OPTIONS) do
            if o[4] == def[3] then
                local id = o[1]
                if def[3] == "item" and SUB[id] then Heading(p, SUB[id]) end
                Toggle(p, o[2], nil, function() return ns.TipOn(id) end, function(on) ns.TipSet(id, on) end, DESC[id], o[3])
            end
        end
        CW = CW_FULL
    end
end

-- Auction house ----------------------------------------------------------------------------------
do
    local p = NewPage("ah", L["Tab & scan"], { cols = 2 })
    Heading(p, L["Auction house tab"])
    Toggle(p, L["Open with the Companion tab"], "Interface\\Icons\\INV_Misc_Book_09",
        function() return ns.db.settings.ahOpenCodex ~= false end,
        function(on) ns.db.settings.ahOpenCodex = on end,
        L["The Companion tab is the first one shown when you open the auction house."], true)
    Heading(p, L["Scan"])
    Toggle(p, L["Collect auction prices myself"], "Interface\\Icons\\INV_Misc_Coin_02",
        function() return ns.AH.Enabled() end,
        function(on) ns.db.settings.ownAuction = on; ns.Value.Reset(); ns.Refresh() end,
        L["Scans the auction house when you open it and keeps the lowest prices. They are used before Auctionator."])
    Note(p, function() return ns.AH.Status() end)
    Button(p, L["Scan the auction house now"], function()
        local ok, why = ns.AH.Scan()
        if not ok then Say(why) end
    end, { alpha = function() return (ns.AH.IsOpen() and not ns.AH.Scanning()) and 1 or 0.5 end })
end

-- Bags ---------------------------------------------------------------------------------------------
-- the rules of the items: one line each, with a button to take it away
local function RuleListRow(p)
    local fr = CreateFrame("Frame", nil, p.content)
    fr:SetSize(CW, 24)
    fr.lines = {}
    fr.height = 24
    fr.none = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fr.none:SetPoint("TOPLEFT", 0, -4)
    fr.none:SetTextColor(unpack(C.muted))
    local function Line(i)
        local ln = fr.lines[i]
        if ln then return ln end
        ln = CreateFrame("Frame", nil, fr)
        ln:SetSize(CW, 24)
        ln.icon = ln:CreateTexture(nil, "ARTWORK")
        ln.icon:SetSize(20, 20)
        ln.icon:SetPoint("LEFT", 0, 0)
        ln.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ln.name = ln:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ln.name:SetPoint("LEFT", ln.icon, "RIGHT", 8, 0)
        ln.name:SetWidth(CW - 250)
        ln.name:SetJustifyH("LEFT")
        ln.name:SetWordWrap(false)
        ln.kind = ln:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ln.kind:SetPoint("LEFT", ln.name, "RIGHT", 8, 0)
        ln.kind:SetWidth(170)
        ln.kind:SetJustifyH("LEFT")
        ln.kind:SetWordWrap(false)
        ln.del = W.NewButton(ln, "×", 22, 20, "GameFontNormal")
        ln.del:SetPoint("RIGHT", 0, 0)
        ln.del:SetScript("OnClick", function() if ln.id and ns.Manager then ns.Manager.SetRule(ln.id, nil) end end)
        fr.lines[i] = ln
        return ln
    end
    return AddRow(p, { frame = fr, h = 24, hfn = function() return fr.height end, noSearch = true, label = L["Rules"],
        update = function()
            local list = ns.Manager and ns.Manager.RuleList() or {}
            local shown = math.min(#list, 40)
            for i = 1, shown do
                local e = list[i]
                local ln = Line(i)
                ln:ClearAllPoints()
                ln:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, -(i - 1) * 24)
                ln.id = e.id
                ln.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                ln.name:SetText(e.name)
                local k = ns.Manager.KIND[e.kind]
                ln.kind:SetText((k and k.label or e.kind) .. (e.target and (": " .. e.target) or ""))
                if k then ln.kind:SetTextColor(k.color[1], k.color[2], k.color[3]) end
                ln:Show()
            end
            for i = shown + 1, #fr.lines do fr.lines[i]:Hide() end
            if #list == 0 then fr.none:SetText(L["No rules yet. Click an item in the bags manager to set one."]) else fr.none:SetText("") end
            if #list > shown then fr.none:SetText((L["... and %d more"]):format(#list - shown)); fr.none:ClearAllPoints(); fr.none:SetPoint("TOPLEFT", 0, -(shown * 24) - 4) end
            fr.height = math.max(24, shown * 24 + (#list > shown and 22 or 0))
            fr:SetHeight(fr.height)
        end })
end

local function CatListRow(p)
    local fr = CreateFrame("Frame", nil, p.content)
    fr:SetSize(CW, 24)
    fr.lines = {}
    local function Line(i, cat)
        local ln = fr.lines[i]
        if ln then return ln end
        ln = CreateFrame("Frame", nil, fr)
        ln:SetSize(CW, 26)
        ln:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, -(i - 1) * 26)
        ln.icon = ln:CreateTexture(nil, "ARTWORK")
        ln.icon:SetSize(20, 20)
        ln.icon:SetPoint("LEFT", 0, 0)
        ln.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ln.icon:SetTexture(cat.icon)
        ln.name = ln:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ln.name:SetPoint("LEFT", ln.icon, "RIGHT", 8, 0)
        ln.name:SetWidth(200)
        ln.name:SetJustifyH("LEFT")
        ln.name:SetText(cat.label)
        ln.rule = ln:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ln.rule:SetPoint("LEFT", ln.name, "RIGHT", 8, 0)
        ln.rule:SetWidth(CW - 330)
        ln.rule:SetJustifyH("LEFT")
        ln.rule:SetWordWrap(false)
        ln.btn = W.NewButton(ln, L["Change"], 90, 22)
        ln.btn:SetPoint("RIGHT", 0, 0)
        ln.btn:SetScript("OnClick", function(self) if ns.Manager then ns.Manager.OpenCatMenu(self, cat) end end)
        fr.lines[i] = ln
        return ln
    end
    return AddRow(p, { frame = fr, h = 26, hfn = function() return #ns.Manager.CATS * 26 end, noSearch = true, label = L["Kinds of items"],
        update = function()
            for i, cat in ipairs(ns.Manager.CATS) do
                local ln = Line(i, cat)
                local r = ns.Manager.CatRule(cat.id)
                local k = r and ns.Manager.KIND[r.kind]
                if k then
                    ln.rule:SetText(k.label .. ((r.kind == "mail" and r.target) and (": " .. r.target) or ""))
                    ln.rule:SetTextColor(k.color[1], k.color[2], k.color[3])
                else
                    local who = ns.Manager.Suggest(cat)
                    ln.rule:SetText(who and ("– (" .. L["Suggestion"] .. ": " .. who .. ")") or "–")
                    ln.rule:SetTextColor(0.55, 0.55, 0.55)
                end
            end
            fr:SetHeight(#ns.Manager.CATS * 26)
        end })
end

do
    local p = NewPage("bags", L["Bags"], { cols = 2 })
    Heading(p, L["Bags manager"])
    Toggle(p, L["Open by itself"], "Interface\\Icons\\INV_Misc_Bag_10",
        function() return ns.Manager and ns.Manager.AutoOpen() end,
        function(on) ns.db.settings.mgrAutoOpen = on end,
        L["The bags window opens with a merchant, the mailbox and the bank, and closes with them."], true)
    Toggle(p, L["Sell junk automatically"], "Interface\\Icons\\INV_Misc_Coin_01",
        function() return ns.Manager and ns.Manager.JunkAuto() end,
        function(on) ns.db.settings.mgrSellJunk = on end,
        L["Gray items are sold when a merchant opens (not those you keep, mail or store)."], true)
    Choice(p, L["Worth a look at the auction house from"], { { "10", "10 %" }, { "25", "25 %" }, { "50", "50 %" }, { "100", "100 %" } },
        function() return tostring(ns.Manager and ns.Manager.AhGain() or 25) end,
        function(v) ns.db.settings.mgrAhGain = tonumber(v) or 25 end,
        L["When the auction house pays this much more than a vendor (after its fee), the item is marked for the auction house, not for the vendor."], "25")
    Choice(p, L["Sell without AH: up to"], { { "0", L["gray"] }, { "1", L["white"] }, { "2", L["green"] } },
        function() return tostring(ns.Manager and ns.Manager.SellLimit() or 1) end,
        function(v) ns.db.settings.mgrSellLimit = tonumber(v) or 1 end,
        L["The button at a vendor sells everything up to this quality that the auction house would not pay more for."], "1")
    Button(p, L["Open the bags manager"], function() if ns.Manager then ns.Manager.Show() end end)
    Heading(p, L["Kinds of items"])
    Note(p, L["A rule for a kind of item: cloth to the tailor, leather to the leatherworker, green gear to the enchanter. A rule for one item wins."])
    CatListRow(p)
    Button(p, L["All suggestions"], function() if ns.Manager then ns.Manager.ApplySuggestions() end end, nil,
        L["Takes over the suggestions: each kind that has no rule goes to the character with the profession that uses it."])
    Heading(p, L["Single items"])
    Note(p, L["What to do with an item, set in the bags manager: keep it, always mail it to a character, or store it in the bank."])
    RuleListRow(p)
    Button(p, L["Remove all rules"], function() if ns.Manager then ns.Manager.ClearRules() end end, { confirm = true })
end

-- Data -------------------------------------------------------------------------------------------
do
    local p = NewPage("account", L["Account"], { cols = 2 })
    Note(p, L["Your characters, kept in the saved variables so that one window shows all of them."])
    Heading(p, L["Characters"])
    Toggle(p, L["Remember my characters"], W.ICON.account,
        function() return ns.Acc.Enabled() end,
        function(on) ns.db.settings.accTrack = on end,
        L["Reads level, equipment, bags, professions and more of every character you log in with. Nothing is read while this is off."], true)
    Toggle(p, L["Show the surname"], nil,
        function() return ns.db.settings.accSurname ~= false end,
        function(on) ns.db.settings.accSurname = on; ns.Refresh() end,
        L["Adds the second part of a character's name (a surname or title the game gives it) in the account window."], true)
    Button(p, L["Open the account window"], function() ns.AccountWindow.Show() end)
    Heading(p, L["What is read, and when"])
    Note(p, L["The character, equipment, bags and professions: when you log in and while you play."])
    Note(p, L["The bank: when you open it. The mail: at a mailbox. Recipes: when you open a profession window."])
    Note(p, L["Auctions: when you visit the auction house. Time played: once per login."])
end

do
    local p = NewPage("windows", L["Windows"])
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
    Reset(L["Reset auction window"], function() if ns.AuctionWindow then ns.AuctionWindow.ResetWindow() end end)
    Reset(L["Reset bags window"], function() if ns.Manager then ns.Manager.ResetWindow() end end)
    Reset(L["Reset navigation arrow"], function() if ns.Routes then ns.Routes.ResetNav() end end)
    Reset(L["Reset minimap button"], ResetMinimapButton)
    Reset(L["Reset all windows"], function()
        ns.HUD.ResetWindow()
        UI.ResetWindow()
        ns.MapMain.ResetWindow()
        S.ResetWindow()
        ns.AccountWindow.ResetWindow()
        if ns.AuctionWindow then ns.AuctionWindow.ResetWindow() end
        if ns.Manager then ns.Manager.ResetWindow() end
        if ns.Routes then ns.Routes.ResetNav() end
        ResetMinimapButton()
    end, true)
end

do
    local p = NewPage("data", L["Data"])
    Heading(p, L["Data"])
    Note(p, L["What the addon has saved: sources, items and the history."])
    Button(p, L["Delete all data"], function()
        ns.ResetAll()
        Say(L["All data deleted."])
    end, { confirm = true }, L["Deletes every source, item and history entry. This cannot be undone."])
end

-- pages with options that have a standard value get "reset this page" (the button in the header)
for _, id in ipairs(order) do
    local p = pages[id]
    for _, row in ipairs(p.rows) do if row.reset then p.canReset = true end end
end

-- the groups and the list of the pages ---------------------------------------------------------------
local GROUPS = {
    { label = L["Interface"], pages = { "display", "style", "map" } },
    { label = L["Loot"], pages = { "sources", "session", "value", "notify" } },
    { label = L["Tooltips"], pages = { "tipgen", "tipitem", "tipmob", "tipnode" } },
    { label = L["Auction house"], pages = { "ah" } },
    { label = L["Inventory"], pages = { "bags" } },
    { label = L["Data"], pages = { "account", "windows", "data" } },
}
local navButtons, groupHeads = {}, {}
do
    for gi, g in ipairs(GROUPS) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        groupHeads[gi] = h
        g.buttons = {}
        for _, id in ipairs(g.pages) do
            local b = W.NewButton(f, pages[id].label, NAV_W, 26)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 12, 0)
            b.text:SetPoint("RIGHT", -30, 0)
            b.text:SetJustifyH("LEFT")
            b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.badge:SetPoint("RIGHT", -9, 0)
            b.badge:SetTextColor(0.93, 0.65, 0.37)
            b.id = id
            b:SetScript("OnClick", function() S.Select(id) end)
            navButtons[#navButtons + 1] = b
            g.buttons[#g.buttons + 1] = b
        end
    end
end

-- The places depend on the window style. In the Blizzard style the strip under the title bar is used: the search and the switch for
-- descriptions sit there (outside of the page, like the tabs of the auction house), the page and the list start right below it.
function S.Arrange(blizz)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + NAV_W + 8, blizz and 24 or -TOP)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, BOTTOM)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("RIGHT", resetBtn, "LEFT", -14, 0)
    searchBox:Hide() -- (the search is left out for now; its code stays)
    local y = blizz and -16 or -TOP
    for gi, g in ipairs(GROUPS) do
        groupHeads[gi]:ClearAllPoints()
        groupHeads[gi]:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 4, y)
        y = y - 16
        for _, b in ipairs(g.buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, y)
            y = y - 26
        end
        y = y - 6
    end
end
S.Arrange(false)

-- how many options of a page are not at their standard
local function Changed(p)
    local n = 0
    for _, row in ipairs(p.rows) do
        if row.def ~= nil and row.cur and tostring(row.cur()) ~= tostring(row.def) then n = n + 1 end
    end
    return n
end

-- the search: the options of all pages whose name or description has the words, on a page of their own
local searchPage = { id = "search", label = L["Search results"], content = CreateFrame("Frame", nil, sf), rows = {}, height = 0, cards = {}, cw = CW_FULL, side = 0 }
searchPage.content:SetSize(CW_FULL + 24, 10)
searchPage.content:Hide()
pages.search = searchPage
local searchHeading = searchPage.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
searchHeading:SetJustifyH("LEFT")
searchHeading:SetTextColor(1, 0.88, 0.5)
local searchRow = { frame = searchHeading, h = 16, heading = true }

local function GiveBack() -- every option goes back to its own page
    for _, id in ipairs(order) do
        local p = pages[id]
        for _, row in ipairs(p.rows) do
            if row.frame:GetParent() ~= p.content then row.frame:SetParent(p.content) end
            if row.descBox and row.descBox:GetParent() ~= p.content then row.descBox:SetParent(p.content) end
        end
    end
end

local function Matches(row, words)
    local hay = ((row.label or "") .. " " .. (row.descText or "")):lower()
    for _, w in ipairs(words) do
        if not hay:find(w, 1, true) then return false end
    end
    return true
end

-- an option that only makes sense while another one is on (row.enabled): dimmed and not to be clicked while it is off
local function SetRowEnabled(row, on)
    local fr = row.frame
    fr:SetAlpha(on and 1 or 0.4)
    local function Each(f)
        if f.Enable and f.Disable then
            if on then f:Enable() else f:Disable() end
        end
    end
    Each(fr)
    for _, child in ipairs({ fr:GetChildren() }) do Each(child) end
end

function S.Refresh()
    local p = pages[current]
    if not p then return end
    local total = {}
    for _, b in ipairs(navButtons) do
        Selected(b, b.id == current)
        local n = Changed(pages[b.id])
        b.badge:SetText(n > 0 and tostring(n) or "")
        total[b] = n
    end
    for gi, g in ipairs(GROUPS) do
        local sum = 0
        for _, id in ipairs(g.pages) do sum = sum + Changed(pages[id]) end
        groupHeads[gi]:SetText(g.label:upper() .. (sum > 0 and ("  |cffed9c5e(" .. sum .. ")|r") or ""))
    end
    resetBtn:SetShown(p.canReset and true or false)
    for _, row in ipairs(p.rows) do
        if row.update then row.update() end
        if row.enabled then SetRowEnabled(row, row.enabled()) end
    end
    UpdatePreview(p)
    Layout(p)
    local maxScroll = math.max(0, p.height - sf:GetHeight())
    if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
    UpdateThumb()
end

local syncSearch = false
function S.Select(id)
    if id ~= "search" and pages[id] then
        S.lastPage = id
        if searchBox:GetText() ~= "" then
            syncSearch = true
            searchBox:SetText("")
            syncSearch = false
        end
        GiveBack()
    end
    if not pages[id] then id = order[1] end
    for _, other in pairs(pages) do other.content:Hide() end
    current = id
    if ns.db and id ~= "search" then ns.db.settingsPage = id end
    local p = pages[id]
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", 12, -46)
    sf:SetPoint("BOTTOMRIGHT", -20 - (p.side or 0), 10)
    p.content:Show()
    sf:SetScrollChild(p.content)
    sf:SetVerticalScroll(0)
    pageTitle:SetText(p.label)
    S.Refresh()
end

function S.Search(text)
    local words = {}
    for w in tostring(text or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then
        if current == "search" then S.Select(S.lastPage or order[1]) end
        return
    end
    GiveBack()
    wipe(searchPage.rows)
    for _, id in ipairs(order) do
        for _, row in ipairs(pages[id].rows) do
            if row.label and not row.noSearch and Matches(row, words) then
                searchPage.rows[#searchPage.rows + 1] = row
                row.frame:SetParent(searchPage.content)
                if row.descBox then row.descBox:SetParent(searchPage.content) end
            end
        end
    end
    table.insert(searchPage.rows, 1, searchRow)
    searchHeading:SetText((L["Search results"]) .. "  |cff8a806e(" .. (#searchPage.rows - 1) .. ")|r")
    S.Select("search")
end

do
    local armed
    local label = L["Reset this page"]
    resetBtn:HookScript("OnHide", function(self) armed = nil; self.text:SetText(label); self.text:SetTextColor(unpack(C.text)) end)
    resetBtn:SetScript("OnClick", function(self)
        local p = pages[current]
        if not (p and p.canReset) then return end
        if not armed then
            armed = true
            self.text:SetText(L["Sure? Click again"])
            self.text:SetTextColor(unpack(C.red))
            C_Timer.After(3, function()
                if armed then armed = nil; self.text:SetText(label); self.text:SetTextColor(unpack(C.text)) end
            end)
            return
        end
        armed = nil
        self.text:SetText(label)
        self.text:SetTextColor(unpack(C.text))
        for _, row in ipairs(p.rows) do if row.reset then row.reset() end end
        ns.Refresh()
        S.Refresh()
    end)
end
resetBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Reset this page"], 1, 0.85, 0.4)
    GameTooltip:AddLine(L["Puts the options of this page back to their standard."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
resetBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
searchBox:SetScript("OnTextChanged", function(self)
    searchHint:SetShown(self:GetText() == "")
    if syncSearch then return end
    S.Search(self:GetText())
end)
searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    W.Step(dt)
    if f.fcMoving then return end -- (nothing is drawn again while the window is dragged: it follows the mouse without a hitch)
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

SLASH_FOREVERCOMPANIONSETTINGS1 = "/fcsettings"
SLASH_FOREVERCOMPANIONSETTINGS2 = "/fklsettings"
SlashCmdList.FOREVERCOMPANIONSETTINGS = function() S.Toggle() end
