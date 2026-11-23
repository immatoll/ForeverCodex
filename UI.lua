local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C
local Ease, CancelEase, CurrentEase, LerpColor, Hex = W.Ease, W.CancelEase, W.CurrentEase, W.LerpColor, W.Hex

-- The journal: bookmark rail on the left and one page at a time. List pages are two-page spreads
-- (list on the left, the selected entry on the right).

local UI = { pages = {}, order = {}, listviews = {} }
ns.UI = UI

local WIDTH, HEIGHT = 800, 566
local PAD = 18
local RAIL_W = 46
local AREA_X, AREA_TOP = PAD + RAIL_W + 10, -24 -- (the page begins in the strip under the title bar, right of the ring)
local RAIL_TOP = 14 -- (the rail starts below the ring)
UI.AREA_W = WIDTH - AREA_X - PAD
UI.AREA_H = HEIGHT - AREA_TOP - 18

local FRAME_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local dirty = true
local collapsed = false

function ns.Refresh() dirty = true end
function UI.Dirty() dirty = true end

-- Main frame ------------------------------------------------------------

local main = CreateFrame("Frame", "ForeverCompanionFrame", UIParent, W.TEMPLATE)
UI.frame = main
main:SetSize(WIDTH, HEIGHT)
main:SetPoint("CENTER")
main:SetFrameStrata("MEDIUM")
main:SetToplevel(true)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:EnableMouse(true)
main:RegisterForDrag("LeftButton")
main:Hide()
main:SetBackdrop(FRAME_BACKDROP)
tinsert(UISpecialFrames, "ForeverCompanionFrame")

local face = main:CreateTexture(nil, "BACKGROUND", nil, 1)
face:SetPoint("TOPLEFT", 8, -8)
face:SetPoint("BOTTOMRIGHT", -8, 8)
face:SetColorTexture(0.055, 0.045, 0.038, 0.97)

main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.pos = { point, rel, x, y }
end)

local banner = main:CreateTexture(nil, "ARTWORK")
banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
banner:SetSize(300, 64)
banner:SetPoint("TOP", 0, 12)

local titleFont = CreateFont("ForeverCompanionTitleFont")
local fancy = titleFont:SetFont("Fonts\\MORPHEUS.TTF", 16, "")
local title = main:CreateFontString(nil, "OVERLAY")
UI.titleFontObject = fancy and titleFont or "GameFontNormalLarge"

-- The banner's title: the regular heading face, a little smaller than before, with a thin outline
-- and a shadow so it holds its own on the plate (the plate's upper part reaches over the frame).
local bannerFont = CreateFont("ForeverCompanionBannerFont")
if not bannerFont:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE") then
    bannerFont:CopyFontObject(_G.GameFontNormalLarge)
end
bannerFont:SetShadowColor(0, 0, 0, 0.8)
bannerFont:SetShadowOffset(1, -1)
UI.bannerFontObject = bannerFont

title:SetFontObject(bannerFont)
title:SetJustifyH("CENTER")
title:SetPoint("CENTER", banner, "CENTER", 0, 12)
title:SetText(L["Journal"])
title:SetTextColor(1, 0.85, 0.4)

-- Frame style (settings): "ornate" is the dialog frame with the hanging banner,
-- "plain" a slim gilded plate. The session overlay follows the same setting.
function UI.ApplyFrameStyle()
    local ornate = false
    local blizz = W.BlizzSkin(main, true, W.ICON.journal, title:GetText(), "journal")
    title:SetAlpha(blizz and 0 or 1) -- (the frame's own title is shown instead)
    if ornate then
        main:SetBackdrop(FRAME_BACKDROP)
        face:Show()
        banner:Show()
        title:ClearAllPoints()
        title:SetPoint("CENTER", banner, "CENTER", 0, 12)
    else
        if blizz then
            main:SetBackdrop(nil)
        else
            main:SetBackdrop(W.PLATE_BACKDROP)
            main:SetBackdropColor(0.055, 0.045, 0.038, 1)
            main:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
        end
        face:Hide()
        banner:Hide()
        title:ClearAllPoints()
        title:SetPoint("TOP", 0, blizz and 42 or -14)
    end
end

-- window buttons: gilded plates in the same style as everything else
local close = W.NewButton(main, "×", 22, 22, "GameFontNormalLarge")
main.closeBtn = close
close:SetPoint("TOPRIGHT", -16, -16)
close:SetScript("OnClick", function() main:Hide() end)

-- the corner grip: its layout is fixed, so dragging scales the whole journal
local jgrip = CreateFrame("Button", nil, main)
jgrip:SetSize(16, 16)
jgrip:SetPoint("BOTTOMRIGHT", -12, 12)
jgrip:SetFrameLevel(main:GetFrameLevel() + 20)
jgrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
jgrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
jgrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
W.AttachScaleGrip(main, jgrip, {
    scaleOnly = true, minScale = 0.6, maxScale = 1.6,
    gridScale = 0.05,
    saveScale = function() if ns.db then ns.db.uiScale = main:GetScale() end end,
    savePos = function()
        if ns.db then
            local point, _, rel, x, y = main:GetPoint()
            ns.db.pos = { point, rel, x, y }
        end
    end,
})

local opacityBtn = W.NewOpacityButton(main, "journal", main, 22)
opacityBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
main.opacityBtn = opacityBtn

-- switch to the quiet session overlay
local hudBtn = W.NewIconButton(main, W.ICON.session, 24)
hudBtn:SetPoint("TOPLEFT", 18, -15)
hudBtn:SetTip(L["Session"], L["Show or hide the small session overlay."])
hudBtn:SetScript("OnClick", function() if ns.HUD then ns.HUD.Toggle() end end)
local mapBtn = W.NewIconButton(main, W.ICON.map, 24)
mapBtn:SetPoint("LEFT", hudBtn, "RIGHT", 6, 0)
mapBtn:SetTip(L["Loot map"], L["Open the loot map in a window of its own."])
mapBtn:SetScript("OnClick", function() if ns.MapMain then ns.MapMain.Toggle() end end)
local accountBtn = W.NewIconButton(main, W.ICON.account, 24)
accountBtn:SetPoint("LEFT", mapBtn, "RIGHT", 6, 0)
accountBtn:SetTip(L["Account"], L["All your characters: equipment, bags, professions, mail."])
accountBtn:SetScript("OnClick", function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end)
local settingsBtn = W.NewIconButton(main, W.ICON.settings, 24) -- the last of the window buttons
settingsBtn:SetPoint("LEFT", accountBtn, "RIGHT", 6, 0)
settingsBtn:SetTip(L["Settings"], L["Open the settings."])
settingsBtn:SetScript("OnClick", function() if ns.Settings then ns.Settings.Toggle() end end)
main.skinRowAll = { hudBtn, mapBtn, accountBtn, settingsBtn }

main:SetScript("OnShow", function(self)
    dirty = true
    Ease(self, "open", 1, 12, function(o, v) o:SetAlpha(v * W.WindowAlpha("journal")) end, 0)
    W.FadeWindowParts(self, W.WindowAlpha("journal"))
    self:SetAlpha(0)
end)

-- Pages and the bookmark rail ---------------------------------------------

local area = CreateFrame("Frame", nil, main)
area:SetPoint("TOPLEFT", AREA_X, -AREA_TOP)
area:SetPoint("BOTTOMRIGHT", -PAD, 18)
UI.area = area

function UI.AddPage(def)
    UI.pages[def.id] = def
    UI.order[#UI.order + 1] = def.id
end

local rail = {}

local function ApplyRail(b, v)
    local on = b.active and 1 or 0
    local k = math.max(on, v)
    b:SetBackdropBorderColor(LerpColor(C.goldDim, C.gold, k))
    b:SetBackdropColor(LerpColor(C.plate, C.plateHi, math.max(on, v * 0.6)))
    b.glow:SetAlpha(on * 0.35 + v * 0.3)
    b.icon:SetAlpha(0.65 + 0.35 * k)
end

local function SelectPage(id)
    UI.current = id
    if ns.db then ns.db.tab = id end
    for pid, def in pairs(UI.pages) do
        if def.obj then def.obj.frame:SetShown(pid == id) end
    end
    local def = UI.pages[id]
    if def and not def.obj then
        def.obj = def.Build(area)
        def.obj.frame:SetAllPoints(area)
    end
    if def and def.obj then W.FadeWindowParts(main, W.WindowAlpha("journal")) end
    if def then
        def.obj.frame:Show()
        Ease(def.obj.frame, "page", 1, 12, function(o, v) o:SetAlpha(v) end, 0)
        def.obj.frame:SetAlpha(0)
    end
    for pid, b in pairs(rail) do
        b.active = pid == id
        ApplyRail(b, CurrentEase(b, "hv"))
    end
    dirty = true
end
UI.Select = SelectPage

local railBuilt = false
local function BuildRail()
    if railBuilt then return end
    railBuilt = true
    -- the rail shrinks its spacing so every page fits however many there are
    local step = math.min(RAIL_W + 6, math.floor(UI.AREA_H / #UI.order))
    for i, id in ipairs(UI.order) do
        local def = UI.pages[id]
        local b = CreateFrame("Button", nil, main, W.TEMPLATE)
        b:SetSize(RAIL_W, RAIL_W)
        b:SetPoint("TOPLEFT", PAD, -RAIL_TOP - (i - 1) * step)
        b:SetBackdrop(W.PLATE_BACKDROP)
        b:SetBackdropColor(unpack(C.plate))
        b.glow = W.GlowTexture(b)
        b.glow:SetPoint("TOPLEFT", 3, -3)
        b.glow:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(30, 30)
        b.icon:SetPoint("CENTER")
        b.icon:SetTexture(def.icon)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetScript("OnClick", function() SelectPage(id) end)
        b:SetScript("OnEnter", function(self)
            Ease(self, "hv", 1, 16, ApplyRail)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(def.label, 1, 0.85, 0.4)
            if def.hint then GameTooltip:AddLine(def.hint, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            Ease(self, "hv", 0, 16, ApplyRail)
            GameTooltip:Hide()
        end)
        rail[id] = b
    end
end

-- List view: pooled rows, smooth scrolling, hover, selection, flash ----------

local function ApplySel(r, v)
    r.sel:SetAlpha(v * 0.8)
    r.name:SetTextColor(LerpColor(C.text, { 1, 0.9, 0.55 }, v))
end
local function ApplyHl(r, v) r.hl:SetAlpha(v * 0.6) end
local function ApplyFlash(r, v) r.flash:SetAlpha(v) end
local function ApplyAlpha(r, v) r:SetAlpha(v) end

function UI.NewListView(parent, width, height, rowH)
    local lv = { rows = {}, rowH = rowH, seen = {}, known = {}, fadeAt = {}, flashAt = {}, populated = false,
        scroll = 0, target = 0, maxScroll = 0, width = width, height = height, contentH = 0 }

    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(width, height)
    sf:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, sf)
    local rowW = width - 8 -- rows leave a gutter for the scroll thumb
    content:SetSize(rowW, 1)
    sf:SetScrollChild(content)
    lv.frame, lv.content = sf, content

    -- the thumb sits in its own frame above the rows, in the gutter beside them
    local thumbFrame = CreateFrame("Frame", nil, parent)
    thumbFrame:SetFrameLevel(sf:GetFrameLevel() + 20)
    thumbFrame:SetWidth(4)
    local thumb = thumbFrame:CreateTexture(nil, "OVERLAY")
    thumb:SetAllPoints()
    thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)
    thumbFrame:Hide()

    local empty = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", 0, 10)
    empty:SetWidth(width - 50)
    empty:SetTextColor(unpack(C.muted))

    local function UpdateThumb()
        if lv.contentH > height then
            local th = math.max(24, height * height / lv.contentH)
            local off = lv.scroll / (lv.contentH - height) * (height - th)
            thumbFrame:ClearAllPoints()
            thumbFrame:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -1, -off)
            thumbFrame:SetHeight(th)
            thumbFrame:Show()
        else
            thumbFrame:Hide()
        end
    end
    local function ApplyScroll(_, v)
        lv.scroll = v
        sf:SetVerticalScroll(v)
        UpdateThumb()
    end
    sf:SetScript("OnMouseWheel", function(_, delta)
    -- the wheel also reaches windows that are covered by another one: only the one on top scrolls
        if not W.TopFrameIs(lv.owner or main) then return end
        lv.target = math.max(0, math.min(lv.maxScroll, lv.target - delta * rowH * 2))
        Ease(sf, "scroll", lv.target, 14, ApplyScroll, lv.scroll)
    end)

    local function NewRow()
        local r = CreateFrame("Button", nil, content)
        r:SetSize(rowW, rowH)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        r.sel:SetTexture(W.HILITE_TEX)
        r.sel:SetBlendMode("ADD")
        r.sel:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
        r.sel:SetAlpha(0)
        r.hl = r:CreateTexture(nil, "BORDER")
        r.hl:SetAllPoints()
        r.hl:SetTexture(W.HILITE_TEX)
        r.hl:SetBlendMode("ADD")
        r.hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
        r.hl:SetAlpha(0)
        r.sep = r:CreateTexture(nil, "BORDER")
        r.sep:SetPoint("BOTTOMLEFT", 6, 0)
        r.sep:SetPoint("BOTTOMRIGHT", -6, 0)
        r.sep:SetHeight(1)
        r.sep:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.3)
        r.flash = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.flash:SetAllPoints()
        r.flash:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        r.flash:SetBlendMode("ADD")
        r.flash:SetAlpha(0)

        local isz = rowH - 14
        r.iconEdge = r:CreateTexture(nil, "ARTWORK")
        r.iconEdge:SetSize(isz, isz)
        r.iconEdge:SetPoint("LEFT", 13, 0)
        r.icon = r:CreateTexture(nil, "OVERLAY")
        r.icon:SetPoint("TOPLEFT", r.iconEdge, 1, -1)
        r.icon:SetPoint("BOTTOMRIGHT", r.iconEdge, -1, 1)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local tx = 13 + isz + 9
        r.tx = tx
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("TOPLEFT", tx, -8)
        r.name:SetWidth(rowW - tx - 84)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.sub:SetPoint("BOTTOMLEFT", tx, 8)
        r.sub:SetWidth(rowW - tx - 84)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)
        r.sub:SetTextColor(unpack(C.muted))
        r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.right:SetPoint("TOPRIGHT", -12, -8)
        r.right:SetJustifyH("RIGHT")
        r.right2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.right2:SetPoint("BOTTOMRIGHT", -12, 8)
        r.right2:SetJustifyH("RIGHT")

        r:SetScript("OnClick", function(self)
            if lv.onSelect and self.entry then lv.onSelect(self.entry) end
        end)
        r:SetScript("OnEnter", function(self)
            Ease(self, "hl", 1, 16, ApplyHl)
            local e = self.entry
            if e and e.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                e.tip(e)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self)
            Ease(self, "hl", 0, 16, ApplyHl)
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
        return r
    end

    function lv:Reset()
        wipe(self.seen); wipe(self.known); wipe(self.fadeAt); wipe(self.flashAt)
        self.populated = false
    end

    function lv:ScrollToTop()
        self.scroll, self.target = 0, 0
        CancelEase(sf, "scroll")
        sf:SetVerticalScroll(0)
        UpdateThumb()
    end

    -- the list gets another height (a panel beside it opens or closes)
    function lv:Resize(h)
        height = h
        sf:SetHeight(h)
        self.maxScroll = math.max(0, self.contentH - h)
        self.target = math.min(self.target, self.maxScroll)
        if self.scroll > self.maxScroll then self.scroll = self.maxScroll end
        sf:SetVerticalScroll(self.scroll)
        UpdateThumb()
    end

    function lv:SetData(entries, selKey, onSelect, emptyText)
        self.onSelect = onSelect
        local now = GetTime()
        local newKnown = {}
        for i, e in ipairs(entries) do
            local r = self.rows[i]
            if not r then r = NewRow(); self.rows[i] = r end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowH)
            r.entry = e
            local noIcon = e.noIcon
            r.iconEdge:SetShown(not noIcon)
            r.icon:SetShown(not noIcon)
            if not noIcon then
                if e.itemID then r.icon:SetTexture(W.ItemTexture(e.itemID))
                else r.icon:SetTexture(e.texture or 134400) end
                local qc = W.QUALITY_COLOR[e.quality or 1] or W.QUALITY_COLOR[1]
                r.iconEdge:SetColorTexture(qc[1], qc[2], qc[3], 1)
            end
            local tx = noIcon and 14 or r.tx
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", tx, -8)
            r.sub:ClearAllPoints()
            r.sub:SetPoint("BOTTOMLEFT", tx, 8)
            r.name:SetText(e.name or "")
            r.sub:SetText(e.sub or "")
            r.right:SetText(e.right or "")
            r.right:SetTextColor(unpack(e.rightColor or C.text))
            r.right2:SetText(e.right2 or "")
            r.right2:SetTextColor(unpack(e.right2Color or C.muted))
            r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
            Ease(r, "sel", e.key == selKey and 1 or 0, 14, ApplySel)

            -- gold flash when a row's activity went up since the last refresh
            if e.activity then
                local prev = self.seen[e.key]
                self.seen[e.key] = e.activity
                if prev and e.activity > prev then self.flashAt[e.key] = now end
            end
            local at = self.flashAt[e.key]
            if at then
                local v = 0.5 * math.exp(-3 * (now - at))
                if v > 0.02 then Ease(r, "flash", 0, 3, ApplyFlash, v) else self.flashAt[e.key] = nil; r.flash:SetAlpha(0) end
            else
                r.flash:SetAlpha(0)
            end

            -- new rows fade in (not on the first fill)
            newKnown[e.key] = true
            if self.populated and not self.known[e.key] then self.fadeAt[e.key] = now end
            local fa = self.fadeAt[e.key]
            if fa and now - fa < 0.2 then
                local v = (now - fa) / 0.2
                r:SetAlpha(v)
                Ease(r, "fade", 1, 14, ApplyAlpha, v)
            else
                self.fadeAt[e.key] = nil
                CancelEase(r, "fade")
                r:SetAlpha(1)
            end
            r:Show()
        end
        for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
        self.known, self.populated = newKnown, true

        self.contentH = #entries * rowH
        content:SetHeight(math.max(self.contentH, 1))
        self.maxScroll = math.max(0, self.contentH - height)
        self.target = math.min(self.target, self.maxScroll)
        if self.scroll > self.maxScroll then self.scroll = self.maxScroll end
        sf:SetVerticalScroll(self.scroll)
        UpdateThumb()
        empty:SetText(#entries == 0 and (emptyText or "") or "")
    end

    UI.listviews[lv] = true
    return lv
end

-- Render loop -------------------------------------------------------------

local seenSession

local function Render()
    if not ns.db or not ns.session then return end
    if seenSession ~= ns.session then
        seenSession = ns.session
        for lv in pairs(UI.listviews) do lv:Reset() end
    end
    BuildRail()
    local snap = ns.BuildSnapshot()
    if not UI.current or not UI.pages[UI.current] then
        local want = ns.db.tab
        SelectPage(UI.pages[want] and want or UI.order[1])
    end
    local def = UI.pages[UI.current]
    if def and def.obj and not collapsed then def.obj.Refresh(snap) end
end

local acc = 0
main:SetScript("OnUpdate", function(_, elapsed)
    W.Step(elapsed)
    if main.fcMoving then return end -- (nothing is drawn again while the window is dragged: it follows the mouse without a hitch)
    acc = acc + elapsed
    if (dirty and acc > 0.05) or acc > 1 then
        acc, dirty = 0, false
        Render()
    end
end)

function UI.Toggle()
    if main:IsShown() then main:Hide() else main:Show() end
end
function ns.Toggle() UI.Toggle() end

-- jump to an entry of a page (used by the session overlay's rows)
function UI.OpenEntry(pageId, key)
    if not main:IsShown() then main:Show() end
    SelectPage(pageId)
    local def = UI.pages[pageId]
    if def and def.obj and def.obj.SetSel then def.obj.SetSel(key) end
    dirty = true
end

function UI.ResetWindow()
    if ns.db then ns.db.pos, ns.db.uiScale = nil, nil end
    main:SetScale(1)
    main:ClearAllPoints()
    main:SetPoint("CENTER")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    UI.ApplyFrameStyle()
    if ns.db and ns.db.uiScale then main:SetScale(math.max(0.6, math.min(1.6, ns.db.uiScale))) end
    local pos = ns.db and ns.db.pos
    if pos then
        main:ClearAllPoints()
        main:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end)
