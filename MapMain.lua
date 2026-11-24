local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The loot map as a window of its own (not a page of the journal or a tab of the session
-- window): the zone map with every saved spot, filter buttons over the map, a toolbar with
-- the zone list, search and the map's controls, and a full view that takes the whole screen.

local Main = {}
ns.MapMain = Main

local DEFAULT_W, DEFAULT_H = 800, 560
local MIN_W, MIN_H, MAX_W, MAX_H = 560, 380, 2400, 1500
local BAR_TOP = -24 -- the toolbar row: in the strip under the title bar of the Blizzard frame (above the window's top edge)
local BAR_LEFT = 56 -- (right of the ring with the icon)
local MAP_TOP = 8   -- the filter and the map
local BOTTOM = 16   -- room for the resize grip
local EDGE = 8
local BAR_BTN = 22
local MUTED_TXT = W.Hex(C.muted)

local state = { scope = "all", sources = {}, mapID = nil, ids = {}, counts = {}, shown = nil, started = false, full = false }
local dirty = true

local f = CreateFrame("Frame", "ForeverCompanionMap", UIParent, W.TEMPLATE)
Main.frame = f
f:SetSize(DEFAULT_W, DEFAULT_H)
f:SetPoint("CENTER", UIParent, "CENTER", -60, 0)
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
title:SetFontObject(ns.UI and ns.UI.bannerFontObject or "GameFontNormalLarge")
title:SetJustifyH("CENTER")
title:SetText(L["Loot map"])
title:SetTextColor(1, 0.85, 0.4)

function Main.ApplyFrameStyle()
    local ornate = false
    local blizz = W.BlizzSkin(f, true, W.ICON.map, title:GetText(), "map")
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
    if not ns.db or state.full then return end
    local point, _, rel, x, y = f:GetPoint()
    ns.db.mapMain = ns.db.mapMain or {}
    ns.db.mapMain.pos = { point, rel, x, y }
    ns.db.mapMain.size = { f:GetWidth(), f:GetHeight() }
    ns.db.mapMain.scale = f:GetScale()
end

f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)
f:SetScript("OnSizeChanged", function() dirty = true end)

-- window buttons: the other windows on the left, as everywhere
local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
f.closeBtn = close
close:SetPoint("TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() Main.Hide() end)
local opacityBtn = W.NewOpacityButton(f, "mapmain", f, 20)
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
local miniBtn = W.NewIconButton(f, "Interface\\Icons\\INV_Misc_Spyglass_02", 20)
miniBtn:SetPoint("LEFT", sessionBtn, "RIGHT", 4, 0)
miniBtn:SetTip(L["Mini map"], L["The map as a window of its own, following you, with the current filter."])
miniBtn:SetScript("OnClick", function() if ns.MapWindow then ns.MapWindow.Toggle() end end)
local accountBtn = W.NewIconButton(f, W.ICON.account, 20)
accountBtn:SetPoint("LEFT", miniBtn, "RIGHT", 4, 0)
accountBtn:SetTip(L["Account"], L["All your characters: equipment, bags, professions, mail."])
accountBtn:SetScript("OnClick", function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end)
local settingsBtn = W.NewIconButton(f, W.ICON.settings, 20) -- the last of the window buttons
settingsBtn:SetPoint("LEFT", accountBtn, "RIGHT", 4, 0)
settingsBtn:SetTip(L["Settings"], L["Open the settings."])
settingsBtn:SetScript("OnClick", function() if ns.Settings then ns.Settings.Toggle() end end)
f.skinRowAll = { journalBtn, sessionBtn, miniBtn, accountBtn, settingsBtn }

-- grip, bottom right
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(f:GetFrameLevel() + 50)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
local fullBtn -- set below; leaving the full view by hand resizing
W.AttachScaleGrip(f, grip, {
    defaultSize = { DEFAULT_W, DEFAULT_H }, minSize = { MIN_W, MIN_H }, maxSize = { MAX_W, MAX_H },
    gridSize = { 20, 20 }, gridScale = 0.05, minScale = 0.6, maxScale = 1.6,
    saveSize = function()
        state.full = false
        if fullBtn then fullBtn.text:SetText(L["Full view"]) end
        SavePosition()
    end,
    saveScale = SavePosition, savePos = SavePosition,
})

-- toolbar -----------------------------------------------------------------------------
local prev = W.NewIconButton(f, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", BAR_BTN)
prev:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_LEFT, -BAR_TOP)
prev:SetTip(L["Previous zone"])
local nextBtn = W.NewIconButton(f, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", BAR_BTN)
nextBtn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
nextBtn:SetTip(L["Next zone"])

-- the zone's name: a click lists every zone that has spots
local zoneBtn = CreateFrame("Button", nil, f)
zoneBtn:SetHeight(BAR_BTN)
zoneBtn:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
zoneBtn.text = zoneBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
zoneBtn.text:SetPoint("LEFT", 0, 0)
zoneBtn.text:SetTextColor(1, 0.88, 0.5)
zoneBtn.text:SetWordWrap(false)
zoneBtn.text:SetJustifyH("LEFT")
zoneBtn.line = zoneBtn:CreateTexture(nil, "ARTWORK")
zoneBtn.line:SetPoint("BOTTOMLEFT", 0, 2)
zoneBtn.line:SetPoint("BOTTOMRIGHT", 0, 2)
zoneBtn.line:SetHeight(1)
zoneBtn.line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.7)
local zoneCount = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
zoneCount:SetPoint("LEFT", zoneBtn, "RIGHT", 10, -1)
zoneCount:SetTextColor(unpack(C.muted))

-- the right side, from the edge: full view, reset zoom, opacity, brightness, follow; then the search
fullBtn = W.NewButton(f, L["Full view"], 84, BAR_BTN)
fullBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(EDGE + 2), -BAR_TOP)
local resetBtn = W.NewIconButton(f, "Interface\\Buttons\\UI-RefreshButton", BAR_BTN)
resetBtn:SetPoint("RIGHT", fullBtn, "LEFT", -6, 0)
resetBtn:SetTip(L["Reset zoom"], L["Wheel: zoom. Drag: move."])
local opBtn = W.NewIconButton(f, "Interface\\Icons\\Spell_Nature_Invisibilty", BAR_BTN)
opBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
local dimBtn = W.NewIconButton(f, "Interface\\Icons\\INV_Misc_Eye_01", BAR_BTN)
dimBtn:SetPoint("RIGHT", opBtn, "LEFT", -4, 0)
local sizeBtn = W.NewIconButton(f, "Interface\\Icons\\INV_Misc_Gem_Variety_01", BAR_BTN)
sizeBtn:SetPoint("RIGHT", dimBtn, "LEFT", -4, 0)
local followBtn = W.NewIconButton(f, "Interface\\Icons\\Ability_Tracking", BAR_BTN)
followBtn:SetPoint("RIGHT", sizeBtn, "LEFT", -4, 0)
followBtn:SetTip(L["Follow me"], L["Keeps you in the middle of the map while you are zoomed in."])
local RIGHT_W = 84 + 5 *(BAR_BTN + 4) + 6

-- the search: what it finds is shown on the map (here and on the minimap), nothing else
local search = CreateFrame("EditBox", nil, f, W.TEMPLATE)
search:SetHeight(BAR_BTN)
search:SetPoint("RIGHT", followBtn, "LEFT", -10, 0)
search:SetWidth(160)
search:SetBackdrop(W.PLATE_BACKDROP)
search:SetBackdropColor(unpack(C.inset))
search:SetBackdropBorderColor(unpack(C.goldDim))
search:SetFontObject("GameFontHighlightSmall")
search:SetAutoFocus(false)
search:SetMaxLetters(30)
search:SetTextInsets(8, 22, 0, 0)
local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
searchHint:SetPoint("LEFT", 8, 0)
searchHint:SetTextColor(unpack(C.muted))
searchHint:SetText(L["Search the map…"])
local searchClear = CreateFrame("Button", nil, search)
searchClear:SetSize(16, 16)
searchClear:SetPoint("RIGHT", -4, 0)
searchClear.text = searchClear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
searchClear.text:SetPoint("CENTER")
searchClear.text:SetText("×")
searchClear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)
searchClear:Hide()
search:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    ns.SetMapQuery(text)
    searchHint:SetShown(text == "")
    searchClear:SetShown(text ~= "")
    dirty = true
end)
search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.gold)) end)
search:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.goldDim)) end)

-- the filter: a button per group over the map's top left corner, each with a menu of its
-- entries (a click on an entry does what a click in a list would); the first button holds
-- the options. What the search finds is what the menus list.
local holder = CreateFrame("Frame", nil, f)
local view = W.NewMapView(f)
view.popBtn:Hide() -- the toolbar has the button for the small window
view.sf:SetPoint("TOP", holder, "TOP", 0, 0)
local FL = view.border:GetFrameLevel()

local GROUPS = ns.MAP_GROUPS
local DD_W, DD_ROWS, DD_ROW_H = 260, 16, 22
local dd = W.NewPlate(f, { 0.045, 0.035, 0.026, 0.98 })
dd:SetFrameLevel(FL + 14)
dd:SetWidth(DD_W)
dd:EnableMouse(true)
dd:EnableMouseWheel(true)
dd:Hide()
dd.rows, dd.offset = {}, 0

local function CloseDD()
    dd:Hide()
    dd.owner = nil
end
-- the menu is there while the mouse is over its button or over the menu itself
dd:SetScript("OnUpdate", function(self, dt)
    local owner = self.owner
    if owner and (owner:IsMouseOver() or self:IsMouseOver()) then
        self.away = 0
        return
    end
    self.away = (self.away or 0) + dt
    if self.away > 0.2 then CloseDD() end
end)

local function GroupList(id)
    local list, q = {}, ns.mapQuery
    for _, src in ipairs(state.sources) do
        if src.group == id and (not q or src.name:lower():find(q, 1, true)) then list[#list + 1] = src end
    end
    return list
end
local function GroupState(id, list)
    local visible = 0
    for _, src in ipairs(list) do
        if ns.MapSourceVisible(src.key, id) then visible = visible + 1 end
    end
    if #list == 0 then return ns.MapCatShown(id) and "all" or "none" end
    return visible == 0 and "none" or (visible == #list and "all" or "some")
end
-- a click on the group: everything of it, unless everything is shown already
local function ToggleGroup(id)
    local list = GroupList(id)
    local st = GroupState(id, list)
    if ns.mapQuery then
        for _, src in ipairs(list) do ns.MapSetSourceSel(src.key, st ~= "all", id) end
    else
        ns.MapSetGroup(id, st ~= "all")
    end
    dirty = true
end

local subOpen = {} -- which subzone groups are unfolded (they start folded)

local function Entry(src, id, indent)
    return { kind = "check", indent = indent, state = ns.MapSourceVisible(src.key, id) and "all" or "none",
        label = src.name, level = id:find("^mob") and src.level or nil, count = src.n,
        onClick = function()
            ns.MapSetSourceSel(src.key, not ns.MapSourceVisible(src.key, id), id)
            dirty = true
        end }
end

local function GroupMenu(id)
    local list = GroupList(id)
    local d = {}
    -- creatures are grouped by the subzone they live in, folded until you open one
    local groups, byName = {}, {}
    if id:find("^mob") then
        for _, src in ipairs(list) do
            local name = src.sub or L["Unknown area"]
            local g = byName[name]
            if not g then
                g = { name = name, list = {}, n = 0, unknown = src.sub == nil }
                byName[name] = g
                groups[#groups + 1] = g
            end
            g.list[#g.list + 1] = src
            g.n = g.n + src.n
        end
    end
    if #groups > 1 then
        table.sort(groups, function(a, b)
            if a.unknown ~= b.unknown then return b.unknown end
            return a.n > b.n
        end)
        local key = id .. ":"
        for _, g in ipairs(groups) do
            local open = ns.mapQuery ~= nil or subOpen[key .. g.name]
            local visible = 0
            for _, src in ipairs(g.list) do
                if ns.MapSourceVisible(src.key, id) then visible = visible + 1 end
            end
            d[#d + 1] = { kind = "check", header = true, open = open, label = g.name, count = #g.list,
                state = visible == 0 and "none" or (visible == #g.list and "all" or "some"),
                color = C.gold,
                onClick = function() subOpen[key .. g.name] = not subOpen[key .. g.name] end,
                onTick = function()
                    for _, src in ipairs(g.list) do ns.MapSetSourceSel(src.key, visible ~= #g.list, id) end
                    dirty = true
                end }
            if open then
                for _, src in ipairs(g.list) do d[#d + 1] = Entry(src, id, 18) end
            end
        end
    else
        for _, src in ipairs(list) do d[#d + 1] = Entry(src, id) end
    end
    if #list == 0 then d[#d + 1] = { kind = "text", label = L["Nothing here"] } end
    return d
end

local function OptionsMenu()
    local function All(on)
        for _, g in ipairs(GROUPS) do ns.MapSetGroup(g, on) end
        dirty = true
    end
    return {
        { kind = "check", state = state.scope == "session" and "all" or "none", label = L["Only this session"],
            onClick = function()
                state.scope = state.scope == "session" and "all" or "session"
                state.shown = nil
                dirty = true
            end },
        { kind = "check", state = ns.MapMinimapOn() and "all" or "none", label = L["Show on the minimap"],
            onClick = function() ns.MapSetMinimap(not ns.MapMinimapOn()); dirty = true end },
        { kind = "action", label = L["Show everything"], onClick = function() All(true) end },
        { kind = "action", label = L["Hide everything"], onClick = function() All(false) end },
    }
end

local function NewDDRow(i)
    local r = CreateFrame("Button", nil, dd)
    r:SetHeight(DD_ROW_H)
    r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * DD_ROW_H)
    r:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * DD_ROW_H)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.85, 0.4, 0.10)
    r.hl:SetAlpha(0)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetSize(12, 12)
    r.edge:SetPoint("LEFT", 6, 0)
    r.edge:SetColorTexture(unpack(C.goldDim))
    r.box = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.box:SetPoint("TOPLEFT", r.edge, 1, -1)
    r.box:SetPoint("BOTTOMRIGHT", r.edge, -1, 1)
    r.box:SetColorTexture(unpack(C.inset))
    r.tick = r:CreateTexture(nil, "OVERLAY")
    r.tick:SetPoint("TOPLEFT", r.edge, 3, -3)
    r.tick:SetPoint("BOTTOMRIGHT", r.edge, -3, 3)
    r.tick:SetColorTexture(unpack(C.gold))
    r.arrow = r:CreateTexture(nil, "OVERLAY")
    r.arrow:SetSize(10, 10)
    r.arrow:SetPoint("LEFT", 5, 0)
    r.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    r.arrow:SetVertexColor(0.8, 0.72, 0.5)
    r.tickBtn = CreateFrame("Button", nil, r) -- a header's box has a click of its own
    r.tickBtn:SetSize(22, DD_ROW_H)
    r.tickBtn:SetPoint("LEFT", r.edge, "LEFT", -5, 0)
    r.tickBtn:SetScript("OnClick", function(self)
        local row = self:GetParent()
        if row.tickFn then row.tickFn(); Main.RenderMenu() end
    end)
    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.level:SetJustifyH("LEFT")
    r.level:SetWidth(28)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -6, 0)
    r.count:SetTextColor(unpack(C.muted))
    r:SetScript("OnEnter", function(self) if self.fn then self.hl:SetAlpha(1) end end)
    r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
    r:SetScript("OnClick", function(self)
        if self.fn then self.fn(); Main.RenderMenu() end
    end)
    return r
end

function Main.RenderMenu()
    if not (dd:IsShown() and dd.gen) then return end
    local d = dd.gen()
    dd.offset = math.max(0, math.min(dd.offset, math.max(0, #d - DD_ROWS)))
    dd:SetHeight(math.min(#d, DD_ROWS) * DD_ROW_H + 10)
    for i = 1, DD_ROWS do
        local r = dd.rows[i]
        if not r then r = NewDDRow(i); dd.rows[i] = r end
        local e = d[dd.offset + i]
        if not e then
            r:Hide()
        else
            local box = e.kind == "check"
            r.edge:SetShown(box)
            r.box:SetShown(box)
            r.tick:SetShown(box and e.state ~= "none")
            r.tick:SetAlpha(e.state == "some" and 0.5 or 1)
            local head = e.header
            local edgeX = (head and 20) or ((e.indent or 0) + 6)
            r.edge:ClearAllPoints()
            r.edge:SetPoint("LEFT", edgeX, 0)
            r.arrow:SetShown(head and true or false)
            if head then r.arrow:SetRotation(e.open and math.rad(-90) or 0) end
            r.tickBtn:SetShown(head and true or false)
            r.tickFn = e.onTick
            local x = box and (edgeX + 20) or 8
            if e.level then
                r.level:ClearAllPoints()
                r.level:SetPoint("LEFT", x, 0)
                r.level:SetText(e.level)
                r.level:Show()
                x = x + 28
            else
                r.level:Hide()
            end
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", x, 0)
            r.label:SetPoint("RIGHT", -44, 0)
            r.label:SetText(e.label)
            local col = e.color or (e.kind == "action" and C.gold) or (e.kind == "text" and C.muted) or C.text
            r.label:SetTextColor(col[1], col[2], col[3])
            r.label:SetAlpha((e.state == "none") and 0.55 or 1)
            r.count:SetText(e.count or "")
            r.fn = e.onClick
            r:Show()
        end
    end
end
dd:SetScript("OnMouseWheel", function(_, delta)
    if not W.TopFrameIs(dd) then return end
    dd.offset = dd.offset - delta * 3
    Main.RenderMenu()
end)

local function OpenDD(btn, gen)
    if Main.zoneMenu then Main.zoneMenu:Hide() end
    dd.away = 0
    if dd.owner == btn and dd:IsShown() then return end
    dd.owner, dd.gen, dd.offset = btn, gen, 0
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0)
    dd:Show()
    Main.RenderMenu()
end

-- the buttons: the options and one per group, with a box for "all / some / none" shown
local filterButtons = {}
local function NewFilterButton(id)
    local b = W.NewButton(f, "", 90, 24, "GameFontHighlightSmall")
    b:SetFrameLevel(FL + 12)
    b.group = id
    b.text:ClearAllPoints()
    if id then
        b.edge = b:CreateTexture(nil, "ARTWORK")
        b.edge:SetSize(12, 12)
        b.edge:SetPoint("LEFT", 7, 0)
        b.edge:SetColorTexture(unpack(C.goldDim))
        b.box = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.box:SetPoint("TOPLEFT", b.edge, 1, -1)
        b.box:SetPoint("BOTTOMRIGHT", b.edge, -1, 1)
        b.box:SetColorTexture(unpack(C.inset))
        b.tick = b:CreateTexture(nil, "OVERLAY")
        b.tick:SetPoint("TOPLEFT", b.edge, 3, -3)
        b.tick:SetPoint("BOTTOMRIGHT", b.edge, -3, 3)
        b.tick:SetColorTexture(unpack(C.gold))
        b.text:SetPoint("LEFT", 25, 0)
    else
        b.text:SetPoint("LEFT", 10, 0)
    end
    -- hovering shows the entries; a click shows or hides the whole group
    b:HookScript("OnEnter", function(self)
        if self.group then
            local g = self.group
            OpenDD(self, function() return GroupMenu(g) end)
        else
            OpenDD(self, OptionsMenu)
        end
    end)
    b:SetScript("OnClick", function(self)
        if self.group then ToggleGroup(self.group) end
    end)
    return b
end
filterButtons.options = NewFilterButton(nil)
filterButtons.options.text:SetText(L["Options"])
for _, id in ipairs(GROUPS) do filterButtons[id] = NewFilterButton(id) end

local function UpdateFilter(mw)
    local q = ns.mapQuery
    local x, y, rowH = 8, 8, 28
    local avail = mw - 8
    local function Place(b, w)
        b:SetWidth(w)
        if x + w > avail and x > 8 then x = 8; y = y + rowH end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
        b:Show()
        x = x + w + 5
    end
    Place(filterButtons.options, filterButtons.options.text:GetStringWidth() + 26)
    for _, id in ipairs(GROUPS) do
        local b = filterButtons[id]
        local all = 0
        for _, src in ipairs(state.sources) do
            if src.group == id then all = all + 1 end
        end
        local list = GroupList(id)
        if all == 0 and not ns.MAP_ALWAYS[id] then
            b:Hide()
            if dd.owner == b then CloseDD() end
        else
            local info = ns.MapGroupInfo(id)
            local st = GroupState(id, list)
            local n = q and #list or all
            b.text:SetText(info.label .. " " .. MUTED_TXT .. n .. "|r")
            b.baseColor = info.color
            b:Restyle()
            b.tick:SetShown(st ~= "none")
            b.tick:SetAlpha(st == "some" and 0.5 or 1)
            b:SetAlpha((q and #list == 0) and 0.45 or 1)
            Place(b, b.text:GetStringWidth() + 36)
        end
    end
end

resetBtn:SetScript("OnClick", function() view:ResetZoom() end)
opBtn:SetScript("OnClick", function() ns.MapNextOpacity(); dirty = true end)
dimBtn:SetScript("OnClick", function() ns.MapNextDim(); dirty = true end)
sizeBtn:SetScript("OnClick", function() ns.MapNextSize(); dirty = true end)
followBtn:SetScript("OnClick", function()
    local on = not ns.MapFollowOn()
    ns.MapSetFollow(on)
    if on then view:ZoomAtLeast(3) end
    dirty = true
end)

-- while the map is filtered by text, a note on it says so
local note = W.NewPlate(f, { 0.045, 0.036, 0.03, 0.95 })
note:SetSize(300, 32)
note:SetFrameLevel(view.border:GetFrameLevel() + 6)
note:EnableMouse(true) -- the map underneath does not get these clicks
note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
note.text:SetPoint("LEFT", 12, 0)
note.text:SetJustifyH("LEFT")
note.text:SetWordWrap(false)
note.text:SetTextColor(unpack(C.muted))
note.btn = W.NewButton(note, L["Clear"], 76, 22)
note.btn:SetPoint("RIGHT", -5, 0)
note.btn:SetScript("OnClick", function() search:SetText("") end)
note:Hide()

-- the zone list --------------------------------------------------------------------------
local function MapName(mapID)
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and info and info.name then return info.name end
    end
    return "?"
end

local MENU_ROWS, MENU_W, MENU_ROW_H = 14, 270, 20
local menu = W.NewPlate(f, { 0.045, 0.035, 0.026, 0.98 })
menu:SetFrameLevel(f:GetFrameLevel() + 60)
menu:SetWidth(MENU_W)
menu:EnableMouse(true)
menu:EnableMouseWheel(true)
menu:Hide()
menu.rows, menu.offset = {}, 0
Main.zoneMenu = menu

local function RenderMenu()
    local ids = state.ids
    menu.offset = math.max(0, math.min(menu.offset, math.max(0, #ids - MENU_ROWS)))
    local shown = math.min(#ids, MENU_ROWS)
    menu:SetHeight(math.max(1, shown) * MENU_ROW_H + 10)
    for i = 1, MENU_ROWS do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetHeight(MENU_ROW_H)
            r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * MENU_ROW_H)
            r:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * MENU_ROW_H)
            r.hl = r:CreateTexture(nil, "BACKGROUND")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 0.85, 0.4, 0.12)
            r.hl:SetAlpha(0)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.name:SetPoint("LEFT", 8, 0)
            r.name:SetPoint("RIGHT", -60, 0)
            r.name:SetJustifyH("LEFT")
            r.name:SetWordWrap(false)
            r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.count:SetPoint("RIGHT", -8, 0)
            r.count:SetTextColor(unpack(C.muted))
            r:SetScript("OnEnter", function(self) self.hl:SetAlpha(1) end)
            r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
            r:SetScript("OnClick", function(self)
                state.mapID, state.shown = self.mapID, nil
                menu:Hide()
                dirty = true
            end)
            menu.rows[i] = r
        end
        local id = ids[menu.offset + i]
        if id then
            r.mapID = id
            r.name:SetText(MapName(id))
            r.name:SetTextColor(unpack(id == state.mapID and C.gold or C.text))
            r.count:SetText(state.counts[id] or "")
            r:Show()
        else
            r:Hide()
        end
    end
end
menu:SetScript("OnMouseWheel", function(_, delta)
    if not W.TopFrameIs(menu) then return end
    menu.offset = menu.offset - delta * 3
    RenderMenu()
end)
menu:SetScript("OnShow", RenderMenu)
zoneBtn:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); return end
    CloseDD()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", -4, -4)
    menu.offset = 0
    for i, id in ipairs(state.ids) do if id == state.mapID then menu.offset = math.max(0, i - 4) break end end
    menu:Show()
end)
zoneBtn:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 0.95, 0.7)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Zones with spots"], 1, 0.85, 0.4)
    GameTooltip:AddLine(L["Click to pick a zone from the list."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
zoneBtn:SetScript("OnLeave", function(self)
    self.text:SetTextColor(1, 0.88, 0.5)
    GameTooltip:Hide()
end)

local function Step(delta)
    local ids = state.ids
    if #ids == 0 then return end
    local index = 1
    for i, id in ipairs(ids) do if id == state.mapID then index = i break end end
    state.mapID = ids[(index - 1 + delta) % #ids + 1]
    state.shown = nil
    dirty = true
end
prev:SetScript("OnClick", function() Step(-1) end)
nextBtn:SetScript("OnClick", function() Step(1) end)

-- full view: nearly the whole screen, and back to where the window was
local function ToggleFull()
    if not state.full then
        local point, _, rel, x, y = f:GetPoint()
        state.restore = { point, rel, x, y, f:GetWidth(), f:GetHeight() }
        local s = f:GetScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetSize(math.floor(UIParent:GetWidth() / s - 90), math.floor(UIParent:GetHeight() / s - 130))
        state.full = true
    else
        local r = state.restore
        state.full = false
        if r then
            f:ClearAllPoints()
            f:SetPoint(r[1], UIParent, r[2], r[3], r[4])
            f:SetSize(r[5], r[6])
        end
    end
    fullBtn.text:SetText(state.full and L["Normal view"] or L["Full view"])
    dirty = true
end
fullBtn:SetScript("OnClick", ToggleFull)
fullBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(state.full and L["Back to the normal size"] or L["Fill the screen with the map"], 1, 0.85, 0.4)
    GameTooltip:Show()
end)
fullBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- what is shown ---------------------------------------------------------------------------
-- the zones that have something to show, the busiest first
local function Collect()
    local counts = {}
    if state.scope == "session" then
        for _, p in ipairs(ns.session.points or {}) do
            if ns.CatOn(p.cat) then counts[p.m] = (counts[p.m] or 0) + 1 end
        end
    else
        for _, gm in pairs(ns.db.mobs) do
            if gm.spots and ns.CatOn(gm.cat) and (gm.cat == "mob" or gm.cat == "herb" or gm.cat == "ore" or gm.cat == "object") then
                for _, sp in pairs(gm.spots) do counts[sp.m] = (counts[sp.m] or 0) + 1 end
            end
        end
    end
    local list = {}
    for mapID, n in pairs(counts) do list[#list + 1] = { m = mapID, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    local ids = {}
    for i, e in ipairs(list) do ids[i] = e.m end
    return ids, counts
end

local function Layout()
    local w = f:GetWidth()
    local free = w - (BAR_LEFT + EDGE + 2) - (2 * BAR_BTN + 3) - 8 - RIGHT_W - 10
    -- zone name, its count and the search share what is left; the search gives way last
    local zoneW = math.min(zoneBtn.text:GetStringWidth() + 4, math.max(80, free * 0.45))
    zoneBtn:SetWidth(zoneW)
    zoneBtn.text:SetWidth(zoneW)
    local showCount = free - zoneW - 70 > 120
    zoneCount:SetShown(showCount)
    local searchW = free - zoneW - (showCount and 70 or 0) - 14
    search:SetWidth(math.max(80, math.min(220, searchW)))

    local h = f:GetHeight() - MAP_TOP - BOTTOM - 8
    -- the map's frame is 3 px around its picture
    local mw = w - 2 * EDGE - 6
    h = h - 6
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 3, -(MAP_TOP + 3))
    holder:SetSize(mw, h)
    view.sf:ClearAllPoints()
    view.sf:SetPoint("TOP", holder, "TOP", 0, 0)
    view:SetArea(mw, h)
    return mw
end

function Main.Render()
    if not f:IsShown() then return end
    local ids, counts = Collect()
    state.ids, state.counts = ids, counts
    local mapID
    for _, id in ipairs(ids) do if id == state.mapID then mapID = id break end end
    if not mapID and #ids > 0 then
        if not state.started then
            local here = ns.PlayerPos()
            for _, id in ipairs(ids) do if id == here then mapID = id break end end
        end
        mapID = mapID or ids[1]
    end
    state.started = true
    state.mapID = mapID

    followBtn:SetActive(ns.MapFollowOn())
    miniBtn:SetActive(ns.MapWindow and ns.MapWindow.IsShown())
    ns.MapDimTip(dimBtn)
    ns.MapOpacityTip(opBtn)
    ns.MapSizeTip(sizeBtn)
    prev:SetShown(#ids > 1)
    nextBtn:SetShown(#ids > 1)
    zoneBtn:ClearAllPoints()
    if #ids > 1 then zoneBtn:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
    else zoneBtn:SetPoint("LEFT", prev, "LEFT", 2, 0) end
    zoneBtn:SetEnabled(#ids > 0)
    zoneBtn.line:SetShown(#ids > 1)
    if menu:IsShown() then RenderMenu() end

    zoneBtn.text:SetText(mapID and MapName(mapID) or L["Loot map"])
    local mw = Layout()

    local query = ns.mapQuery
    note:SetShown(query ~= nil)
    if query then
        note:SetWidth(math.max(200, math.min(330, mw - 24)))
        note.text:SetWidth(note:GetWidth() - 106)
        note.text:SetText(L["Showing: %s"]:format("|cffffd100" .. search:GetText() .. "|r"))
        note:ClearAllPoints()
        note:SetPoint("BOTTOM", holder, "BOTTOM", 0, 10)
    end

    if not mapID then
        zoneCount:SetText("")
        view:SetDots({})
        view:SetHeat({})
        state.sources = {}
        UpdateFilter(mw)
        Main.RenderMenu()
        view.note:SetText(state.scope == "session" and L["Loot appears here as you play."] or L["Spots appear here as you kill and gather."])
        return
    end
    if state.shown ~= mapID then
        view:SetMap(mapID)
        state.shown = mapID
    end
    local data = ns.MapData(mapID, state.scope, query)
    view:SetHeat(data.heat)
    view:SetDots(data.dots)
    state.sources = data.sources
    UpdateFilter(mw)
    Main.RenderMenu()
    zoneCount:SetText(MUTED_TXT .. L["%d spots"]:format(data.shown) .. "|r")
end

local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    W.Step(dt)
    if f.fcMoving then return end -- (nothing is drawn again while the window is dragged: it follows the mouse without a hitch)
    acc = acc + dt
    if (dirty and acc > 0.05) or acc > 1 then
        acc, dirty = 0, false
        Main.Render()
    end
end)
f:SetScript("OnShow", function() dirty = true end)
f:SetScript("OnHide", function() menu:Hide(); CloseDD() end)

-- Open the map. opts: scope ("session" / "all"), query (what to search for), mapID.
function Main.Show(opts)
    -- opened afresh it shows everything that was ever saved; "this session" is an option
    if not f:IsShown() and not (opts and opts.scope) then state.scope, state.shown = "all", nil end
    f:Show()
    if ns.db then ns.db.mapMainShown = true end
    if opts then
        if opts.scope then state.scope, state.shown = opts.scope, nil end
        if opts.mapID then state.mapID, state.shown = opts.mapID, nil end
        if opts.query ~= nil then search:SetText(opts.query) end
    end
    dirty = true
end

-- the map filtered to one source (a creature, a plant, a vein): everything saved, in the
-- zone where it was seen most
function Main.ShowSource(key)
    local gm = ns.db.mobs[key]
    if not gm then return end
    local counts, best = {}, nil
    for _, sp in pairs(gm.spots or {}) do counts[sp.m] = (counts[sp.m] or 0) + (sp.n or 1) end
    local here = ns.PlayerPos()
    for m, n in pairs(counts) do
        if m == here then best = m break end
        if not best or n > counts[best] then best = m end
    end
    Main.Show({ scope = "all", query = gm.name or key, mapID = best })
end

function Main.Hide()
    f:Hide()
    if ns.db then ns.db.mapMainShown = false end
    if search:GetText() ~= "" then search:SetText("") end -- a search should not stay behind on the minimap
end
function Main.IsShown() return f:IsShown() end
function Main.Toggle()
    if f:IsShown() then Main.Hide() else Main.Show() end
end

function Main.ResetWindow()
    if ns.db then ns.db.mapMain = nil end
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 0)
    f:SetSize(DEFAULT_W, DEFAULT_H)
    state.full = false
    fullBtn.text:SetText(L["Full view"])
    dirty = true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    Main.ApplyFrameStyle()
    local saved = ns.db and ns.db.mapMain
    if saved and saved.scale then f:SetScale(math.max(0.6, math.min(1.6, saved.scale))) end
    if saved and saved.size then
        f:SetSize(math.max(MIN_W, math.min(MAX_W, saved.size[1])), math.max(MIN_H, math.min(MAX_H, saved.size[2])))
    end
    if saved and saved.pos then
        f:ClearAllPoints()
        f:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
    end
    W.SetWindowAlpha(f, W.WindowAlpha("mapmain"))
    if ns.db and ns.db.mapMainShown then Main.Show() end
end)

SLASH_FOREVERCOMPANIONMAP1 = "/fcmap"
SLASH_FOREVERCOMPANIONMAP2 = "/fklmap"
SlashCmdList.FOREVERCOMPANIONMAP = function() Main.Toggle() end
