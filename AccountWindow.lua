local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C

-- The account window: all your characters at a glance (level, race, class, professions, money,
-- time played ...) and, for each of them, equipment, bags and bank, professions with their
-- recipes, mail and auctions. A search finds an item on every character. What is shown is what
-- the account data (Account.lua) has read so far; every part says how old it is, or what to do
-- to have it read.

local AW = {}
ns.AccountWindow = AW

local DEFAULT_W, DEFAULT_H = 1300, 720
local MIN_W, MIN_H, MAX_W, MAX_H = 900, 460, 2400, 1500
-- (the Blizzard frame: the toolbar sits in the strip under the title bar, above the window's top edge, right of the ring with the icon;
-- the plates begin right below it)
local EDGE, BAR_TOP, MAP_TOP, BOTTOM = 8, -24, 8, 16
local LIST_W = 214
local ROW_H = 24

local MUTED = W.Hex(C.muted)
local GOLD = W.Hex(C.gold)
local AMBER = "|cffeda65f"
local JADE = "|cff66dbb0"
local RED = "|cffe86a5a"

local view = { mode = "all", key = nil, tab = "overview", inv = "bags", prof = nil, query = "", itemFilter = "all",
    onlyCraftable = false, allView = "overview", hideBound = false, hideBoundAll = true, hideBoP = false, hideBoPAll = true, hideQuest = true, hiddenChars = {},
    craftOpt = { profit = true }, craftCat = "all", craftRarity = {}, craftSlots = {},
    rarity = {}, slots = {}, craftProfs = {} } -- rarity, slots, craftProfs: sets of what is shown (empty: all)
local dirty = true

-- helpers -------------------------------------------------------------------------------------
local function ClassColor(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.85, 0.7
end
local function ClassHex(class)
    local r, g, b = ClassColor(class)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
local function ClassIcon(class)
    local t = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    return "Interface\\WorldStateFrame\\Icons-Classes", t
end
local function Money(copper, tint)
    copper = copper or 0
    local s = ns.Value.Format(copper, tint)
    return s ~= "" and s or (MUTED .. "0|r")
end
local function Played(sec)
    if not sec then return MUTED .. "–|r" end
    local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    return ("%dh %02dm"):format(h, m)
end
-- how long ago, short: "5 min", "3 h", "2 d" (no "ago": it only makes the columns too narrow)
local function Ago(t)
    if not t then return MUTED .. "–|r" end
    local d = math.max(0, time() - t)
    if d < 60 then return L["now"] end
    if d < 3600 then return ("%d min"):format(math.floor(d / 60)) end
    if d < 86400 then return ("%d h"):format(math.floor(d / 3600)) end
    return ("%d d"):format(math.floor(d / 86400))
end
local function ItemIcon(link_or_id)
    local get = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if not get then return nil end
    local ok, _, _, _, _, icon = pcall(get, link_or_id)
    return ok and icon or nil
end
local function Rec() return view.key and ns.db.account and ns.db.account.chars[view.key] end

-- item filters (shared by the account-wide item list and a character's bags): rarity, slot,
-- soulbound and quest items
local QUALITY_BY_HEX = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6 }
local infoCache = {}
local function BindType(id)
    local get = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if not get then return nil end
    local ok, bind = pcall(function() return (select(14, get(id))) end)
    if ok and bind ~= nil then return bind end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return nil
end

local function ItemGroupOf(id)
    local get = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    local classID
    if get then
        local ok, cls = pcall(function() return (select(6, get(id))) end)
        if ok then classID = cls end
    end
    if classID == 7 or classID == 5 then return "mat" end
    if classID == 0 then return "cons" end
    if classID == 2 or classID == 4 then return "gear" end
    return "other"
end

local function ItemFacts(id)
    local c = infoCache[id]
    if c then
        if c.bind == nil then c.bind = BindType(id) end
        return c
    end
    local get = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    local equipLoc, classID
    if get then
        local ok, _, _, _, loc, _, cls = pcall(get, id)
        if ok then equipLoc, classID = loc, cls end
    end
    local hex = ns.Acc.LinkOf(id):match("|cff(%x%x%x%x%x%x)")
    c = { equipLoc = equipLoc, classID = classID, quality = QUALITY_BY_HEX[hex or ""] or 1, bind = BindType(id) }
    if classID then infoCache[id] = c end
    return c
end

local function RarityName(q)
    local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or ""
    return hex .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or q) .. "|r"
end

local PD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
-- the slots to pick from, in groups: { id, label, picture, item locations ... }
local SLOT_GROUPS = {
    { L["Armor"],
        { "head", _G.INVTYPE_HEAD, PD .. "Head", "INVTYPE_HEAD" },
        { "shoulder", _G.INVTYPE_SHOULDER, PD .. "Shoulder", "INVTYPE_SHOULDER" },
        { "chest", _G.INVTYPE_CHEST, PD .. "Chest", "INVTYPE_CHEST", "INVTYPE_ROBE" },
        { "wrist", _G.INVTYPE_WRIST, PD .. "Wrists", "INVTYPE_WRIST" },
        { "hands", _G.INVTYPE_HAND, PD .. "Hands", "INVTYPE_HAND" },
        { "waist", _G.INVTYPE_WAIST, PD .. "Waist", "INVTYPE_WAIST" },
        { "legs", _G.INVTYPE_LEGS, PD .. "Legs", "INVTYPE_LEGS" },
        { "feet", _G.INVTYPE_FEET, PD .. "Feet", "INVTYPE_FEET" },
        { "back", _G.INVTYPE_CLOAK, PD .. "Back", "INVTYPE_CLOAK" } },
    { L["Jewelry"],
        { "neck", _G.INVTYPE_NECK, PD .. "Neck", "INVTYPE_NECK" },
        { "finger", _G.INVTYPE_FINGER, PD .. "Finger", "INVTYPE_FINGER" },
        { "trinket", _G.INVTYPE_TRINKET, PD .. "Trinket", "INVTYPE_TRINKET" } },
    { L["Weapons"],
        { "weapon", L["Weapons"], PD .. "MainHand", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
            "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" },
        { "offhand", L["Shield & held"], PD .. "SecondaryHand", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
    { L["Other"], { "bag", L["Bags"], PD .. "Bag", "INVTYPE_BAG", "INVTYPE_QUIVER" } },
}
local SLOT_BY_ID = {}
for _, group in ipairs(SLOT_GROUPS) do
    for i = 2, #group do SLOT_BY_ID[group[i][1]] = group[i] end
end

local function Count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function HideBoPOn()
    if view.mode == "items" then return view.hideBoPAll end
    return view.hideBoP
end

local function HideBoundOn()
    if view.mode == "items" then return view.hideBoundAll end
    return view.hideBound
end

-- does this item pass the filters? tradable: how many of it are not soulbound
local function PassesFilters(id, tradable)
    local facts = ItemFacts(id)
    if view.hideQuest and facts.classID == 12 then return false end
    if HideBoundOn() and (tradable or 1) <= 0 then return false end
    if HideBoPOn() and facts.bind == 1 then return false end
    if next(view.rarity) and not view.rarity[facts.quality] then return false end
    if next(view.slots) then
        local ok = false
        for key in pairs(view.slots) do
            local def = SLOT_BY_ID[key]
            for i = 4, #def do if facts.equipLoc == def[i] then ok = true end end
        end
        if not ok then return false end
    end
    return true
end

-- the menus ---------------------------------------------------------------------------------------------------------
local menu -- the context menu (made with the window)
local function State(on) return on and "all" or "none" end

local function RarityMenu(set)
    local rows = {}
    for q = 0, 5 do
        rows[#rows + 1] = { kind = "check", state = State(set[q]), label = RarityName(q),
            onClick = function() set[q] = (not set[q]) or nil; dirty = true end }
    end
    rows[#rows + 1] = { kind = "separator" }
    rows[#rows + 1] = { kind = "action", label = L["Show all"], onClick = function() wipe(set); dirty = true end }
    return rows
end

local function SlotMenu(set)
    local rows = {}
    for gi, group in ipairs(SLOT_GROUPS) do
        if gi > 1 then rows[#rows + 1] = { kind = "separator" } end
        rows[#rows + 1] = { kind = "header", label = group[1] }
        for i = 2, #group do
            local def = group[i]
            rows[#rows + 1] = { kind = "check", state = State(set[def[1]]), label = def[2], icon = def[3],
                onClick = function() set[def[1]] = (not set[def[1]]) or nil; dirty = true end }
        end
    end
    rows[#rows + 1] = { kind = "separator" }
    rows[#rows + 1] = { kind = "action", label = L["Show all"], onClick = function() wipe(set); dirty = true end }
    return rows
end

local function HideMenu()
    return {
        { kind = "check", state = State(HideBoundOn()), label = L["Soulbound"], icon = "Interface\\Icons\\INV_Misc_Key_03",
            onClick = function()
                if view.mode == "items" then view.hideBoundAll = not view.hideBoundAll else view.hideBound = not view.hideBound end
                dirty = true
            end },
        { kind = "check", state = State(HideBoPOn()), label = L["Bind on pickup"], icon = "Interface\\Icons\\INV_Misc_Key_04",
            onClick = function()
                if view.mode == "items" then view.hideBoPAll = not view.hideBoPAll else view.hideBoP = not view.hideBoP end
                dirty = true
            end },
        { kind = "check", state = State(view.hideQuest), label = L["Quest items"], icon = "Interface\\Icons\\INV_Misc_Note_01",
            onClick = function() view.hideQuest = not view.hideQuest; dirty = true end },
    }
end

-- does the item a recipe makes pass the filters of the crafting view? (no item: only when none is set)
local function RecipePasses(r)
    local category = view.craftCat ~= "all"
    local rarity, slots = next(view.craftRarity), next(view.craftSlots)
    if not r.id then return not (category or rarity or slots) end
    local facts = ItemFacts(r.id)
    if category and ItemGroupOf(r.id) ~= view.craftCat then return false end
    if rarity and not view.craftRarity[facts.quality] then return false end
    if slots then
        local ok = false
        for key in pairs(view.craftSlots) do
            local def = SLOT_BY_ID[key]
            for i = 4, #def do if facts.equipLoc == def[i] then ok = true end end
        end
        if not ok then return false end
    end
    return true
end

-- which characters' belongings are counted
local function CharsMenu()
    local rows = {}
    for _, rec in ipairs(ns.Acc.Chars()) do
        local tex, coords = ClassIcon(rec.class)
        rows[#rows + 1] = { kind = "check", state = State(not view.hiddenChars[rec.key]),
            label = ClassHex(rec.class) .. ns.Acc.NameOf(rec) .. "|r", icon = tex, coords = coords,
            onClick = function() view.hiddenChars[rec.key] = (not view.hiddenChars[rec.key]) or nil; dirty = true end }
    end
    rows[#rows + 1] = { kind = "separator" }
    rows[#rows + 1] = { kind = "action", label = L["Show all"], onClick = function() wipe(view.hiddenChars); dirty = true end }
    rows[#rows + 1] = { kind = "action", label = L["Only this character"], onClick = function()
        wipe(view.hiddenChars)
        for _, rec in ipairs(ns.Acc.Chars()) do
            if rec.key ~= ns.Acc.MyKey() then view.hiddenChars[rec.key] = true end
        end
        dirty = true
    end }
    return rows
end

local function ResetFilters()
    wipe(view.rarity); wipe(view.slots); wipe(view.craftProfs); wipe(view.craftRarity); wipe(view.craftSlots)
    view.craftCat = "all"
    view.hideBound, view.hideBoundAll, view.hideQuest, view.itemFilter, view.onlyCraftable = false, true, true, "all", false
    view.hideBoP, view.hideBoPAll = false, true
    view.craftOpt = { profit = true }
    wipe(view.hiddenChars)
    dirty = true
end

-- the menu buttons the item tables share: rarity, slot, what to hide
local function ItemFilterButtons(first)
    local n = Count(view.rarity)
    local m = Count(view.slots)
    local h = (HideBoundOn() and 1 or 0) + (HideBoPOn() and 1 or 0) + (view.hideQuest and 1 or 0)
    local items = { first }
    items[#items + 1] = { label = L["Rarity"] .. (n > 0 and (" (" .. n .. ")") or ""), icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", gen = function() return RarityMenu(view.rarity) end, on = n > 0 }
    items[#items + 1] = { label = L["Slot"] .. (m > 0 and (" (" .. m .. ")") or ""), icon = PD .. "Chest", gen = function() return SlotMenu(view.slots) end, on = m > 0 }
    items[#items + 1] = { label = L["Hide"] .. (h > 0 and (" (" .. h .. ")") or ""), icon = "Interface\\Icons\\INV_Misc_Bone_01", gen = HideMenu, on = h > 0 }
    return items
end

-- One physical screen pixel, in the units of a frame; sizes and offsets that are multiples of it
-- are drawn sharp (fractions of a pixel are what makes thin bars look blurred).
local function Pixel(frame)
    local ph
    if GetPhysicalScreenSize then local _, h = GetPhysicalScreenSize(); ph = h end
    local up = UIParent:GetHeight()
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if not ph or ph <= 0 or not up or up <= 0 or ratio <= 0 then return 1 end
    return up / ph / ratio
end
local function Snap(frame, v)
    local px = Pixel(frame)
    return math.floor(v / px + 0.5) * px
end

-- the table ---------------------------------------------------------------------------------------
-- cols: { id, title, w (pixels) or flex (a share of the rest), align, sort = true }
-- rows: { cells = { "text" or { text, icon, icons = { { tex, count } } } ... }, sort = { id = value },
--         link = item link for the tooltip, tip = function(tooltip), onClick = function }
local function NewTable(parent, owner)
    local t = { rows = {}, cols = {}, data = {}, sortId = nil, sortAsc = true, heads = {} }
    local frame = CreateFrame("Frame", nil, parent)
    t.frame = frame

    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(ROW_H)
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.13, 0.095, 0.06, 1)
    local hrule = head:CreateTexture(nil, "ARTWORK")
    hrule:SetPoint("BOTTOMLEFT", 4, 0)
    hrule:SetPoint("BOTTOMRIGHT", -4, 0)
    hrule:SetHeight(1)
    hrule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
    t.head = head

    local sf = CreateFrame("ScrollFrame", nil, frame)
    sf:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
    sf:SetPoint("BOTTOMRIGHT", -8, 0)
    sf:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(10, 10)
    sf:SetScrollChild(content)
    t.sf, t.content = sf, content
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
    thumb:Hide()

    local function UpdateThumb()
        local viewH, total = sf:GetHeight(), content:GetHeight()
        if total <= viewH + 1 then thumb:Hide() return end
        local h = math.max(24, viewH * viewH / total)
        local off = sf:GetVerticalScroll() / (total - viewH) * (viewH - h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 6, -off)
        thumb:SetHeight(h)
        thumb:Show()
    end
    sf:SetScript("OnMouseWheel", function(self, delta)
        if not W.TopFrameIs(owner) then return end
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * ROW_H * 3)))
        UpdateThumb()
    end)

    -- the tooltip sits to the upper right of the mouse pointer and follows it
    local function Follow()
        local x, y = GetCursorPosition()
        local k = UIParent:GetEffectiveScale()
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / k + 16, y / k + 8)
    end

    -- a picture in a row has a tooltip of its own (the item, and what the row adds to it)
    local function NewHit(r, tex)
        local hit = CreateFrame("Button", nil, r)
        if tex then hit:SetAllPoints(tex) end
        hit:SetScript("OnEnter", function(self)
            local ic = self.ic
            if not ic then return end
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            if ic.link then pcall(GameTooltip.SetHyperlink, GameTooltip, ic.link) end
            if ic.extra then ic.extra(GameTooltip) end
            GameTooltip:Show()
            Follow()
            self:SetScript("OnUpdate", Follow)
        end)
        hit:SetScript("OnLeave", function(self)
            self:SetScript("OnUpdate", nil)
            GameTooltip:Hide()
        end)
        hit:SetScript("OnClick", function(self)
            local row = self:GetParent()
            if row.data and row.data.onClick then row.data.onClick() end
        end)
        return hit
    end

    local function Cell(r, i)
        local c = r.cells[i]
        if not c then
            c = { fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), icon = r:CreateTexture(nil, "ARTWORK"), ico = {} }
            c.fs:SetWordWrap(false)
            c.icon:SetSize(16, 16)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            c.more = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            c.more:SetTextColor(unpack(C.muted))
            r.cells[i] = c
        end
        return c
    end

    local function NewRow()
        local r = CreateFrame("Button", nil, content)
        r:SetHeight(ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.85, 0.4, 0.10)
        r.hl:SetAlpha(0)
        r.cells = {}
        r:SetScript("OnEnter", function(self)
            if self.data and (self.data.onClick or self.data.link or self.data.tip) then self.hl:SetAlpha(1) end
            local d = self.data
            if not d then return end
            if d.link then
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
                GameTooltip:Show()
            elseif d.tip then
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                d.tip(GameTooltip)
                GameTooltip:Show()
            else
                return
            end
            Follow()
            self:SetScript("OnUpdate", Follow)
        end)
        r:SetScript("OnLeave", function(self)
            self.hl:SetAlpha(0)
            self:SetScript("OnUpdate", nil)
            GameTooltip:Hide()
        end)
        r:SetScript("OnClick", function(self)
            if self.data and self.data.onClick then self.data.onClick() end
        end)
        return r
    end

    local function Sorted()
        local list = {}
        for i, d in ipairs(t.data) do list[i] = d end
        local id = t.sortId
        if id then
            local function Key(d)
                local v = d.sort and d.sort[id]
                if v == nil then
                    local ci
                    for i, col in ipairs(t.cols) do if col.id == id then ci = i end end
                    local c = ci and d.cells[ci]
                    v = type(c) == "table" and c.text or c or ""
                    v = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
                end
                return v
            end
            table.sort(list, function(a, b)
                local x, y = Key(a), Key(b)
                if x == y then return false end
                if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
                if t.sortAsc then return x < y end
                return x > y
            end)
        end
        -- characters of several realms or factions: one heading per group, sorted within it
        local groups, order = {}, {}
        for _, d in ipairs(list) do
            local g = d.group
            if g then
                if not groups[g] then groups[g] = {}; order[#order + 1] = g end
                groups[g][#groups[g] + 1] = d
            end
        end
        if #order > 1 then
            table.sort(order)
            local out = {}
            for _, g in ipairs(order) do
                out[#out + 1] = { header = true, label = g }
                for _, d in ipairs(groups[g]) do out[#out + 1] = d end
            end
            return out
        end
        return list
    end

    function t:Layout()
        local width = math.max(100, frame:GetWidth() - 8)
        local fixed, flex = 0, 0
        for _, col in ipairs(self.cols) do
            if col.w then fixed = fixed + col.w else flex = flex + (col.flex or 1) end
        end
        local share = flex > 0 and (width - fixed) / flex or 0
        local x = 0
        self.xs, self.ws = {}, {}
        for i, col in ipairs(self.cols) do
            local w = col.w or math.max(col.min or 40, share * (col.flex or 1))
            self.xs[i], self.ws[i] = x, w
            x = x + w
        end
        content:SetWidth(width)
        -- the column titles
        for i, col in ipairs(self.cols) do
            local b = self.heads[i]
            if not b then
                b = CreateFrame("Button", nil, head)
                b:SetHeight(ROW_H)
                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                b.text:SetPoint("LEFT", 8, 0)
                b.text:SetPoint("RIGHT", -4, 0)
                b.text:SetWordWrap(false)
                b:SetScript("OnClick", function(self)
                    local c = self.col
                    if not (c and c.sort) then return end
                    if t.sortId == c.id then t.sortAsc = not t.sortAsc else t.sortId, t.sortAsc = c.id, c.desc ~= true end
                    t:Refresh()
                end)
                self.heads[i] = b
            end
            b.col = col
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", head, "TOPLEFT", self.xs[i], 0)
            b:SetWidth(self.ws[i])
            b.text:SetJustifyH(col.align or "LEFT")
            local arrow = (self.sortId == col.id) and (self.sortAsc and " ^" or " v") or ""
            b.text:SetText((col.title or "") .. arrow)
            b.text:SetTextColor(unpack(self.sortId == col.id and { 1, 0.95, 0.7 } or { 0.9, 0.78, 0.5 }))
            b:Show()
        end
        for i = #self.cols + 1, #self.heads do self.heads[i]:Hide() end
        head:SetShown(not self.noHeader)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", self.noHeader and frame or head, self.noHeader and "TOPLEFT" or "BOTTOMLEFT", 0, self.noHeader and 0 or -1)
        sf:SetPoint("BOTTOMRIGHT", -8, 0)
    end

    function t:Refresh()
        self:Layout()
        local list = Sorted()
        for i, d in ipairs(list) do
            local r = self.rows[i]
            if not r then r = NewRow(); self.rows[i] = r end
            r.data = d
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
            if d.header then
                r.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.12)
                for _, cell in ipairs(r.cells) do
                    cell.fs:Hide(); cell.icon:Hide(); cell.more:Hide(); if cell.hit then cell.hit:Hide() end
                    for _, tex in ipairs(cell.ico) do tex:Hide(); tex.txt:Hide(); tex.hit:Hide() end
                    if cell.barBg then cell.barBg:Hide(); cell.barFill:Hide(); cell.barBg2:Hide(); cell.barRest:Hide(); cell.barEdge:Hide(); cell.barEdge2:Hide(); if cell.shine then cell.shine:Hide(); cell.shine2:Hide() end; if cell.fs2 then cell.fs2:Hide() end end
                end
                if not r.headFS then
                    r.headFS = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    r.headFS:SetPoint("LEFT", 10, 0)
                end
                r.headFS:SetText(d.label)
                r.headFS:SetTextColor(1, 0.88, 0.5)
                r.headFS:Show()
            else
            if r.headFS then r.headFS:Hide() end
            for ci, col in ipairs(self.cols) do
                local cell = Cell(r, ci)
                local spec = d.cells[ci]
                if type(spec) ~= "table" then spec = { text = spec } end
                local x, w = self.xs[ci], self.ws[ci]
                local tx = x + 8
                if spec.icon then
                    cell.icon:ClearAllPoints()
                    cell.icon:SetPoint("LEFT", r, "LEFT", x + 6, 0)
                    cell.icon:SetTexture(spec.icon)
                    if spec.coords then cell.icon:SetTexCoord(unpack(spec.coords)) else cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                    cell.icon:Show()
                    tx = x + 28
                else
                    cell.icon:Hide()
                end
                cell.fs:ClearAllPoints()
                local align = col.align or "LEFT"
                if align == "RIGHT" then
                    cell.fs:SetPoint("LEFT", r, "LEFT", tx, 0)
                    cell.fs:SetPoint("RIGHT", r, "LEFT", x + w - 8, 0)
                elseif align == "CENTER" then
                    cell.fs:SetPoint("LEFT", r, "LEFT", tx, 0)
                    cell.fs:SetPoint("RIGHT", r, "LEFT", x + w - 8, 0)
                else
                    cell.fs:SetPoint("LEFT", r, "LEFT", tx, 0)
                    cell.fs:SetPoint("RIGHT", r, "LEFT", x + w - 6, 0)
                end
                cell.fs:SetJustifyH(align)
                cell.fs:SetText(spec.text or "")
                cell.fs:SetTextColor(unpack(C.text))
                -- two bars side by side (experience, rested bonus) in the look of the goal bars: a dark
                -- track with a thin gilded edge, a fill with the game's own bar texture, the figure inside.
                -- Gold is progress; jade is the rested bonus, brighter and with a jade edge when it is full.
                -- Every size and offset is a whole number of screen pixels, so the edges stay sharp.
                if spec.bar then
                    if not cell.barBg then
                        cell.barBg = r:CreateTexture(nil, "ARTWORK")
                        cell.barFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
                        cell.barBg2 = r:CreateTexture(nil, "ARTWORK")
                        cell.barRest = r:CreateTexture(nil, "ARTWORK", nil, 1)
                        cell.barEdge = r:CreateTexture(nil, "BACKGROUND", nil, 2)
                        cell.barEdge2 = r:CreateTexture(nil, "BACKGROUND", nil, 2)
                        cell.shine = r:CreateTexture(nil, "ARTWORK", nil, 2)
                        cell.shine2 = r:CreateTexture(nil, "ARTWORK", nil, 2)
                        cell.shine:SetColorTexture(1, 1, 1, 0.07)
                        cell.shine2:SetColorTexture(1, 1, 1, 0.07)
                        cell.barFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        cell.barRest:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        for _, t in ipairs({ cell.barBg, cell.barFill, cell.barBg2, cell.barRest, cell.barEdge, cell.barEdge2, cell.shine, cell.shine2 }) do
                            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
                            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
                        end
                    end
                    if not cell.fs2 then
                        cell.fs2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        cell.fs2:SetShadowOffset(1, -1)
                        cell.fs:SetShadowOffset(1, -1)
                    end
                    local px = Pixel(r)
                    local H = Snap(r, 10)
                    -- top edge of the bar's frame, a whole number of pixels from the row's top: it sits in the middle, and none of its four edges is lost
                    local yTop = Snap(r, (ROW_H - (H + 2 * px)) / 2)
                    local GAP = Snap(r, 12)
                    local bw = Snap(r, math.max(14, math.min(120, (w - 16 - GAP) / 2)))
                    local bx1 = Snap(r, x + 8)
                    local bx2 = bx1 + bw + GAP
                    local v = math.max(0, math.min(1, spec.bar.value or 0))
                    local rv = math.max(0, math.min(1, spec.bar.rest or 0))
                    local function Frame(edge, bg, fill, shine, bx, frac)
                        edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", r, "TOPLEFT", bx - px, -yTop); edge:SetSize(bw + 2 * px, H + 2 * px)
                        bg:ClearAllPoints(); bg:SetPoint("TOPLEFT", r, "TOPLEFT", bx, -(yTop + px)); bg:SetSize(bw, H)
                        bg:SetColorTexture(0.015, 0.012, 0.01, 1)
                        local fw = frac > 0 and math.max(px, Snap(r, bw * frac)) or 0
                        fill:ClearAllPoints(); fill:SetPoint("TOPLEFT", r, "TOPLEFT", bx, -(yTop + px)); fill:SetSize(math.max(px, fw), H)
                        shine:ClearAllPoints()
                        shine:SetPoint("TOPLEFT", fill, "TOPLEFT")
                        shine:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
                        shine:SetHeight(Snap(r, 3))
                        edge:Show(); bg:Show(); fill:SetShown(frac > 0); shine:SetShown(frac > 0)
                    end
                    Frame(cell.barEdge, cell.barBg, cell.barFill, cell.shine, bx1, v)
                    cell.barEdge:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
                    cell.barFill:SetVertexColor(0.78, 0.62, 0.28, 1) -- the muted gold of the goal bars (the texture darkens it)
                    Frame(cell.barEdge2, cell.barBg2, cell.barRest, cell.shine2, bx2, rv)
                    if spec.bar.full then
                        cell.barEdge2:SetColorTexture(C.jade[1], C.jade[2], C.jade[3], 1)
                        cell.barRest:SetVertexColor(0.34, 0.74, 0.60, 1)
                    else
                        cell.barEdge2:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
                        cell.barRest:SetVertexColor(0.25, 0.53, 0.43, 1)
                    end
                    cell.fs:ClearAllPoints()
                    cell.fs:SetPoint("CENTER", r, "LEFT", bx1 + bw / 2, 0)
                    cell.fs:SetWidth(bw)
                    cell.fs:SetJustifyH("CENTER")
                    cell.fs:SetText(spec.bar.t1 or "")
                    cell.fs:Show()
                    cell.fs2:ClearAllPoints()
                    cell.fs2:SetPoint("CENTER", r, "LEFT", bx2 + bw / 2, 0)
                    cell.fs2:SetWidth(bw)
                    cell.fs2:SetJustifyH("CENTER")
                    cell.fs2:SetText(spec.bar.t2 or "")
                    cell.fs2:Show()
                elseif cell.barBg then
                    cell.barBg:Hide(); cell.barFill:Hide(); cell.barBg2:Hide(); cell.barRest:Hide()
                    cell.barEdge:Hide(); cell.barEdge2:Hide(); cell.shine:Hide(); cell.shine2:Hide()
                    if cell.fs2 then cell.fs2:Hide() end
                end
                -- a row of small pictures (mail attachments, materials), each with a number on it if it has one
                local n = spec.icons and #spec.icons or 0
                local size = spec.iconSize or 18
                local step = size + 3
                local limit = spec.fit and math.max(1, math.floor((w - 12) / step)) or 6
                for k = 1, math.max(n, #cell.ico) do
                    local tex = cell.ico[k]
                    if k <= math.min(n, limit) then
                        if not tex then
                            tex = r:CreateTexture(nil, "ARTWORK")
                            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                            tex.txt = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                            tex.hit = NewHit(r, tex)
                            cell.ico[k] = tex
                        end
                        local ic = spec.icons[k]
                        tex:SetSize(size, size)
                        tex:ClearAllPoints()
                        tex:SetPoint("LEFT", r, "LEFT", x + 6 + (k - 1) * step, 0)
                        tex:SetTexture(ic.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                        tex:Show()
                        tex.hit.ic = ic
                        tex.hit:SetShown((ic.link or ic.extra) and true or false)
                        if ic.count then
                            tex.txt:ClearAllPoints()
                            tex.txt:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 2, -1)
                            tex.txt:SetText(ic.count)
                            local col = ic.color or { 1, 1, 1 }
                            tex.txt:SetTextColor(col[1], col[2], col[3])
                            tex.txt:Show()
                        else
                            tex.txt:Hide()
                        end
                    elseif tex then
                        tex:Hide()
                        tex.txt:Hide()
                        tex.hit:Hide()
                    end
                end
                if n > limit then
                    cell.more:ClearAllPoints()
                    cell.more:SetPoint("LEFT", r, "LEFT", x + 6 + limit * step, 0)
                    cell.more:SetText("+" .. (n - limit))
                    cell.more:Show()
                else
                    cell.more:Hide()
                end
                cell.fs:SetShown(spec.text ~= nil or spec.bar ~= nil)
                -- the cell's own tooltip (the item of a recipe); elsewhere in the row the row's applies
                if spec.link or spec.extra then
                    if not cell.hit then cell.hit = NewHit(r) end
                    cell.hit:ClearAllPoints()
                    cell.hit:SetPoint("TOPLEFT", r, "TOPLEFT", x, 0)
                    cell.hit:SetSize(w, ROW_H)
                    cell.hit.ic = spec
                    cell.hit:Show()
                elseif cell.hit then
                    cell.hit:Hide()
                end
            end
            for ci = #self.cols + 1, #r.cells do
                local cell = r.cells[ci]
                cell.fs:Hide(); cell.icon:Hide(); cell.more:Hide(); if cell.hit then cell.hit:Hide() end
                for _, tex in ipairs(cell.ico) do tex:Hide(); tex.txt:Hide(); tex.hit:Hide() end
                if cell.barBg then cell.barBg:Hide(); cell.barFill:Hide(); cell.barBg2:Hide(); cell.barRest:Hide(); cell.barEdge:Hide(); cell.barEdge2:Hide(); if cell.shine then cell.shine:Hide(); cell.shine2:Hide() end; if cell.fs2 then cell.fs2:Hide() end end
            end
            end
            r:Show()
        end
        for i = #list + 1, #self.rows do self.rows[i]:Hide() end
        content:SetHeight(math.max(1, #list * ROW_H))
        local maxScroll = math.max(0, #list * ROW_H - sf:GetHeight())
        if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
        UpdateThumb()
    end

    function t:Set(cols, data, opts)
        opts = opts or {}
        local same = #self.cols == #cols
        if same then for i, c in ipairs(cols) do if self.cols[i].id ~= c.id then same = false end end end
        self.cols, self.data = cols, data
        self.noHeader = opts.noHeader
        if not same or opts.resetSort then
            self.sortId, self.sortAsc = opts.sort, opts.asc ~= false
        end
        self:Refresh()
    end
    return t
end

-- the window ---------------------------------------------------------------------------------------
local f = CreateFrame("Frame", "ForeverCompanionAccount", UIParent, W.TEMPLATE)
AW.frame = f
f:SetSize(DEFAULT_W, DEFAULT_H)
f:SetPoint("CENTER", UIParent, "CENTER", 30, 0)
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
title:SetText(L["Account"])
title:SetTextColor(1, 0.85, 0.4)

function AW.ApplyFrameStyle()
    local ornate = false
    local blizz = W.BlizzSkin(f, true, W.ICON.account, title:GetText(), "account")
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
    ns.db.accountWin = { v = 2, pos = { point, rel, x, y }, size = { f:GetWidth(), f:GetHeight() }, scale = f:GetScale() }
end
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
f:SetScript("OnSizeChanged", function() dirty = true end)

local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
f.closeBtn = close
close:SetPoint("TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() AW.Hide() end)
local opacityBtn = W.NewOpacityButton(f, "account", f, 20)
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
local settingsBtn = W.NewIconButton(f, W.ICON.settings, 20) -- the last of the window buttons
settingsBtn:SetPoint("LEFT", mapBtn, "RIGHT", 4, 0)
settingsBtn:SetTip(L["Settings"], L["Open the settings."])
settingsBtn:SetScript("OnClick", function() if ns.Settings then ns.Settings.Toggle() end end)
f.skinRowAll = { journalBtn, sessionBtn, mapBtn, settingsBtn }

local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(f:GetFrameLevel() + 50)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
W.AttachScaleGrip(f, grip, {
    defaultSize = { DEFAULT_W, DEFAULT_H }, minSize = { MIN_W, MIN_H }, maxSize = { MAX_W, MAX_H },
    gridSize = { 20, 20 }, gridScale = 0.05, minScale = 0.6, maxScale = 1.6,
    saveSize = SavePosition, saveScale = SavePosition, savePos = SavePosition,
})

-- toolbar: what is open, and the search over all characters ------------------------------------------
local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
heading:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + LIST_W + 18, -(BAR_TOP - 1))
heading:SetJustifyH("LEFT")
heading:SetWordWrap(false)
local subheading = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subheading:SetPoint("LEFT", heading, "RIGHT", 10, -1)
subheading:SetTextColor(unpack(C.muted))

local search = CreateFrame("EditBox", nil, f, W.TEMPLATE)
search:SetHeight(22)
search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(EDGE + 2), -BAR_TOP)
search:SetWidth(230)
search:SetBackdrop(W.PLATE_BACKDROP)
search:SetBackdropColor(unpack(C.inset))
search:SetBackdropBorderColor(unpack(C.goldDim))
search:SetFontObject("GameFontHighlightSmall")
search:SetAutoFocus(false)
search:SetMaxLetters(40)
search:SetTextInsets(8, 22, 0, 0)
local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
searchHint:SetPoint("LEFT", 8, 0)
searchHint:SetTextColor(unpack(C.muted))
searchHint:SetText(L["Find an item on all characters…"])
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
    view.query = text:lower()
    searchHint:SetShown(text == "")
    searchClear:SetShown(text ~= "")
    dirty = true
end)
search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.gold)) end)
search:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.goldDim)) end)

-- the character list on the left -----------------------------------------------------------------------
local listPlate = W.NewPlate(f, C.page)
listPlate:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -(MAP_TOP + 6)) -- (under the ring)
listPlate:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, BOTTOM)
listPlate:SetWidth(LIST_W)

-- the whole account at a glance, whatever is open: cash and total worth of all characters
local function SummaryLine(y, label)
    local l = listPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 12, -y)
    l:SetTextColor(unpack(C.muted))
    l:SetText(label)
    local v = listPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v:SetPoint("TOPRIGHT", -12, -y)
    v:SetJustifyH("RIGHT")
    return v
end
local cashValue = SummaryLine(11, L["Cash"])
local worthValue = SummaryLine(29, L["Total worth"])
local summaryRule = listPlate:CreateTexture(nil, "ARTWORK")
summaryRule:SetPoint("TOPLEFT", 10, -47)
summaryRule:SetPoint("TOPRIGHT", -10, -47)
summaryRule:SetHeight(1)
summaryRule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

-- a small picture at the left of a button's text
local function AddIcon(b, tex)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetSize(14, 14)
    t:SetPoint("LEFT", 8, 0)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t:SetTexture(tex)
    b.text:ClearAllPoints()
    b.text:SetPoint("CENTER", 8, 0)
end

-- the views over the whole account
local navButtons = {}
for i, def in ipairs({ { "all", L["All characters"], "Interface\\Icons\\INV_Misc_GroupLooking" }, { "items", L["Items & materials"], "Interface\\Icons\\INV_Misc_Bag_08" }, { "craft", L["Crafting"], "Interface\\Icons\\Trade_BlackSmithing" } }) do
    local b = W.NewButton(listPlate, def[2], LIST_W - 16, 26)
    AddIcon(b, def[3])
    b:SetPoint("TOPLEFT", 8, -56 - (i - 1) * 30)
    b.id = def[1]
    b:SetScript("OnClick", function() view.mode, view.key, view.prof = def[1], nil, nil; dirty = true end)
    navButtons[i] = b
end

local listSF = CreateFrame("ScrollFrame", nil, listPlate)
listSF:SetPoint("TOPLEFT", 6, -152)
listSF:SetPoint("BOTTOMRIGHT", -6, 6)
listSF:EnableMouseWheel(true)
local listContent = CreateFrame("Frame", nil, listSF)
listContent:SetSize(LIST_W - 12, 10)
listSF:SetScrollChild(listContent)
listSF:SetScript("OnMouseWheel", function(self, delta)
    if not W.TopFrameIs(f) then return end
    local maxScroll = math.max(0, listContent:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 40)))
end)
local charRows = {}

local function NewCharRow(i)
    local r = CreateFrame("Button", nil, listContent)
    r:SetHeight(50)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 0.85, 0.4, 0.14)
    r.bg:SetAlpha(0)
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.85, 0.4, 0.08)
    r.hl:SetAlpha(0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("TOPLEFT", 6, -7)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
    r.name:SetPoint("RIGHT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.sub:SetTextColor(unpack(C.muted))
    -- where the character is now
    r.loc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.loc:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -1)
    r.loc:SetPoint("RIGHT", -6, 0)
    r.loc:SetJustifyH("LEFT")
    r.loc:SetWordWrap(false)
    r.loc:SetTextColor(C.goldDim[1], C.goldDim[2], C.goldDim[3])
    r:SetScript("OnEnter", function(self) if self.key then self.hl:SetAlpha(1) end end)
    r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
    r:SetScript("OnClick", function(self)
        if not self.key then return end
        view.mode, view.key, view.prof = "char", self.key, nil
        dirty = true
    end)
    charRows[i] = r
    return r
end

local function RenderList()
    local chars = ns.Acc.Chars()
    local groupFn = ns.Acc.GroupFn()
    local entries = {}
    if groupFn then
        local order, by = {}, {}
        for _, rec in ipairs(chars) do
            local g = groupFn(rec)
            if not by[g] then by[g] = {}; order[#order + 1] = g end
            table.insert(by[g], rec)
        end
        table.sort(order)
        for _, g in ipairs(order) do
            entries[#entries + 1] = { header = g }
            for _, rec in ipairs(by[g]) do entries[#entries + 1] = { rec = rec } end
        end
    else
        for _, rec in ipairs(chars) do entries[#entries + 1] = { rec = rec } end
    end
    local y = 0
    for i, e in ipairs(entries) do
        local r = charRows[i] or NewCharRow(i)
        local h = e.header and 22 or 50
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", 0, -y)
        r.name:ClearAllPoints()
        if e.header then
            r.key = nil
            r.icon:Hide()
            r.sub:Hide()
            r.loc:Hide()
            r.name:SetPoint("LEFT", 8, 0)
            r.name:SetPoint("RIGHT", -6, 0)
            r.name:SetText(GOLD .. e.header .. "|r")
            r.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.12)
            r.bg:SetAlpha(1)
        else
            local rec = e.rec
            r.key = rec.key
            r.icon:Show()
            r.sub:Show()
            r.loc:Show()
            r.loc:SetText(rec.zone or "")
            r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
            r.name:SetPoint("RIGHT", -6, 0)
            local tex, coords = ClassIcon(rec.class)
            r.icon:SetTexture(tex)
            if coords then r.icon:SetTexCoord(unpack(coords)) else r.icon:SetTexCoord(0, 1, 0, 1) end
            r.name:SetText(ClassHex(rec.class) .. ns.Acc.NameOf(rec) .. "|r")
            local here = rec.key == ns.Acc.MyKey()
            r.sub:SetText(("%s %d%s"):format(L["Level"], rec.level or 0, here and ("  ·  " .. JADE .. L["online"] .. "|r") or ""))
            r.bg:SetColorTexture(1, 0.85, 0.4, 0.14)
            r.bg:SetAlpha(view.mode == "char" and view.key == rec.key and 1 or 0)
        end
        y = y + h + 2
        r:Show()
    end
    for i = #entries + 1, #charRows do charRows[i]:Hide() end
    listContent:SetHeight(math.max(1, y))
    for _, b in ipairs(navButtons) do b:SetSelected(view.mode == b.id) end
    local totals = ns.Acc.Totals()
    cashValue:SetText(Money(totals.money))
    worthValue:SetText(Money(totals.worth))
end

-- the right side: tabs and the table ---------------------------------------------------------------------
local right = W.NewPlate(f, C.page)
right:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + LIST_W + 8, -MAP_TOP + 4)
right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, BOTTOM)

local TABS = {
    { "overview", L["Overview"], "Interface\\Icons\\INV_Misc_GroupLooking" }, { "equip", L["Equipment"], "Interface\\Icons\\INV_Chest_Chain_03" },
    { "inv", L["Bags & bank"], "Interface\\Icons\\INV_Misc_Bag_08" }, { "prof", L["Professions"], "Interface\\Icons\\Trade_BlackSmithing" },
    { "mail", L["Mail"], "Interface\\Icons\\INV_Letter_15" }, { "ah", L["Auctions"], "Interface\\Icons\\INV_Misc_Coin_02" },
}
local tabButtons = {}
for i, def in ipairs(TABS) do
    local b = W.NewButton(right, def[2], 116, 24)
    AddIcon(b, def[3])
    b.id = def[1]
    b:SetScript("OnClick", function() view.tab, view.prof = def[1], nil; dirty = true end)
    tabButtons[i] = b
end
-- menu buttons above the table; a view sets bar = { items = { { label, icon, gen, on } } }
local bar
local menuButtons = {}
menu = W.NewDropdown(right, { level = f:GetFrameLevel() + 60, width = 250 })
local forgetBtn = W.NewButton(right, L["Forget character"], 130, 22)
local forgetArmed
forgetBtn:SetScript("OnClick", function(self)
    if not forgetArmed then
        forgetArmed = true
        self.text:SetText(L["Sure? Click again"])
        self.text:SetTextColor(unpack(C.red))
        C_Timer.After(3, function()
            if forgetArmed then forgetArmed = nil; self.text:SetText(L["Forget character"]); self.text:SetTextColor(unpack(C.text)) end
        end)
        return
    end
    forgetArmed = nil
    self.text:SetText(L["Forget character"])
    ns.Acc.Forget(view.key)
    view.mode, view.key = "all", nil
    dirty = true
end)

local status = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetJustifyH("LEFT")
status:SetWordWrap(true)
status:SetTextColor(unpack(C.muted))

local tbl = NewTable(right, f)

-- views ------------------------------------------------------------------------------------------------------
local function Fresh(rec, part)
    local t = rec.at and rec.at[part]
    if t then return ("%s: %s"):format(L["part_" .. part], ns.Ago(t)), true end
    return AMBER .. (ns.Acc.HINT[part] or "") .. "|r", false
end

-- the list of all characters, in views: which columns it shows is chosen with the buttons above it
local ALL_VIEWS = {
    { id = "overview", label = L["Overview"], icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
    { id = "prof", label = L["Professions"], icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { id = "xp", label = L["Experience"], icon = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
    { id = "loc", label = L["Location"], icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { id = "gold", label = L["Money"], icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { id = "storage", label = L["Storage"], icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { id = "gear", label = L["Equipment"], icon = "Interface\\Icons\\INV_Chest_Chain_03" },
    { id = "time", label = L["Time played"], icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
}

local PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"
local ENCHANT_ICON = "Interface\\Icons\\INV_Enchant_EssenceMagicLarge"
-- the picture of a recipe that makes no item: an enchantment has its own, the others use their profession's
local function RecipeIcon(prof)
    local n = (prof or ""):lower()
    if n == "enchanting" or n == "verzauberkunst" then return ENCHANT_ICON end
    return ns.Acc.ProfIcon(prof) or PLACEHOLDER
end

local function SkillColor(s)
    local pct = s.max > 0 and s.rank / s.max or 0
    return pct >= 1 and JADE or (pct > 0.7 and "|cffffff66" or "|cffffffff")
end

-- a profession's skill: with its picture the name is not repeated; without one the name stays
local function ProfText(s)
    local rank = SkillColor(s) .. s.rank .. "|r" .. MUTED .. "/" .. s.max .. "|r"
    return ns.Acc.ProfIcon(s.name) and rank or (s.name .. " " .. rank)
end

-- the same inside a line of text (a small picture and the rank)
local function ProfInline(s)
    local icon = ns.Acc.ProfIcon(s.name)
    local rank = SkillColor(s) .. s.rank .. "|r"
    if icon then return ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(icon, rank) end
    return s.name .. " " .. rank
end

-- the tooltip of a row: every profession by name
local function ProfTip(rec)
    return function(tt)
        tt:AddLine(ns.Acc.NameOf(rec), 1, 0.85, 0.4)
        for _, s in ipairs(rec.skills or {}) do
            if ns.Acc.SkillKind(s) then tt:AddDoubleLine(s.name, ("%d / %d"):format(s.rank, s.max), 0.9, 0.9, 0.9, 1, 1, 1) end
        end
    end
end

-- rested experience: what was read when you last played, and what has probably built up since
-- (a quarter of the rate away from an inn or a city)
local function Rested(rec, here)
    if not (rec.xpMax and rec.xpMax > 0) then return nil end
    local base = rec.rested or 0
    if here then return base, false end
    local gone = math.max(0, time() - (rec.lastSeen or time()))
    local rate = (rec.resting and 0.05 / (8 * 3600) or 0.05 / (32 * 3600)) * rec.xpMax
    return math.min(base + gone * rate, rec.xpMax * 1.5), true
end

local function SlotsText(set)
    if not (set and set.slots and set.slots > 0) then return MUTED .. "–|r", -1 end
    local used = set.slots - (set.free or 0)
    local col = (set.free or 0) <= 2 and RED or ((set.free or 0) <= 6 and AMBER or "")
    return col .. used .. "|r" .. MUTED .. " / " .. set.slots .. "|r", set.free or 0
end

local function MailStats(rec)
    local n, gold, soon = 0, 0, 0
    for _, m in ipairs(rec.mail and rec.mail.list or {}) do
        n = n + 1
        gold = gold + (m.money or 0)
        if (m.expires or 0) - time() < 3 * 86400 then soon = soon + 1 end
    end
    return n, gold, soon
end

local function AuctionStats(rec)
    local n, worth = 0, 0
    for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do
        n = n + 1
        worth = worth + (a.buyout or 0)
    end
    return n, worth
end

-- everything a character is worth: coins, mail, auctions, and what bags and bank hold
local function WorthOf(rec) return ns.Acc.WorthOf(rec) end

local ALL_COLS = {
    overview = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "race", title = L["Race"], flex = 1, sort = true },
        { id = "class", title = L["Class"], flex = 1, sort = true },
        { id = "profs", title = L["Professions"], flex = 1.8 },
        { id = "money", title = L["Money"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "played", title = L["Played"], w = 80, align = "RIGHT", sort = true, desc = true },
        { id = "seen", title = L["Last seen"], w = 90, align = "RIGHT", sort = true, desc = true },
    },
    prof = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "p1", title = L["Profession"] .. " 1", flex = 1, sort = true },
        { id = "p2", title = L["Profession"] .. " 2", flex = 1, sort = true },
        { id = "sec", title = L["Secondary skills"], flex = 1.6 },
        { id = "recipes", title = L["Recipes"], w = 80, align = "RIGHT", sort = true, desc = true },
    },
    xp = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "xp", title = L["Experience"], w = 90, align = "RIGHT", sort = true, desc = true },
        { id = "left", title = L["To next level"], w = 100, align = "RIGHT", sort = true },
        { id = "rested", title = L["Rested"], flex = 1, align = "RIGHT", sort = true, desc = true },
        { id = "resting", title = L["Resting"], w = 90, align = "RIGHT" },
    },
    loc = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "zone", title = L["Zone"], flex = 1.1, sort = true },
        { id = "sub", title = L["Subzone"], flex = 1, sort = true },
        { id = "hearth", title = L["Hearthstone"], flex = 1.1, sort = true },
        { id = "seen", title = L["Last seen"], w = 90, align = "RIGHT", sort = true, desc = true },
    },
    gold = {
        { id = "money", title = L["Money"], w = 120, align = "RIGHT", sort = true, desc = true },
        { id = "mail", title = L["In mail"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "ah", title = L["On auction"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "bags", title = L["Worth of bags"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "bank", title = L["Worth of bank"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "sum", title = L["Total worth"], w = 120, align = "RIGHT", sort = true, desc = true },
    },
    storage = {
        { id = "bags", title = L["Bags"], w = 90, align = "RIGHT", sort = true },
        { id = "bank", title = L["Bank"], w = 90, align = "RIGHT", sort = true },
        { id = "bankSeen", title = L["Bank read"], w = 100, align = "RIGHT" },
        { id = "mail", title = L["Mail"], w = 70, align = "RIGHT", sort = true, desc = true },
        { id = "soon", title = L["Expiring soon"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "auctions", title = L["Auctions"], w = 80, align = "RIGHT", sort = true, desc = true },
    },
    gear = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "ilvl", title = L["Item level"], w = 100, align = "RIGHT", sort = true, desc = true },
        { id = "worn", title = L["Slots filled"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "read", title = L["Equipment read"], w = 130, align = "RIGHT" },
    },
    time = {
        { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
        { id = "played", title = L["Played"], w = 100, align = "RIGHT", sort = true, desc = true },
        { id = "atLevel", title = L["At this level"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "seen", title = L["Last seen"], w = 110, align = "RIGHT", sort = true, desc = true },
    },
}

-- the columns of the views that have professions or experience: the professions are one column
-- each (two professions, then cooking, fishing, first aid ...), so that they line up
local function SecondaryNames()
    local names, seen = {}, {}
    for _, rec in ipairs(ns.Acc.Chars()) do
        for _, sk in ipairs(rec.skills or {}) do
            if ns.Acc.SkillKind(sk) == "secondary" and not seen[sk.name:lower()] then
                seen[sk.name:lower()] = true
                names[#names + 1] = sk.name
            end
        end
    end
    table.sort(names, function(x, y) return x:lower() < y:lower() end)
    return names
end

local function ProfColumns(secNames, wide)
    local w = wide and 110 or 64
    local cols = {
        { id = "p1", title = L["Prof."] .. " 1", w = w, sort = true, desc = true },
        { id = "p2", title = L["Prof."] .. " 2", w = w, sort = true, desc = true },
    }
    for i, name in ipairs(secNames) do
        local icon = ns.Acc.ProfIcon(name)
        cols[#cols + 1] = { id = "s" .. i, title = icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t"):format(icon) or name, w = w, sort = true, desc = true, secName = name }
    end
    return cols
end

local function DynamicCols(kind, secNames)
    if kind == "overview" then
        local cols = {
            { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
            { id = "xp", title = L["Experience"], flex = 1, min = 210, sort = true, desc = true },
        }
        for _, col in ipairs(ProfColumns(secNames, false)) do cols[#cols + 1] = col end
        cols[#cols + 1] = { id = "money", title = L["Money"], w = 100, align = "RIGHT", sort = true, desc = true }
        cols[#cols + 1] = { id = "worth", title = L["Total worth"], w = 106, align = "RIGHT", sort = true, desc = true }
        cols[#cols + 1] = { id = "seen", title = L["Last seen"], w = 76, align = "RIGHT", sort = true, desc = true }
        return cols
    elseif kind == "prof" then
        local cols = { { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true } }
        for _, col in ipairs(ProfColumns(secNames, true)) do cols[#cols + 1] = col end
        cols[#cols + 1] = { id = "recipes", title = L["Recipes"], w = 80, align = "RIGHT", sort = true, desc = true }
        return cols
    elseif kind == "xp" then
        return {
            { id = "level", title = L["Level"], w = 68, align = "RIGHT", sort = true, desc = true },
            { id = "xp", title = L["Experience"], flex = 1.6, sort = true, desc = true },
            { id = "left", title = L["To next level"], w = 110, align = "RIGHT", sort = true },
            { id = "rested", title = L["Rested"], w = 140, align = "RIGHT", sort = true, desc = true },
            { id = "resting", title = L["Resting"], w = 90, align = "RIGHT" },
        }
    end
end

-- the experience bar of a character: filled part, rested part, text; "full" when the rested bonus is at its cap
local function XPCell(rec, here)
    if not (rec.xpMax and rec.xpMax > 0) then return MUTED .. L["max level"] .. "|r", 2, 0, false end
    local pct = (rec.xp or 0) / rec.xpMax
    local rested = Rested(rec, here)
    local rpct = rested and rested / rec.xpMax or 0
    local full = rpct >= 1.499
    local t2 = full and L["full"] or (rpct > 0 and ("+%d %%"):format(rpct * 100) or "–")
    return { bar = { value = pct, rest = math.min(1, rpct / 1.5), full = full, t1 = ("%d %%"):format(pct * 100), t2 = t2 } }, pct, rpct, full
end

-- the tooltip of a row: the experience figures, then the professions
local function RowTip(rec, here)
    local profs = ProfTip(rec)
    return function(tt)
        profs(tt)
        if rec.xpMax and rec.xpMax > 0 then
            tt:AddLine(" ")
            tt:AddDoubleLine(L["Experience"], ("%d %%  (%s / %s)"):format((rec.xp or 0) / rec.xpMax * 100, ns.ShortNumber(rec.xp or 0), ns.ShortNumber(rec.xpMax)), 0.8, 0.8, 0.8, 1, 1, 1)
            local rested, est = Rested(rec, here)
            if rested and rested > 0 then
                local full = rested / rec.xpMax >= 1.499
                tt:AddDoubleLine(L["Rested"], (full and (L["full"] .. "  ") or "") .. ("+%d %%  (%s XP)"):format(rested / rec.xpMax * 100, ns.ShortNumber(rested)) .. (est and ("  " .. L["est."]) or ""),
                    0.8, 0.8, 0.8, full and 0.4 or 0.56, full and 0.86 or 0.7, full and 0.66 or 1)
            end
        end
    end
end

-- the cells and the sort values of one character in one view
local function AllRow(kind, rec, here, secNames)
    local cells, sort = {}, {}
    local function Seen() return here and (JADE .. L["now"] .. "|r") or Ago(rec.lastSeen) end
    local seenSort = here and math.huge or (rec.lastSeen or 0)
    -- professions in their columns: the two professions, then the secondary skills by name
    local function ProfCells(wide)
        local primary, secondary = {}, {}
        for _, sk in ipairs(rec.skills or {}) do
            local k = ns.Acc.SkillKind(sk)
            if k == "primary" then primary[#primary + 1] = sk
            elseif k == "secondary" then secondary[sk.name:lower()] = sk end
        end
        local function Cell(sk)
            if not sk then return MUTED .. "–|r" end
            local rank = SkillColor(sk) .. sk.rank .. "|r" .. (wide and (MUTED .. "/" .. sk.max .. "|r") or "")
            local icon = ns.Acc.ProfIcon(sk.name)
            return { text = icon and rank or (sk.name .. " " .. rank), icon = icon }
        end
        local cells, sorts = { Cell(primary[1]), Cell(primary[2]) }, { p1 = primary[1] and primary[1].rank or -1, p2 = primary[2] and primary[2].rank or -1 }
        for i, name in ipairs(secNames) do
            local sk = secondary[name:lower()]
            cells[#cells + 1] = Cell(sk)
            sorts["s" .. i] = sk and sk.rank or -1
        end
        return cells, sorts
    end
    if kind == "overview" then
        local xpCell, pct = XPCell(rec, here)
        local pc, ps = ProfCells(false)
        cells = { tostring(rec.level or 0), xpCell }
        for _, x in ipairs(pc) do cells[#cells + 1] = x end
        local worth = WorthOf(rec)
        cells[#cells + 1] = Money(rec.money)
        cells[#cells + 1] = Money(worth)
        cells[#cells + 1] = Seen()
        sort = { level = rec.level or 0, xp = pct, money = rec.money or 0, worth = worth, seen = seenSort }
        for k, v in pairs(ps) do sort[k] = v end
    elseif kind == "prof" then
        local pc, ps = ProfCells(true)
        local recipes = 0
        for _, r in pairs(rec.recipes or {}) do recipes = recipes + #(r.list or {}) end
        cells = { tostring(rec.level or 0) }
        for _, x in ipairs(pc) do cells[#cells + 1] = x end
        cells[#cells + 1] = recipes > 0 and tostring(recipes) or MUTED .. "–|r"
        sort = { level = rec.level or 0, recipes = recipes }
        for k, v in pairs(ps) do sort[k] = v end
    elseif kind == "xp" then
        local maxed = not (rec.xpMax and rec.xpMax > 0)
        local xpCell, pct = XPCell(rec, here)
        local rested, est = Rested(rec, here)
        cells = { tostring(rec.level or 0), xpCell,
            maxed and "" or ns.ShortNumber(math.max(0, rec.xpMax - (rec.xp or 0))) .. " XP",
            (rested and rested > 0) and ((rec.xpMax and rested / rec.xpMax >= 1.499 and (JADE .. L["full"] .. "|r  ") or "") .. ns.ShortNumber(rested) .. " XP" .. (est and (" " .. MUTED .. L["est."] .. "|r") or "")) or MUTED .. "–|r",
            rec.resting and (JADE .. L["resting"] .. "|r") or "" }
        sort = { level = rec.level or 0, xp = pct, left = maxed and 0 or (rec.xpMax - (rec.xp or 0)), rested = rested or 0 }
    elseif kind == "loc" then
        cells = { tostring(rec.level or 0), rec.zone or MUTED .. "–|r", (rec.sub and rec.sub ~= "") and rec.sub or MUTED .. "–|r",
            rec.hearth or MUTED .. "–|r", Seen() }
        sort = { level = rec.level or 0, zone = (rec.zone or ""):lower(), sub = (rec.sub or ""):lower(), hearth = (rec.hearth or ""):lower(), seen = seenSort }
    elseif kind == "gold" then
        local _, mailGold = MailStats(rec)
        local _, ahWorth = AuctionStats(rec)
        local bagWorth = 0
        for id, n in pairs(rec.bags and rec.bags.items or {}) do bagWorth = bagWorth + ns.Value.Get(id) * n end
        local bankWorth = 0
        for id, n in pairs(rec.bank and rec.bank.items or {}) do bankWorth = bankWorth + ns.Value.Get(id) * n end
        -- everything the character is worth: coins, mail, auctions, and what bags and bank hold
        local sum = (rec.money or 0) + mailGold + ahWorth + bagWorth + bankWorth
        local bankRead = rec.at and rec.at.bank
        cells = { Money(rec.money), mailGold > 0 and Money(mailGold) or "", ahWorth > 0 and Money(ahWorth) or "",
            bagWorth > 0 and Money(bagWorth) or "",
            bankRead and (bankWorth > 0 and Money(bankWorth) or "") or (AMBER .. L["not read"] .. "|r"), Money(sum) }
        sort = { money = rec.money or 0, mail = mailGold, ah = ahWorth, bags = bagWorth, bank = bankWorth, sum = sum }
    elseif kind == "storage" then
        local bagText, bagFree = SlotsText(rec.bags)
        local bankText, bankFree = SlotsText(rec.bank)
        local n, _, soon = MailStats(rec)
        local ahN = AuctionStats(rec)
        cells = { bagText, bankText, rec.at and rec.at.bank and Ago(rec.at.bank) or (AMBER .. L["never"] .. "|r"),
            (rec.at and rec.at.mail) and tostring(n) or MUTED .. "?|r", soon > 0 and (RED .. soon .. "|r") or MUTED .. "0|r",
            (rec.at and rec.at.auctions) and tostring(ahN) or MUTED .. "?|r" }
        sort = { bags = bagFree, bank = bankFree, mail = n, soon = soon, auctions = ahN }
    elseif kind == "gear" then
        local filled = 0
        for _ in pairs(rec.equip or {}) do filled = filled + 1 end
        cells = { tostring(rec.level or 0), rec.ilvl and ("%d"):format(rec.ilvl) or MUTED .. "–|r", ("%d / 19"):format(filled), Ago(rec.at and rec.at.equip) }
        sort = { level = rec.level or 0, ilvl = rec.ilvl or 0, worn = filled }
    else -- time
        cells = { tostring(rec.level or 0), Played(rec.played), Played(rec.playedLevel), Seen() }
        sort = { level = rec.level or 0, played = rec.played or 0, atLevel = rec.playedLevel or 0, seen = seenSort }
    end
    local tip = (kind == "overview" or kind == "prof" or kind == "xp") and RowTip(rec, here) or nil
    return cells, sort, tip
end

local function ViewAll()
    local chars = ns.Acc.Chars()
    local kind = view.allView
    local current = ALL_VIEWS[1]
    for _, v in ipairs(ALL_VIEWS) do if v.id == kind then current = v end end
    bar = { items = { { label = L["View"] .. ": " .. current.label, icon = current.icon, on = false, gen = function()
        local rows = {}
        for _, v in ipairs(ALL_VIEWS) do
            rows[#rows + 1] = { kind = "radio", state = State(view.allView == v.id), label = v.label, icon = v.icon,
                onClick = function() view.allView = v.id; dirty = true end }
        end
        return rows
    end } } }
    local cols = { { id = "name", title = L["Name"], w = 150, sort = true } }
    local secNames = SecondaryNames()
    local kindCols = DynamicCols(kind, secNames) or ALL_COLS[kind] or DynamicCols("overview", secNames)
    for _, col in ipairs(kindCols) do cols[#cols + 1] = col end
    local data = {}
    local groupFn = ns.Acc.GroupFn()
    for _, rec in ipairs(chars) do
        local tex, coords = ClassIcon(rec.class)
        local here = rec.key == ns.Acc.MyKey()
        local cells, sort, tip = AllRow(kind, rec, here, secNames)
        table.insert(cells, 1, { text = ClassHex(rec.class) .. ns.Acc.NameOf(rec) .. "|r" .. (here and ("  " .. JADE .. L["online"] .. "|r") or "")
            , icon = tex, coords = coords })
        sort.name = (rec.name or ""):lower()
        data[#data + 1] = { cells = cells, sort = sort, tip = tip, group = groupFn and groupFn(rec) or nil,
            onClick = function() view.mode, view.key = "char", rec.key; dirty = true end }
    end
    local totals = ns.Acc.Totals()
    heading:SetText(L["All characters"])
    subheading:SetText(("%d %s"):format(totals.chars, L["characters"]))
    local note
    if #chars == 0 then
        note = AMBER .. L["No character known yet. Log in with each of your characters once."] .. "|r"
    elseif kind == "xp" then
        note = L["Rested experience of characters that are not logged in is an estimate from when you last played."]
    else
        note = L["Click a character to see its equipment, bags, professions and mail."]
    end
    local first = kindCols[1]
    return cols, data, note, { sort = first.id, asc = first.desc ~= true }
end

local function ViewSearch()
    local q = view.query
    local ids = ns.Acc.AllItemIds()
    local cols = {
        { id = "item", title = L["Item"], flex = 1.2, sort = true },
        { id = "total", title = L["Total"], w = 64, align = "RIGHT", sort = true, desc = true },
        { id = "where", title = L["Where"], flex = 2 },
    }
    local data, n = {}, 0
    for id in pairs(ids) do
        local name = ns.Acc.ItemName(id)
        if name and name:lower():find(q, 1, true) then
            local owners, total = ns.Acc.Owners(id)
            local parts = {}
            for i = 1, math.min(4, #owners) do
                local o = owners[i]
                local bits = {}
                if o.equip > 0 then bits[#bits + 1] = L["worn"] end
                if o.bags > 0 then bits[#bits + 1] = o.bags .. " " .. L["bags"] end
                if o.bank > 0 then bits[#bits + 1] = o.bank .. " " .. L["bank"] end
                if o.mail > 0 then bits[#bits + 1] = o.mail .. " " .. L["mail"] end
                if o.auction > 0 then bits[#bits + 1] = o.auction .. " " .. L["auction"] end
                parts[#parts + 1] = ClassHex(o.rec.class) .. ns.Acc.NameOf(o.rec) .. "|r " .. MUTED .. table.concat(bits, ", ") .. "|r"
            end
            if #owners > 4 then parts[#parts + 1] = MUTED .. ("+%d"):format(#owners - 4) .. "|r" end
            n = n + 1
            if n <= 400 then
                local link = ns.Acc.LinkOf(id)
                data[#data + 1] = { cells = { { text = link, icon = ItemIcon(id) }, tostring(total), table.concat(parts, "   ") },
                    sort = { item = name:lower(), total = total }, link = link }
            end
        end
    end
    heading:SetText(L["Search"])
    subheading:SetText(("%d %s"):format(n, L["items"]))
    local note = n > 400 and L["Showing the first 400 matches. Narrow the search."] or L["Items that characters have in bags, bank, mail, auctions or are wearing."]
    return cols, data, note, { sort = "total", asc = false }
end

local function ViewOverview(rec)
    local cols = { { id = "k", title = "", w = 170 }, { id = "v", title = "", flex = 1 } }
    local function Row(k, v) return { cells = { MUTED .. k .. "|r", v or MUTED .. "–|r" } } end
    local xp = (rec.xp and rec.xpMax and rec.xpMax > 0) and ("%d %%"):format(rec.xp / rec.xpMax * 100) or nil
    if xp and rec.rested and rec.xpMax and rec.xpMax > 0 then xp = xp .. "  " .. JADE .. ("+%d %% %s"):format(rec.rested / rec.xpMax * 100, L["rested"]) .. "|r" end
    local data = {
        Row(L["Level"], rec.level and tostring(rec.level) or nil),
        Row(L["Race"], rec.race),
        Row(L["Class"], rec.className and (ClassHex(rec.class) .. rec.className .. "|r") or nil),
        Row(L["Faction"], rec.faction),
        Row(L["Guild"], rec.guild),
        Row(L["Experience"], xp),
        Row(L["Item level"], rec.ilvl and ("%d"):format(rec.ilvl) or nil),
        Row(L["Money"], rec.money and Money(rec.money) or nil),
        Row(L["Played"], rec.played and Played(rec.played) or nil),
        Row(L["Location"], rec.zone and (rec.zone .. ((rec.sub and rec.sub ~= "") and (" – " .. rec.sub) or "")) or nil),
        Row(L["Hearthstone"], rec.hearth),
        Row(L["Last seen"], Ago(rec.lastSeen)),
    }
    -- what has been read, and what to do for the rest
    data[#data + 1] = { cells = { "", "" } }
    data[#data + 1] = { cells = { GOLD .. L["Data"] .. "|r", "" } }
    for _, part in ipairs({ "info", "equip", "bags", "bank", "mail", "skills", "recipes", "auctions" }) do
        local text, ok = Fresh(rec, part)
        data[#data + 1] = { cells = { MUTED .. (L["part_" .. part]) .. "|r", ok and text or text } }
    end
    return cols, data, nil, { noHeader = true }
end

local function ViewEquip(rec)
    local cols = {
        { id = "slot", title = L["Slot"], w = 120 },
        { id = "item", title = L["Item"], flex = 1 },
        { id = "ilvl", title = L["Item level"], w = 90, align = "RIGHT" },
    }
    local data = {}
    for _, def in ipairs(ns.Acc.SLOTS) do
        local link = rec.equip and rec.equip[def[1]]
        local ilvl
        if link then
            local get = GetDetailedItemLevelInfo or (C_Item and C_Item.GetDetailedItemLevelInfo)
            if get then ilvl = get(link) end
        end
        data[#data + 1] = {
            cells = { MUTED .. def[2] .. "|r", link and { text = link, icon = ItemIcon(link) } or (MUTED .. "–|r"), ilvl and tostring(ilvl) or "" },
            link = link,
        }
    end
    local text, ok = Fresh(rec, "equip")
    return cols, data, ok and text or text, { noSort = true }
end

local function ViewInventory(rec)
    local part = view.inv
    local set = rec[part] or {}
    local cols = {
        { id = "item", title = L["Item"], flex = 1, sort = true },
        { id = "count", title = L["Count"], w = 70, align = "RIGHT", sort = true, desc = true },
        { id = "value", title = L["Value"], w = 110, align = "RIGHT", sort = true, desc = true },
    }
    local data, worth = {}, 0
    for id, count in pairs(set.items or {}) do
        local tradable = count - ((set.bound and set.bound[id]) or 0)
        if PassesFilters(id, tradable) then
            local shown = HideBoundOn() and tradable or count
            local unit = ns.Value.Get(id)
            worth = worth + unit * shown
            local link = ns.Acc.LinkOf(id)
            data[#data + 1] = { cells = { { text = link, icon = ItemIcon(id) }, tostring(shown), unit > 0 and Money(unit * shown) or "" },
                sort = { item = (ns.Acc.ItemName(id) or ""):lower(), count = shown, value = unit * shown }, link = link }
        end
    end
    local place = { { "bags", L["Bags"], "Interface\\Icons\\INV_Misc_Bag_08" }, { "bank", L["Bank"], "Interface\\Icons\\INV_Misc_Bag_10" } }
    local cur = place[1]
    for _, p in ipairs(place) do if p[1] == view.inv then cur = p end end
    bar = { reset = true, items = ItemFilterButtons({ label = L["Location"] .. ": " .. cur[2], icon = cur[3], on = false, gen = function()
        local rows = {}
        for _, p in ipairs(place) do
            rows[#rows + 1] = { kind = "radio", state = State(view.inv == p[1]), label = p[2], icon = p[3],
                onClick = function() view.inv = p[1]; dirty = true end }
        end
        return rows
    end }) }
    local text, ok = Fresh(rec, part)
    local info = ""
    if set.slots then info = ("%d / %d %s  ·  %s  ·  "):format(set.slots - (set.free or 0), set.slots, L["slots used"], Money(worth)) end
    return cols, data, info .. text, { sort = "value", asc = false }
end

local function ViewProfessions(rec)
    if view.prof then
        local rc = rec.recipes and rec.recipes[view.prof]
        local cols = { { id = "name", title = view.prof, flex = 1, sort = true }, { id = "diff", title = L["Difficulty"], w = 110 } }
        local data = {}
        local DIFF = { optimal = AMBER, medium = "|cffffff66", easy = JADE, trivial = "|cff9a9080" }
        for _, r in ipairs(rc and rc.list or {}) do
            data[#data + 1] = { cells = { { text = r.link or r.name, icon = (r.link and ItemIcon(r.link)) or RecipeIcon(view.prof) }, (DIFF[r.difficulty] or "") .. (r.difficulty or "") .. "|r" },
                sort = { name = r.name:lower() }, link = r.link }
        end
        local note = rc and ("%d %s  ·  %s"):format(#(rc.list or {}), L["recipes"], ns.Ago(rc.time)) or AMBER .. ns.Acc.HINT.recipes .. "|r"
        return cols, data, note .. "   " .. MUTED .. L["Click the Professions tab to go back."] .. "|r", { sort = "name" }
    end
    local cols = {
        { id = "name", title = L["Profession"], flex = 1.2, sort = true },
        { id = "skill", title = L["Skill"], w = 150, sort = true, desc = true },
        { id = "recipes", title = L["Recipes"], w = 90, align = "RIGHT", sort = true, desc = true },
    }
    local data = {}
    for _, s in ipairs(rec.skills or {}) do
        local isProf = ns.Acc.SkillKind(s) ~= nil
        local rc = rec.recipes and rec.recipes[s.name]
        local pct = s.max > 0 and s.rank / s.max or 0
        local col = pct >= 1 and JADE or (pct > 0.7 and "|cffffff66" or "|cffffffff")
        data[#data + 1] = {
            cells = { { text = (isProf and "" or MUTED) .. s.name .. "|r" .. "  " .. MUTED .. (s.header or "") .. "|r", icon = ns.Acc.ProfIcon(s.name) },
                col .. ("%d / %d"):format(s.rank, s.max) .. "|r", rc and tostring(#(rc.list or {})) or MUTED .. "–|r" },
            sort = { name = (isProf and "0" or "1") .. s.name:lower(), skill = (isProf and 1000 or 0) + s.rank, recipes = rc and #(rc.list or {}) or -1 },
            onClick = rc and function() view.prof = s.name; dirty = true end or nil,
        }
    end
    local text = Fresh(rec, "skills")
    local rtext, rok = Fresh(rec, "recipes")
    return cols, data, text .. "   " .. (rok and (MUTED .. L["Click a profession to see its recipes."] .. "|r") or rtext), { sort = "skill", asc = false }
end

local function ViewMail(rec)
    local cols = {
        { id = "from", title = L["From"], w = 140, sort = true },
        { id = "subject", title = L["Subject"], flex = 1, sort = true },
        { id = "money", title = L["Money"], w = 100, align = "RIGHT", sort = true, desc = true },
        { id = "items", title = L["Items"], w = 140 },
        { id = "left", title = L["Expires in"], w = 100, align = "RIGHT", sort = true },
    }
    local data, gold, items = {}, 0, 0
    for _, m in ipairs(rec.mail and rec.mail.list or {}) do
        local icons = {}
        for _, a in ipairs(m.items or {}) do
            icons[#icons + 1] = { tex = ItemIcon(a.id), count = (a.count or 1) > 1 and a.count or nil, link = ns.Acc.LinkOf(a.id) }
            items = items + (a.count or 1)
        end
        gold = gold + (m.money or 0)
        local left = (m.expires or 0) - time()
        local days = left / 86400
        local text = left <= 0 and (RED .. L["expired"] .. "|r") or (days < 3 and RED or "") .. (days >= 1 and ("%dd"):format(math.floor(days)) or ("%dh"):format(math.max(1, math.floor(left / 3600)))) .. "|r"
        data[#data + 1] = {
            cells = { m.sender or "?", m.subject or "", m.money > 0 and Money(m.money) or "", { icons = icons }, text },
            sort = { from = (m.sender or ""):lower(), subject = (m.subject or ""):lower(), money = m.money or 0, left = left },
            tip = function(tt)
                tt:AddLine(m.subject or "", 1, 0.85, 0.4)
                tt:AddLine(m.sender or "?", 0.8, 0.8, 0.8)
                for _, a in ipairs(m.items or {}) do tt:AddLine(("%dx %s"):format(a.count or 1, ns.Acc.ItemName(a.id) or ("item:" .. a.id)), 1, 1, 1) end
                if (m.money or 0) > 0 then tt:AddLine(ns.Value.Format(m.money)) end
            end,
        }
    end
    local text, ok = Fresh(rec, "mail")
    local info = ok and ("%d %s  ·  %d %s  ·  %s  ·  "):format(#data, L["mails"], items, L["items"], Money(gold)) or ""
    return cols, data, info .. text, { sort = "left", asc = true }
end

local function ViewAuctions(rec)
    local cols = {
        { id = "item", title = L["Item"], flex = 1, sort = true },
        { id = "count", title = L["Count"], w = 70, align = "RIGHT", sort = true },
        { id = "buyout", title = L["Buyout"], w = 120, align = "RIGHT", sort = true, desc = true },
        { id = "left", title = L["Time left"], w = 100, align = "RIGHT" },
    }
    local LEFT4 = { L["short"], L["medium"], L["long"], L["very long"] }
    local data, worth = {}, 0
    for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do
        local link = ns.Acc.LinkOf(a.id)
        worth = worth + (a.buyout or 0)
        local left = a.left and ns.Ago(a.left) or (a.left4 and LEFT4[a.left4]) or ""
        if a.left and a.left > time() then left = ("%dh"):format(math.max(1, math.floor((a.left - time()) / 3600))) end
        data[#data + 1] = { cells = { { text = link, icon = ItemIcon(a.id) }, tostring(a.count or 1), (a.buyout or 0) > 0 and Money(a.buyout) or "", left },
            sort = { item = (ns.Acc.ItemName(a.id) or ""):lower(), count = a.count or 1, buyout = a.buyout or 0 }, link = link }
    end
    local text, ok = Fresh(rec, "auctions")
    return cols, data, (ok and (("%d %s  ·  %s  ·  "):format(#data, L["auctions"], Money(worth))) or "") .. text, { sort = "item" }
end

local ITEM_FILTERS = {
    { id = "all", label = L["All"], icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { id = "mat", label = L["Materials"], icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
    { id = "cons", label = L["Consumables"], icon = "Interface\\Icons\\INV_Potion_51" },
    { id = "gear", label = L["Equipment"], icon = "Interface\\Icons\\INV_Chest_Chain_03" },
    { id = "other", label = L["Other"], icon = "Interface\\Icons\\INV_Misc_Note_01" },
}
local ItemGroup = ItemGroupOf

-- everything the account holds, with the total and who has it
local function ViewItems()
    local q = view.query
    local cat = ITEM_FILTERS[1]
    for _, d in ipairs(ITEM_FILTERS) do if d.id == view.itemFilter then cat = d end end
    local nHidden = Count(view.hiddenChars)
    bar = { reset = true, items = ItemFilterButtons({ label = L["Category"] .. ": " .. cat.label, icon = cat.icon, on = view.itemFilter ~= "all", gen = function()
        local rows = {}
        for _, d in ipairs(ITEM_FILTERS) do
            rows[#rows + 1] = { kind = "radio", state = State(view.itemFilter == d.id), label = d.label, icon = d.icon,
                onClick = function() view.itemFilter = d.id; dirty = true end }
        end
        return rows
    end }) }
    table.insert(bar.items, #bar.items, { label = L["Characters"] .. (nHidden > 0 and (" (-" .. nHidden .. ")") or ""),
        icon = "Interface\\Icons\\INV_Misc_GroupLooking", gen = CharsMenu, on = nHidden > 0 })
    local cols = {
        { id = "item", title = L["Item"], flex = 1.2, sort = true },
        { id = "total", title = L["Total"], w = 64, align = "RIGHT", sort = true, desc = true },
        { id = "value", title = L["Value"], w = 110, align = "RIGHT", sort = true, desc = true },
        { id = "who", title = L["Characters"], flex = 1.6 },
    }
    local data, n, worth = {}, 0, 0
    for id in pairs(ns.Acc.AllItemIds()) do
        local name = ns.Acc.ItemName(id)
        if name and (q == "" or name:lower():find(q, 1, true)) and (view.itemFilter == "all" or ItemGroup(id) == view.itemFilter) then
            local owners, total, tradable = ns.Acc.Owners(id)
            if next(view.hiddenChars) then
                local o2, t2, r2 = {}, 0, 0
                for _, o in ipairs(owners) do
                    if not view.hiddenChars[o.rec.key] then o2[#o2 + 1] = o; t2 = t2 + o.sum; r2 = r2 + o.tradable end
                end
                owners, total, tradable = o2, t2, r2
            end
            if total > 0 and PassesFilters(id, tradable) then
                local shown = HideBoundOn() and tradable or total
                local parts = {}
                for i = 1, math.min(3, #owners) do
                    local amount = HideBoundOn() and owners[i].tradable or owners[i].sum
                    if amount > 0 then
                        parts[#parts + 1] = ClassHex(owners[i].rec.class) .. ns.Acc.NameOf(owners[i].rec) .. "|r " .. MUTED .. amount .. "|r"
                    end
                end
                if #owners > 3 then parts[#parts + 1] = MUTED .. ("+%d"):format(#owners - 3) .. "|r" end
                local unit = ns.Value.Get(id)
                worth = worth + unit * shown
                n = n + 1
                if n <= 500 then
                    local link = ns.Acc.LinkOf(id)
                    data[#data + 1] = { cells = { { text = link, icon = ItemIcon(id) }, tostring(shown), unit > 0 and Money(unit * shown) or "", table.concat(parts, "   ") },
                        sort = { item = name:lower(), total = shown, value = unit * shown }, link = link }
                end
            end
        end
    end
    heading:SetText(L["Items & materials"])
    subheading:SetText(("%d %s  ·  %s"):format(n, L["items"], Money(worth)))
    return cols, data, n > 500 and L["Showing the first 500 items. Narrow the filter."] or L["Everything the characters carry, store, have in the mail, auction or wear."], { sort = "value", asc = false }
end

-- every recipe any character knows, and what can be made from what the account holds
-- which of the characters could still learn a recipe: they have the profession and do not know it
-- (those whose recipes were never read are listed apart, since it cannot be told)
local function LearnLines(tt, r)
    local known = {}
    for _, rec in ipairs(r.knownBy) do known[rec.key] = true end
    local can, unread = {}, {}
    for _, rec in ipairs(ns.Acc.Chars(view.hiddenChars)) do
        if not known[rec.key] then
            local skill
            for _, sk in ipairs(rec.skills or {}) do
                if sk.name == r.prof then skill = sk end
            end
            if skill then
                if rec.recipes and rec.recipes[r.prof] then can[#can + 1] = { rec = rec, skill = skill }
                else unread[#unread + 1] = rec end
            end
        end
    end
    if #can > 0 then
        tt:AddLine(" ")
        tt:AddLine(L["Could still learn it"], 1, 0.85, 0.4)
        for _, e in ipairs(can) do
            tt:AddDoubleLine(ClassHex(e.rec.class) .. ns.Acc.NameOf(e.rec) .. "|r", ("%s %d / %d"):format(r.prof, e.skill.rank, e.skill.max), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        tt:AddLine(L["Needs enough skill, and the recipe or a trainer."], 0.6, 0.6, 0.6, true)
    end
    if #unread > 0 then
        local names = {}
        for _, rec in ipairs(unread) do names[#names + 1] = ns.Acc.NameOf(rec) end
        tt:AddLine(" ")
        tt:AddLine(L["Recipes not read yet"] .. ": " .. table.concat(names, ", "), 0.6, 0.6, 0.6, true)
    end
end

local function ViewCraft()
    local q = view.query
    local opt = view.craftOpt
    local recipes, have = ns.Acc.Recipes(), ns.Acc.MaterialIndex(view.hiddenChars)
    local profs, seen = {}, {}
    for _, r in ipairs(recipes) do
        if not seen[r.prof] then seen[r.prof] = true; profs[#profs + 1] = r.prof end
    end
    table.sort(profs)
    local pn = Count(view.craftProfs)
    local cat = ITEM_FILTERS[1]
    for _, d in ipairs(ITEM_FILTERS) do if d.id == view.craftCat then cat = d end end
    local rn, sn = Count(view.craftRarity), Count(view.craftSlots)
    local function Opt(key, label)
        return { kind = "check", state = State(opt[key]), label = label,
            onClick = function() opt[key] = not opt[key] or nil; dirty = true end }
    end
    bar = { reset = true, items = {
        { label = L["Profession"] .. (pn > 0 and (" (" .. pn .. ")") or ""), icon = "Interface\\Icons\\Trade_BlackSmithing", on = pn > 0, gen = function()
            local rows = {}
            for _, p in ipairs(profs) do
                rows[#rows + 1] = { kind = "check", state = State(view.craftProfs[p]), label = p, icon = ns.Acc.ProfIcon(p),
                    onClick = function() view.craftProfs[p] = (not view.craftProfs[p]) or nil; dirty = true end }
            end
            rows[#rows + 1] = { kind = "separator" }
            rows[#rows + 1] = { kind = "action", label = L["Show all"], onClick = function() wipe(view.craftProfs); dirty = true end }
            return rows
        end },
        { label = L["Makes"] .. ": " .. cat.label, icon = cat.icon, on = view.craftCat ~= "all", gen = function()
            local rows = {}
            for _, d in ipairs(ITEM_FILTERS) do
                rows[#rows + 1] = { kind = "radio", state = State(view.craftCat == d.id), label = d.label, icon = d.icon,
                    onClick = function() view.craftCat = d.id; dirty = true end }
            end
            return rows
        end },
        { label = L["Rarity"] .. (rn > 0 and (" (" .. rn .. ")") or ""), icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", on = rn > 0,
            gen = function() return RarityMenu(view.craftRarity) end },
        { label = L["Slot"] .. (sn > 0 and (" (" .. sn .. ")") or ""), icon = PD .. "Chest", on = sn > 0,
            gen = function() return SlotMenu(view.craftSlots) end },
        { label = L["Show"], icon = "Interface\\Icons\\INV_Hammer_20", on = view.onlyCraftable, gen = function()
            return {
                { kind = "check", state = State(view.onlyCraftable), label = L["Craftable now"],
                    onClick = function() view.onlyCraftable = not view.onlyCraftable; dirty = true end },
                { kind = "separator" },
                { kind = "header", label = L["Values"] },
                Opt("value", L["Value of the result"]),
                Opt("cost", L["Cost of the materials"]),
                Opt("profit", L["Profit"]),
            }
        end },
    } }
    for p in pairs(view.craftProfs) do if not seen[p] then view.craftProfs[p] = nil end end

    local cols = {
        { id = "recipe", title = L["Recipe"], flex = 1.2, sort = true },
        { id = "prof", title = L["Prof."], w = 64, sort = true },
        { id = "known", title = L["Known by"], flex = 1 },
        { id = "mats", title = L["Materials (needed)"], flex = 1.3 },
        { id = "can", title = L["Can make"], w = 74, align = "RIGHT", sort = true, desc = true },
    }
    if opt.value then cols[#cols + 1] = { id = "value", title = L["Value"], w = 100, align = "RIGHT", sort = true, desc = true } end
    if opt.cost then cols[#cols + 1] = { id = "cost", title = L["Cost"], w = 100, align = "RIGHT", sort = true, desc = true } end
    if opt.profit then cols[#cols + 1] = { id = "profit", title = L["Profit"], w = 110, align = "RIGHT", sort = true, desc = true } end
    local data = {}
    for _, r in ipairs(recipes) do
        local show = (not next(view.craftProfs) or view.craftProfs[r.prof])
            and (q == "" or r.name:lower():find(q, 1, true) or r.prof:lower():find(q, 1, true))
        if show and RecipePasses(r) then
            local can, cost, mats = nil, 0, {}
            for _, g in ipairs(r.reagents) do
                local n = have[g.id] or 0
                local need = math.max(1, g.count or 1)
                local unit = ns.Value.Get(g.id)
                can = math.min(can or math.huge, math.floor(n / need))
                cost = cost + unit * need
                -- a picture of the material with what is needed on it, green when the account has enough
                local enough = n >= need
                mats[#mats + 1] = { tex = ItemIcon(g.id), count = need, color = enough and { 0.4, 0.86, 0.66 } or { 0.92, 0.35, 0.30 },
                    link = ns.Acc.LinkOf(g.id),
                    extra = function(tt)
                        tt:AddLine(" ")
                        tt:AddDoubleLine(L["On all characters"], n .. " / " .. need, 0.8, 0.8, 0.8, enough and 0.4 or 0.92, enough and 0.86 or 0.35, enough and 0.66 or 0.30)
                        if unit > 0 then tt:AddDoubleLine(L["Needed for this recipe"], ns.Value.Format(unit * need), 0.8, 0.8, 0.8, 1, 1, 1) end
                    end }
            end
            if #r.reagents == 0 then can = nil end
            if not (view.onlyCraftable and not (can and can > 0)) then
                local value = r.id and ns.Value.Get(r.id) or 0
                local profit = (value > 0 and cost > 0) and (value - cost) or nil
                local known = {}
                for i = 1, math.min(3, #r.knownBy) do known[#known + 1] = ClassHex(r.knownBy[i].class) .. ns.Acc.NameOf(r.knownBy[i]) .. "|r" end
                if #r.knownBy > 3 then known[#known + 1] = MUTED .. ("+%d"):format(#r.knownBy - 3) .. "|r" end
                local cells = { { text = r.link or r.name, icon = (r.id and ItemIcon(r.id)) or RecipeIcon(r.prof) },
                    ns.Acc.ProfIcon(r.prof) and { icon = ns.Acc.ProfIcon(r.prof) } or r.prof, table.concat(known, ", "),
                    #mats > 0 and { icons = mats, fit = true } or MUTED .. L["unknown"] .. "|r",
                    can and ((can > 0 and JADE or RED) .. can .. "|r") or MUTED .. "?|r" }
                if opt.value then cells[#cells + 1] = value > 0 and Money(value) or "" end
                if opt.cost then cells[#cells + 1] = cost > 0 and Money(cost) or "" end
                if opt.profit then
                    cells[#cells + 1] = profit and ((profit >= 0 and JADE or RED) .. (profit < 0 and "-" or "+") .. "|r" .. Money(math.abs(profit), profit >= 0 and JADE or RED)) or ""
                end
                local function Details(tt)
                    for _, g in ipairs(r.reagents) do
                        local n = have[g.id] or 0
                        local unit = ns.Value.Get(g.id)
                        local gi = ItemIcon(g.id)
                        tt:AddDoubleLine((gi and (("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(gi)) or "") .. (ns.Acc.ItemName(g.id) or "?") .. (unit > 0 and ("  " .. ns.Value.Format(unit * (g.count or 1))) or ""),
                            n .. " / " .. (g.count or 1), 0.9, 0.9, 0.9, n >= (g.count or 1) and 0.4 or 0.9, n >= (g.count or 1) and 0.86 or 0.35, 0.4)
                    end
                    if value > 0 then tt:AddDoubleLine(L["Value of the result"], ns.Value.Format(value), 0.8, 0.8, 0.8, 1, 1, 1) end
                    if cost > 0 then tt:AddDoubleLine(L["Cost of the materials"], ns.Value.Format(cost), 0.8, 0.8, 0.8, 1, 1, 1) end
                    for _, rec in ipairs(r.knownBy) do tt:AddLine(ns.Acc.NameOf(rec), 0.8, 0.8, 0.8) end
                    LearnLines(tt, r)
                end
                if r.link and r.link:find("item:") then
                    cells[1].link = r.link
                    cells[1].extra = function(tt) tt:AddLine(" "); Details(tt) end
                end
                data[#data + 1] = {
                    cells = cells,
                    sort = { recipe = r.name:lower(), prof = r.prof:lower(), can = can or -1, profit = profit or -math.huge,
                        value = value, cost = cost },
                    tip = function(tt)
                        tt:AddLine(r.name, 1, 0.85, 0.4)
                        tt:AddLine(r.prof, 0.7, 0.7, 0.7)
                        Details(tt)

                    end,
                }
            end
        end
    end
    heading:SetText(L["Crafting"])
    subheading:SetText(("%d %s"):format(#data, L["recipes"]))
    local note = #recipes == 0 and (AMBER .. L["No recipes read yet. Open a profession window with each character (use /fc accdebug if nothing appears)."] .. "|r")
        or L["Materials count what all characters have in bags, bank and mail. Profit is the value of the result minus the materials."]
    return cols, data, note, { sort = "can", asc = false }
end

-- render ---------------------------------------------------------------------------------------------------------
local function LayoutRight()
    local charView = view.mode == "char" and Rec() and view.query == ""
    local x = 10
    for _, b in ipairs(tabButtons) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", right, "TOPLEFT", x, -8)
        b:SetShown(charView)
        b:SetSelected(b.id == view.tab)
        x = x + 120
    end
    local baseTop = charView and 38 or 8
    local bx = 10
    for i = 1, math.max(#menuButtons, bar and #bar.items or 0) do
        local def = bar and bar.items[i]
        if def then
            local b = menuButtons[i]
            if not b then b = W.NewMenuButton(right, menu); menuButtons[i] = b end
            b:SetContent(def.label, def.icon, def.gen, def.on)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", right, "TOPLEFT", bx, -baseTop)
            b:Show()
            bx = bx + b:GetWidth() + 4
        elseif menuButtons[i] then
            menuButtons[i]:Hide()
        end
    end
    if bar and bar.reset then
        local b = menuButtons.reset
        if not b then
            b = W.NewButton(right, L["Reset filters"], 110, 24)
            b:SetScript("OnClick", ResetFilters)
            menuButtons.reset = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", right, "TOPLEFT", bx + 6, -baseTop)
        b:Show()
    elseif menuButtons.reset then
        menuButtons.reset:Hide()
    end
    local forget = charView and view.key ~= ns.Acc.MyKey()
    forgetBtn:ClearAllPoints()
    forgetBtn:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, -8)
    forgetBtn:SetShown(forget and true or false)
    local top = baseTop + (bar and 28 or 0)
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -top - 2)
    status:SetPoint("TOPRIGHT", right, "TOPRIGHT", -12, -top - 2)
    local sh = math.max(14, status:GetStringHeight())
    tbl.frame:ClearAllPoints()
    tbl.frame:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -top - sh - 8)
    tbl.frame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 6)
end

function AW.Render()
    if not f:IsShown() then return end
    RenderList()
    local cols, data, note, opts
    bar = nil
    if view.mode == "items" then
        cols, data, note, opts = ViewItems()
    elseif view.mode == "craft" then
        cols, data, note, opts = ViewCraft()
    elseif view.query ~= "" then
        cols, data, note, opts = ViewSearch()
    elseif view.mode == "char" and Rec() then
        local rec = Rec()
        heading:SetText(ClassHex(rec.class) .. ns.Acc.NameOf(rec) .. "|r")
        local groupFn = ns.Acc.GroupFn()
        local g = groupFn and groupFn(rec)
        subheading:SetText(("%s %d %s %s%s"):format(L["Level"], rec.level or 0, rec.race or "", rec.className or "", g and ("  ·  " .. g) or ""))
        if view.tab == "equip" then cols, data, note, opts = ViewEquip(rec)
        elseif view.tab == "inv" then cols, data, note, opts = ViewInventory(rec)
        elseif view.tab == "prof" then cols, data, note, opts = ViewProfessions(rec)
        elseif view.tab == "mail" then cols, data, note, opts = ViewMail(rec)
        elseif view.tab == "ah" then cols, data, note, opts = ViewAuctions(rec)
        else cols, data, note, opts = ViewOverview(rec) end
    else
        view.mode = "all"
        cols, data, note, opts = ViewAll()
    end
    status:SetText(note or "")
    LayoutRight()
    local o = opts or {}
    local key = view.mode .. (view.key or "") .. view.tab .. (view.prof or "") .. view.inv .. (view.query ~= "" and "q" or "")
        .. view.itemFilter .. tostring(view.onlyCraftable) .. view.allView
    if AW.lastKey ~= key then AW.lastKey = key; o.resetSort = true end
    tbl:Set(cols, data, o)
end

function AW.Dirty() dirty = true end

local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    W.Step(dt)
    if f.fcMoving then return end -- (nothing is drawn again while the window is dragged: it follows the mouse without a hitch)
    acc = acc + dt
    if (dirty and acc > 0.05) or acc > 5 then
        acc, dirty = 0, false
        AW.Render()
    end
end)
f:SetScript("OnShow", function() dirty = true end)
f:SetScript("OnSizeChanged", function() dirty = true end)

function AW.Show(key)
    if key then view.mode, view.key, view.prof = "char", key, nil end
    f:Show()
    if ns.db then ns.db.accountShown = true end
    dirty = true
end
function AW.Hide()
    f:Hide()
    if ns.db then ns.db.accountShown = false end
end
function AW.Toggle()
    if f:IsShown() then AW.Hide() else AW.Show() end
end
function AW.ResetWindow()
    if ns.db then ns.db.accountWin = nil end
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 30, 0)
    f:SetSize(DEFAULT_W, DEFAULT_H)
    dirty = true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    AW.ApplyFrameStyle()
    local saved = ns.db and ns.db.accountWin
    if saved and saved.v ~= 2 then saved.size = nil end -- the window grew: an older, smaller size is dropped
    if saved and saved.scale then f:SetScale(math.max(0.6, math.min(1.6, saved.scale))) end
    if saved and saved.size then
        f:SetSize(math.max(MIN_W, math.min(MAX_W, saved.size[1])), math.max(MIN_H, math.min(MAX_H, saved.size[2])))
    end
    if saved and saved.pos then
        f:ClearAllPoints()
        f:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
    end
    W.SetWindowAlpha(f, W.WindowAlpha("account"))
    view.key = ns.Acc.MyKey()
    if ns.db and ns.db.accountShown then AW.Show() end
end)

SLASH_FOREVERCOMPANIONACCOUNT1 = "/fcaccount"
SLASH_FOREVERCOMPANIONACCOUNT2 = "/fcalts"
SLASH_FOREVERCOMPANIONACCOUNT3 = "/fklaccount"
SLASH_FOREVERCOMPANIONACCOUNT4 = "/fklalts"
SlashCmdList.FOREVERCOMPANIONACCOUNT = function() AW.Toggle() end
