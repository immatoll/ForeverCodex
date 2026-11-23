local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C

-- The recipe window (a small codex): the start page lists the professions; the search at the top finds recipes (by name or by a
-- material) in all of them; from the context menu of an item (ns.ItemInfo.Show(itemId)) it shows the recipes that make or use that item.
-- A profession each down the left, the recipes as rows (the skill each needs, which of your characters know it); a click on a recipe opens
-- the materials in a panel at the bottom (what you have of each, what it costs, what the product is worth). The recipes come from the
-- recipe data of the game (Data/Recipes.lua). Home goes back to the start page, "<" to where you were before.

local I = {}
ns.ItemInfo = I

local WIN_W, WIN_H = 940, 680
local TABS_W = 160
local LIST_X = 12 + TABS_W + 10
local LIST_W = WIN_W - LIST_X - 12
local BODY_TOP = 106          -- where the list starts (under the header and the line of your characters)
local DETAIL_H = 222
local ROW_H = 44
local MAX_ROWS = 400
local MAX_TABS = 16
local GREY, JADE = "|cff8a806e", "|cff66dbb0"
local CARD_COLS = 5
local CARD_W = math.floor((LIST_W - 24 - (CARD_COLS - 1) * 6) / CARD_COLS)
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"

local function SpellName(id)
    local n
    if C_Spell and C_Spell.GetSpellName then
        n = C_Spell.GetSpellName(id)
    elseif GetSpellInfo then
        n = GetSpellInfo(id)
        if type(n) == "table" then n = n.name end
    end
    return n
end

local function Hex(c, text)
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5, text)
end

local function Coloured(q, text)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    return c and Hex(c, text) or text
end

local function ClassName(rec)
    local c = RAID_CLASS_COLORS and rec.class and RAID_CLASS_COLORS[rec.class]
    local name = rec.name or "?"
    return c and Hex(c, name) or name
end

local function ProfIcon(prof)
    return ns.Acc and ns.Acc.ProfIcon and ns.Acc.ProfIcon(prof)
end

local function ProfName(prof) return L[prof] or prof end

-- (green is halfway between yellow and grey: the colours of a recipe change at orange, yellow, green and grey, as in the game's list)
-- the colour a recipe has for a skill: orange, yellow, green or grey
local function Difficulty(R, skill)
    if skill >= R.grey then return "|cff8a8a8a" end
    if skill >= R.green then return "|cff40c040" end
    if skill >= R.yellow then return "|cffffff00" end
    return "|cffff8040"
end

-- the values at which a recipe is orange (where it starts: only known for recipes with a recipe item), yellow, green and grey, each in its colour
local function SkillBands(R)
    local bands = {}
    bands[#bands + 1] = "|cffff8040" .. (R.orange or "–") .. "|r"
    bands[#bands + 1] = "|cffffff00" .. R.yellow .. "|r"
    bands[#bands + 1] = "|cff40c040" .. R.green .. "|r"
    bands[#bands + 1] = "|cff8a8a8a" .. R.grey .. "|r"
    return table.concat(bands, " · ")
end

-- Where a recipe is learned: from a trainer (known once a trainer window showed it: ns.db.trainerSpells), and/or from a recipe item (a scroll, a
-- pattern, a plan: the data of the game names the item that teaches it). Without either it is a trainer or another way, not confirmed.
local function Trainer(R)
    return ns.db and ns.db.trainerSpells and ns.db.trainerSpells[R.spell] and true or false
end
local function SourceTag(R)
    if Trainer(R) then return "|cff66dbb0" .. L["Trainer"] .. "|r" end
    if R.teach > 0 then return "|cffffa040" .. L["Recipe"] .. "|r" end
    return GREY .. L["Trainer"] .. "?|r"
end
local function SourceText(R)
    local parts = {}
    if Trainer(R) then parts[#parts + 1] = "|cff66dbb0" .. L["Trainer"] .. "|r" end
    if R.teach > 0 then
        local name, q = W.ItemData(R.teach)
        parts[#parts + 1] = "|cffffa040" .. L["Recipe"] .. "|r " .. Coloured(q, "[" .. (name or ("item:" .. R.teach)) .. "]")
    end
    if #parts == 0 then return GREY .. L["Trainer or another way (not confirmed)"] .. "|r" end
    return table.concat(parts, "  ·  ")
end

-- the recipes of the game data, once: { prof, spell, item (0: none), orange (the lowest skill in the data: often just 1), yellow, grey,
-- req (what is shown as the skill it needs: the orange value when the data has one, otherwise the yellow), re = { reagent, count, ... } }
local ALL
local function Recipes()
    if ALL then return ALL end
    ALL = {}
    for prof, recipes in pairs(ns.RecipeDB and ns.RecipeDB.professions or {}) do
        for _, r in ipairs(recipes) do
            ALL[#ALL + 1] = { prof = prof, spell = r[1], item = r[2], orange = (r[8] and r[8] > 0) and r[8] or nil, teach = r[7] or 0, req = (r[3] and r[3] > 1) and r[3] or r[4], yellow = r[4], green = math.floor((r[4] + r[5]) / 2), grey = r[5], re = r[6], key = prof .. ":" .. r[1] }
        end
    end
    return ALL
end

-- the name of a recipe (what it makes, or the spell), kept once it is known
local function NameOf(R)
    if R.name then return R.name end
    local n
    if R.item > 0 then n = W.ItemData(R.item) end
    n = n or SpellName(R.spell)
    if n then R.name = n end
    return n or ("spell:" .. R.spell)
end

-- the text that a search looks in: the name, the profession and the materials (as far as their names are known)
local function SearchText(R)
    if R.text then return R.text end
    local parts, complete = { NameOf(R):lower(), ProfName(R.prof):lower() }, true
    for i = 1, #R.re, 2 do
        local n = W.ItemData(R.re[i])
        if n then parts[#parts + 1] = n:lower() else complete = false end
    end
    local text = table.concat(parts, " ")
    if complete then R.text = text end
    return text
end

-- your characters with a profession, and how far each has got in it (the best first)
local function Skillful(prof)
    local out = {}
    if not (ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled()) then return out end
    local a, b = prof:lower(), ProfName(prof):lower()
    for _, rec in ipairs(ns.Acc.Chars()) do
        for _, sk in ipairs(rec.skills or {}) do
            local n = (sk.name or ""):lower()
            if n == a or n == b then out[#out + 1] = { rec = rec, rank = sk.rank or 0, max = sk.max or 0 } end
        end
    end
    table.sort(out, function(x, y) return x.rank > y.rank end)
    return out
end

-- the characters that know the recipes that make an item
local function KnownByMap()
    local map = {}
    if ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled() then
        for _, e in ipairs(ns.Acc.Recipes()) do
            if e.id then
                local recs = map[e.id] or {}
                for _, rec in ipairs(e.knownBy) do recs[#recs + 1] = rec end
                map[e.id] = recs
            end
        end
    end
    return map
end

-- a small tooltip for a text button (the buttons with a text have none of their own)
local function Tip(btn, text)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(text, 1, 0.85, 0.4)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Build()
    local f = W.NewPlate(UIParent, C.page)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", 100, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:Hide()
    _G.ForeverCompanionItemInfo = f
    tinsert(UISpecialFrames, "ForeverCompanionItemInfo")
    f.hist = {}

    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = close

    -- the strip at the top (under the title bar): start page, back, and the search over all recipes
    local home = W.NewButton(f, L["Start"], 70, 24)
    home:SetPoint("TOPLEFT", f, "TOPLEFT", 56, 24) -- (right of the round icon)
    home:SetScript("OnClick", function() f:Go({ mode = "home" }) end)
    local back = W.NewButton(f, "<", 28, 24)
    back:SetPoint("LEFT", home, "RIGHT", 6, 0)
    back:SetScript("OnClick", function() f:Back() end)
    Tip(back, L["Back"])
    local box = W.NewPlate(f, C.inset)
    box:SetPoint("TOPLEFT", back, "TOPRIGHT", 8, 0)
    box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, 24)
    box:SetHeight(24)
    local mag = box:CreateTexture(nil, "ARTWORK")
    mag:SetSize(14, 14)
    mag:SetPoint("LEFT", 8, 0)
    mag:SetTexture(W.ICON.search)
    mag:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", 28, -4)
    edit:SetPoint("BOTTOMRIGHT", -8, 4)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 28, 0)
    hint:SetTextColor(unpack(C.muted))
    hint:SetText(L["Search recipes or materials…"])
    local syncing = false
    edit:SetScript("OnTextChanged", function(self)
        local q = strtrim(self:GetText() or "")
        hint:SetShown(self:GetText() == "")
        if syncing then return end
        if q == "" then
            if f.state and f.state.mode == "search" then f.state = { mode = "home" }; f:Refresh() end
        elseif f.state and f.state.mode == "search" then
            f.state.query = q
            f:Refresh()
        else
            f:Go({ mode = "search", query = q }, true)
        end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    function f:SetSearchText(text)
        syncing = true
        edit:SetText(text or "")
        hint:SetShown((text or "") == "")
        syncing = false
    end

    -- the header: what the page is about
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("TOPLEFT", 16, -16)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFontObject(UI and UI.titleFontObject or "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -2)
    f.name:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -5)
    f.sub:SetTextColor(unpack(C.muted))
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 16, -62)
    rule:SetPoint("TOPRIGHT", -16, -62)
    rule:SetHeight(1)
    rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

    -- the tabs, down the left: all, then a profession each (the buttons are kept and used again)
    f.tabs, f.pool = {}, {}
    local function Tab(i, label, icon, prof)
        local b = f.pool[i]
        if not b then
            b = W.NewButton(f, "", TABS_W, 28)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -70 - (i - 1) * 32)
            b.pic = b:CreateTexture(nil, "OVERLAY")
            b.pic:SetSize(16, 16)
            b.pic:SetPoint("LEFT", 8, 0)
            b.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetScript("OnClick", function(self) f:ShowTab(self.prof) end)
            f.pool[i] = b
        end
        b.prof = prof
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", icon and 30 or 10, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetText(label)
        b.pic:SetShown(icon ~= nil)
        if icon then b.pic:SetTexture(icon) end
        b:Show()
        return b
    end

    -- your characters with the open profession
    f.chars = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.chars:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X + 2, -70)
    f.chars:SetSize(LIST_W - 4, 30)
    f.chars:SetJustifyH("LEFT")
    f.chars:SetJustifyV("TOP")
    f.chars:SetWordWrap(true)

    -- the list
    local lbox = W.NewPlate(f, C.inset)
    lbox:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -BODY_TOP)
    f.listBox = lbox
    f.lv = UI.NewListView(lbox, LIST_W - 8, WIN_H - BODY_TOP - 12 - 8, ROW_H)
    f.lv.owner = f
    f.lv.frame:SetPoint("TOPLEFT", lbox, "TOPLEFT", 4, -4)

    -- the panel at the bottom: the materials of the chosen recipe
    local d = W.NewPlate(f, C.inset)
    d:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LIST_X, 12)
    d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    d:SetHeight(DETAIL_H)
    d:Hide()
    f.detail = d
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(36, 36)
    d.icon:SetPoint("TOPLEFT", 12, -10)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- the picture of the product has its tooltip too (the item, or the enchantment as the game words it); a click shows the recipes for the item
    local pic = CreateFrame("Button", nil, d)
    pic:SetAllPoints(d.icon)
    pic:SetScript("OnEnter", function(self)
        local R = f.recipe
        if not R then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if R.item > 0 then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. R.item)
            if shown and ns.TipItem then ns.TipItem(GameTooltip, R.item) end
        else
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, R.spell)
        end
        if not shown then GameTooltip:SetText(NameOf(R), 1, 0.85, 0.4) end
        if R.item > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click to see its recipes."], 0.93, 0.74, 0.30)
        end
        GameTooltip:Show()
    end)
    pic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pic:SetScript("OnClick", function() if f.recipe and f.recipe.item > 0 then I.Show(f.recipe.item) end end)
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, 0)
    d.name:SetPoint("RIGHT", d, "RIGHT", -40, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.line = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.line:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    d.line:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.line:SetJustifyH("LEFT")
    d.line:SetWordWrap(false)
    d.line:SetTextColor(unpack(C.muted))
    d.known = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.known:SetPoint("TOPLEFT", d.line, "BOTTOMLEFT", 0, -3)
    d.known:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.known:SetJustifyH("LEFT")
    d.known:SetWordWrap(false)
    -- where it is learned: the line has a tooltip of its own, the one of the recipe item (and what the recipe item teaches)
    d.src = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.src:SetPoint("TOPLEFT", d.known, "BOTTOMLEFT", 0, -3)
    d.src:SetJustifyH("LEFT")
    d.src:SetWordWrap(false)
    d.srcBtn = CreateFrame("Button", nil, d)
    d.srcBtn:SetPoint("TOPLEFT", d.src, "TOPLEFT", 0, 1)
    d.srcBtn:SetHeight(16)
    d.srcBtn:SetScript("OnEnter", function(self)
        local R = f.recipe
        if not (R and R.teach > 0) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. R.teach) then
            if ns.TipItem then ns.TipItem(GameTooltip, R.teach) end
        else
            GameTooltip:SetText(L["Recipe"], 1, 0.85, 0.4)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Teaches"] .. ": " .. NameOf(R), 0.93, 0.74, 0.30)
        GameTooltip:AddLine(ProfName(R.prof) .. "  ·  " .. L["Skill"] .. " " .. R.req, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    d.srcBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.sum = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.sum:SetPoint("BOTTOMLEFT", 12, 9)
    d.sum:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.sum:SetJustifyH("LEFT")
    d.sum:SetWordWrap(false)
    local dclose = W.NewButton(d, "×", 20, 20, "GameFontNormal")
    dclose:SetPoint("TOPRIGHT", -8, -8)
    dclose:SetScript("OnClick", function() f:CloseDetail() end)
    Tip(dclose, L["Close"])
    d.cards = {}
    local function Card(i)
        local c = d.cards[i]
        if c then return c end
        c = CreateFrame("Button", nil, d)
        c:SetSize(CARD_W, 44)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bg:SetColorTexture(1, 1, 1, 0.04)
        c.hl = c:CreateTexture(nil, "BORDER")
        c.hl:SetAllPoints()
        c.hl:SetTexture(W.HILITE_TEX)
        c.hl:SetBlendMode("ADD")
        c.hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
        c.hl:SetAlpha(0)
        c.edge = c:CreateTexture(nil, "ARTWORK")
        c.edge:SetSize(34, 34)
        c.edge:SetPoint("LEFT", 5, 0)
        c.icon = c:CreateTexture(nil, "OVERLAY")
        c.icon:SetPoint("TOPLEFT", c.edge, 1, -1)
        c.icon:SetPoint("BOTTOMRIGHT", c.edge, -1, 1)
        c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.name:SetPoint("TOPLEFT", c.edge, "TOPRIGHT", 6, -3)
        c.name:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        c.name:SetJustifyH("LEFT")
        c.name:SetWordWrap(false)
        c.have = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.have:SetPoint("BOTTOMLEFT", c.edge, "BOTTOMRIGHT", 6, 3)
        c.have:SetJustifyH("LEFT")
        c:SetScript("OnEnter", function(self)
            self.hl:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id) then GameTooltip:SetText(tostring(self.id)) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click to see its recipes."], 0.93, 0.74, 0.30)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function(self) self.hl:SetAlpha(0); GameTooltip:Hide() end)
        c:SetScript("OnClick", function(self) if self.id then I.Show(self.id) end end)
        d.cards[i] = c
        return c
    end

    -- the list and the panel share the height: the panel takes its room at the bottom when it is open
    function f:Layout()
        local extra = d:IsShown() and (DETAIL_H + 8) or 0
        lbox:ClearAllPoints()
        lbox:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -BODY_TOP)
        lbox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12 + extra)
        self.lv:Resize(WIN_H - BODY_TOP - 12 - extra - 8)
    end

    function f:CloseDetail()
        self.recipe = nil
        d:Hide()
        self:Layout()
        self.lv:SetData(self.entries or {}, nil, self.onSelect, self.emptyText)
    end

    -- the materials of a recipe: what is needed, what your characters have of it (bags and bank), what it costs and what it brings
    function f:ShowDetail(R)
        self.recipe = R
        local pname, q, icon
        if R.item > 0 then pname, q, icon = W.ItemData(R.item) end
        d.icon:SetTexture(icon or ProfIcon(R.prof) or BOOK_ICON)
        d.name:SetText(Coloured(q, NameOf(R)))
        d.line:SetText(ProfName(R.prof) .. "  ·  " .. L["Skill"] .. ": " .. "|cffff8040" .. (R.orange or "–") .. "|r  " .. "|cffffff00" .. R.yellow .. "|r  |cff40c040" .. R.green .. "|r  |cff8a8a8a" .. R.grey .. "|r")
        local recs = R.item > 0 and self.knownBy[R.item] or nil
        if recs and #recs > 0 then
            local names = {}
            for _, rec in ipairs(recs) do names[#names + 1] = ClassName(rec) end
            d.known:SetText(L["Known by"] .. ": " .. table.concat(names, ", "))
        elseif ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled() then
            d.known:SetText(GREY .. L["Not known"] .. "|r")
        else
            d.known:SetText("")
        end
        d.src:SetText(L["Learned from"] .. ": " .. SourceText(R))
        d.srcBtn:SetWidth(math.max(20, d.src:GetStringWidth()))
        d.srcBtn:SetShown(R.teach > 0)
        if R.teach > 0 and not W.ItemData(R.teach) and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, R.teach); C_Timer.After(1.2, function() if d:IsShown() and self.recipe == R then self:ShowDetail(R) end end) end
        local have = (ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled() and ns.Acc.Holdings) and ns.Acc.Holdings(nil, true, true, false) or nil
        local cost, missing = 0, false
        local n = 0
        for i = 1, #R.re, 2 do
            n = n + 1
            if n > 10 then break end
            local id, need = R.re[i], R.re[i + 1]
            local c = Card(n)
            local rname, rq, ricon = W.ItemData(id)
            if not rname and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id); missing = true end
            c.id = id
            c.icon:SetTexture(ricon or W.ItemTexture(id))
            local qc = W.QUALITY_COLOR[rq or 1] or W.QUALITY_COLOR[1]
            c.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
            c.name:SetText(Coloured(rq, rname or ("item:" .. id)))
            local own = have and (have[id] or 0)
            c.have:SetText("×" .. need .. (own and ("   " .. (own >= need and JADE or "|cffe86a5a") .. L["Have"] .. " " .. own .. "|r") or ""))
            local col, row = (n - 1) % CARD_COLS, math.floor((n - 1) / CARD_COLS)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", d, "TOPLEFT", 12 + col * (CARD_W + 6), -(82 + row * 50))
            c:Show()
            cost = cost + (ns.Value.Get(id) or 0) * need
        end
        for i = n + 1, #d.cards do d.cards[i]:Hide() end
        local value = R.item > 0 and (ns.Value.Get(R.item) or 0) or 0
        local parts = {}
        if cost > 0 then parts[#parts + 1] = L["Cost of materials"] .. ": " .. ns.Value.Format(cost) end
        if value > 0 then
            parts[#parts + 1] = L["Worth"] .. ": " .. ns.Value.Format(value)
            if cost > 0 then
                local gain = value - cost
                parts[#parts + 1] = L["Gain"] .. ": " .. ns.Value.Format(math.abs(gain), gain >= 0 and "|cff66dbb0" or "|cffe86a5a")
            end
        end
        d.sum:SetText(table.concat(parts, "     "))
        d:Show()
        self:Layout()
        self.lv:SetData(self.entries or {}, R.key, self.onSelect, self.emptyText)
        if missing then
            C_Timer.After(1.2, function() if d:IsShown() and self.recipe == R then self:ShowDetail(R) end end)
        end
    end

    -- one recipe as a row
    local function RowOf(R, need, best, tracking, kind)
        local pname, q
        if R.item > 0 then pname, q = W.ItemData(R.item) end
        local recs = R.item > 0 and f.knownBy[R.item] or nil
        local skill = best[R.prof] or 0
        local right2, names
        if recs and #recs > 0 then
            names = {}
            for _, rec in ipairs(recs) do names[#names + 1] = ClassName(rec) end
            right2 = names[1] .. (#recs > 1 and (" " .. GREY .. "+" .. (#recs - 1) .. "|r") or "")
        end
        return {
            key = R.key, R = R, name = pname or NameOf(R), quality = q or 1,
            itemID = R.item > 0 and R.item or nil, texture = ProfIcon(R.prof),
            sub = ProfName(R.prof) .. "  ·  " .. L["Skill"] .. " " .. SkillBands(R) .. "  ·  " .. SourceTag(R),
            right = need and ("×" .. need) or "",
            right2 = right2 or (tracking and L["Not known"] or ""),
            plain = pname or NameOf(R), names = names, spell = R.spell,
            tip = function(en)
                if not pcall(GameTooltip.SetSpellByID, GameTooltip, en.spell) then GameTooltip:SetText(en.plain or "") end
                if en.names then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["Known by"] .. ": " .. table.concat(en.names, ", "), 1, 1, 1, true)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click for the materials."], 0.93, 0.74, 0.30)
            end,
        }
    end

    -- the results of the page: { R, kind (1 makes it, 2 uses it), need } for an item; all that match for a search; all for the start page
    local function Results(state)
        local out = {}
        if state.mode == "item" then
            local id = state.id
            for _, R in ipairs(Recipes()) do
                local need
                for i = 1, #R.re, 2 do if R.re[i] == id then need = R.re[i + 1] end end
                if need then out[#out + 1] = { R = R, kind = 2, need = need } end
                if R.item == id then out[#out + 1] = { R = R, kind = 1 } end
            end
            table.sort(out, function(a, b)
                if a.kind ~= b.kind then return a.kind < b.kind end
                if a.R.prof ~= b.R.prof then return a.R.prof < b.R.prof end
                if a.R.req ~= b.R.req then return a.R.req < b.R.req end
                return a.R.spell < b.R.spell
            end)
        elseif state.mode == "search" then
            local words = {}
            for w in (state.query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
            for _, R in ipairs(Recipes()) do
                local text = SearchText(R)
                local hit = true
                for _, w in ipairs(words) do if not text:find(w, 1, true) then hit = false break end end
                if hit then out[#out + 1] = { R = R, kind = 0 } end
            end
            table.sort(out, function(a, b)
                if a.R.prof ~= b.R.prof then return a.R.prof < b.R.prof end
                if a.R.req ~= b.R.req then return a.R.req < b.R.req end
                return NameOf(a.R) < NameOf(b.R)
            end)
        else
            for _, R in ipairs(Recipes()) do out[#out + 1] = { R = R, kind = 0 } end
            -- by the skill needed (the lowest first), then by name
            table.sort(out, function(a, b)
                if a.R.prof ~= b.R.prof then return a.R.prof < b.R.prof end
                if a.R.req ~= b.R.req then return a.R.req < b.R.req end
                return NameOf(a.R) < NameOf(b.R)
            end)
        end
        return out
    end

    function f:ShowTab(prof)
        if not self.state then return end
        self.state.prof = prof
        self:Refresh()
    end

    function f:Go(state, keepSearch)
        if self.state then
            self.hist[#self.hist + 1] = self.state
            if #self.hist > 30 then table.remove(self.hist, 1) end
        end
        self.state = state
        if not keepSearch then self:SetSearchText(state.mode == "search" and state.query or "") end
        self:Refresh()
    end

    function f:Back()
        local s = table.remove(self.hist)
        if not s then return end
        self.state = s
        self:SetSearchText(s.mode == "search" and s.query or "")
        self:Refresh()
    end

    -- the whole page, from its state: { mode = "home" | "item" | "search", id, query, prof }
    function f:Refresh()
        local state = self.state or { mode = "home" }
        self.state = state
        back:SetAlpha(#self.hist > 0 and 1 or 0.4)
        self.knownBy = KnownByMap()
        local results = Results(state)

        -- the header
        local total, profs = #results, 0
        local perProf, order = {}, {}
        for _, e in ipairs(results) do
            if not perProf[e.R.prof] then perProf[e.R.prof] = 0; order[#order + 1] = e.R.prof end
            perProf[e.R.prof] = perProf[e.R.prof] + 1
        end
        profs = #order
        if state.mode == "item" then
            local name, q, icon = W.ItemData(state.id)
            if not name and C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, state.id)
                C_Timer.After(1, function() if self:IsShown() and self.state == state then self:Refresh() end end)
            end
            icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(state.id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
            self.icon:SetTexture(icon)
            self.name:SetText(Coloured(q, name or ("item:" .. state.id)))
            local nMade, nUsed = 0, 0
            for _, e in ipairs(results) do if e.kind == 1 then nMade = nMade + 1 else nUsed = nUsed + 1 end end
            self.sub:SetText((L["%d recipes use it, %d make it"]):format(nUsed, nMade))
        elseif state.mode == "search" then
            self.icon:SetTexture(W.ICON.search)
            self.name:SetText(L["Search"] .. ": " .. (state.query or ""))
            self.sub:SetText((L["%d recipes found"]):format(total))
        else
            self.icon:SetTexture(BOOK_ICON)
            self.name:SetText(L["Recipes"])
            self.sub:SetText((L["%d recipes in %d professions"]):format(total, profs))
        end

        -- the tabs: all, and the professions of the results
        table.sort(order, function(a, b) return ProfName(a) < ProfName(b) end)
        if state.prof and not perProf[state.prof] then state.prof = nil end
        for _, b in ipairs(self.pool) do b:Hide() end
        wipe(self.tabs)
        self.tabs[1] = Tab(1, (state.mode == "home" and L["All"] or L["All"]) .. " " .. GREY .. total .. "|r", nil, nil)
        for i, prof in ipairs(order) do
            if i > MAX_TABS - 1 then break end
            self.tabs[i + 1] = Tab(i + 1, ProfName(prof) .. " " .. GREY .. perProf[prof] .. "|r", ProfIcon(prof), prof)
        end
        for _, t in ipairs(self.tabs) do t:SetSelected(t.prof == state.prof) end

        -- your characters with the open profession
        if state.prof then
            local people = Skillful(state.prof)
            if #people == 0 then
                self.chars:SetText(GREY .. L["None of your characters has this profession."] .. "|r")
            else
                local parts = {}
                for _, p in ipairs(people) do parts[#parts + 1] = ClassName(p.rec) .. " " .. GREY .. p.rank .. "/" .. p.max .. "|r" end
                self.chars:SetText(L["Your characters with it"] .. ": " .. table.concat(parts, "   "))
            end
        else
            self.chars:SetText("")
        end

        -- the best skill of any of your characters in each profession (a skill is green when one of them has got that far)
        local best = {}
        for _, prof in ipairs(order) do
            local people = Skillful(prof)
            best[prof] = people[1] and people[1].rank or 0
        end
        local tracking = ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled()

        local entries = {}
        if state.mode == "home" and not state.prof then
            -- the start page: the professions, with your best character in each
            for _, prof in ipairs(order) do
                local people = Skillful(prof)
                local top = people[1]
                entries[#entries + 1] = { key = "p:" .. prof, prof = prof, name = ProfName(prof), texture = ProfIcon(prof),
                    sub = (L["%d recipes"]):format(perProf[prof]),
                    right = top and (ClassName(top.rec)) or "", right2 = top and (GREY .. top.rank .. "/" .. top.max .. "|r") or "" }
            end
            self.emptyText = L["Nothing to show."]
        else
            local lastKind, lastProf, shown = nil, nil, 0
            for _, e in ipairs(results) do
                if not state.prof or e.R.prof == state.prof then
                    shown = shown + 1
                    if shown > MAX_ROWS then
                        entries[#entries + 1] = { key = "more", noIcon = true, name = GREY .. L["Narrow the search to see more."] .. "|r" }
                        break
                    end
                    if state.mode == "item" and (e.kind ~= lastKind or (not state.prof and e.R.prof ~= lastProf)) then
                        lastKind, lastProf = e.kind, e.R.prof
                        local head = e.kind == 1 and L["Recipes that make it"] or L["Recipes that use it"]
                        if not state.prof then head = head .. "  " .. GREY .. ProfName(e.R.prof) .. "|r" end
                        entries[#entries + 1] = { key = "h" .. #entries, noIcon = true, name = "|cffffd100" .. head .. "|r" }
                    end
                    entries[#entries + 1] = RowOf(e.R, e.need, best, tracking, e.kind)
                end
            end
            self.emptyText = state.mode == "search" and L["No recipe matches."] or L["Nothing to show."]
        end
        self.entries = entries
        self.onSelect = function(en)
            if en.R then
                if self.recipe == en.R then self:CloseDetail() else self:ShowDetail(en.R) end
            elseif en.prof then
                self:ShowTab(en.prof)
            end
        end
        if self.recipe and not (perProf[self.recipe.prof] and (not state.prof or state.prof == self.recipe.prof)) then
            self.recipe = nil
            d:Hide()
            self:Layout()
        end
        self.lv:ScrollToTop()
        self.lv:SetData(entries, self.recipe and self.recipe.key or nil, self.onSelect, self.emptyText)
        if self.recipe then self:ShowDetail(self.recipe) end
    end

    -- position and size (scale) are kept; the grip in the corner scales the window (shift + right-click: the default scale)
    local function Save()
        if not ns.db then return end
        local point, _, rel, px, py = f:GetPoint()
        ns.db.recipeWin = { pos = { point, rel, px, py }, scale = f:GetScale() }
    end
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Save() end)
    local saved = ns.db and ns.db.recipeWin
    if saved then
        f:SetScale(math.max(0.6, math.min(1.6, saved.scale or 1)))
        if saved.pos and saved.pos[1] then
            f:ClearAllPoints()
            f:SetPoint(saved.pos[1], UIParent, saved.pos[2] or saved.pos[1], saved.pos[3] or 0, saved.pos[4] or 0)
        end
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 50)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    W.AttachScaleGrip(f, grip, { scaleOnly = true, minScale = 0.6, maxScale = 1.6, gridScale = 0.05, topInset = 54,
        saveScale = Save, savePos = Save })

    f:Layout()
    return f
end

-- the spells that trainers teach are noted as their windows are seen (the game does not say it otherwise)
local trainerWatch = CreateFrame("Frame")
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do pcall(trainerWatch.RegisterEvent, trainerWatch, e) end
trainerWatch:SetScript("OnEvent", function()
    if not (ns.db and GetNumTrainerServices and GetTrainerServiceItemLink) then return end
    local seen = ns.db.trainerSpells
    if not seen then seen = {}; ns.db.trainerSpells = seen end
    for i = 1, GetNumTrainerServices() or 0 do
        local ok, link = pcall(GetTrainerServiceItemLink, i)
        local id = ok and link and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
        if id then seen[id] = true end
    end
end)

local frame

-- the window style of the settings: the game's own frame, or the plate (the same as the other windows)
function I.ApplyFrameStyle()
    if not frame then return end
    local blizz = W.BlizzSkin(frame, true, BOOK_ICON, L["Recipes"], "recipes")
    if blizz then
        frame:SetBackdrop(nil)
    else
        frame:SetBackdrop(W.PLATE_BACKDROP)
        frame:SetBackdropColor(unpack(C.page))
        frame:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    end
end

local function Open()
    if not frame then frame = Build(); I.ApplyFrameStyle() end
    -- like the other windows (a click on one brings it to the front); only above the game's auction house while that is open (it is opened from there)
    frame:SetFrameStrata((AuctionHouseFrame and AuctionHouseFrame:IsShown()) and "DIALOG" or "MEDIUM")
    frame:Show()
    frame:Raise()
    return frame
end

-- the recipes that make or use an item
function I.Show(id)
    if not id then return end
    local f = Open()
    f.recipe = nil
    f.detail:Hide()
    f:Layout()
    f:Go({ mode = "item", id = id })
end

-- the start page
function I.Home()
    local f = Open()
    f.recipe = nil
    f.detail:Hide()
    f:Layout()
    f:Go({ mode = "home" })
end

function I.Toggle()
    if frame and frame:IsShown() then frame:Hide() else I.Home() end
end

SLASH_FOREVERCOMPANIONRECIPES1 = "/fcrecipes"
SlashCmdList.FOREVERCOMPANIONRECIPES = function() I.Toggle() end
