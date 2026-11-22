local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C

-- A small window about one item: which professions use it as a material or make it (a tab for each, down the left), the recipes
-- of the open tab as rows like the ones in the loot journal, the skill each needs and which of your characters know it, and which
-- of your characters have the profession and how far. The recipes come from the recipe data of the game (Data/Recipes.lua).
-- It opens from the context menu of the tables in the auction house tab (ns.ItemInfo.Show(itemId)).

local I = {}
ns.ItemInfo = I

local WIN_W, WIN_H = 640, 500
local TABS_W = 130
local LIST_X = 12 + TABS_W + 10
local LIST_W = WIN_W - LIST_X - 12
local TOP = 80
local CHARS_H = 32
local ROW_H = 44
local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GREY, JADE = "|cff8a806e", "|cff66dbb0"

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

-- what is known: the recipes that use or make the item (per profession), and what your characters know
local function Collect(id)
    local profs, list = {}, {}
    for prof, recipes in pairs(ns.RecipeDB and ns.RecipeDB.professions or {}) do
        for _, r in ipairs(recipes) do
            local spell, item, low, re = r[1], r[2], r[4], r[6]
            local need
            for i = 1, #re, 2 do if re[i] == id then need = re[i + 1] end end
            if need or item == id then
                local p = profs[prof] or { name = prof, used = 0, made = 0 }
                profs[prof] = p
                if need then p.used = p.used + 1 end
                if item == id then p.made = p.made + 1 end
                if need then list[#list + 1] = { kind = 2, prof = prof, spell = spell, item = item, low = low, need = need } end
                if item == id then list[#list + 1] = { kind = 1, prof = prof, spell = spell, item = item, low = low } end
            end
        end
    end
    local tabs = {}
    for _, p in pairs(profs) do tabs[#tabs + 1] = p end
    table.sort(tabs, function(a, b)
        local x, y = a.used + a.made, b.used + b.made
        if x ~= y then return x > y end
        return a.name < b.name
    end)
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.prof ~= b.prof then return a.prof < b.prof end
        if a.low ~= b.low then return a.low < b.low end
        return a.spell < b.spell
    end)
    local knownBy = {}
    if ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled() then
        for _, e in ipairs(ns.Acc.Recipes()) do
            if e.id then
                local recs = knownBy[e.id] or {}
                for _, rec in ipairs(e.knownBy) do recs[#recs + 1] = rec end
                knownBy[e.id] = recs
            end
        end
    end
    return tabs, list, knownBy
end

-- your characters with a profession, and how far each has got in it (the best first)
local function Skillful(prof)
    local out = {}
    if not (ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled()) then return out end
    local a, b = prof:lower(), (L[prof] or prof):lower()
    for _, rec in ipairs(ns.Acc.Chars()) do
        for _, sk in ipairs(rec.skills or {}) do
            local n = (sk.name or ""):lower()
            if n == a or n == b then out[#out + 1] = { rec = rec, rank = sk.rank or 0, max = sk.max or 0 } end
        end
    end
    table.sort(out, function(x, y) return x.rank > y.rank end)
    return out
end

local function Build()
    local f = W.NewPlate(UIParent, C.page)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", 140, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    _G.ForeverCompanionItemInfo = f
    tinsert(UISpecialFrames, "ForeverCompanionItemInfo")

    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = close

    -- the item
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("TOPLEFT", 16, -14)
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
    rule:SetPoint("TOPLEFT", 16, -68)
    rule:SetPoint("TOPRIGHT", -16, -68)
    rule:SetHeight(1)
    rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

    -- the tabs, down the left: all, then a profession each (the buttons are kept and used again)
    f.tabs, f.pool = {}, {}
    local function Tab(i, label, icon, prof)
        local b = f.pool[i]
        if not b then
            b = W.NewButton(f, "", TABS_W, 28)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -TOP - (i - 1) * 32)
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
    f.chars:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X + 2, -TOP)
    f.chars:SetSize(LIST_W - 4, CHARS_H)
    f.chars:SetJustifyH("LEFT")
    f.chars:SetJustifyV("TOP")
    f.chars:SetWordWrap(true)

    -- the list
    local box = W.NewPlate(f, C.inset)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -(TOP + CHARS_H + 6))
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    f.lv = UI.NewListView(box, LIST_W - 8, WIN_H - TOP - CHARS_H - 6 - 12 - 8, ROW_H)
    f.lv.owner = f
    f.lv.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)

    function f:ShowTab(prof)
        self.tab = prof
        for _, t in ipairs(self.tabs) do t:SetSelected(t.prof == prof) end
        if prof then
            local people = Skillful(prof)
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
        for _, t in ipairs(self.tabInfo or {}) do
            local people = Skillful(t.name)
            best[t.name] = people[1] and people[1].rank or 0
        end
        local tracking = ns.Acc and ns.Acc.Enabled and ns.Acc.Enabled()
        local entries, lastKind, lastProf = {}, nil, nil
        for _, e in ipairs(self.list or {}) do
            if not prof or e.prof == prof then
                if e.kind ~= lastKind or (not prof and e.prof ~= lastProf) then
                    lastKind, lastProf = e.kind, e.prof
                    local head = e.kind == 1 and L["Recipes that make it"] or L["Recipes that use it"]
                    if not prof then head = head .. "  " .. GREY .. (L[e.prof] or e.prof) .. "|r" end
                    entries[#entries + 1] = { key = "h" .. #entries, noIcon = true, name = "|cffffd100" .. head .. "|r" }
                end
                local pname, q
                if e.item > 0 then
                    pname, q = W.ItemData(e.item)
                end
                local rname = pname or SpellName(e.spell) or ("spell:" .. e.spell)
                local recs = e.item > 0 and self.knownBy[e.item] or nil
                local ok = (best[e.prof] or 0) >= e.low
                local right2, names
                if recs and #recs > 0 then
                    names = {}
                    for _, rec in ipairs(recs) do names[#names + 1] = ClassName(rec) end
                    right2 = names[1] .. (#recs > 1 and (" " .. GREY .. "+" .. (#recs - 1) .. "|r") or "")
                end
                entries[#entries + 1] = {
                    key = e.kind .. ":" .. e.spell, name = rname, quality = q or 1,
                    itemID = e.item > 0 and e.item or nil, texture = ProfIcon(e.prof),
                    sub = (L[e.prof] or e.prof) .. "  ·  " .. L["Skill"] .. " " .. (ok and JADE or GREY) .. e.low .. "|r",
                    right = e.need and ("×" .. e.need) or "",
                    right2 = right2 or (tracking and L["Not known"] or ""),
                    spell = e.spell, plain = rname, names = names,
                    tip = function(en)
                        if not pcall(GameTooltip.SetSpellByID, GameTooltip, en.spell) then GameTooltip:SetText(en.plain or "") end
                        if en.names then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(L["Known by"] .. ": " .. table.concat(en.names, ", "), 1, 1, 1, true)
                        end
                    end,
                }
            end
        end
        self.lv:ScrollToTop()
        self.lv:SetData(entries, nil, nil, L["Nothing to show."])
    end

    function f:SetItem(id)
        self.id = id
        local name, q, icon = W.ItemData(id)
        if not name and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
            C_Timer.After(1, function() if self:IsShown() and self.id == id then self:SetItem(id) end end)
        end
        icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        self.icon:SetTexture(icon)
        self.name:SetText(Coloured(q, name or ("item:" .. id)))
        local tabs, list, knownBy = Collect(id)
        self.list, self.knownBy, self.tabInfo = list, knownBy, tabs
        local nUsed, nMade = 0, 0
        for _, t in ipairs(tabs) do nUsed, nMade = nUsed + t.used, nMade + t.made end
        self.sub:SetText((L["%d recipes use it, %d make it"]):format(nUsed, nMade))
        for _, b in ipairs(self.pool) do b:Hide() end
        wipe(self.tabs)
        self.tabs[1] = Tab(1, L["All"] .. " " .. GREY .. (nUsed + nMade) .. "|r", nil, nil)
        for i, t in ipairs(tabs) do
            if i > 12 then break end
            self.tabs[i + 1] = Tab(i + 1, (L[t.name] or t.name) .. " " .. GREY .. (t.used + t.made) .. "|r", ProfIcon(t.name), t.name)
        end
        self:ShowTab(nil)
    end
    return f
end

local frame

-- the window style of the settings: the game's own frame, or the plate (the same as the other windows)
function I.ApplyFrameStyle()
    if not frame then return end
    local blizz = W.BlizzSkin(frame, true, nil, L["Recipes"])
    if blizz then
        frame:SetBackdrop(nil)
    else
        frame:SetBackdrop(W.PLATE_BACKDROP)
        frame:SetBackdropColor(unpack(C.page))
        frame:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    end
end

function I.Show(id)
    if not id then return end
    if not frame then frame = Build(); I.ApplyFrameStyle() end
    frame:SetItem(id)
    frame:Show()
    frame:Raise()
end
